// Deterministic scheduler regression checks; no browser or third-party packages.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
class Element{
 constructor(){this.attrs={};this.children=[];this.events={};this.style={setProperty(){}};this.dataset={};this.classList={toggle(){},add(){}};this.offsetHeight=88;this.clientWidth=940;this.open=false;}
 setAttribute(k,v){this.attrs[k]=v}getAttribute(k){return this.attrs[k]??null}
 addEventListener(k,f){(this.events[k]??=[]).push(f)}emit(k,e={}){for(const f of this.events[k]??[])f(e)}
 append(...els){for(const el of els){if(typeof el==='string'){this.children.push(el);continue;}if(el.parent)el.parent.children=el.parent.children.filter(e=>e!==el);el.parent=this;this.children.push(el);}}
 querySelectorAll(){return []}querySelector(){return null}animate(){}focus(){}getBoundingClientRect(){return {bottom:700}}showModal(){this.open=true}close(){this.open=false;this.emit('close')}
}
function setup(reduce=false){
 const ids=new Map(),get=id=>{if(!ids.has(id))ids.set(id,new Element());return ids.get(id)};
 const observers=[],ticks=new Map(),docEvents={},mediaEvents={};let now=0,token=0,current,mounts=0,destroys=0,steps=[];
 const media={matches:reduce,addEventListener(k,f){mediaEvents[k]=f}};
 const document={getElementById:get,createElement:()=>new Element(),hidden:false,activeElement:new Element(),documentElement:new Element(),querySelector:()=>new Element(),querySelectorAll:()=>[],addEventListener(k,f){docEvents[k]=f}};
 const context={window:{},document,matchMedia:()=>media,performance:{now:()=>now},setInterval:f=>{ticks.set(++token,f);return token},clearInterval:id=>ticks.delete(id),ResizeObserver:class{constructor(f){}observe(){}},IntersectionObserver:class{constructor(f){this.f=f}observe(el){observers.push({el,f:this.f})}unobserve(){}},addEventListener(){},requestAnimationFrame(){},scrollY:0};
 vm.runInNewContext(fs.readFileSync('website/dist/native-content.js','utf8'),context);
 vm.runInNewContext(fs.readFileSync('website/dist/native-demo.js','utf8'),context);
 context.window.OneReadDemo.mount=(root,id,opts)=>{mounts++;current={id,opts};return {step:n=>steps.push([id,n]),destroy:()=>destroys++}};
 vm.runInNewContext(fs.readFileSync('website/dist/main.js','utf8'),context);
 const observe=on=>observers.find(o=>o.el===get('demo-stage')).f([{isIntersecting:on}]);
 const advance=ms=>{for(let t=0;t<ms;t+=80){now+=80;for(const fn of [...ticks.values()])fn();}};
 return {get,observe,advance,document,docEvents,media,mediaEvents,current:()=>current,mounts:()=>mounts,destroys:()=>destroys,steps,ticks,scenes:context.window.OneReadDemo.scenes};
}
let env=setup();env.observe(true);
for(let i=0;i<env.scenes.length;i++){assert.equal(env.current().id,env.scenes[i].id);env.advance(env.scenes[i].duration);}
assert.equal(env.current().id,'magazines');assert.equal(env.ticks.size,1);assert.equal(env.destroys(),env.mounts()-1);
console.log('PASS: seven native scenes advance in order, wrap, and dispose old controllers');
env.get('scene-tabs').children[4].emit('click');env.advance(11000);assert.equal(env.current().id,'word');assert.equal(env.get('demo-panel').dataset.playback,'single');
env.current().opts.onInteract();const count=env.mounts();env.advance(30000);assert.ok(env.mounts()>count);assert.equal(env.ticks.size,1);assert.equal(env.get('demo-panel').dataset.playback,'single');assert.equal(env.get('native-demo').inert,true);assert.equal(env.get('native-demo').getAttribute('aria-hidden'),'true');
console.log('PASS: selected scene loops; canvas stays inert and interaction callbacks do not interrupt playback');
env.get('sequence-toggle').emit('click');env.observe(false);env.advance(20000);assert.equal(env.current().id,'word');env.observe(true);env.advance(11000);assert.equal(env.current().id,'clauses');
env.document.hidden=true;env.docEvents.visibilitychange();const hiddenCount=env.mounts();env.advance(20000);assert.equal(env.mounts(),hiddenCount);env.document.hidden=false;env.docEvents.visibilitychange();
console.log('PASS: offscreen and background pause; resuming continues the selected sequence');
const beforeModal=env.mounts();env.get('enlarge').emit('click');assert.equal(env.get('viewer-mount').children[0],env.get('native-demo'));env.get('viewer-close').emit('click');assert.equal(env.get('demo-stage').children[0],env.get('native-demo'));assert.equal(env.mounts(),beforeModal);
console.log('PASS: enlargement moves the existing UI and preserves its state');
env=setup(true);env.observe(true);env.advance(30000);assert.equal(env.ticks.size,0);assert.equal(env.mounts(),1);env.get('scene-tabs').children[0].emit('keydown',{key:'End',preventDefault(){}});assert.equal(env.current().id,'vocabulary');assert.equal(env.ticks.size,0);
console.log('PASS: reduced motion stays static, with keyboard scene selection available');
