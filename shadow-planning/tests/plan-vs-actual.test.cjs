'use strict';
const assert=require('node:assert/strict');
const {aggregate,compare,num,norm}=require('../plan-vs-actual-core.js');

assert.equal(num('١٢٣'),123);
assert.equal(num('۱۲۳٫۵'),123.5);
assert.equal(num('1,250.5'),1250.5);
assert.equal(norm(' فيش  ـ  أبيض '),norm('فيش أبيض'));

// SheetJS reads spreadsheet rows as positional arrays; keep the test fixture
// faithful to the real import shape rather than passing objects to an array reader.
const r=compare(
 [['A1','فيشة',100],['B2','مشترك',50]],
 [['A1','فيشة',80],['B2','مشترك',60],['C3','صنف إضافي',5]],
 {code:0,name:1,qty:2},{code:0,name:1,qty:2}
);
assert.equal(r.totals.plan,150);
assert.equal(r.totals.actual,145);
assert.equal(r.totals.variance,-5);
assert.equal(r.rows.find(x=>x.code==='A1').remaining,20);
assert.equal(r.rows.find(x=>x.code==='B2').over,10);
assert.equal(r.rows.find(x=>x.code==='C3').planMissing,true);

// Duplicate lines with the same official code must aggregate, not overwrite.
const duplicates=aggregate([['A1','فيشة',10],['A1','فيشة',15]],{code:0,name:1,qty:2});
assert.equal(duplicates.items.get('C:a1').qty,25);
assert.equal(duplicates.items.get('C:a1').rows,2);

const bad=aggregate([['X','صنف سالب',-2],['Y','صنف نصي','abc']],{code:0,name:1,qty:2});
assert.equal(bad.errors.length,2);
assert.equal(aggregate([['','','']],{code:0,name:1,qty:2}).errors.length,0);
console.log('PASS: Arabic/Western number parsing, normalized labels, totals, variance, remaining, overproduction, unmatched items, duplicate aggregation, invalid quantities');
