'use strict';
(()=>{
 const reduced=matchMedia('(prefers-reduced-motion: reduce)');
 const tabs=document.getElementById('scene-tabs');
 let indicatorFrame=0;
 function positionIndicator(){
  cancelAnimationFrame(indicatorFrame);indicatorFrame=requestAnimationFrame(()=>{
   const selected=tabs.querySelector('[aria-selected="true"]');if(!selected)return;
   tabs.style.setProperty('--active-x',selected.offsetLeft+'px');tabs.style.setProperty('--active-width',selected.offsetWidth+'px');
   const left=selected.offsetLeft,right=left+selected.offsetWidth;
   if(left<tabs.scrollLeft||right>tabs.scrollLeft+tabs.clientWidth)tabs.scrollTo({left:Math.max(0,left-(tabs.clientWidth-selected.offsetWidth)/2),behavior:reduced.matches?'instant':'smooth'});
  });
 }
 new MutationObserver(positionIndicator).observe(tabs,{subtree:true,attributes:true,attributeFilter:['aria-selected'],childList:true});
 if(typeof ResizeObserver!=='undefined')new ResizeObserver(positionIndicator).observe(tabs);
 positionIndicator();
 const desk=document.getElementById('reading-desk');
 let tiltFrame=0;
 desk.addEventListener('pointermove',e=>{
  if(reduced.matches||e.pointerType==='touch')return;
  const bounds=desk.getBoundingClientRect(),x=(e.clientX-bounds.left)/bounds.width-.5,y=(e.clientY-bounds.top)/bounds.height-.5;
  cancelAnimationFrame(tiltFrame);tiltFrame=requestAnimationFrame(()=>{desk.style.setProperty('--tilt-x',(x*3)+'deg');desk.style.setProperty('--tilt-y',(-y*3)+'deg');});
 });
 function resetDesk(){cancelAnimationFrame(tiltFrame);desk.style.removeProperty('--tilt-x');desk.style.removeProperty('--tilt-y');}
 desk.addEventListener('pointerleave',resetDesk);reduced.addEventListener('change',resetDesk);
})();
