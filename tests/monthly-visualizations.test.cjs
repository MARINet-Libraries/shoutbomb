'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const vm = require('node:vm');
const parser = require('../lib/monthly-report.cjs');
const dashboard = require('../lib/monthly-dashboard.js');
const cli = path.resolve(__dirname, '../visualize-monthly-reports');

const sample = `Branch::,Novato Library
Hold text notices sent,for the month,25
Hold text reminders notices sent ,for the month,2
Hold text reminders sent for the month = 2
Overdue text notices sent,for the month,28
Overdue items eligible for renewal text notices sent,for the month,3
Overdue items ineligible for renewal text notices sent,for the month,97
Overdue (text) items unsuccessfully renewed by patrons ,for the month,1
Branch::,"Branch, With Comma"
Hold text notices sent,for the month,0
.........................TOTALS.............................
Hold text notices sent,for the month,25
Hold text reminders notices sent ,for the month,2
Overdue text notices sent,for the month,28
Overdue items eligible for renewal text notices sent,for the month,3
Overdue items ineligible for renewal text notices sent,for the month,97
Overdue (text) items unsuccessfully renewed by patrons ,for the month,1
Percentage of overall overdue (text) items where renewal failed::,33.33%
.........................TOTALS BY BRANCH.........................
Novato Library, sent, for the month, this many text notices,55
.........................TOTALS OF REGISTERED PATRON BY BRANCH.........................
Novato Library, has, 12, registered patrons for text notices
Sausalito Public Library, has, 1, registered patrons for text notices
................................FREQUENCY OF KEYWORD USAGE BY PATRONS (for the month)........................
RENEW was used 3 times.
Total registered users for your branches = 13
Total registered barcodes = 14
Total registered users for the English language is 13
Total registered users for the Spanish language is 1
Registered users the last month = 1
Novato Library signed up 1 patron(s) for text notices the last month
................................*****................................
No Patron Initiated Cancellation of Notice Service
`;

function fixture(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'monthly-visualizations-test-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  // Fake configuration is deliberately irrelevant: the new script never loads it.
  fs.writeFileSync(path.join(dir, '.env'), 'exit 99\n');
  return dir;
}
function input(dir, date = '2026-11-05', text = sample, suffix = 'test') {
  const file = path.join(dir, `sb_generate_monthly_report_${suffix}_${date}_00_10_18.csv`);
  fs.writeFileSync(file, text); return file;
}
function run(dir, args) { return spawnSync(process.execPath, [cli, ...args], { cwd: dir, encoding: 'utf8' }); }
function embedded(html) { return JSON.parse(html.match(/<script id="dashboard-data" type="application\/json">(.*?)<\/script>/s)[1]); }

test('section-aware parser handles CRLF, BOM, CSV quoting, repeated summaries, and registration-only branches', () => {
  const report = parser.parseReport('\uFEFF' + sample.replace(/\n/g, '\r\n'));
  const novato = report.branches.find(b => b.name === 'Novato Library').metrics;
  assert.equal(report.branches.length, 3);
  assert.equal(novato.reminders, 2);
  assert.equal(novato.notice_total, 55);
  assert.equal(novato.ineligible, 97);
  assert.deepEqual(report.branches.find(b => b.name === 'Sausalito Public Library').metrics, { registered: 1 });
  const missing = report.branches.find(b => b.name === 'Branch, With Comma').metrics;
  assert.equal(missing.holds, 0);
  assert.equal(missing.overdue, undefined);
  assert.equal(report.keywords.RENEW, 3);
  assert.equal(report.totals.holds, 25);
  assert.equal(Object.keys(report.percentages).length, 1);
  assert.equal(report.warnings.length, 1);
  assert.match(report.warnings[0], /Language counts/);
  assert.deepEqual(parser.csvRow('"A ""quoted"" branch", has, 2', 1), ['A "quoted" branch', 'has', '2']);
});

test('malformed metrics and conflicting repetitions fail rather than silently changing data', () => {
  for (const value of ['-1', 'NaN', '1.5', '9007199254740992']) {
    assert.throws(() => parser.parseReport(sample.replace('for the month,25', `for the month,${value}`)), /line 2: expected/);
  }
  assert.throws(() => parser.parseReport(sample.replace('month = 2', 'month = 3')), /conflicting repeated metric/);
  assert.throws(() => parser.parseReport('Branch::,"unclosed'), /unterminated CSV/);
  assert.throws(() => parser.parseReport(sample.replace('Branch::,"Branch, With Comma"', 'Branch::,Broken,Header')), /malformed branch header/);
  assert.throws(() => parser.parseReport(sample.replace('month = 2', 'month = -1')), /expected a non-negative/);
  assert.throws(() => parser.parseReport(sample.replace('branches = 13', 'branches = -1')), /expected a non-negative/);
  assert.throws(() => parser.parseReport(sample.replace('RENEW was used 3', 'RENEW was used abc')), /expected a non-negative/);
  assert.throws(() => parser.parseReport('not a report'), /no supported branch data/);
  assert.throws(() => parser.parseReport(sample.replace('33.33%', '101%')), /malformed percentage/);
  const report = parser.parseReport(sample + 'Private future source text\n');
  assert.ok(report.warnings.some(w => /unrecognized content omitted/.test(w)));
  assert.ok(!report.warnings.join().includes('Private future'));
  const mismatch = parser.parseReport(sample.replace('this many text notices,55', 'this many text notices,56'));
  assert.ok(mismatch.warnings.some(w => w.includes('Notice components differ')));
});

test('report periods are explicit and calendar arithmetic handles January', () => {
  assert.equal(parser.generatedDate('sb_generate_monthly_report_test_2026-11-05_00_10_18.csv'), '2026-11-05');
  assert.equal(parser.generatedDate('renamed.csv'), null);
  assert.throws(() => parser.generatedDate('sb_generate_monthly_report_test_2026-02-30_00_10_18.csv'), /invalid filename date/);
  assert.equal(parser.previousMonth('2026-01-05'), '2025-12');
  assert.equal(parser.previousMonth('2026-11-05'), '2026-10');
  assert.ok(!parser.validPeriod('2026-13'));
  assert.ok(!parser.validPeriod('0000-01'));
});

test('branch IDs are stable, reserved IDs and slug collisions are handled', () => {
  const names = ['Novato Library', 'A B', 'A-B', 'All', '図書館'];
  const ids = parser.branchIds(names);
  assert.equal(ids[0].id, 'novato-library');
  assert.equal(new Set(ids.map(b => b.id)).size, names.length);
  assert.notEqual(ids[3].id, 'all');
  assert.deepEqual(parser.branchIds([...names].reverse()).reverse(), ids);
});

test('CLI generates a private offline HTML file, without changing input or interpreting month by default', t => {
  const dir = fixture(t), file = input(dir), out = path.join(dir, 'output', 'report.html');
  const result = run(dir, ['--output', out, file]);
  assert.equal(result.status, 0, result.stderr);
  const html = fs.readFileSync(out, 'utf8'), data = embedded(html);
  assert.equal(data.reports[0].date, '2026-11-05');
  assert.equal(data.reports[0].period, null);
  assert.equal(fs.readFileSync(file, 'utf8'), sample);
  assert.equal(fs.statSync(out).mode & 0o777, 0o600);
  assert.ok(!/<(?:script|link)[^>]+(?:src|href)=/i.test(html));
  assert.ok(!/\/\*__DASHBOARD_/.test(html));
  const js = html.match(/<script>\n(.*?)<\/script>/s)[1];
  assert.doesNotThrow(() => new vm.Script(js));
  const runtime = domHarness(data, '#branch=novato-library', js, html);
  assert.equal(runtime.get('title').textContent, 'Novato Library');
  assert.match(runtime.get('period-note').textContent, /not been confirmed/);
  assert.equal(runtime.get('registered-summary').children[0].textContent, '12');
  assert.equal(runtime.get('trend-section').hidden, false);
  assert.ok(!runtime.get('registered-chart').children.some(node => node.tagName === 'svg'));
  assert.deepEqual(fs.readdirSync(path.dirname(out)), ['report.html']);
});

test('embedded data escapes script termination and source text is rendered as text only', t => {
  const dir = fixture(t);
  const payload = '</script><img src=x onerror=alert(1)> $& /*__DASHBOARD_SCRIPT__*/';
  const file = input(dir, '2026-11-05', sample.replaceAll('Novato Library', () => payload));
  const out = path.join(dir, 'report.html');
  const result = run(dir, ['--output', out, file]);
  assert.equal(result.status, 0, result.stderr);
  const html = fs.readFileSync(out, 'utf8');
  assert.ok(!html.includes('<img src=x'));
  assert.equal(embedded(html).branches.find(b => b.name === payload).name, payload);
});

test('CLI validates options, filenames, and input/output aliases; failures preserve existing output', t => {
  const dir = fixture(t), file = input(dir), out = path.join(dir, 'report.html');
  fs.writeFileSync(out, 'previous good report');
  for (const args of [[], ['--wat'], ['--help', file], ['--output'], ['--period', '2026-13', file], ['--period', '2026-10', '--previous-month', file], ['--period', '2026-10', file, file]]) {
    assert.equal(run(dir, args).status, 2, JSON.stringify(args));
  }
  assert.equal(run(dir, ['--help']).status, 0);
  for (const alias of [file, path.join(dir, 'symlink.csv'), path.join(dir, 'hardlink.csv')]) {
    if (alias.endsWith('symlink.csv')) fs.symlinkSync(file, alias);
    if (alias.endsWith('hardlink.csv')) fs.linkSync(file, alias);
    assert.equal(run(dir, ['--output', alias, file]).status, 1);
  }
  const invalid = input(dir, '2026-10-05', 'broken');
  assert.equal(run(dir, ['--output', out, invalid]).status, 1);
  assert.equal(fs.readFileSync(out, 'utf8'), 'previous good report');
  const renamed = path.join(dir, 'renamed.csv'); fs.writeFileSync(renamed, sample);
  assert.equal(run(dir, ['--previous-month', '--output', out, renamed]).status, 1);
  assert.equal(run(dir, ['--period', '2026-10', '--output', out, renamed]).status, 0);
  assert.equal(embedded(fs.readFileSync(out, 'utf8')).reports[0].period, '2026-10');
});

test('multiple reports sort by confirmed month, skip duplicate reports, and reject conflicting corrections', t => {
  const dir = fixture(t), november = input(dir), october = input(dir, '2026-10-05');
  const reordered = sample.replace('Hold text notices sent,for the month,25\nHold text reminders notices sent ,for the month,2', 'Hold text reminders notices sent ,for the month,2\nHold text notices sent,for the month,25');
  const duplicate = input(dir, '2026-11-06', reordered, 'duplicate');
  const out = path.join(dir, 'report.html');
  const result = run(dir, ['--previous-month', '--output', out, november, october, duplicate]);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stderr, /Skipped duplicate/);
  assert.deepEqual(embedded(fs.readFileSync(out, 'utf8')).reports.map(r => r.period), ['2026-09', '2026-10']);
  const before = fs.readFileSync(out, 'utf8');
  fs.writeFileSync(duplicate, sample.replace('for the month,25', 'for the month,26'));
  const failed = run(dir, ['--previous-month', '--output', out, november, duplicate]);
  assert.equal(failed.status, 1);
  assert.match(failed.stderr, /conflicting reports/);
  assert.equal(fs.readFileSync(out, 'utf8'), before);
});

// Small DOM/event harness: no dependencies or real browser/network services.
class Element {
  constructor(tag = 'div') { this.tagName = tag; this.children = []; this.style = {}; this.events = {}; this.value = ''; this.attributes = {}; this._text = ''; this.hidden = false; }
  set textContent(value) { this._text = String(value); this.children = []; }
  get textContent() { return this._text + this.children.map(c => c.textContent).join(''); }
  append(...children) { this.children.push(...children); }
  replaceChildren(...children) { this._text = ''; this.children = children; }
  setAttribute(key, value) { this.attributes[key] = value; }
  addEventListener(type, fn) { this.events[type] = fn; }
  fire(type) { this.events[type](); }
  focus() { this.focused = true; }
}
function domHarness(data, hash, bundledScript, template) {
  const nodes = new Map(), events = {}, history = [hash]; let index = 0, current = hash;
  if (template) {
    for (const match of template.matchAll(/\bid="([^"]+)"/g)) {
      assert.ok(!nodes.has(match[1]), `duplicate template ID: ${match[1]}`);
      nodes.set(match[1], new Element());
    }
  }
  const doc = { getElementById(id) {
    if (template) assert.ok(nodes.has(id), `missing template ID: ${id}`);
    if (!nodes.has(id)) nodes.set(id, new Element());
    return nodes.get(id);
  }, createElement(tag) { return new Element(tag); }, createElementNS(namespace, tag) { return new Element(tag); } };
  const media = { matches: false, addEventListener(type, fn) { this.change = fn; } };
  const win = { location: {}, matchMedia() { return media; }, addEventListener(type, fn) { events[type] = fn; }, print() { win.printed = true; } };
  Object.defineProperty(win.location, 'hash', { get() { return current; }, set(value) { if (value === current) return; history.splice(++index); history.push(value); current = value; events.hashchange(); } });
  function move(delta) { index += delta; current = history[index]; events.hashchange(); }
  if (bundledScript) {
    doc.getElementById('dashboard-data').textContent = JSON.stringify(data);
    vm.runInNewContext(bundledScript, { window: win, document: doc, URLSearchParams });
  } else dashboard.mount(data, win, doc);
  return { doc, win, get: doc.getElementById.bind(doc), back() { move(-1); }, forward() { move(1); }, resize(compact) { media.matches = compact; media.change(); } };
}
function dashboardData() {
  const parsed = parser.parseReport(sample);
  return {
    branches: parser.branchIds(parsed.branches.map(b => b.name)),
    reports: [{ ...parser.parseReport(sample), id: 'older', source: 'older.csv', period: '2026-09' }, { ...parsed, id: 'latest', source: 'latest.csv', period: '2026-10' }],
  };
}
function tableBody(h, id) {
  // Chart values live in the additional-information section, not beside the plot.
  const container = h.get(id.endsWith('-chart') ? id.replace('-chart', '-values') : id);
  return container.children.find(node => node.tagName === 'table').children.find(node => node.tagName === 'tbody');
}
function tableRows(h, id) {
  if (id === 'comparison') {
    return h.get(id).children[0].children.filter(node => node.tagName === 'tbody').map(group => [group.children[0].textContent, ...group.children.slice(1).flatMap(row => row.children.slice(1).map(cell => cell.textContent))]);
  }
  return tableBody(h, id).children.map(row => row.children.map(cell => cell.textContent));
}

test('branch URL restores on load, updates on selection, and supports simulated Back/Forward', () => {
  const data = dashboardData(), h = domHarness(data, '#branch=novato-library&report=older&extra=kept');
  assert.equal(h.get('branch').value, 'novato-library');
  assert.equal(h.get('report').value, 'older');
  assert.equal(h.get('title').textContent, 'Novato Library');
  assert.equal(h.get('notice-total').textContent, '55');
  h.get('branch').value = 'sausalito-public-library'; h.get('branch').fire('change');
  assert.match(h.win.location.hash, /branch=sausalito-public-library/);
  assert.match(h.win.location.hash, /extra=kept/);
  assert.equal(h.get('title').textContent, 'Sausalito Public Library');
  assert.match(h.get('notice-summary').textContent, /Not reported/);
  h.back(); assert.equal(h.get('title').textContent, 'Novato Library');
  h.forward(); assert.equal(h.get('title').textContent, 'Sausalito Public Library');
  h.get('report').value = 'latest'; h.get('report').fire('change');
  assert.match(h.win.location.hash, /report=latest/);
  assert.equal(h.get('permalink').href, h.win.location.hash);
  h.get('print').fire('click'); assert.equal(h.win.printed, true);
});

test('missing/unknown URL values, branch links, absent branches, and unconfirmed periods render safely', () => {
  const data = dashboardData();
  const h = domHarness(data, '#branch=unknown&report=unknown');
  assert.equal(h.get('branch').value, 'all');
  assert.equal(h.get('report').value, 'latest');
  assert.match(h.get('status').textContent, /Unknown branch/);
  assert.match(h.get('status').textContent, /Unknown report/);
  assert.equal(tableRows(h, 'notice-chart').length, 2);
  const group = h.get('comparison').children[0].children.find(node => node.tagName === 'tbody' && node.children[0].textContent === 'Novato Library');
  const link = group.children[0].children[0].children[0];
  h.win.location.hash = link.href;
  assert.equal(h.get('title').textContent, 'Novato Library');
  data.reports[0].branches = [];
  h.win.location.hash = '#branch=novato-library&report=older';
  assert.match(h.get('status').textContent, /no reported data/);
  assert.match(h.get('notices').textContent, /Not reported/);
  data.reports.forEach(r => { r.period = null; });
  h.win.location.hash = '';
  assert.equal(h.get('branch').value, 'all');
  assert.match(h.get('period-note').textContent, /not been confirmed/);
  assert.match(h.get('trend-note').textContent, /at least two reports/);
  assert.equal(dashboard.noticeTotal({ holds: 1, reminders: 0, overdue: 2 }), 3);
  assert.equal(dashboard.noticeTotal({ holds: 1 }), undefined);
});

test('overview defaults to system totals, prior-month changes, and alphabetical branch detail', () => {
  const data = dashboardData();
  data.branches.reverse(); // Presentation must not depend on input order.
  const h = domHarness(data, '');
  assert.equal(h.get('title').textContent, 'All branches');
  assert.equal(h.get('heading-period').textContent, 'October 2026');
  assert.match(h.get('scope-note').textContent, /3 branches in this report/);
  const summaries = ['registered-summary', 'signups-summary', 'notice-summary'].map(id => h.get(id));
  assert.deepEqual(summaries.map(summary => summary.children[0].textContent), ['13', '1', '55']);
  assert.equal(summaries[0].children[1].textContent, 'No change from September 2026 (0%)');
  assert.equal(h.get('notice-total').textContent, '55');
  assert.match(h.get('notice-total-note').textContent, /counted once/);
  assert.deepEqual(tableRows(h, 'comparison').map(row => row[0]), ['Branch, With Comma', 'Novato Library', 'Sausalito Public Library']);
  assert.equal(h.get('registered-chart').children[0].tagName, 'svg');
  assert.deepEqual(tableRows(h, 'registered-chart').map(row => row[1]), ['13', '13']);
  assert.match(h.get('system-registrations').textContent, /Registered users \(snapshot\): 13/);
  assert.match(h.get('quality-summary').textContent, /2 source warning/);
  assert.equal(h.get('quality-summary').className, 'has-warnings');
  assert.match(h.get('quality').textContent, /Language counts/);
  assert.equal(h.get('report-control').hidden, false);
  assert.equal(h.get('trend-section').hidden, false);
});

test('branch view preserves unknown metrics, explicit zeros, and separately labeled system context', () => {
  const h = domHarness(dashboardData(), '#branch=sausalito-public-library');
  const system = h.get('system-registrations').textContent, keywords = h.get('keywords').textContent;
  assert.deepEqual(tableRows(h, 'registered-chart').map(row => row[1]), ['1', '1']);
  assert.match(h.get('signups-summary').textContent, /Not reported/);
  assert.ok(tableRows(h, 'signups-chart').every(row => row[1] === 'Not reported'));
  assert.ok(!h.get('signups-chart').children.some(node => node.tagName === 'svg')); // No fabricated zero points.
  assert.equal(h.get('notice-total').textContent, 'Not reported');
  assert.match(h.get('notice-total-note').textContent, /incomplete/);
  assert.match(h.get('items').textContent, /Not reported/);
  assert.match(h.get('scope-note').textContent, /System-wide keyword activity/);
  h.win.location.hash = '#branch=branch-with-comma';
  assert.equal(tableRows(h, 'notices')[0][1], '0');
  assert.equal(tableRows(h, 'notices')[0][3], '0 (prior count 0; % undefined)');
  assert.equal(h.get('notice-total').textContent, 'Not reported');
  assert.equal(h.get('system-registrations').textContent, system);
  assert.equal(h.get('keywords').textContent, keywords);
  assert.match(h.get('system-percentages').textContent, /denominator unverified/);
  h.win.location.hash = '#branch=all';
  assert.equal(tableRows(h, 'comparison').length, 3);
  assert.equal(h.get('notice-total').textContent, '55');
});

test('single October report keeps primary counts visible without an empty chart or report selector', t => {
  const dir = fixture(t), file = input(dir), out = path.join(dir, 'october.html');
  const result = run(dir, ['--period', '2026-10', '--output', out, file]);
  assert.equal(result.status, 0, result.stderr);
  const html = fs.readFileSync(out, 'utf8'), data = embedded(html);
  const js = html.match(/<script>\n(.*?)<\/script>/s)[1];
  const h = domHarness(data, '', js, html);
  assert.equal(h.get('heading-period').textContent, 'October 2026');
  assert.equal(h.get('branch').value, 'all');
  assert.equal(h.get('report-control').hidden, true);
  assert.equal(h.get('trend-section').hidden, false);
  assert.equal(h.get('notice-summary').children[0].textContent, '55');
  assert.equal(tableRows(h, 'notice-chart').length, 1);
  assert.ok(!h.get('notice-chart').children.some(node => node.tagName === 'svg'));
  assert.match(h.get('notice-chart').textContent, /Add another reporting month/);
  assert.match(h.get('period-note').textContent, /2026-10/);
  assert.ok(!h.get('period-note').textContent.includes('unconfirmed'));
  assert.match(html, /All branches · Not branch-specific/);
  assert.match(html, /\[hidden\]\{display:none!important\}/);
  const qualitySection = html.match(/<section class="detail-group" aria-labelledby="quality-heading">([\s\S]*?)<\/section>/)[1];
  assert.match(qualitySection, /id="quality"/);
  assert.ok(!qualitySection.includes('<details'));
  assert.equal(fs.readFileSync(file, 'utf8'), sample);
});

test('complete notice components supply branch comparison totals without fabricating missing counts', () => {
  const data = dashboardData();
  for (const report of data.reports) {
    delete report.branches.find(b => b.name === 'Novato Library').metrics.notice_total;
    report.warnings = [];
  }
  const h = domHarness(data, '#branch=novato-library');
  const row = tableRows(h, 'comparison').find(row => row[0] === 'Novato Library');
  assert.equal(row[5], '55');
  const missing = tableRows(h, 'comparison').find(row => row[0] === 'Sausalito Public Library');
  assert.equal(missing[5], 'Not reported');
  assert.match(h.get('quality-summary').textContent, /0 source warning/);
  assert.equal(h.get('quality-summary').className, '');
  assert.equal(dashboard.periodLabel('2026-09'), 'September 2026');
});

function variantSample() {
  return sample.split('\n').map(line => line.startsWith('.') && line.includes('TOTALS') ? line.replaceAll('.', '=') : line).join('\n')
    .replace('Hold text reminders sent for the month = 2', 'Hold text reminders sent,for the month,2')
    .replace('Novato Library, sent, for the month, this many text notices,55', 'Novato Library sent for the month, this many text notices,55')
    .replace('Total registered users for your branches = 13', 'Total registered users for your branches,13')
    .replace('Total registered barcodes = 14', 'Total registered barcodes,14')
    .replace('Total registered users for the English language is 13', 'Total registered users for the English language is,13')
    .replace('Total registered users for the Spanish language is 1', 'Total registered users for the Spanish language is,1')
    .replace('Registered users the last month = 1', 'Registered users the last month,3')
    .replace('Novato Library signed up 1 patron(s) for text notices the last month', 'Novato Library signed up,2 patron(s),for text notices the last month\n signed up 1 patron(s),for text notices the last month')
    .replaceAll('Overdue (text) items unsuccessfully renewed by patrons ,for the month,1', 'Overdue (text) items unsuccessfully renewed by patrons ,for the month,1\nOverdue (text) items renewed successfully by patrons,for the month,4')
    .replace('failed::,33.33%', 'failed:: 33.33%');
}
function namedInput(dir, month, text = sample, suffix = 'synthetic') {
  const file = path.join(dir, `sb_report_${month}_2026_${suffix}_2026-11-10_16_02_39.csv`);
  fs.writeFileSync(file, text); return file;
}

test('equals separators and CSV reminder/totals/signup variants preserve successful renewals and unattributed signups', () => {
  const text = variantSample(), report = parser.parseReport(text);
  const novato = report.branches.find(b => b.name === 'Novato Library').metrics;
  assert.equal(novato.reminders, 2); // Alias is a repeated summary, not additional activity.
  assert.equal(novato.notice_total, 55);
  assert.equal(novato.renewed, 4);
  assert.equal(report.totals.renewed, 4);
  assert.equal(report.registrations.users, 13);
  assert.equal(report.registrations.barcodes, 14);
  assert.equal(report.registrations.signups, 3);
  assert.equal(novato.signups, 2);
  assert.deepEqual(report.unattributed, { signups: 1 });
  assert.equal(report.branches.length, 3); // No invented blank-name branch.
  assert.equal(Object.values(report.percentages)[0], '33.33%');
  const proseUnknown = parser.parseReport(text.replace('signed up 1 patron(s),for text notices the last month', 'signed up 1 patron(s) for text notices the last month'));
  assert.deepEqual(proseUnknown.unattributed, { signups: 1 });
  assert.equal(report.warnings.length, 2);
  assert.ok(report.warnings.some(w => w.includes('preserved as unattributed')));
  assert.ok(!report.warnings.some(w => w.includes('unrecognized') || w.includes('signups do not reconcile')));
  assert.throws(() => parser.parseReport(text.replace('signed up,2 patron(s)', 'signed up,-2 patron(s)')), /non-negative/);
  assert.throws(() => parser.parseReport(text.replace('Total registered barcodes,14', 'Total registered barcodes,invalid')), /non-negative/);
  assert.throws(() => parser.parseReport(text.replace('successfully by patrons,for the month,4', 'successfully by patrons,for the month,-1')), /non-negative/);
  const mismatched = parser.parseReport(text.replace('Registered users the last month,3', 'Registered users the last month,4'));
  assert.ok(mismatched.warnings.some(w => w.includes('signups do not reconcile')));
  assert.throws(() => parser.parseReport(text.replace('Hold text reminders sent,for the month,2', 'Hold text reminders sent,for the month,3')), /conflicting repeated metric/);
});

test('named-month assignment is explicit, independent of generation dates, and rejects incompatible modes', t => {
  const dir = fixture(t), august = namedInput(dir, 'August', variantSample()), september = namedInput(dir, 'September'), october = namedInput(dir, 'October');
  const out = path.join(dir, 'report.html');
  assert.equal(parser.namedPeriod(august), '2026-08');
  assert.equal(parser.generatedDate(august), '2026-11-10');
  assert.equal(parser.namedPeriod('renamed.csv'), null);
  assert.throws(() => parser.namedPeriod('sb_report_Nonesuch_2026_id_2026-11-10_16_02_39.csv'), /invalid named reporting month/);
  assert.throws(() => parser.generatedDate('sb_report_August_2026_id_2026-02-30_16_02_39.csv'), /invalid filename date/);
  assert.equal(run(dir, ['--output', out, october]).status, 0);
  assert.equal(embedded(fs.readFileSync(out, 'utf8')).reports[0].period, null);
  const result = run(dir, ['--named-periods', '--output', out, october, august, september]);
  assert.equal(result.status, 0, result.stderr);
  const html = fs.readFileSync(out, 'utf8'), data = embedded(html);
  assert.deepEqual(data.reports.map(r => r.period), ['2026-08', '2026-09', '2026-10']);
  assert.ok(data.reports.every(r => r.date === '2026-11-10' && r.periodMethod === 'named'));
  const js = html.match(/<script>\n(.*?)<\/script>/s)[1];
  const h = domHarness(data, '', js, html);
  assert.equal(h.get('heading-period').textContent, 'October 2026');
  assert.match(h.get('period-note').textContent, /not the generation date/);
  assert.equal(tableRows(h, 'registered-chart').length, 3);
  assert.ok(h.get('quality').textContent.includes('unattributed'));
  for (const args of [['--named-periods', '--previous-month', october], ['--named-periods', '--period', '2026-10', october]]) assert.equal(run(dir, args).status, 2);
  assert.equal(run(dir, ['--named-periods', '--output', out, input(dir)]).status, 1);
  assert.equal(run(dir, ['--previous-month', '--output', out, august]).status, 1);
  // Same-date generation does not establish a reporting month without explicit assignment.
  assert.equal(run(dir, ['--output', out, august, october]).status, 1);
  const duplicate = namedInput(dir, 'October', sample, 'duplicate');
  assert.match(run(dir, ['--named-periods', '--output', out, october, duplicate]).stderr, /Skipped duplicate/);
  fs.writeFileSync(duplicate, sample.replace('for the month,25', 'for the month,26'));
  const before = fs.readFileSync(out, 'utf8');
  assert.equal(run(dir, ['--named-periods', '--output', out, october, duplicate]).status, 1);
  assert.equal(fs.readFileSync(out, 'utf8'), before);
});

test('month-over-month changes distinguish decline, unknown data, and undefined percentages from zero', () => {
  assert.equal(dashboard.change(81, 71).text, '+10 (+14.1%)');
  assert.equal(dashboard.change(12, 35).text, '-23 (-65.7%)');
  assert.equal(dashboard.change(241, 272).text, '-31 (-11.4%)');
  assert.equal(dashboard.change(0, 5).text, '-5 (-100%)');
  assert.equal(dashboard.change(0, 0).percent, null);
  assert.equal(dashboard.change(4, 0).delta, 4);
  assert.equal(dashboard.change(4, 0).percent, null);
  assert.match(dashboard.change(4, 0).text, /prior count 0; % undefined/);
  assert.equal(dashboard.change(undefined, 4).text, 'Not comparable');
  assert.equal(dashboard.change(4, undefined).delta, undefined);
  const reports = [{ period: '2026-08' }, { period: '2026-10' }, { period: '2026-12' }, { period: '2027-01' }];
  assert.equal(dashboard.previousReport(reports, reports[1]), undefined);
  assert.equal(dashboard.previousReport(reports, reports[3]), reports[2]);
  assert.equal(dashboard.previousReport(reports, { period: null }), undefined);
});

test('line charts break at missing months and values, preserve zeros, and use real calendar spacing', () => {
  const rows = [{ period: '2026-08', value: 0 }, { period: '2026-09', value: 10 }, { period: '2026-10', value: undefined }, { period: '2026-12', value: 5 }];
  const geometry = dashboard.chartGeometry(rows);
  assert.deepEqual(geometry.segments.map(s => s.length), [2, 1]);
  assert.equal(geometry.points[0].y, 205);
  assert.equal(geometry.points[2].y, null);
  assert.equal(geometry.points[1].x - geometry.points[0].x, (geometry.points[3].x - geometry.points[1].x) / 3);
  const gap = dashboard.chartGeometry([rows[0], rows[3]]);
  assert.deepEqual(gap.segments.map(s => s.length), [1, 1]);
  assert.ok(Number.isFinite(dashboard.chartGeometry([{ period: '2026-08', value: 0 }]).points[0].y));
});

test('growth presentation shows current/prior counts, historical warnings, and branch-specific missing data', () => {
  const data = dashboardData();
  data.reports[0].registrations = { users: 71, signups: 35 };
  data.reports[1].registrations = { users: 81, signups: 12 };
  data.reports[0].unattributed = { signups: 1 };
  data.reports[0].warnings = ['1 signup preserved as unattributed.'];
  data.reports[1].totals = { holds: 148, reminders: 19, overdue: 74 };
  data.reports[0].totals = { holds: 147, reminders: 36, overdue: 89 };
  const h = domHarness(data, '');
  assert.match(h.get('registered-summary').textContent, /10 more than September 2026 \(\+14.1%\)/);
  assert.match(h.get('signups-summary').textContent, /23 fewer than September 2026 \(-65.7%\)/);
  assert.match(h.get('notice-summary').textContent, /31 fewer than September 2026 \(-11.4%\)/);
  assert.deepEqual(tableRows(h, 'registered-chart'), [['September 2026', '71', 'Not comparable'], ['October 2026', '81', '+10 (+14.1%)']]);
  assert.match(h.get('quality').textContent, /September 2026: 1 signup preserved as unattributed/);
  const globalKeywords = h.get('keyword-chart').textContent;
  h.win.location.hash = '#branch=sausalito-public-library&report=older';
  assert.match(h.get('unattributed').textContent, /1 signup\(s\) have no branch/);
  assert.equal(h.get('signups-summary').children[0].textContent, 'Not reported');
  assert.equal(h.get('keyword-chart').textContent, globalKeywords);
  assert.match(h.get('comparison-note').textContent, /No report for the immediately preceding/);
  // A wholly missing month is never replaced by the nearest earlier report.
  data.reports[0].period = '2026-08';
  h.win.location.hash = '#branch=all&report=latest';
  assert.match(h.get('registered-summary').textContent, /Not comparable/);
  assert.match(h.get('comparison-note').textContent, /No report for the immediately preceding/);
  const svg = h.get('registered-chart').children.find(n => n.tagName === 'svg');
  assert.equal(svg.children.filter(n => n.tagName === 'polyline').length, 0);
  assert.equal(svg.attributes.role, 'img');
  assert.match(svg.attributes['aria-label'], /August 2026: 71; October 2026: 81/);
});

test('visual polish preserves neutral changes, aligns numeric tables, and highlights the selected month', () => {
  const html = fs.readFileSync(path.resolve(__dirname, '../lib/monthly-dashboard.html'), 'utf8');
  const style = html.match(/<style>([\s\S]*?)<\/style>/)[1];
  const data = dashboardData();
  data.reports[0].registrations = { users: 71, signups: 35 };
  data.reports[1].registrations = { users: 81, signups: 12 };
  const h = domHarness(data, '', undefined, html);
  assert.equal(h.get('registered-summary').children[1].textContent, '10 more than September 2026 (+14.1%)');
  assert.equal(h.get('signups-summary').children[1].textContent, '23 fewer than September 2026 (-65.7%)');
  // Increases and decreases use the same neutral presentation, not success/error colors.
  assert.equal(h.get('registered-summary').children[1].className, h.get('signups-summary').children[1].className);
  assert.match(style, /\.metric-summary span\{[^}]*color:var\(--muted\)/);
  assert.match(style, /\.numeric\{text-align:right\}/);
  for (const id of ['registered-values', 'comparison', 'notices', 'items', 'keywords', 'sources']) {
    const table = h.get(id).children.find(node => node.tagName === 'table');
    const header = table.children.find(node => node.tagName === 'thead').children[0];
    const row = tableBody(h, id).children[id === 'comparison' ? 1 : 0];
    for (const cells of [header.children, row.children]) {
      assert.notEqual(cells[0].className, 'numeric');
      assert.ok(cells.slice(1).every(cell => id === 'sources' ? cell.className !== 'numeric' : cell.className === 'numeric'));
    }
  }
  function selectedMonth() {
    const svg = h.get('registered-chart').children.find(node => node.tagName === 'svg');
    assert.equal(svg.children.filter(node => node.attributes.class === 'point current').length, 1);
    return svg.children.filter(node => node.attributes.class === 'axis-label selected').map(node => node.textContent);
  }
  assert.deepEqual(selectedMonth(), ['Oct 2026']);
  h.win.location.hash = '#report=older';
  assert.deepEqual(selectedMonth(), ['Sep 2026']);
  h.back();
  assert.deepEqual(selectedMonth(), ['Oct 2026']);
  assert.match(style, /:focus-visible\{outline:2px solid var\(--accent\)/);
  assert.ok(!/@import|url\(/i.test(style)); // No external fonts, images, or stylesheets.
  const printStyle = style.slice(style.indexOf('@media print'));
  assert.match(printStyle, /body\{[^}]*background:#fff/);
  assert.match(printStyle, /\.toolbar,\.detail-jumps\{display:none\}/);
  assert.match(printStyle, /thead th\{background:transparent\}/);
});

test('plain report stacks three primary metric sections before all supporting information', t => {
  const dir = fixture(t), first = input(dir, '2026-10-05'), second = input(dir);
  const out = path.join(dir, 'simple.html');
  const result = run(dir, ['--previous-month', '--output', out, second, first]);
  assert.equal(result.status, 0, result.stderr);
  const html = fs.readFileSync(out, 'utf8'), data = embedded(html);
  const js = html.match(/<script>\n(.*?)<\/script>/s)[1];
  const h = domHarness(data, '', js, html);
  const ordered = ['registered-metric', 'signups-metric', 'notices-metric', 'additional-details', 'activity-heading', 'keyword-metric', 'values-heading', 'breakdown-heading', 'items-heading', 'system-heading', 'branches-heading', 'quality-heading'];
  const positions = ordered.map(id => html.indexOf(`id="${id}"`));
  assert.ok(positions.every((position, i) => position > -1 && (!i || position > positions[i - 1])));
  const primary = html.slice(html.indexOf('<div id="trend-section">'), html.indexOf('<section id="additional-details"'));
  assert.equal((primary.match(/<section /g) || []).length, 3);
  for (const [metric, summary, chart] of [['registered', 'registered-summary', 'registered-chart'], ['signups', 'signups-summary', 'signups-chart'], ['notices', 'notice-summary', 'notice-chart']]) {
    const section = primary.match(new RegExp(`<section id="${metric}-metric"[^>]*>([\\s\\S]*?)<\\/section>`))[1];
    assert.ok(section.includes(`id="${summary}"`) && section.includes(`id="${chart}"`));
    assert.equal(h.get(chart).children.filter(node => node.tagName === 'svg').length, 1);
    assert.ok(!h.get(chart).children.some(node => node.tagName === 'table'));
    const valuesId = chart.replace('-chart', '-values');
    assert.ok(html.indexOf(`id="${valuesId}"`) > positions[3]);
    assert.equal(tableRows(h, chart).length, 2);
  }
  assert.ok(!html.includes('id="cards"'));
  const style = html.match(/<style>([\s\S]*?)<\/style>/)[1];
  assert.ok(!/display:\s*grid|scroll-snap|(?:min-)?height:\s*100(?:vh|svh|dvh)/.test(style));
  assert.match(style, /background:var\(--paper\)/);
  assert.equal(h.get('keyword-summary').children[0].textContent, '3');
  h.win.location.hash = '#branch=sausalito-public-library';
  assert.equal(h.get('registered-summary').children[0].textContent, '1');
  assert.equal(h.get('keyword-summary').children[0].textContent, '3');
  assert.match(h.get('quality').textContent, /Language counts/);
  for (const id of ['comparison', 'notices', 'items', 'keywords', 'sources']) assert.ok(tableBody(h, id).children.length > 0);
});

test('compact header and supporting-section jumps preserve selected branch/report and history', () => {
  const html = fs.readFileSync(path.resolve(__dirname, '../lib/monthly-dashboard.html'), 'utf8');
  const h = domHarness(dashboardData(), '#branch=novato-library&report=older', undefined, html);
  const context = html.match(/<p class="report-context">([\s\S]*?)<\/p>/)[1];
  assert.match(context, /id="heading-period"/);
  assert.match(context, /id="title"/);
  assert.ok(!html.includes('id="subtitle"'));
  assert.equal(h.get('title').textContent, 'Novato Library');
  assert.equal(h.get('heading-period').textContent, 'September 2026');
  const before = h.win.location.hash;
  for (const [button, target] of [['jump-activity', 'activity-heading'], ['jump-branches', 'branches-heading'], ['jump-sources', 'quality-heading']]) {
    assert.match(html, new RegExp(`id="${target}"[^>]*tabindex="-1"`));
    h.get(button).fire('click');
    assert.equal(h.get(target).focused, true);
    assert.equal(h.win.location.hash, before);
  }
  h.get('report').value = 'latest'; h.get('report').fire('change');
  h.get('jump-sources').fire('click');
  h.back();
  assert.equal(h.win.location.hash, before);
  assert.equal(h.get('title').textContent, 'Novato Library');
});

test('mobile charts reflow without shrinking desktop geometry or changing selection and data', () => {
  const h = domHarness(dashboardData(), '#branch=novato-library&report=older');
  const beforeHash = h.win.location.hash, beforeValues = tableRows(h, 'registered-chart');
  const plot = () => h.get('registered-chart').children.find(node => node.tagName === 'svg');
  assert.equal(plot().attributes.viewBox, '0 0 600 250');
  h.resize(true);
  assert.equal(plot().attributes.viewBox, '0 0 320 265');
  assert.equal(h.win.location.hash, beforeHash);
  assert.deepEqual(tableRows(h, 'registered-chart'), beforeValues);
  assert.deepEqual(plot().children.filter(node => node.attributes.class === 'axis-label selected').map(node => node.textContent), ['Sep', '2026']);
  const circles = plot().children.filter(node => node.tagName === 'circle');
  assert.deepEqual(circles.map(node => node.attributes.cx), ['48', '292']);
  assert.ok(circles.every(node => Number.isFinite(Number(node.attributes.cy))));
  h.win.location.hash = '#branch=novato-library&report=latest';
  assert.deepEqual(plot().children.filter(node => node.attributes.class === 'axis-label selected').map(node => node.textContent), ['Oct', '2026']);
  h.back();
  assert.equal(plot().attributes.viewBox, '0 0 320 265');
  h.resize(false);
  assert.equal(plot().attributes.viewBox, '0 0 600 250');
  assert.deepEqual(tableRows(h, 'registered-chart'), beforeValues);
  const geometry = dashboard.chartGeometry([{ period: '2026-09', value: 0 }, { period: '2026-11', value: 2 }], true);
  assert.deepEqual(geometry.segments.map(segment => segment.length), [1, 1]);
  assert.equal(geometry.points[0].y, 205);
});

test('long mobile timelines limit labels while keeping the selected month and all points', () => {
  const data = dashboardData(), baseline = data.reports[0];
  data.reports = Array.from({ length: 12 }, (_, i) => ({ ...baseline, id: `month-${i + 1}`, period: `2026-${String(i + 1).padStart(2, '0')}` }));
  const h = domHarness(data, '#report=month-2');
  h.resize(true);
  const plot = h.get('registered-chart').children.find(node => node.tagName === 'svg');
  const labels = plot.children.filter(node => node.tagName === 'text' && node.attributes.y === '232');
  assert.ok(labels.length <= 3);
  assert.equal(labels.find(node => node.attributes.class === 'axis-label selected').textContent, 'Feb');
  const xs = labels.map(node => Number(node.attributes.x)).sort((a, b) => a - b);
  assert.ok(xs.every((x, i) => !i || x - xs[i - 1] >= 75));
  assert.equal(plot.children.filter(node => node.tagName === 'circle').length, 12);
  assert.equal(plot.children.filter(node => node.attributes.class === 'point-label').length, 1);
  assert.equal(tableRows(h, 'registered-chart').length, 12);
});

test('branch comparison groups retain every metric and change in a wrapping three-column table', () => {
  const html = fs.readFileSync(path.resolve(__dirname, '../lib/monthly-dashboard.html'), 'utf8');
  const h = domHarness(dashboardData(), '', undefined, html);
  const table = h.get('comparison').children[0];
  const groups = table.children.filter(node => node.tagName === 'tbody');
  assert.equal(groups.length, 3);
  assert.equal(table.children.find(node => node.tagName === 'thead').children[0].children.length, 3);
  for (const group of groups) {
    assert.equal(group.children.length, 4);
    const heading = group.children[0].children[0];
    assert.equal(heading.attributes.scope, 'rowgroup');
    assert.equal(heading.attributes.colspan, '3');
    assert.ok(heading.children[0].href.includes('report=latest'));
    assert.deepEqual(group.children.slice(1).map(row => row.children[0].textContent), ['Registered patrons', 'New signups', 'Text notices']);
    assert.ok(group.children.slice(1).every(row => row.children.length === 3));
  }
  assert.deepEqual(tableRows(h, 'comparison').find(row => row[0] === 'Novato Library'), ['Novato Library', '12', '0 (0%)', '1', '0 (0%)', '55', '0 (0%)']);
  assert.ok(tableRows(h, 'comparison').find(row => row[0] === 'Sausalito Public Library').includes('Not reported'));
  const style = html.match(/<style>([\s\S]*?)<\/style>/)[1];
  assert.ok(!/min-width:850px/.test(style));
  assert.match(style, /#comparison th,#comparison td\{[^}]*white-space:normal/);
  assert.match(style, /#comparison table\{table-layout:fixed\}/);
});

test('headline changes use neutral conversational labels without altering compact table calculations', () => {
  assert.equal(dashboard.summaryChange(81, 71, 'September 2026'), '10 more than September 2026 (+14.1%)');
  assert.equal(dashboard.summaryChange(12, 35, 'September 2026'), '23 fewer than September 2026 (-65.7%)');
  assert.equal(dashboard.summaryChange(5, 5, 'September 2026'), 'No change from September 2026 (0%)');
  assert.equal(dashboard.summaryChange(0, 5, 'September 2026'), '5 fewer than September 2026 (-100%)');
  assert.equal(dashboard.summaryChange(4, 0, 'September 2026'), '4 more than September 2026 (percentage undefined from zero)');
  assert.equal(dashboard.summaryChange(0, 0, 'September 2026'), 'No change from September 2026 (percentage undefined from zero)');
  assert.equal(dashboard.summaryChange(undefined, 5, 'September 2026'), 'Not comparable with September 2026');
  assert.equal(dashboard.summaryChange(5, undefined, null), 'Not comparable · previous calendar month unavailable');
  assert.equal(dashboard.change(81, 71).text, '+10 (+14.1%)');
});
