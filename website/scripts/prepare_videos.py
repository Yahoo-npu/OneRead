"""Encode the real edited captures as seekable 60fps H.264 MP4 for browser playback.
Requires macOS and the bundled encode_video.swift helper compiled with a matching SDK.
No screen capture or synthesized interface is produced here.
"""
from pathlib import Path
from PIL import Image
import json,subprocess,tempfile
root=Path(__file__).resolve().parents[1]
encoder=Path('/tmp/oneread-encode-video')
index=json.loads((root/'dist/assets/live/recording-index.json').read_text())
for row in index:
 name=row['id'];source=root/f'dist/assets/live/{name}.webp'
 if not source.exists():source=root.parent/f'.local/website-legacy-animations/{name}.webp'
 with tempfile.TemporaryDirectory(prefix=f'oneread-{name}-') as folder:
  frames=[];im=Image.open(source)
  for n in range(im.n_frames):
   im.seek(n);im.load();p=Path(folder)/f'{n:04}.png';im.convert('RGB').save(p,compress_level=1)
   frames.append({'file':str(p),'ms':im.info.get('duration',40)})
  manifest=Path(folder)/'frames.json';manifest.write_text(json.dumps(frames))
  out=root/f'dist/assets/live/{name}.mp4'
  subprocess.run([str(encoder),str(manifest),str(out)],check=True)
  row['video']={'file':out.name,'bytes':out.stat().st_size,'fps':60,'codec':'H.264','note':'60fps 输出；保留实录与原有编辑过渡，未增加原始采集细节'}
  print(name,out.stat().st_size,flush=True)
(root/'dist/assets/live/recording-index.json').write_text(json.dumps(index,ensure_ascii=False,indent=2))
