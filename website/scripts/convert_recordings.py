"""Edit real CUA captures into five smooth, palette-stable GIF demonstrations."""
from pathlib import Path
from PIL import Image, ImageOps
import json
ROOT=Path(__file__).resolve().parents[1]
RAW=ROOT.parent/'.local/website-recordings'
OUT=ROOT/'dist/assets/live'
recordings=json.loads((RAW/'manifest.json').read_text())
def rows(group,indices=None):
 r=[x for x in recordings if x['group']==group]
 return r if indices is None else [r[i] for i in indices]
def canvas(r):
 im=ImageOps.contain(Image.open(r['file']).convert('RGB'),(1440,900),Image.Resampling.LANCZOS)
 c=Image.new('RGB',(1440,900),'#f2f1ec');c.paste(im,((1440-im.width)//2,(900-im.height)//2));return c
select={'magazines':rows('magazines'),'reading':rows('reading-focus'),'word':rows('word',[0,2,3,4,5]),'clauses':rows('clauses'),'vocabulary':rows('vocabulary-sync',[0,2])}
public=[]
for group,rs in select.items():
 originals=[canvas(r) for r in rs];frames=[];durations=[]
 for i,im in enumerate(originals):
  # Actual consecutive scroll frames already carry motion. Crossfade only edits.
  if i and rs[i]['ms']>=500:
   for t in [.2,.4,.6,.8]:frames.append(Image.blend(originals[i-1],im,t));durations.append(40)
  frames.append(im);durations.append(100 if rs[i]['ms']<500 else max(1200,rs[i]['ms']))
 # One shared palette avoids inter-frame colour flicker.
 sheet=Image.new('RGB',(240*len(originals),150))
 for i,im in enumerate(originals):sheet.paste(im.resize((240,150)),(i*240,0))
 palette=sheet.quantize(colors=256,method=Image.Quantize.MEDIANCUT)
 ps=[im.quantize(palette=palette,dither=Image.Dither.NONE) for im in frames]
 ps[0].save(OUT/f'{group}.gif',save_all=True,append_images=ps[1:],duration=durations,loop=0,optimize=True,disposal=1)
 originals[0].save(OUT/f'{group}-poster.webp',quality=92)
 originals[2 if group=='word' else -1].save(OUT/f'{group}-still.webp',quality=92)
 public.append({'id':group,'frames':len(frames),'durationMs':sum(durations),'source':'本地 OneRead 实际操作采集；连续滚动和关键步骤剪辑，编辑切点使用短叠化','steps':[r['label'] for r in rs]})
 print(group,len(frames),sum(durations))
for group,index,name in [('home-new',0,'hero-shelf'),('reading',0,'hero-reader'),('word',3,'hero-word')]:
 im=Image.open(rows(group)[index]['file']).convert('RGB');im.thumbnail((1440,1000));im.save(OUT/f'{name}.webp',quality=92)
(OUT/'recording-index.json').write_text(json.dumps(public,ensure_ascii=False,indent=2))
# Only ship media used by this focused edition. Raw recordings remain local.
keep={f'{g}{ext}' for g in select for ext in ['.gif','-poster.webp','-still.webp']}|{'hero-shelf.webp','hero-reader.webp','hero-word.webp','recording-index.json'}
for p in OUT.iterdir():
 if p.is_file() and p.name not in keep:p.unlink()
