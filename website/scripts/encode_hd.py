"""Native-resolution, High-quality animated WebP from real OneRead captures."""
from pathlib import Path
from PIL import Image
import json
import numpy as np
ROOT=Path(__file__).resolve().parents[1];RAW=ROOT.parent/'.local/website-recordings';OUT=ROOT/'dist/assets/live'
r=json.loads((RAW/'manifest.json').read_text())
def rows(g,indices=None):
 a=[x for x in r if x['group']==g];return a if indices is None else [a[i] for i in indices]
clips={'magazines':rows('magazines'),'reading':rows('reading-hd'),'word':rows('word',[0,2,3,4,5]),'clauses':rows('clauses'),'vocabulary':rows('vocabulary-sync',[0,2])}
def scroll_mid(previous,current):
 # Align each actual column independently. Translate existing pixels between captures;
 # retain the fixed toolbar and sidebar, and expose the next frame at the bottom.
 middle=previous.copy()
 for left,right in [(542,1629),(1631,2720)]:
  a=np.asarray(previous.convert('L'))[280:1450,left+80:right-80:4].astype(np.int16)
  b=np.asarray(current.convert('L'))[280:1450,left+80:right-80:4].astype(np.int16)
  shift=min(range(0,65),key=lambda d:float(np.mean(np.abs(a[d:]-b[:len(b)-d]))) if d else float(np.mean(np.abs(a-b))))
  half=round(shift/2)
  if half:
   middle.paste(previous.crop((left,105+half,right,1628)),(left,105))
   middle.paste(current.crop((left,1628-half,right,1628)),(left,1628-half))
 return middle
index=[]
for name,rs in clips.items():
 originals=[Image.open(x['file']).convert('RGB') for x in rs];frames=[];dur=[]
 for i,im in enumerate(originals):
  # Short, 60fps editorial dissolves only at cuts. No tweened or redrawn UI.
  if i and rs[i]['ms']>=500:
   for k in range(1,9):frames.append(Image.blend(originals[i-1],im,k/9));dur.append(16)
  if i and rs[i]['ms']<500:
   # 25fps original scrolling -> 50fps pixel-aligned presentation.
   frames.append(scroll_mid(originals[i-1],im));dur.append(20)
   frames.append(im);dur.append(20)
  else:
   frames.append(im);dur.append(max(1500,rs[i]['ms']))
 frames[0].save(OUT/f'{name}.webp',save_all=True,append_images=frames[1:],duration=dur,loop=0,quality=95,method=4,minimize_size=True)
 originals[0].save(OUT/f'{name}-poster.webp',lossless=True,method=3)
 originals[2 if name=='word' else -1].save(OUT/f'{name}-still.webp',lossless=True,method=3)
 index.append({'id':name,'resolution':list(originals[0].size),'frames':len(frames),'durationMs':sum(dur),'format':'native-resolution animated WebP, quality 95; stills lossless','source':'OneRead 实机采集；连续滚动 50fps（25fps 实录与像素对齐中间帧）；编辑切点短叠化约 60fps'})
 print(name,originals[0].size,len(frames),(OUT/f'{name}.webp').stat().st_size,flush=True)
for g,i,n in [('home-new',0,'hero-shelf'),('reading',0,'hero-reader'),('word',3,'hero-word')]:Image.open(rows(g)[i]['file']).convert('RGB').save(OUT/f'{n}.webp',lossless=True,method=3)
(OUT/'recording-index.json').write_text(json.dumps(index,ensure_ascii=False,indent=2))
