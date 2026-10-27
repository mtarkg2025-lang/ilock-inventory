const CACHE_NAME="shadow-inventory-v3";
const APP_FILES=["./offline.html","./manifest.webmanifest","./shadow-icon.svg"];
self.addEventListener("install",event=>{event.waitUntil(caches.open(CACHE_NAME).then(cache=>cache.addAll(APP_FILES)).then(()=>self.skipWaiting()))});
self.addEventListener("activate",event=>{event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key.startsWith("shadow-inventory-")&&key!==CACHE_NAME).map(key=>caches.delete(key)))).then(()=>self.clients.claim()))});
self.addEventListener("fetch",event=>{const req=event.request;if(req.method!=="GET"||new URL(req.url).origin!==self.location.origin)return;event.respondWith(caches.match(req).then(cached=>cached||fetch(req).then(response=>{if(response&&response.ok){const copy=response.clone();caches.open(CACHE_NAME).then(cache=>cache.put(req,copy))}return response}).catch(()=>caches.match("./offline.html"))))});
