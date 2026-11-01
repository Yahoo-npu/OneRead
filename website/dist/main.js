'use strict';
(()=>{
 const {scenes,mount}=window.OneReadDemo;
 const $=id=>document.getElementById(id);
 const root=$('native-demo'),stage=$('demo-stage'),viewer=$('viewer'),tabs=$('scene-tabs'),panel=$('demo-panel');
 const reduced=matchMedia('(prefers-reduced-motion: reduce)');
 let index=0,sequence=true,demonstrating=!reduced.matches,inView=false,controller=null,elapsed=0,nextStep=1,timer=null,lastTick=0,lastFocus=null,closingScroll=[];
 const marks=[0,950,2700,5000,7700];
 function fitCanvas(){root.style.setProperty('--app-scale',String(root.clientWidth/1360));}
 const canvasObserver=new ResizeObserver(fitCanvas);canvasObserver.observe(stage);canvasObserver.observe($('viewer-mount'));
 addEventListener('resize',fitCanvas,{passive:true});
 function state(){
  $('sequence-toggle').setAttribute('aria-pressed',String(sequence&&demonstrating));
  $('sequence-toggle').title='从当前功能开始连续演示';
  panel.dataset.playback=demonstrating?(sequence?'sequence':'single'):'paused';
  root.inert=true;
  root.setAttribute('aria-hidden','true');
  root.querySelector('.nr-status-text')?.setAttribute('aria-live',demonstrating?'off':'polite');
  document.querySelector('.scene-caption').setAttribute('aria-live',demonstrating?'off':'polite');
  const hint=demonstrating?(sequence?'自动演示中 · 仅播放动画':'单项循环演示 · 仅播放动画'):'已减少动态效果 · 静态预览';
  if($('demo-hint').textContent!==hint)$('demo-hint').textContent=hint;
 }
 function build(){controller?.destroy();controller=mount(root,scenes[index].id,{onInteract:()=>{},reduced});elapsed=0;nextStep=1;fitCanvas();state();}
 function select(n,focus=false,manual=false){
  index=n;if(manual){sequence=false;demonstrating=!reduced.matches;}
  [...tabs.children].forEach((b,i)=>{b.setAttribute('aria-selected',String(i===n));b.tabIndex=i===n?0:-1;});
  const scene=scenes[n];panel.setAttribute('aria-labelledby','tab-'+scene.id);
  $('scene-label').textContent=scene.label;$('scene-title').textContent=scene.title;$('scene-description').textContent=scene.description;$('scene-counter').textContent=`${String(n+1).padStart(2,'0')} / 07`;
  $('viewer-title').textContent=scene.label+' · 功能演示';
  build();
  if(!reduced.matches)root.animate([{opacity:.35},{opacity:1}],{duration:320,easing:'ease-out'});
  if(focus)tabs.children[n].focus({preventScroll:true});
  schedule();
 }
 function tick(){
  const now=performance.now();elapsed+=Math.min(now-lastTick,500);lastTick=now;
  while(nextStep<marks.length&&elapsed>=marks[nextStep])controller.step(nextStep++);
  if(elapsed>=scenes[index].duration)select(sequence?(index+1)%scenes.length:index);
 }
 function schedule(){
  const canRun=demonstrating&&!reduced.matches&&!document.hidden&&(viewer.open||inView);
  if(canRun&&!timer){lastTick=performance.now();timer=setInterval(tick,80);}
  else if(!canRun&&timer){clearInterval(timer);timer=null;}
 }
 scenes.forEach((scene,i)=>{
  const b=document.createElement('button');b.type='button';b.className='scene-tab';b.id='tab-'+scene.id;b.setAttribute('role','tab');b.setAttribute('aria-controls','demo-panel');
  const n=document.createElement('span');n.className='tab-index';n.textContent=String(i+1).padStart(2,'0');n.setAttribute('aria-hidden','true');b.append(n,scene.label);
  b.addEventListener('click',()=>select(i,false,true));
  b.addEventListener('keydown',e=>{let n=i;if(e.key==='ArrowRight')n=(i+1)%scenes.length;else if(e.key==='ArrowLeft')n=(i+scenes.length-1)%scenes.length;else if(e.key==='Home')n=0;else if(e.key==='End')n=scenes.length-1;else return;e.preventDefault();select(n,true,true);});tabs.append(b);
 });
 root.addEventListener('demo-scene',event=>{const n=scenes.findIndex(scene=>scene.id===event.detail);if(n>=0)select(n,false,true);});
 $('sequence-toggle').addEventListener('click',()=>{sequence=true;demonstrating=!reduced.matches;build();schedule();});
 function scrollPositions(){return [...root.querySelectorAll('.nr-pane,.nr-words-list,.nr-analysis,.nr-issues')].map(el=>[el,el.scrollTop]);}
 function restoreScroll(positions){positions.forEach(([el,top])=>{el.scrollTop=top;});}
 $('enlarge').addEventListener('click',()=>{
  lastFocus=document.activeElement;const positions=scrollPositions();$('viewer-mount').append(root);viewer.showModal();fitCanvas();restoreScroll(positions);$('viewer-close').focus();schedule();
 });
 $('viewer-close').addEventListener('click',()=>{closingScroll=scrollPositions();viewer.close();});
 viewer.addEventListener('cancel',()=>{closingScroll=scrollPositions();});
 viewer.addEventListener('close',()=>{stage.append(root);fitCanvas();restoreScroll(closingScroll);closingScroll=[];lastFocus?.focus({preventScroll:true});schedule();});
 new IntersectionObserver(entries=>{inView=entries[0].isIntersecting;schedule();},{threshold:0}).observe(stage);
 document.addEventListener('visibilitychange',schedule);
 reduced.addEventListener('change',e=>{document.documentElement.classList.toggle('motion-on',!e.matches);demonstrating=!e.matches;state();schedule();});
 const header=document.querySelector('header'),hero=document.querySelector('.hero');
 let queued=false;function scrollUpdate(){
  queued=false;const box=hero.getBoundingClientRect();const hidden=box.bottom<=header.offsetHeight+30;
  header.classList.toggle('nav-folded',hidden);header.inert=hidden;
  header.classList.toggle('scrolled',scrollY>15&&!hidden);
 }
 addEventListener('resize',scrollUpdate,{passive:true});
 document.querySelectorAll('.publication-flip').forEach(button=>button.addEventListener('click',()=>{
  const flipped=button.getAttribute('aria-pressed')!=='true';
  button.setAttribute('aria-pressed',String(flipped));
  button.querySelector('.publication-front').setAttribute('aria-hidden',String(flipped));
  button.querySelector('.publication-back').setAttribute('aria-hidden',String(!flipped));
 }));
 $('see-import').addEventListener('click',()=>select(0,false,true));

 addEventListener('scroll',()=>{if(!queued){queued=true;requestAnimationFrame(scrollUpdate);}},{passive:true});scrollUpdate();
 const observer=new IntersectionObserver(entries=>entries.forEach(e=>{if(e.isIntersecting){e.target.classList.add('visible');observer.unobserve(e.target);}}),{threshold:.08});document.querySelectorAll('.reveal').forEach(el=>observer.observe(el));
 document.querySelectorAll('.publication-grid,.audience-grid').forEach(group=>[...group.children].forEach((card,i)=>card.style.setProperty('--stagger',`${i*85}ms`)));
 if(!reduced.matches)document.documentElement.classList.add('motion-on');select(0);
})();
