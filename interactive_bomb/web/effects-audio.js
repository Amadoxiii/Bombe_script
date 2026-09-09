// Sons originaux locaux ; chaque observateur entend une seule voix par événement.
(() => {
const allowed=new Set(['explosive','bio','nuke','emp']);
const buffers=new Map(),voices=new Set(),seen=new Set();
let context,master,generation=0;
const clamp=(x,a,b)=>Math.max(a,Math.min(b,Number(x)||0));
function audioContext(){
 if(!context){
  context=new (window.AudioContext||window.webkitAudioContext)();
  master=context.createDynamicsCompressor();
  master.threshold.value=-8;master.knee.value=8;master.ratio.value=12;
  master.attack.value=.003;master.release.value=.2;master.connect(context.destination);
 }
 return context;
}
function stop(){
 generation++;
 for(const voice of voices){try{voice.stop()}catch(e){}}
 voices.clear();seen.clear();
}
async function play(d){
 if(!allowed.has(d.kind)||typeof d.key!=='string'||seen.has(d.key))return;
 seen.add(d.key);if(seen.size>128)seen.delete(seen.values().next().value);
 const mine=generation,ctx=audioContext();
 if(ctx.state==='suspended')await ctx.resume();
 if(!buffers.has(d.kind))buffers.set(d.kind,fetch('audio/'+d.kind+'.wav')
  .then(r=>{if(!r.ok)throw Error('audio missing');return r.arrayBuffer()})
  .then(bytes=>ctx.decodeAudioData(bytes)));
 const buffer=await buffers.get(d.kind);
 if(mine!==generation)return;
 if(voices.size>=8){const oldest=voices.values().next().value;oldest.stop();voices.delete(oldest);}
 const source=ctx.createBufferSource(),gain=ctx.createGain(),pan=ctx.createStereoPanner();
 source.buffer=buffer;gain.gain.value=clamp(d.volume,0,1);pan.pan.value=clamp(d.pan,-1,1);
 source.connect(gain);gain.connect(pan);pan.connect(master);
 voices.add(source);
 source.onended=()=>{voices.delete(source);source.disconnect();gain.disconnect();pan.disconnect();};
 source.start();
}
function geiger(d){
 const ctx=audioContext();
 if(ctx.state==='suspended'){ctx.resume().catch(()=>{});return;}
 if(voices.size>=8)return;
 const source=ctx.createBufferSource(),gain=ctx.createGain();
 const buffer=ctx.createBuffer(1,Math.floor(ctx.sampleRate*.018),ctx.sampleRate),data=buffer.getChannelData(0);
 for(let i=0;i<data.length;i++)data[i]=(Math.random()*2-1)*Math.exp(-i/data.length*8);
 source.buffer=buffer;gain.gain.value=clamp(d.volume,0,.4);
 source.connect(gain);gain.connect(master);voices.add(source);
 source.onended=()=>{voices.delete(source);source.disconnect();gain.disconnect();};
 source.start();
}
window.addEventListener('message',({data:d})=>{
 if(!d||typeof d!=='object')return;
 if(d.action==='bomb_fx')play(d).catch(()=>{}); // le son ne bloque jamais le jeu
 else if(d.action==='bomb_geiger'){try{geiger(d)}catch(e){}}
 else if(d.action==='bomb_fx_stop')stop();
});
window.addEventListener('pagehide',stop);
})();
