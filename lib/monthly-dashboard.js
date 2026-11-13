/* Shared by the offline dashboard and isolated Node tests. No external runtime. */
(function (root) {
  'use strict';
  const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  const format = value => value === undefined ? 'Not reported' : value.toLocaleString('en-US');
  function periodLabel(period) { const [year, month] = period.split('-'); return `${MONTHS[Number(month) - 1]} ${year}`; }
  function monthIndex(period) { const [year, month] = period.split('-').map(Number); return year * 12 + month - 1; }
  function reportLabel(report) {
    return report.period ? `${periodLabel(report.period)} · activity` : report.date ? `Generated ${report.date} · activity month unconfirmed` : `${report.source} · activity month unconfirmed`;
  }
  function noticeTotal(metrics) {
    if (metrics.notice_total !== undefined) return metrics.notice_total;
    return ['holds', 'reminders', 'overdue'].every(key => metrics[key] !== undefined) ? metrics.holds + metrics.reminders + metrics.overdue : undefined;
  }
  function metricValue(report, name, key) {
    if (!report) return undefined;
    if (key === 'keywords') {
      if (name || !Object.keys(report.keywords).length) return undefined;
      return Object.values(report.keywords).reduce((sum, value) => sum + value, 0);
    }
    const metrics = name ? (report.branches.find(b => b.name === name)?.metrics || {}) : report.totals;
    if (key === 'notices') return noticeTotal(metrics);
    if (!name && key === 'registered') return report.registrations.users;
    if (!name && key === 'signups') return report.registrations.signups;
    return metrics[key];
  }
  function previousReport(reports, report) {
    return report.period ? reports.find(r => r.period && monthIndex(r.period) === monthIndex(report.period) - 1) : undefined;
  }
  function change(current, previous) {
    if (current === undefined || previous === undefined) return { text: 'Not comparable', direction: 'unknown' };
    const delta = current - previous, percent = previous === 0 ? null : delta / previous * 100;
    const signed = value => `${value > 0 ? '+' : ''}${value.toLocaleString('en-US', { maximumFractionDigits: 1 })}`;
    return { delta, percent, direction: delta > 0 ? 'increase' : delta < 0 ? 'decrease' : 'unchanged',
      text: `${signed(delta)} (${percent === null ? 'prior count 0; % undefined' : `${signed(percent)}%`})` };
  }
  function readSelection(hash, data) {
    const params = new URLSearchParams(hash.replace(/^#/, ''));
    const branch = params.get('branch') || 'all', report = params.get('report');
    const validBranch = branch === 'all' || data.branches.some(b => b.id === branch);
    const selectedReport = data.reports.find(r => r.id === report) || data.reports[data.reports.length - 1];
    return { branch: validBranch ? branch : 'all', report: selectedReport,
      warning: [!validBranch ? 'Unknown branch in URL; showing all branches.' : '', report && report !== selectedReport.id ? 'Unknown report in URL; showing the latest included report.' : ''].filter(Boolean).join(' ') };
  }
  function selectionHash(hash, branch, report) {
    const params = new URLSearchParams(hash.replace(/^#/, ''));
    params.set('branch', branch); params.set('report', report);
    return `#${params}`;
  }
  // SVG paths never bridge an absent metric or a missing calendar month.
  function chartGeometry(rows) {
    const known = rows.filter(row => row.value !== undefined);
    const max = Math.max(1, ...known.map(row => row.value));
    const power = 10 ** Math.floor(Math.log10(max / 4));
    const step = Math.max(1, [1, 2, 5, 10].map(n => n * power).find(n => n >= max / 4));
    const ceiling = Math.ceil(max / step) * step;
    const first = monthIndex(rows[0].period), span = monthIndex(rows[rows.length - 1].period) - first;
    const points = rows.map(row => ({ ...row, x: span ? 60 + (monthIndex(row.period) - first) / span * 490 : 305, y: row.value === undefined ? null : 205 - row.value / ceiling * 175 }));
    const segments = []; let segment = [];
    for (let i = 0; i < points.length; i++) {
      const point = points[i];
      if (point.y === null || (i && monthIndex(point.period) - monthIndex(points[i - 1].period) !== 1)) {
        if (segment.length) segments.push(segment);
        segment = [];
      }
      if (point.y !== null) segment.push(point);
    }
    if (segment.length) segments.push(segment);
    return { points, segments, ceiling, step };
  }
  function mount(data, win, doc) {
    const get = id => doc.getElementById(id);
    const el = (tag, text, className) => {
      const node = doc.createElement(tag);
      if (text !== undefined) node.textContent = text;
      if (className) node.className = className;
      return node;
    };
    const svgEl = (tag, attributes = {}, text) => {
      const node = doc.createElementNS('http://www.w3.org/2000/svg', tag);
      for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, String(value));
      if (text !== undefined) node.textContent = text;
      return node;
    };
    function table(container, caption, headings, rows) {
      const node = el('table'); node.append(el('caption', caption));
      const head = el('thead'), tr = el('tr');
      for (const heading of headings) { const th = el('th', heading); th.setAttribute('scope', 'col'); tr.append(th); }
      head.append(tr); node.append(head);
      const body = el('tbody');
      for (const row of rows) {
        const line = el('tr');
        row.forEach((value, i) => {
          const cell = el(i ? 'td' : 'th');
          if (!i) cell.setAttribute('scope', 'row');
          if (value && typeof value === 'object') cell.append(value); else cell.textContent = value;
          line.append(cell);
        });
        body.append(line);
      }
      node.append(body); container.append(node);
    }
    function link(branch, report) {
      const node = el('a', branch.name);
      node.href = selectionHash(win.location.hash, branch.id, report.id);
      return node;
    }
    function dataTable(id, caption, headings, rows) { get(id).replaceChildren(); table(get(id), caption, headings, rows); }
    function chart(id, key, name, title, current) {
      const container = get(id), values = get(id.replace('-chart', '-values'));
      container.replaceChildren(); values.replaceChildren();
      const reports = data.reports.filter(r => r.period).sort((a, b) => a.period.localeCompare(b.period));
      const rows = reports.map(r => ({ period: r.period, value: metricValue(r, name, key), id: r.id }));
      if (!rows.length) {
        container.append(el('p', 'No confirmed activity months; no trend shown.', 'muted'));
        values.append(el('p', `${title}: activity month unconfirmed.`, 'muted'));
        return;
      }
      const geometry = chartGeometry(rows);
      if (rows.length >= 2 && rows.some(row => row.value !== undefined)) {
        const svg = svgEl('svg', { viewBox: '0 0 600 250', role: 'img', 'aria-label': `${title}. ${rows.map(row => `${periodLabel(row.period)}: ${format(row.value)}`).join('; ')}. Exact values and changes appear under Monthly values below.` });
        svg.append(svgEl('title', {}, title));
        for (let value = 0; value <= geometry.ceiling; value += geometry.step) {
          const y = 205 - value / geometry.ceiling * 175;
          svg.append(svgEl('line', { x1: 60, x2: 550, y1: y, y2: y, class: 'grid-line' }), svgEl('text', { x: 50, y: y + 4, 'text-anchor': 'end', class: 'axis-label' }, format(value)));
        }
        for (const segment of geometry.segments) {
          if (segment.length > 1) svg.append(svgEl('polyline', { points: segment.map(p => `${p.x},${p.y}`).join(' '), class: 'series-line', fill: 'none' }));
        }
        geometry.points.forEach((point, i) => {
          if (rows.length <= 6 || i === 0 || i === rows.length - 1 || i % Math.ceil(rows.length / 6) === 0) {
            svg.append(svgEl('text', { x: point.x, y: 232, 'text-anchor': 'middle', class: 'axis-label' }, `${MONTHS[Number(point.period.slice(5)) - 1].slice(0, 3)} ${point.period.slice(0, 4)}`));
          }
          if (point.y === null) return;
          svg.append(svgEl('circle', { cx: point.x, cy: point.y, r: point.id === current.id ? 6 : 4, class: point.id === current.id ? 'point current' : 'point' }));
          if (rows.length <= 8) svg.append(svgEl('text', { x: point.x, y: point.y - 12, 'text-anchor': 'middle', class: 'point-label' }, format(point.value)));
        });
        container.append(svg);
      } else container.append(el('p', rows.length < 2 ? 'Add another reporting month to see a trend.' : 'No values reported for this view. Missing values are not zero.', 'muted'));
      table(values, `${title} · exact values`, ['Month', 'Count', 'Change vs prior month'], reports.map(r => [periodLabel(r.period), format(metricValue(r, name, key)), change(metricValue(r, name, key), metricValue(previousReport(data.reports, r), name, key)).text]));
    }
    const alphabetical = [...data.branches].sort((a, b) => a.name.localeCompare(b.name, 'en'));
    function option(select, value, text) { const node = el('option', text); node.value = value; select.append(node); }
    option(get('branch'), 'all', 'All branches');
    for (const branch of alphabetical) option(get('branch'), branch.id, branch.name);
    for (const report of data.reports) option(get('report'), report.id, reportLabel(report));
    get('report-control').hidden = data.reports.length < 2;

    function render() {
      const state = readSelection(win.location.hash, data), r = state.report;
      const selected = data.branches.find(b => b.id === state.branch), name = selected?.name;
      const branch = name ? r.branches.find(b => b.name === name) : null;
      const prior = previousReport(data.reports, r), priorLabel = prior ? periodLabel(prior.period) : null;
      const m = name ? (branch?.metrics || {}) : r.totals;
      get('branch').value = state.branch; get('report').value = r.id;
      get('title').textContent = name || 'All branches';
      get('heading-period').textContent = r.period ? periodLabel(r.period) : 'Activity month unconfirmed';
      get('subtitle').textContent = 'Enrollment and activity over time.';
      get('scope-note').textContent = name ? 'Branch view · System-wide keyword activity below is not attributable to this branch.' : `${r.branches.length} branches in this report · Summary figures use reported system totals.`;
      doc.title = `${name || 'All branches'} · ${reportLabel(r)} · Shoutbomb`;
      get('status').textContent = [state.warning, name && !branch ? 'This branch has no reported data in this file.' : ''].filter(Boolean).join(' ');
      get('period-note').textContent = r.period ? `Reporting month: ${r.period} · ${r.periodMethod === 'named' ? 'Explicit filename month label (--named-periods), not the generation date.' : 'Explicitly assigned for this report.'}` : 'The activity month has not been confirmed. Filename generation dates are not reporting periods; comparisons require explicit months.';
      get('permalink').href = selectionHash(win.location.hash, state.branch, r.id);
      get('comparison-note').textContent = prior ? `Changes compare with ${priorLabel}. Enrollment is a reported snapshot, not a unique active-user count or an adoption rate.` : 'No report for the immediately preceding calendar month is included. Changes are unavailable; no earlier month is substituted.';
      for (const [id, key] of [['registered-summary', 'registered'], ['signups-summary', 'signups'], ['notice-summary', 'notices'], ['keyword-summary', 'keywords']]) {
        const scope = key === 'keywords' ? undefined : name;
        const value = metricValue(r, scope, key), difference = change(value, metricValue(prior, scope, key));
        get(id).replaceChildren(el('strong', format(value)), el('span', ` · ${difference.text}${prior ? ` vs ${priorLabel}` : ' · previous calendar month unavailable'}`));
      }
      const confirmed = data.reports.filter(report => report.period);
      get('trend-section').hidden = false; // Counts remain visible even without a trend.
      get('trend-note').textContent = confirmed.length >= 2 ? 'All confirmed months are shown. Each chart has its own count axis starting at zero; lines connect adjacent months only. The outlined point is the selected report. Missing values are not zero.' : 'Include at least two reports with explicitly assigned months to see trends. Selected-month counts remain available above.';
      chart('registered-chart', 'registered', name, 'Registered patrons · reported snapshots', r);
      chart('signups-chart', 'signups', name, 'New signups · monthly additions', r);
      chart('notice-chart', 'notices', name, 'Text notices · monthly messages', r);
      chart('keyword-chart', 'keywords', undefined, 'System-wide keyword uses · not unique users', r);
      dataTable('comparison', `${r.period ? periodLabel(r.period) : 'Selected report'} · branch counts and changes`, ['Branch', 'Registered', 'Change', 'Signups', 'Change', 'Notices', 'Change'], alphabetical.map(b => [link(b, r), ...['registered', 'signups', 'notices'].flatMap(key => [format(metricValue(r, b.name, key)), change(metricValue(r, b.name, key), metricValue(prior, b.name, key)).text])]));
      const monthColumns = ['Metric', 'Selected month', priorLabel || 'Previous month unavailable', 'Change'];
      const metricRows = keys => keys.map(([label, key]) => [label, format(metricValue(r, name, key)), format(metricValue(prior, name, key)), change(metricValue(r, name, key), metricValue(prior, name, key)).text]);
      get('notice-total').textContent = format(noticeTotal(m));
      get('notice-total-note').textContent = m.notice_total !== undefined ? 'Source-reported total.' : noticeTotal(m) !== undefined ? 'Sum of hold, reminder, and overdue notices; repeated summaries counted once.' : 'A total cannot be calculated from incomplete notice counts.';
      dataTable('notices', 'Notice breakdown · messages', monthColumns, metricRows([['Hold notices', 'holds'], ['Hold reminders', 'reminders'], ['Overdue notices', 'overdue']]));
      dataTable('items', 'Overdue items · separate from message counts', monthColumns, metricRows([['Eligible for renewal', 'eligible'], ['Ineligible for renewal', 'ineligible'], ['Successfully renewed by patrons', 'renewed'], ['Unsuccessfully renewed by patrons', 'failed']]));
      get('renewals').textContent = 'Eligibility is not an attempt or an outcome. Renewal outcome counts may overlap other item counts; no renewal rate is inferred.';
      const keywordNames = [...new Set([...Object.keys(r.keywords), ...Object.keys(prior?.keywords || {})])].sort();
      dataTable('keywords', 'System-wide command counts · not branch-specific or unique users', monthColumns, keywordNames.map(key => [key, format(r.keywords[key]), format(prior?.keywords[key]), change(r.keywords[key], prior?.keywords[key]).text]));
      get('system-registrations').replaceChildren();
      const labels = { users: 'Registered users (snapshot)', barcodes: 'Registered barcodes (snapshot)', english: 'English-language users', spanish: 'Spanish-language users', signups: 'New signups during the month' };
      for (const [key, value] of Object.entries(r.registrations)) get('system-registrations').append(el('p', `${labels[key]}: ${format(value)}`));
      get('unattributed').textContent = r.unattributed?.signups !== undefined ? `System-wide source note: ${format(r.unattributed.signups)} signup(s) have no branch. They are preserved separately, not assigned to a branch or added again to the overall signup total.` : '';
      get('system-percentages').replaceChildren();
      for (const [label, value] of Object.entries(r.percentages)) get('system-percentages').append(el('p', `${label.replace(/::$/, '')}: ${value} (source-reported; denominator unverified)`));
      if (!Object.keys(r.percentages).length) get('system-percentages').append(el('p', 'Not reported.'));
      get('source').textContent = `Selected source: ${r.source}${r.date ? ` · filename generation date: ${r.date}` : ''}`;
      const warningCount = data.reports.reduce((sum, report) => sum + report.warnings.length, 0);
      get('quality-summary').textContent = `${warningCount} source warning(s) across ${data.reports.length} included report(s). Missing values remain unknown.`;
      get('quality-summary').className = warningCount ? 'has-warnings' : '';
      get('quality').replaceChildren();
      const notes = [
        'Counts compare reported values, not a fixed cohort. Registered users may differ from branch patron/barcode populations; snapshots are not confirmed month-end counts. Net snapshot changes are not signup counts.',
        'No adoption rates or unique active-user counts can be derived here. Keyword uses are system-wide commands, including administrative/test commands, not necessarily patron engagement.',
        'Missing branch metrics and missing keywords are not zero. Comparisons require both values and the immediately prior calendar month; a zero prior count has no defined percentage change.',
        'All included months and branches remain embedded in this file. Branch selection is not access control.',
      ];
      for (const note of notes) get('quality').append(el('li', note));
      for (const report of data.reports) {
        for (const warning of report.warnings) get('quality').append(el('li', `${report.period ? periodLabel(report.period) : report.source}: ${warning}`));
      }
      dataTable('sources', 'Included source reports', ['Activity month', 'Source filename', 'Generation date'], data.reports.map(report => [report.period ? periodLabel(report.period) : 'Unconfirmed', report.source, report.date || 'Unknown']));
    }
    function update() { win.location.hash = selectionHash(win.location.hash, get('branch').value, get('report').value); }
    get('branch').addEventListener('change', update);
    get('report').addEventListener('change', update);
    get('print').addEventListener('click', () => win.print());
    win.addEventListener('hashchange', render);
    render();
    return { render };
  }
  const api = { readSelection, selectionHash, noticeTotal, periodLabel, reportLabel, metricValue, previousReport, change, chartGeometry, mount };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.MonthlyDashboard = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
