'use strict';

const crypto = require('node:crypto');
const path = require('node:path');

const METRICS = {
  'Hold text notices sent': 'holds',
  'Hold text reminders notices sent': 'reminders',
  'Hold text reminders sent': 'reminders',
  'Overdue text notices sent': 'overdue',
  'Overdue items eligible for renewal text notices sent': 'eligible',
  'Overdue items ineligible for renewal text notices sent': 'ineligible',
  'Overdue (text) items unsuccessfully renewed by patrons': 'failed',
  'Overdue (text) items renewed successfully by patrons': 'renewed',
};

// The upstream format is line-oriented CSV interspersed with prose, not a table.
function csvRow(line, number) {
  const fields = [];
  let field = '', quoted = false, closed = false;
  for (let i = 0; i < line.length; i++) {
    const char = line[i];
    if (quoted) {
      if (char === '"' && line[i + 1] === '"') { field += '"'; i++; }
      else if (char === '"') { quoted = false; closed = true; }
      else field += char;
    } else if (char === ',') {
      fields.push(field.trim()); field = ''; closed = false;
    } else if (char === '"' && !field.trim() && !closed) {
      field = ''; quoted = true;
    } else if ((closed && char.trim()) || char === '"') {
      throw new Error(`line ${number}: malformed CSV quoting`);
    } else field += char;
  }
  if (quoted) throw new Error(`line ${number}: unterminated CSV quote (multiline fields are unsupported)`);
  fields.push(field.trim());
  return fields;
}

function count(value, number) {
  if (!/^\d+$/.test(value) || !Number.isSafeInteger(Number(value))) {
    throw new Error(`line ${number}: expected a non-negative safe integer`);
  }
  return Number(value);
}

function put(target, key, value, number) {
  if (Object.hasOwn(target, key) && target[key] !== value) {
    throw new Error(`line ${number}: conflicting repeated metric ${key}`);
  }
  target[key] = value;
}

function parseReport(text) {
  const branches = new Map(), totals = {}, keywords = Object.create(null), registrations = {}, percentages = {};
  const warnings = [], unattributed = {};
  let section = '', current = null;
  const branch = name => {
    if (!name) throw new Error('empty branch name');
    if (!branches.has(name)) branches.set(name, { name, metrics: {} });
    return branches.get(name).metrics;
  };
  function signup(name, value, number) {
    const total = count(value, number);
    if (name && name.trim()) put(branch(name.trim()), 'signups', total, number);
    else {
      put(unattributed, 'signups', total, number);
      warnings.push(`Line ${number}: ${total} signup(s) have no branch; preserved as unattributed.`);
    }
  }
  const lines = text.replace(/^\uFEFF/, '').split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim(), n = i + 1;
    if (!line) continue;
    if (/^(?:\.{3,}|={3,})/.test(line)) {
      current = null;
      if (line.includes('TOTALS OF REGISTERED PATRON BY BRANCH')) section = 'registered';
      else if (line.includes('TOTALS BY BRANCH')) section = 'branch-totals';
      else if (line.includes('FREQUENCY OF KEYWORD USAGE')) section = 'keywords';
      else if (/TOTALS/.test(line)) section = 'totals';
      else section = '';
      continue;
    }
    let match;
    if ((match = line.match(/^Hold text reminders sent for the month =\s*(.+)$/))) {
      if (!current) throw new Error(`line ${n}: reminder summary outside a branch`);
      put(current, 'reminders', count(match[1], n), n);
      continue;
    }
    if ((match = line.match(/^(\S+) was used (.+) times\.$/))) {
      if (section !== 'keywords') throw new Error(`line ${n}: keyword outside keyword section`);
      put(keywords, match[1], count(match[2], n), n); continue;
    }
    const registrationPatterns = [
      [/^Total registered users for your branches = (.+)$/, 'users'],
      [/^Total registered barcodes = (.+)$/, 'barcodes'],
      [/^Total registered users for the English language is (.+)$/, 'english'],
      [/^Total registered users for the Spanish language is (.+)$/, 'spanish'],
      [/^Registered users the last month = (.+)$/, 'signups'],
    ];
    const registration = registrationPatterns.find(([pattern]) => pattern.test(line));
    if (registration) {
      put(registrations, registration[1], count(line.match(registration[0])[1], n), n); continue;
    }
    if ((match = line.match(/^(?:(.*?) )?signed up (\S+) patron\(s\) for text notices the last month$/))) {
      signup(match[1], match[2], n); continue;
    }
    if (line === 'No Patron Initiated Cancellation of Notice Service') continue;
    if (section === 'totals' && line.startsWith('Percentage of overall overdue (text) items where renewal ')) {
      const percentage = line.match(/^(Percentage of overall overdue \(text\) items where renewal .+?::)\s*,?\s*(.*?)$/);
      if (!percentage || !/^\d+(?:\.\d+)?%$/.test(percentage[2]) || Number(percentage[2].slice(0, -1)) > 100) throw new Error(`line ${n}: malformed percentage`);
      put(percentages, percentage[1], percentage[2], n); continue;
    }
    const row = csvRow(line, n);
    const csvRegistrations = {
      'Total registered users for your branches': 'users',
      'Total registered barcodes': 'barcodes',
      'Total registered users for the English language is': 'english',
      'Total registered users for the Spanish language is': 'spanish',
      'Registered users the last month': 'signups',
    };
    if (Object.hasOwn(csvRegistrations, row[0])) {
      if (row.length !== 2) throw new Error(`line ${n}: malformed registration total`);
      put(registrations, csvRegistrations[row[0]], count(row[1], n), n); continue;
    }
    if (row.length === 3 && (match = row[0].match(/^(?:(.*?) )?signed up$/)) && row[2] === 'for text notices the last month') {
      const amount = row[1].match(/^(\S+) patron\(s\)$/);
      if (!amount) throw new Error(`line ${n}: malformed signup count`);
      signup(match[1], amount[1], n); continue;
    }
    if (row.length === 2 && (match = row[0].match(/^(?:(.*?) )?signed up (\S+) patron\(s\)$/)) && row[1] === 'for text notices the last month') {
      signup(match[1], match[2], n); continue;
    }
    if (row[0] === 'Branch::') {
      if (row.length !== 2 || !row[1]) throw new Error(`line ${n}: malformed branch header`);
      section = 'branch'; current = branch(row[1]); continue;
    }
    if (Object.hasOwn(METRICS, row[0])) {
      if (row.length !== 3 || row[1] !== 'for the month') throw new Error(`line ${n}: malformed metric row`);
      const target = section === 'branch' ? current : section === 'totals' ? totals : null;
      if (!target) throw new Error(`line ${n}: metric outside branch/totals section`);
      put(target, METRICS[row[0]], count(row[2], n), n); continue;
    }
    if (section === 'branch-totals' && row.length === 5 && row[1] === 'sent' && row[2] === 'for the month' && row[3] === 'this many text notices') {
      put(branch(row[0]), 'notice_total', count(row[4], n), n); continue;
    }
    if (section === 'branch-totals' && row.length === 3 && (match = row[0].match(/^(.+?) sent for the month$/)) && row[1] === 'this many text notices') {
      put(branch(match[1]), 'notice_total', count(row[2], n), n); continue;
    }
    if (section === 'registered' && row.length === 4 && row[1] === 'has' && row[3] === 'registered patrons for text notices') {
      put(branch(row[0]), 'registered', count(row[2], n), n); continue;
    }
    // Do not echo unknown source text: future reports may contain private data.
    warnings.push(`Line ${n}: unrecognized content omitted; review the input format.`);
  }
  if (!branches.size || ![...branches.values()].some(b => Object.keys(b.metrics).length)) {
    throw new Error('no supported branch data found');
  }
  for (const [key, value] of Object.entries(totals)) {
    const values = [...branches.values()].map(b => b.metrics[key]).filter(v => v !== undefined);
    if (values.length && values.reduce((a, b) => a + b, 0) !== value) {
      warnings.push(`Reported branch values for ${key} do not reconcile with the system total; missing values remain unknown.`);
    }
  }
  for (const b of branches.values()) {
    const m = b.metrics;
    if (['holds', 'reminders', 'overdue', 'notice_total'].every(k => Object.hasOwn(m, k)) && m.holds + m.reminders + m.overdue !== m.notice_total) {
      warnings.push(`Notice components differ from the reported total for ${b.name}.`);
    }
  }
  if (['users', 'english', 'spanish'].every(k => Object.hasOwn(registrations, k)) && registrations.english + registrations.spanish !== registrations.users) {
    warnings.push('Language counts do not sum to registered users; populations may overlap. No language shares are calculated.');
  }
  if (registrations.signups !== undefined) {
    const branchSignups = [...branches.values()].reduce((sum, b) => sum + (b.metrics.signups || 0), 0);
    if (branchSignups + (unattributed.signups || 0) !== registrations.signups) {
      warnings.push('Reported branch and unattributed signups do not reconcile with the system total; omitted values remain unknown.');
    }
  }
  return { unattributed, branches: [...branches.values()].sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0), totals, registrations, keywords, percentages, warnings };
}

const MONTHS = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'];
function namedParts(filename) {
  return path.basename(filename).match(/^sb_report_([A-Za-z]+)_(\d{4})_[A-Za-z0-9_-]+_(\d{4}-\d{2}-\d{2})_\d{2}_\d{2}_\d{2}\.csv$/);
}
function namedPeriod(filename) {
  const parts = namedParts(filename);
  if (!parts) return null;
  const month = MONTHS.indexOf(parts[1].toLowerCase()) + 1;
  const period = `${parts[2]}-${String(month).padStart(2, '0')}`;
  if (!month || !validPeriod(period)) throw new Error('invalid named reporting month');
  return period;
}
function generatedDate(filename) {
  const match = path.basename(filename).match(/^sb_generate_monthly_report_[A-Za-z0-9_-]+_(\d{4}-\d{2}-\d{2})_\d{2}_\d{2}_\d{2}\.csv$/);
  const value = match ? match[1] : namedParts(filename)?.[3];
  if (!value) return null;
  const date = new Date(`${value}T00:00:00Z`);
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== value) throw new Error('invalid filename date');
  return value;
}

function validPeriod(value) { return /^\d{4}-(0[1-9]|1[0-2])$/.test(value) && !value.startsWith('0000-'); }
function previousMonth(date) {
  const [year, month] = date.split('-').map(Number);
  const result = month === 1 ? `${String(year - 1).padStart(4, '0')}-12` : `${String(year).padStart(4, '0')}-${String(month - 1).padStart(2, '0')}`;
  if (!validPeriod(result)) throw new Error('cannot determine previous month');
  return result;
}
function digest(value) { return crypto.createHash('sha256').update(value).digest('hex').slice(0, 16); }
function branchIds(names) {
  const bases = names.map(name => name.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'branch');
  // Reserve "all" for the overview, and give colliding names stable identities.
  return names.map((name, i) => ({ name, id: bases[i] === 'all' || bases.filter(base => base === bases[i]).length > 1 ? `${bases[i]}-${digest(name)}` : bases[i] }));
}
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  return value;
}
function serialize(value) {
  return JSON.stringify(value).replace(/</g, '\\u003c').replace(/&/g, '\\u0026').replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
}

module.exports = { parseReport, csvRow, generatedDate, namedPeriod, validPeriod, previousMonth, branchIds, digest, canonical, serialize };
