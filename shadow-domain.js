/* SHADOW DOMAIN CORE — deterministic inventory rules.
 * Browser + Node compatible. No network, storage, auth, or database side effects.
 * Server-side database constraints remain authoritative for multi-user operation.
 */
(function(root,factory){
  const api=factory();
  if(typeof module==='object'&&module.exports) module.exports=api;
  if(root) root.SHADOW_DOMAIN=api;
})(typeof globalThis!=='undefined'?globalThis:this,function(){
  'use strict';
  const VERSION='1.0.0';
  const TYPES=Object.freeze({RECEIPT:'receipt',ISSUE:'issue',ADJUSTMENT_IN:'adjustment_in',ADJUSTMENT_OUT:'adjustment_out',TRANSFER:'transfer',RETURN:'return'});
  const STATES=Object.freeze({DRAFT:'draft',PENDING:'pending',APPROVED:'approved',REJECTED:'rejected',REVERSED:'reversed'});
  const TRANSITIONS=Object.freeze({draft:['pending'],pending:['approved','rejected','draft'],approved:['reversed'],rejected:['draft'],reversed:[]});
  const round=(n,d=3)=>Math.round((n+Number.EPSILON)*Math.pow(10,d))/Math.pow(10,d);
  function result(ok,code,message,details){return {ok,code,message,details:details||null};}
  function number(v,label){
    if(v===null||v===undefined||String(v).trim()==='')return {ok:false,error:label+' غير مدخل'};
    const n=Number(v);return Number.isFinite(n)?{ok:true,value:n}:{ok:false,error:label+' ليس رقمًا صالحًا'};
  }
  function calculatePieces(input){
    const mode=input&&input.mode;
    if(mode==='count'){
      const q=number(input.quantity,'العدد');
      if(!q.ok||q.value<=0)return result(false,'INVALID_COUNT',q.error||'العدد يجب أن يكون أكبر من صفر');
      return result(true,'COUNT_OK','عدد مباشر',{quantity:round(q.value,3),basis:'actual_count',estimated:false});
    }
    if(mode!=='weight')return result(false,'UNKNOWN_METHOD','طريقة الحساب غير معروفة');
    const net=number(input.netWeightKg,'الوزن الصافي بالكيلوجرام');
    const unit=number(input.unitWeightG,'وزن القطعة بالجرام');
    if(!net.ok||net.value<=0)return result(false,'INVALID_NET_WEIGHT',net.error||'الوزن الصافي يجب أن يكون موجبًا');
    if(!unit.ok||unit.value<=0)return result(false,'INVALID_UNIT_WEIGHT',unit.error||'وزن القطعة يجب أن يكون موجبًا ومعتمدًا');
    const raw=net.value*1000/unit.value;
    return result(true,'ESTIMATE_ONLY','ناتج تقديري بالوزن؛ يحتاج اعتماد/عد حسب سياسة المصنع',{quantity:round(raw,3),unrounded:raw,basis:'weight_estimate',estimated:true});
  }
  function validateMovement(m,ctx){
    const errors=[];
    if(!m||!m.type||!Object.values(TYPES).includes(m.type))errors.push('نوع الحركة غير صحيح');
    if(!m||!m.itemId)errors.push('الصنف مطلوب');
    const q=number(m&&m.quantity,'الكمية');
    if(!q.ok)errors.push(q.error);else if(q.value<=0)errors.push('الكمية يجب أن تكون أكبر من صفر');
    if(m&&m.type==='transfer'){
      if(!m.fromWarehouseId||!m.toWarehouseId)errors.push('مخزن المصدر والوجهة مطلوبان للتحويل');
      if(m.fromWarehouseId===m.toWarehouseId)errors.push('لا يمكن التحويل إلى المخزن نفسه');
    }
    if(m&&m.type==='issue'&&q.ok&&ctx&&Number.isFinite(ctx.available)&&q.value>ctx.available)errors.push('الرصيد المتاح غير كافٍ');
    if(m&&m.type==='adjustment_out'&&q.ok&&ctx&&Number.isFinite(ctx.available)&&q.value>ctx.available&&!ctx.allowNegative)errors.push('التسوية ستنتج رصيدًا سالبًا؛ يلزم استثناء مخول وسبب');
    return result(errors.length===0,errors.length?'MOVEMENT_INVALID':'MOVEMENT_VALID',errors.join('؛ ')||'بيانات الحركة صالحة',{errors});
  }
  function signedQuantity(m){
    if(m.direction===1||m.direction===-1)return Number(m.quantity)*m.direction;
    if(m.type==='receipt'||m.type==='adjustment_in'||m.type==='return')return Number(m.quantity);
    if(m.type==='issue'||m.type==='adjustment_out')return -Number(m.quantity);
    return 0;
  }
  function balance(lines,filter){
    return round((lines||[]).filter(x=>!filter||filter(x)).reduce((s,x)=>s+signedQuantity(x),0),3);
  }
  function canTransition(from,to,actor,doc){
    if(!TRANSITIONS[from]||!TRANSITIONS[from].includes(to))return result(false,'INVALID_TRANSITION','انتقال الحالة غير مسموح');
    if(to==='approved'&&doc&&doc.createdBy&&actor&&doc.createdBy===actor)return result(false,'SELF_APPROVAL','لا يجوز اعتماد المستخدم لمستنده');
    if(to==='reversed'&&doc&&doc.status!=='approved')return result(false,'NOT_APPROVED','لا يمكن عكس مستند غير معتمد');
    return result(true,'TRANSITION_OK','انتقال الحالة صالح');
  }
  function makePackageId(sequence,when){
    if(!Number.isInteger(sequence)||sequence<1)throw new Error('تسلسل العبوة يجب أن يكون عددًا صحيحًا موجبًا');
    const d=when?new Date(when):new Date();
    if(Number.isNaN(d.getTime()))throw new Error('تاريخ غير صالح');
    const date=d.getFullYear().toString()+String(d.getMonth()+1).padStart(2,'0')+String(d.getDate()).padStart(2,'0');
    return 'PK-'+date+'-'+String(sequence).padStart(7,'0');
  }
  function mergeById(existing,incoming,identityFields){
    const current=Array.isArray(existing)?existing:[],fresh=Array.isArray(incoming)?incoming:[];
    const map=new Map(current.map(x=>[x.id,x])),added=[],duplicates=[],conflicts=[];
    for(const row of fresh){
      if(!row||!row.id){conflicts.push({row,reason:'معرف السجل مفقود'});continue;}
      if(map.has(row.id)){
        const old=map.get(row.id);
        const same=(identityFields||[]).every(k=>old[k]===row[k]);
        if(same)duplicates.push(row.id);else conflicts.push({id:row.id,reason:'المعرف نفسه يحمل بيانات مختلفة'});
        continue;
      }
      map.set(row.id,row);added.push(row);
    }
    return {rows:Array.from(map.values()),added,duplicates,conflicts};
  }
  function productionRequirement(planQty,usagePerUnit){
    const p=number(planQty,'كمية الخطة'),u=number(usagePerUnit,'معدل المكون');
    if(!p.ok||p.value<=0)return result(false,'INVALID_PLAN_QTY',p.error||'كمية الخطة يجب أن تكون موجبة');
    if(!u.ok||u.value<=0)return result(false,'INVALID_USAGE',u.error||'معدل المكون يجب أن يكون موجبًا');
    return result(true,'REQUIREMENT_OK','احتياج حسابي قبل الاعتماد',{quantity:round(p.value*u.value,6),approved:false});
  }
  function daysOfCover(available,dailyDemand){
    const a=number(available,'المتاح'),d=number(dailyDemand,'الاستهلاك اليومي');
    if(!a.ok||a.value<0)return result(false,'INVALID_AVAILABLE',a.error||'المتاح لا يمكن أن يكون سالبًا');
    if(!d.ok||d.value<=0)return result(false,'NO_VALID_DEMAND',d.error||'لا يمكن حساب التغطية دون استهلاك يومي موجب موثوق');
    return result(true,'COVER_OK','تغطية محسوبة',{days:round(a.value/d.value,2)});
  }
  return Object.freeze({VERSION,TYPES,STATES,TRANSITIONS,calculatePieces,validateMovement,signedQuantity,balance,canTransition,makePackageId,mergeById,productionRequirement,daysOfCover,round});
});