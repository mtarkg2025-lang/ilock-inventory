/* SHADOW shared item-master loader. Browser-local cache only; not a central database. */
(function(){
'use strict';
const CACHE_KEY='shadow_item_master_cache_v1';
const script=document.currentScript;
const scriptUrl=script&&script.src?script.src:new URL('./shadow-master.js',location.href).href;
const SOURCE_URL=new URL('./shadow-planning/injection-database.json.gz.b64',scriptUrl).href;
async function load(options){
  options=options||{};
  let cached=null;
  try{const raw=localStorage.getItem(CACHE_KEY);if(raw){const parsed=JSON.parse(raw);if(parsed&&parsed.schemaVersion===1&&Array.isArray(parsed.items))cached=parsed;}}catch(e){}
  if(!options.refresh){
    try{
      const response=await fetch(SOURCE_URL,{cache:'no-store'});
      if(!response.ok)throw Error('HTTP '+response.status);
      const encoded=(await response.text()).trim();
      const bytes=Uint8Array.from(atob(encoded),c=>c.charCodeAt(0));
      const stream=new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
      const source=JSON.parse(await new Response(stream).text());
      if(!Array.isArray(source.columns)||!Array.isArray(source.items))throw Error('صيغة المصدر غير صحيحة');
      const items=source.items.map(row=>Object.fromEntries(source.columns.map((key,index)=>[key,row[index]]))).filter(item=>String(item.code??'').trim());
      const value={schemaVersion:1,source:'shadow-planning/injection-database.json.gz.b64',loadedAt:new Date().toISOString(),columns:source.columns,items};
      try{localStorage.setItem(CACHE_KEY,JSON.stringify(value));}catch(e){}
      return value;
    }catch(error){if(cached)return {...cached,cacheFallback:true,cacheError:error.message};throw error;}
  }
  const response=await fetch(SOURCE_URL,{cache:'no-store'});
  if(!response.ok)throw Error('HTTP '+response.status);
  const encoded=(await response.text()).trim();
  const bytes=Uint8Array.from(atob(encoded),c=>c.charCodeAt(0));
  const stream=new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
  const source=JSON.parse(await new Response(stream).text());
  if(!Array.isArray(source.columns)||!Array.isArray(source.items))throw Error('صيغة المصدر غير صحيحة');
  const items=source.items.map(row=>Object.fromEntries(source.columns.map((key,index)=>[key,row[index]]))).filter(item=>String(item.code??'').trim());
  const value={schemaVersion:1,source:'shadow-planning/injection-database.json.gz.b64',loadedAt:new Date().toISOString(),columns:source.columns,items};
  try{localStorage.setItem(CACHE_KEY,JSON.stringify(value));}catch(e){}
  return value;
}
window.SHADOW_MASTER={load,CACHE_KEY,sourceUrl:SOURCE_URL};
})();