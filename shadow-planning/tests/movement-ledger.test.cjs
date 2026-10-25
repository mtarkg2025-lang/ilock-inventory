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
const key = extractBetween('function key(', 'function balanceRows');
const resolver = extractBetween('function resolveMasterItem(', 'function updateMasterItem');
const norm = "function norm(s){return String(s??'').trim().toLocaleLowerCase().replace(/[\\sـ]+/g,'')}";
const api = vm.runInNewContext(validMove + '\n' + signed + '\n' + norm + '\n' + key + '\n({validMove, signed, key})');
const base = {
  id: 'MV-TEST-1', date: '2026-10-25', type: 'استلام', code: 'REAL-CODE',
  name: 'صنف اختبار', warehouse: 'مخزن الحقن', location: 'منطقة أ', qty: 12, unit: 'قطعة',
  doc: 'TEST-DOC-1', operator: 'اختبار', reviewer: '', note: '',
  state: 'معلق', created: '2026-10-25T10:00:00.000Z', approvedAt: null
};
assert.equal(api.validMove(base), true, 'valid movement should pass');
const master = [{code:'OFF-1',name:'صنف رسمي',unit:'قطعة'},{code:'OFF-2',name:'صنف آخر',unit:'كجم'}];
assert.equal(api.resolveMasterItem('OFF-1', master).status, 'ok', 'unique complete official item should resolve');
assert.equal(api.resolveMasterItem('OFF-X', master).status, 'not-found', 'unknown official code must fail');
assert.equal(api.resolveMasterItem('OFF-1', [...master, master[0]]).status, 'ambiguous', 'duplicate code must fail closed');
assert.equal(api.resolveMasterItem('OFF-3', [{code:'OFF-3',name:'',unit:'قطعة'}]).status, 'incomplete', 'missing master name/unit must fail closed');
assert.equal(api.validMove({...base, date: 'not-a-date'}), false, 'invalid date should fail');
assert.equal(api.validMove({...base, qty: 0}), false, 'zero quantity should fail');
assert.equal(api.validMove({...base, code: ' '}), false, 'blank item code should fail');
assert.equal(api.validMove({...base, location: ''}), false, 'blank storage location should fail');
assert.equal(api.validMove({...base, location: undefined}), true, 'legacy records without location remain readable');
assert.notEqual(api.key(base), api.key({...base, location: 'منطقة ب'}), 'different internal locations must have separate balances');
assert.equal(api.key({...base, location: 'منطقة أ'}), api.key({...base, location: 'منطقة أ'}), 'same item, warehouse, location and unit share a balance');
assert.equal(api.validMove({...base, type: 'عكس حركة'}), false, 'unsupported reversal type must fail');
assert.equal(api.validMove({...base, state: 'مجهول'}), false, 'unknown status should fail');
assert.equal(api.signed({...base, type: 'استلام', qty: 10}), 10);
assert.equal(api.signed({...base, type: 'صرف', qty: 4}), -4);
assert.equal(api.signed({...base, type: 'تسوية زيادة', qty: 3}), 3);
assert.equal(api.signed({...base, type: 'تسوية عجز', qty: 2}), -2);
assert.equal(api.signed({...base, type: 'مرتجع للمخزن', qty: 5}), 5);
console.log('PASS: SHADOW movement-ledger validation and signed-quantity tests');
