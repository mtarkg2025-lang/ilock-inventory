/* SHADOW CORE — shared browser-side guardrails and navigation.
   Prototype only: this file does not provide authentication or central persistence. */
(function(){
'use strict';
const CORE={
 version:'0.2.0',
 status:'prototype-local',
 rules:[
  {id:'DATA-01',title:'مصدر الحقيقة',rule:'لا يُعرض أي رقم كحقيقة معتمدة دون مصدر ووحدة وفترة وحالة اعتماد.'},
  {id:'DATA-02',title:'عدم الاختلاق',rule:'لا تخمين للأكواد أو الأرصدة أو الأوزان أو معدلات المكونات الناقصة.'},
  {id:'MOV-01',title:'اعتماد الحركة',rule:'المسودة والمرفوضة لا تغيّر الرصيد الرسمي؛ لا تعديل صامت للحركة المعتمدة.'},
  {id:'MOV-02',title:'أثر التصحيح',rule:'التصحيح يكون بمستند جديد مرتبط بالأصل مع سبب ومراجعة.'},
  {id:'WEIGHT-01',title:'الاستلام بالوزن',rule:'الوزن يحسب كمية تقديرية فقط عندما يكون معامل الصنف/العبوة معتمدًا؛ وإلا يلزم عد أو مراجعة.'},
  {id:'PLAN-01',title:'تخطيط المكونات',rule:'لا يُحسب احتياج معتمد دون معدل مكون صالح ووحدة متوافقة وتاريخ سريان واضح.'},
  {id:'GOV-01',title:'فصل المهام',rule:'منشئ المستند لا يعتمد مستنده ذاتيًا إلا استثناء رسمي محدد ومراجع.'},
  {id:'PMP-01',title:'بوابات المشروع',rule:'لا انتقال لبوابة حرجة دون معيار قبول ودليل اختبار وموافقة صاحب الصلاحية.'},
  {id:'SEC-01',title:'الأمان',rule:'لا تضع كلمة مرور أو service-role key في المتصفح أو مستودع GitHub.'}
 ],
 links:[
  {label:'واجهة إدارة المخزون',href:'/ilock-inventory/'},
  {label:'لوحة PMO',href:'/ilock-inventory/shadow-pmo/'},
  {label:'تخطيط المخزون',href:'/ilock-inventory/shadow-planning/'},
  {label:'مقارنة الخطة والفعلي',href:'/ilock-inventory/shadow-planning/plan-vs-actual.html'},
  {label:'سجل الحركات',href:'/ilock-inventory/shadow-planning/movement-ledger.html'},
  {label:'الاستلام بالوزن',href:'/ilock-inventory/weight-receiving/'},
  {label:'مواصفة النواة',href:'/ilock-inventory/SHADOW_INVENTORY_ADVISOR/PMP_PMO_CORE_NOTE.md'},
  {label:'خريطة المصادر',href:'/ilock-inventory/SHADOW_INVENTORY_ADVISOR/KNOWLEDGE_SOURCE_MAP_PMP_PMO_AR.md'},
  {label:'خارطة التنفيذ',href:'/ilock-inventory/SHADOW_INVENTORY_ADVISOR/SHADOW_PMO_DELIVERY_ROADMAP_AR.md'}
 ],
 validateRequired:function(record,fields){const missing=(fields||[]).filter(k=>record[k]===undefined||record[k]===null||String(record[k]).trim()==='');return {ok:missing.length===0,missing};},
 safeNumber:function(value){if(value===null||value===undefined||String(value).trim()==='')return {ok:false,value:null,reason:'قيمة غير موجودة'};const n=Number(value);return Number.isFinite(n)?{ok:true,value:n}:{ok:false,value:null,reason:'قيمة غير رقمية'};},
 sourceLabel:function(status){return status==='approved'?'معتمد':status==='pending'?'معلق للمراجعة':status==='rejected'?'مرفوض':'غير معتمد/غير معروف';}
};
window.SHADOW_CORE=CORE;
function el(tag,attrs,text){const n=document.createElement(tag);Object.entries(attrs||{}).forEach(([k,v])=>{if(k==='class')n.className=v;else n.setAttribute(k,v)});if(text!==undefined)n.textContent=text;return n}
function mount(){
 if(document.getElementById('shadowCoreRibbon'))return;
 const style=el('style');style.textContent='#shadowCoreRibbon{margin:10px auto;max-width:1400px;padding:0 12px;font:13px Tahoma,Arial,sans-serif;color:#1d2b36}#shadowCoreRibbon .scr-panel{background:#fff;border:1px solid #cbd5e1;border-radius:10px;padding:10px;margin-top:8px}#shadowCoreRibbon .scr-links{display:flex;gap:7px;flex-wrap:wrap;margin-top:8px}#shadowCoreRibbon a{color:#145a74;text-decoration:underline}#shadowCoreRibbon button{font:inherit;border:1px solid #a9bacb;background:#eef4f8;color:#16364c;border-radius:7px;padding:6px 9px;cursor:pointer}#shadowCoreRibbon .scr-state{display:inline-block;background:#fff0cc;border:1px solid #e5c76e;border-radius:20px;padding:3px 8px;margin-inline-start:6px}#shadowCoreRibbon ul{margin:8px 0;padding-right:22px;line-height:1.8}';
 document.head.appendChild(style);
 const root=el('section',{id:'shadowCoreRibbon','aria-label':'نواة شادو المشتركة'});
 const row=el('div',{});
 const msg=el('span',{},'SHADOW Core v'+CORE.version+' — قواعد تحقق وتنقل مشتركة بين الواجهات');
 const state=el('span',{class:'scr-state'},'بيانات محلية منفصلة');
 const btn=el('button',{type:'button','aria-expanded':'false'},'عرض قواعد النواة');
 btn.addEventListener('click',()=>{const p=root.querySelector('.scr-panel');const show=p.hidden;p.hidden=!show;btn.setAttribute('aria-expanded',String(show));btn.textContent=show?'إخفاء قواعد النواة':'عرض قواعد النواة'});
 row.append(msg,state,document.createTextNode(' '),btn);root.appendChild(row);
 const panel=el('div',{class:'scr-panel'});panel.hidden=true;
 panel.appendChild(el('strong',{},'القواعد المشتركة'));
 const list=el('ul',{});CORE.rules.forEach(r=>list.appendChild(el('li',{},r.id+' — '+r.title+': '+r.rule)));panel.appendChild(list);
 panel.appendChild(el('strong',{},'التنقل بين وحدات SHADOW'));
 const links=el('div',{class:'scr-links'});CORE.links.forEach(l=>{const a=el('a',{href:l.href},l.label);links.appendChild(a)});panel.appendChild(links);
 panel.appendChild(el('p',{},'تنبيه تكامل: النواة توحّد قواعد التحقق والتنقل فقط. بيانات الواجهات لا تتزامن تلقائيًا، ولا توجد قاعدة مركزية مفعلة حاليًا. لا تعتبر رصيدًا أو حركة من واجهة أخرى مسجلة هنا إلا بعد استيراد ومراجعة موثقين.'));
 const header=document.querySelector('header');if(header&&header.parentNode)header.insertAdjacentElement('afterend',root);else document.body.insertAdjacentElement('afterbegin',root);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',mount);else mount();
})();