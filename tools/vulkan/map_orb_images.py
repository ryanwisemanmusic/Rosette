#!/usr/bin/env python3
"""Coarse, reproducible glare/red masks of supplied screenshots; no rendering proof."""
import argparse
from collections import deque
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def classify(data, width, height):
    if len(data) != width*height*3: raise ValueError('RGB extent mismatch')
    white = bytearray(width*height); red = 0
    for i in range(width*height):
        r,g,b = data[i*3:i*3+3]
        white[i] = r >= 240 and g >= 240 and b >= 240
        red += r >= 230 and r-g >= 80 and r-b >= 80
    white_count = sum(white); components = []
    for i in range(len(white)):
        if not white[i]: continue
        white[i] = 0; queue = deque([i]); count = 0
        x0=x1=i%width; y0=y1=i//width
        while queue:
            at=queue.popleft(); x,y=at%width,at//width; count+=1
            x0=min(x0,x);x1=max(x1,x);y0=min(y0,y);y1=max(y1,y)
            for nx,ny in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
                if 0 <= nx < width and 0 <= ny < height:
                    k=ny*width+nx
                    if white[k]:white[k]=0;queue.append(k)
        if count >= 8:components.append({'pixels':count,'box':[x0,y0,x1-x0+1,y1-y0+1]})
    return {'width':width,'height':height,'white_samples':white_count,'red_samples':red,
            'white_percent':100*white_count/(width*height),'red_percent':100*red/(width*height),
            'regions':sorted(components,key=lambda x:-x['pixels'])[:6]}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',required=True,type=Path);p.add_argument('images',nargs='+',type=Path);a=p.parse_args()
    out=a.out.resolve()
    if out.exists():p.error('Use a fresh evidence directory')
    out.mkdir(parents=True);ffmpeg=Path(shutil.which('ffmpeg')).resolve()
    m={'schema':'rosette-orb-regions-v1','images':[],'source_hashes':{str(Path(__file__).resolve()):sha(__file__)},'tool_hashes':{str(ffmpeg):sha(ffmpeg)}}
    for i,image in enumerate(a.images):
        image=image.resolve(strict=True);header=image.read_bytes()[:24]
        if header[:8]!=b'\x89PNG\r\n\x1a\n':raise ValueError('PNG required')
        width,height=struct.unpack('>II',header[16:24]);h=round(height*320/width)
        raw=out/f'{i}.rgb';log=out/f'{i}.log'
        cmd=[str(ffmpeg),'-hide_banner','-loglevel','error','-hwaccel','none','-i',str(image),'-vf',f'scale=320:{h}:flags=neighbor','-frames:v','1','-f','rawvideo','-pix_fmt','rgb24',str(raw)]
        with log.open('wb') as stream:r=subprocess.run(cmd,stderr=stream,stdout=stream,timeout=30)
        if r.returncode:raise ValueError(log.read_text())
        m['images'].append({'path':str(image),'sha256':sha(image),'source_dimensions':[width,height],
                            'analysis':classify(raw.read_bytes(),320,h),'command':cmd,'returncode':r.returncode,
                            'raw':str(raw),'raw_sha256':sha(raw),'log':str(log),'log_sha256':sha(log)})
    m['scope']='Nearest-neighbor 320-pixel screenshot sampling: white RGB >=240, red R>=230 and R-G/R-B>=80; boxes are coarse connected regions, not bloom attribution or reference-image error.'
    (out/'manifest.json').write_text(json.dumps(m,indent=2)+'\n')
    print([(Path(x['path']).name,x['analysis']['white_percent'],x['analysis']['red_percent']) for x in m['images']])
if __name__=='__main__':main()
