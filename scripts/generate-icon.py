#!/usr/bin/env python3
"""Export the selected PNG into a macOS ICNS with standard and Retina sizes."""
from pathlib import Path
import struct
import subprocess

root = Path(__file__).resolve().parent.parent
source = root / 'Sources/OneRead/AppIcon.png'
iconset = root / '.build/AppIcon.iconset'
iconset.mkdir(parents=True, exist_ok=True)
chunks = []
for tag, size, filename in [
    ('icp4', 16, 'icon_16x16.png'), ('icp5', 32, 'icon_32x32.png'),
    ('icp6', 64, 'icon_32x32@2x.png'), ('ic07', 128, 'icon_128x128.png'),
    ('ic08', 256, 'icon_256x256.png'), ('ic09', 512, 'icon_512x512.png'),
    ('ic10', 1024, 'icon_512x512@2x.png'), ('ic11', 32, 'icon_16x16@2x.png'),
    ('ic12', 64, 'icon_32x32@2x.png'), ('ic13', 256, 'icon_128x128@2x.png'),
    ('ic14', 512, 'icon_256x256@2x.png')
]:
    target = iconset / filename
    subprocess.run(['sips', '-z', str(size), str(size), str(source), '--out', str(target)], check=True, stdout=subprocess.DEVNULL)
    data = target.read_bytes()
    chunks.append(tag.encode('ascii') + struct.pack('>I', len(data) + 8) + data)
body = b''.join(chunks)
(root / 'Sources/OneRead/AppIcon.icns').write_bytes(b'icns' + struct.pack('>I', len(body) + 8) + body)
