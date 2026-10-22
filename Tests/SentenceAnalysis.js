const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
class Element {
  constructor() { this.children = []; this.textContent = ''; this.className = ''; this.hidden = false; this.classList = {toggle() {}}; }
  appendChild(node) { this.children.push(node); }
  replaceChildren() { this.children = []; }
}
const nodes = new Map();
const document = {createElement: () => new Element(), getElementById: id => {
  if (!nodes.has(id)) nodes.set(id, new Element()); return nodes.get(id);
}};
const html = fs.readFileSync('Sources/OneRead/Reader.html', 'utf8');
const code = html.slice(html.indexOf('function prepareSelectionMode('), html.indexOf('function applySelectionState('));
const context = vm.createContext({document, popup: new Element()});
vm.runInContext(code, context);
context.prepareSelectionMode('Although he was tired, he finished the book.', true);
assert.equal(nodes.get('selection-title').textContent, '长难句解析 · ⌘T');
assert.equal(nodes.get('selection-collect').hidden, true);
context.renderSentenceAnalysis({translation:'中文译文', backbone:'he finished the book', components:[{label:'主语',text:'<img src=x>',explanation:'动作执行者'}],clauses:[],grammar:[{label:'一般过去时',text:'finished',explanation:'已完成的动作'}]});
const root = nodes.get('sentence-analysis');
assert.equal(root.children.length, 6);
assert.equal(root.children[2].children[1].children[1].textContent, '<img src=x>');
assert(root.children[3].children[1].textContent.includes('未发现从句'));
context.prepareSelectionMode('reader');
assert.equal(nodes.get('selection-title').textContent, '划词翻译');
assert.equal(root.children.length, 0);
assert.equal(nodes.get('selection-collect').hidden, false);
console.log('PASS: sentence popup renders all sections as text, handles absent clauses and resets when switching to a word');

context.prepareSelectionMode('Although he was tired, he finished the book.');
assert.equal(nodes.get('selection-title').textContent, '划词翻译');
const events = {};
const hovered = {dataset:{sentence:'s1'},getClientRects:()=>[{left:10,right:300,top:20,bottom:50}],getBoundingClientRect:()=>({left:10,right:300,top:20,bottom:50})};
let target = hovered, opened;
const shortcutDocument = {
  addEventListener:(name, handler)=>{events[name]=handler;},
  documentElement:{addEventListener:(name, handler)=>{events[name]=handler;}},
  elementFromPoint:()=>({closest:()=>target})
};
const shortcutContext = vm.createContext({document:shortcutDocument, window:{}, payload:{sentences:[{id:'s1',original:'The original English sentence.',translation:'中文译文。'}]}, flows:[{contains:node=>node===hovered}],preview:{open:false},openSelection:(...args)=>{opened=args;}});
vm.runInContext(html.slice(html.indexOf('let readerPointer = null;'), html.indexOf("document.addEventListener('mouseup'")),shortcutContext);
assert.equal(shortcutContext.window.analyzeHoveredSentence(),false);
events.pointermove({clientX:30,clientY:35});
assert.equal(shortcutContext.window.analyzeHoveredSentence(),true);
assert.equal(opened[0],'The original English sentence.');
assert.equal(opened[3],true);assert.equal(opened[4],'s1');
target=null;assert.equal(shortcutContext.window.analyzeHoveredSentence(),false);
events.pointerleave();assert.equal(shortcutContext.window.analyzeHoveredSentence(),false);
target=hovered;assert.equal(shortcutContext.window.analyzeHoveredSentence(30,35),true);
console.log('PASS: only explicit sentence mode opens analysis; hover shortcut maps either column to original English and ignores empty space');

const pronunciationHTML = html.slice(html.indexOf('<div id="pronunciation"'), html.indexOf('<div id="dictionary-details"'));
assert.equal((pronunciationHTML.match(/<button\b/g) || []).length, 1);
assert(pronunciationHTML.includes('<svg'));
assert(!pronunciationHTML.includes('慢速') && !pronunciationHTML.includes('停止') && !pronunciationHTML.includes('美式'));
let spoken;
const speaker = {dataset:{accent:'en-US'}};
const speechContext = vm.createContext({document:{querySelectorAll:()=>[speaker]},post:(action,payload)=>{spoken={action,payload};}});
vm.runInContext(html.slice(html.indexOf("document.querySelectorAll('[data-accent]')"), html.indexOf("window.addEventListener('resize'")), speechContext);
speaker.onclick();
assert.equal(spoken.action,'speak');assert.equal(spoken.payload.accent,'en-US');assert.equal(spoken.payload.slow,false);
console.log('PASS: selection popup has one icon-only US pronunciation control with normal-speed playback');
