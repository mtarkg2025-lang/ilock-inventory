/* SHADOW plan-vs-actual comparison core: pure functions, no persistence or inventory posting. */
(function(root){
'use strict';
function norm(v){return String(v==null?'':v).normalize('NFKC').toLocaleLowerCase('ar').replace(/[\u064B-\u065F\u0670\u0640]/g,'').replace(/[\s\u200f\u200e]+/g,' ').trim();}
function num(v){if(typeof v==='number')return Number.isFinite(v)?v:NaN;let s=String(v==null?'':v).trim().replace(/[٠-٩]/g,d=>String('٠١٢٣٤٥٦٧٨٩'.indexOf(d))).replace(/[۰-۹]/g,d=>String('۰۱۲۳۴۵۶۷۸۹'.indexOf(d))).replace(/[٬,]/g,'').replace(/[٫]/g,'.');if(!s)return NaN;const n=Number(s);return Number.isFinite(n)?n:NaN;}
function aggregate(rows, map){
 const out=new Map(), errors=[];
 rows.forEach((r,i)=>{
  const code=map.code>=0?String(r[map.code]??'').trim():'';
  const name=map.name>=0?String(r[map.name]??'').trim():'';
  const raw=map.qty>=0?r[map.qty]:null, qty=num(raw);
  if(!code&&!name&& (raw==null||String(raw).trim()===''))return;
  if(!code&&!name){errors.push({row:i+2,reason:'لا يوجد كود أو اسم صنف'});return;}
  if(!Number.isFinite(qty)||qty<0){errors.push({row:i+2,reason:'الكمية فارغة أو غير رقمية أو سالبة'});return;}
  const key=code?'C:'+norm(code):'N:'+norm(name);
  const label=name||code;
  const old=out.get(key)||{key,code,name:label,qty:0,rows:0};
  old.qty+=qty;old.rows++;out.set(key,old);
 });
 return {items:out,errors};
}
function compare(planRows,actualRows,planMap,actualMap){
 const p=aggregate(planRows,planMap),a=aggregate(actualRows,actualMap),keys=new Set([...p.items.keys(),...a.items.keys()]),rows=[];
 for(const key of keys){
  const plan=p.items.get(key),actual=a.items.get(key);
  rows.push({key,code:(plan&&plan.code)|| (actual&&actual.code)||'',name:(plan&&plan.name)|| (actual&&actual.name)||'',plan:plan?plan.qty:0,actual:actual?actual.qty:0,variance:(actual?actual.qty:0)-(plan?plan.qty:0),remaining:Math.max((plan?plan.qty:0)-(actual?actual.qty:0),0),over:Math.max((actual?actual.qty:0)-(plan?plan.qty:0),0),rate:plan&&plan.qty>0?(actual?actual.qty:0)/plan.qty:null,planRows:plan?plan.rows:0,actualRows:actual?actual.rows:0,planMissing:!plan,actualMissing:!actual});
 }
 rows.sort((x,y)=>x.name.localeCompare(y.name,'ar'));
 return {rows,planErrors:p.errors,actualErrors:a.errors,totals:rows.reduce((t,r)=>{t.plan+=r.plan;t.actual+=r.actual;t.variance+=r.variance;t.remaining+=r.remaining;t.over+=r.over;return t;},{plan:0,actual:0,variance:0,remaining:0,over:0})};
}
const api={norm,num,aggregate,compare};
if(typeof module!=='undefined'&&module.exports)module.exports=api;
root.SHADOWPlanActual=api;
})(typeof globalThis!=='undefined'?globalThis:this);
