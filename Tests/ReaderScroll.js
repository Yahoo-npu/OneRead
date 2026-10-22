'use strict';
const assert = require('node:assert/strict');
const {mapPosition, createController} = require('../Sources/OneRead/ReaderScroll.js');
let checks = 0;
function check(label, callback) { callback(); checks++; console.log('PASS: ' + label); }
const source = [{id:'title',top:40,height:50},{id:'image',top:120,height:300},{id:'text',top:460,height:400}];
const target = [{id:'title',top:40,height:70},{id:'image',top:140,height:300},{id:'text',top:480,height:600}];
check('scroll anchors include paragraph margins rather than reversing the gap', () => {
  assert.equal(mapPosition(90,700,900,source,target),102.5);
  assert.equal(mapPosition(0,700,900,source,target),0);
  assert.equal(mapPosition(700,700,900,source,target),900);
  assert.equal(mapPosition(270,700,900,source,target),290);
});
check('short or empty peer panes never produce negative or invalid scroll positions', () => {
  assert.equal(mapPosition(300,700,0,source,target),0);
  assert.equal(mapPosition(300,700,900,[],[]),300/700*900);
});
function fixture() {
  let queue = new Map(), id = 0;
  const calls = [];
  const frame = callback => { queue.set(++id, callback); return id; };
  const cancelFrame = token => queue.delete(token);
  let controller;
  controller = createController({frame,cancelFrame,sync: index => {
    calls.push(index);
    // A real browser can deliver the peer's scroll event several frames after the write.
    frame(() => frame(() => controller.changed(1-index)));
  }});
  return {controller,calls,frame,flush() {
    let loops = 0;
    while (queue.size) {
      assert.ok(++loops < 30,'scrolling must settle instead of entering a feedback loop');
      const batch = [...queue.values()]; queue.clear(); batch.forEach(callback=>callback());
    }
  }};
}
check('late programmatic peer scroll events cannot drive the original pane back down', () => {
  const f=fixture(); f.controller.claim(0); f.controller.changed(0); f.flush(); assert.deepEqual(f.calls,[0]);
});
check('the user can reverse direction repeatedly without changing the driver pane', () => {
  const f=fixture(); f.controller.claim(0);
  for(let i=0;i<12;i++){f.controller.changed(0);f.flush()}
  assert.deepEqual(f.calls,Array(12).fill(0));
});
check('scroll momentum is coalesced into one update per frame', () => {
  const f=fixture(); f.controller.claim(1); for(let i=0;i<30;i++)f.controller.changed(1); f.flush(); assert.deepEqual(f.calls,[1]);
});
check('only a new gesture can transfer ownership to the opposite column', () => {
  const f=fixture(); f.controller.claim(0); f.controller.changed(1); f.flush(); assert.equal(f.calls.length,0);
  f.controller.claim(1); f.controller.changed(1); f.flush(); assert.deepEqual(f.calls,[1]);
});
check('translation layout changes suspend scroll feedback until layout settles', () => {
  const f=fixture(); let restored=false; f.controller.claim(0); f.controller.suspend(); f.controller.changed(0);
  f.controller.resume(()=>restored=true); f.flush(); assert.ok(restored); assert.deepEqual(f.calls,[0]);
});
check('a new wheel gesture invalidates an older pending scroll restoration', () => {
  const f=fixture(); let restored=false; f.controller.claim(0); f.controller.suspend(); f.controller.resume(()=>restored=true);
  f.controller.claim(1); f.controller.changed(1); f.flush(); assert.equal(restored,false); assert.deepEqual(f.calls,[1]);
});
check('chapter changes cancel stale frames and do not start automatic scrolling', () => {
  const f=fixture(); f.controller.claim(0); f.controller.changed(0); f.controller.reset(); f.flush(); assert.deepEqual(f.calls,[]);
});
console.log(`All ${checks} scrolling regression checks passed`);
