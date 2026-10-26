'use strict';
const assert=require('node:assert/strict');
const {aggregate,compare,num,norm}=require('./plan-vs-actual-core.js');
assert.equal(num('١٢٣'),123);
assert.equal(num('۱۲۳٫۵'),123.5);
assert.equal(num('1,250.5'),1250.5);
assert.equal(norm(' فيش  ـ  أبيض '),norm('فيش أبيض'));
const r=compare(
 [{code:'A1',name:'فيشة',qty:100},{code:'B2',name:'مشترك',qty:50}],
 [{code:'A1',name:'فيشة',qty:80},{code:'B2',name:'مشترك',qty:60},{code:'C3',name:'صنف إضافي',qty:5}],
 {code:0,name:1,qty:2},{code:0,name:1,qty:2}
);
assert.equal(r.totals.plan,150);
assert.equal(r.totals.actual,145);
assert.equal(r.totals.variance,-5);
assert.equal(r.rows.find(x=>x.code==='A1').remaining,20);
assert.equal(r.rows.find(x=>x.code==='B2').over,10);
assert.equal(r.rows.find(x=>x.code==='C3').planMissing,true);
const bad=aggregate([{code:'X',name:'x',qty:-2},{code:'Y',name:'y',qty:'abc'}],{code:0,name:1,qty:2});
assert.equal(bad.errors.length,2);
console.log('PASS: Arabic/Western number parsing, normalized labels, totals, variance, remaining, overproduction, unmatched items, invalid quantities');
