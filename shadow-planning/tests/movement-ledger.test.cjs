'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const html = fs.readFileSync('shadow-planning/movement-ledger.html', 'utf8');
function extractBetween(start, end) {
  const from = html.indexOf(start);
  const to = html.indexOf(end, from);
  assert.ok(from >= 0 && to > from, 'Function block missing: ' + start);
  return html.slice(from, to).trim();
}
const validMove = extractBetween('function validMove(', 'function persist');
const signed = extractBetween('function signed(', 'function key');
const api = vm.runInNewContext(validMove + '\n' + signed + '\\n({validMove, signed})');
const base = {
  id: 'MV-TEST-1', date: '2026-10-25', type: 'استلام', code: 'REAL-CODE',
  name: 'صنف اختبار', warehouse: 'مخزن الحقن', qty: 12, unit: 'قطعة',
  doc: 'TEST-DOC-1', operator: 'اختبار', reviewer: '', note: '',
  state: 'معلق', created: '2026-10-25T10:00:00.000Z', approvedAt: null
};
assert.equal(api.validMove(base), true, 'valid movement should pass');
assert.equal(api.validMove({...base, date: 'not-a-date'}), false, 'invalid date should fail');
assert.equal(api.validMove({...base, qty: 0}), false, 'zero quantity should fail');
assert.equal(api.validMove({...base, code: ' '}), false, 'blank item code should fail');
assert.equal(api.validMove({...base, type: 'عكس حركة'}), false, 'unsupported reversal type must fail');
assert.equal(api.validMove({...base, state: 'مجهول'}), false, 'unknown status should fail');
assert.equal(api.signed({...base, type: 'استلام', qty: 10}), 10);
assert.equal(api.signed({...base, type: 'صرف', qty: 4}), -4);
assert.equal(api.signed({...base, type: 'تسوية زيادة', qty: 3}), 3);
assert.equal(api.signed({...base, type: 'تسوية عجز', qty: 2}), -2);
assert.equal(api.signed({...base, type: 'مرتجع للمخزن', qty: 5}), 5);
console.log('PASS: SHADOW movement-ledger validation and signed-quantity tests');
