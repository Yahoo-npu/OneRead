// Exercise the actual pointer choreography with a deterministic clock.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('website/dist/native-demo.js','utf8');
const choreography=source.slice(source.indexOf('  const pointerTravel='),source.indexOf('  const interact='));
let now=0,actions=0;const timers=[],classes=new Set();
const pointer={style:{},offsetWidth:24,classList:{add:k=>classes.add(k),remove:k=>classes.delete(k)}};
const target={getBoundingClientRect:()=>({left:100,top:50,width:40,height:20})};
const app={getBoundingClientRect:()=>({left:0,top:0,width:1360,height:848})};
const context={q:s=>s==='.nr-pointer'?pointer:s==='.nr-app'?app:s==='.missing'?null:target,reduced:{matches:false},later:(fn,delay)=>timers.push({at:now+delay,fn}),action:()=>{assert.ok(classes.has('nr-click'),'response must coincide with click pulse');actions++;}};
vm.runInNewContext(choreography+'\ndemonstrateClick(".target",action);',context);
function advance(to){while(true){timers.sort((a,b)=>a.at-b.at);if(!timers.length||timers[0].at>to)break;const task=timers.shift();now=task.at;task.fn();}now=to;}
assert.equal(actions,0);assert.ok(Math.abs(parseFloat(pointer.style.left)-117)<.001);assert.ok(Math.abs(parseFloat(pointer.style.top)-58)<.001);
advance(359);assert.equal(actions,0);assert.equal(classes.has('nr-click'),false);
advance(360);assert.equal(actions,1);assert.ok(classes.has('nr-click'));
advance(780);assert.equal(classes.has('nr-click'),false);
vm.runInNewContext('demonstrateClick(".target",action)',context);advance(1140);assert.equal(actions,2);advance(1560);assert.equal(classes.has('nr-click'),false);
vm.runInNewContext('demonstrateClick(".missing",action)',context);assert.equal(timers.length,0);
console.log('PASS: response waits for cursor arrival, shares the click pulse, and repeated clicks reset without looping');
// New-issue playback must use the notification's direct-import action once.
const runStart=source.indexOf('   run=n=>{',source.indexOf("if(id==='magazines'||id==='updates'){"));
const runEnd=source.indexOf('\n  }else if',runStart);
const clicks=[];let imports=0;
const updateContext={id:'updates',q:selector=>({click(){assert.equal(selector,'.nr-import-update');imports++;}}),demonstrateClick:(selector,action)=>{clicks.push(selector);action();}};
vm.runInNewContext(source.slice(runStart,runEnd).replace('run=n=>','var run=n=>')+'\n[1,2,3,4].forEach(run);',updateContext);
assert.deepEqual(clicks,['.nr-import-update']);assert.equal(imports,1);
console.log('PASS: new-issue animation clicks Import this issue once, without journal switching or importing an older issue');
// Completing a new-issue import opens the reader in the same animation scene.
const finishStart=source.indexOf('function finishImport('),finishEnd=source.indexOf('\n   function startImport',finishStart);
const elements=new Map();let rendered=null,status='';
const finishContext={id:'updates',busy:true,journal:0,journals:[['经济学人','The Economist']],dates:[['2026.10.24']],reader:()=>'<reader>',shell:(html,reading)=>{rendered={html,reading};},q:s=>{if(!elements.has(s))elements.set(s,{});return elements.get(s);},announce:s=>status=s};
vm.runInNewContext(source.slice(finishStart,finishEnd)+'\nfinishImport(0);',finishContext);
assert.deepEqual(rendered,{html:'<reader>',reading:true});assert.equal(elements.get('.nr-appname').textContent,'The Economist.2026.10.24');assert.equal(elements.get('.nr-pointer').hidden,true);assert.equal(status,'已打开 经济学人 · 2026.10.24');assert.equal(finishContext.busy,false);
console.log('PASS: new-issue import opens the reader with the imported issue title, without returning to the shelf');
