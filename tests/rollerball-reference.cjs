// Execute the actual browser brush in a minimal DOM to produce a cross-language oracle.
const fs = require('fs'), vm = require('vm');
const source = fs.readFileSync('tools/rollerball-remote/brush.js', 'utf8');
const context = new Proxy({}, { get: () => () => {} });
const elements = new Map();
const values = {size:8,pressure:.45,speed:240,power:2.6,response:25,pool:.65};
function element(id) {
  if (!elements.has(id)) elements.set(id, { value:values[id], style:{}, dataset:{},
    classList:{ toggle(){}, add(){}, remove(){} }, addEventListener(){},
    hasPointerCapture:()=>false, getContext:()=>context, getBoundingClientRect:()=>({left:0,top:0,width:500,height:700}) });
  return elements.get(id);
}
const sandbox = { console, Math, performance:{now:()=>2000}, requestAnimationFrame:()=>1,
  cancelAnimationFrame(){}, setTimeout(){}, clearTimeout(){},
  ResizeObserver:class { observe(){} }, window:{addEventListener(){}},
  document:{ getElementById:element, createElement:()=>element(Symbol()), querySelectorAll:()=>[], addEventListener(){} } };
vm.createContext(sandbox);
vm.runInContext(source, sandbox);
const sequences = [
 [{x:0,y:0,t:1000},{x:10,y:3,t:1016},{x:60,y:9,t:1032},{x:64,y:10,t:1050},{kind:'tick',t:1120},{kind:'tick',t:1180}],
 [{x:5,y:6,t:1000,pressure:.3},{x:15,y:10,t:1012,pressure:.7},{x:15,y:10,t:1020,pressure:.9},{x:40,y:30,t:1030,pressure:.2}],
 [{x:0,y:0,t:1000},{x:0,y:0,t:1001},{kind:'tick',t:1100},{kind:'tick',t:1700}],
 [{x:0,y:0,t:1000},{x:100,y:100,t:1000},{x:150,y:200,t:1400},{x:160,y:180,t:1500}]
];
const traces = [];
for (const events of sequences) {
 sandbox.events = events;
 const trace = vm.runInContext(`(() => {
   const p=events[0], usePressure=p.pressure!==undefined, pressure=usePressure?calibratedPressure(p.pressure):settings.pressure;
   const r=radiusAt(0,settings,pressure);
   active={id:1,color:ink,params:{...settings},usePressure,pressure,points:[{...p,r}],radius:r,velocity:0,prev:p,lastMotion:p.t,visualTime:p.t,pool:null};
   for(const e of events.slice(1)) {
     if(e.kind==='tick') tick(e.t);
     else move({pointerId:1,clientX:e.x,clientY:e.y,timeStamp:e.t,pressure:e.pressure===undefined?undefined:calibratedPressure(e.pressure)},e.pressure!==undefined);
   }
   const endTime=events[events.length-1].t+30;
   const end=active.points[active.points.length-1];
   finish({pointerId:1,clientX:end.x,clientY:end.y,timeStamp:endTime},true);
   return {events,endTime,points:strokes[strokes.length-1].points,pool:strokes[strokes.length-1].pool};
 })()`, sandbox);
 traces.push(trace);
}
process.stdout.write(JSON.stringify(traces));
