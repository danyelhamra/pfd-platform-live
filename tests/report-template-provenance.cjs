// Compare the migrated template data with an independently supplied original source.
// Usage: node tests/report-template-provenance.cjs /path/to/original/public/report.html
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const originalPath = process.argv[2];
if (!originalPath) throw new Error('Supply the original PFD report.html path.');
const html = fs.readFileSync(originalPath, 'utf8');
const start = html.indexOf('const categories=');
const end = html.indexOf("const KEY='pfd-reports-v3-'");
assert(start >= 0 && end > start, 'Original definition boundaries must exist');
const original = vm.runInNewContext(html.slice(start, end) + ';({templates,behaviours,exercises})', {}, { timeout: 1000 });
const current = JSON.parse(fs.readFileSync(require.resolve('../lib/report-templates.json'), 'utf8'));
assert.deepEqual(current, JSON.parse(JSON.stringify(original)));
assert.equal(Object.keys(current.templates).length, 5);
assert.equal(Object.values(current.templates).flatMap(t => Object.values(t.categories).flat()).length, 75);
console.log('PASS: all 5 template definitions, 75 questions, category/notes text, behaviours and progress exercises exactly match the original source.');
