"""Create native-resolution lossless WebP posters from user-video review frames."""
from pathlib import Path
from PIL import Image
root=Path(__file__).resolve().parents[1]
frames=root.parent/'.local/user-demo-frames'
for name in ['magazines','updates','reading','translation','word','clauses','vocabulary']:
    Image.open(frames/f'{name}-middle.png').save(root/f'dist/assets/demos/{name}-poster.webp',lossless=True,method=4)
Image.open(frames/'magazines-start.png').save(root/'dist/assets/library.webp',lossless=True,method=4)
