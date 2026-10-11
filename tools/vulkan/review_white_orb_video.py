#!/usr/bin/env python3
"""Read-only CPU video frame extraction; visual notes remain human observations."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from graphics_support.iso import hash_file


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('video', type=Path)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--notes', type=Path, required=True, help='JSON list of seconds/note objects')
    a=p.parse_args();out=a.out.resolve()
    if out.exists():p.error('Use a new output directory')
    video=a.video.resolve(strict=True)
    frames=json.loads(a.notes.read_text())
    if not 1 <= len(frames) <= 8:p.error('Use 1–8 reviewed frames')
    ffprobe=shutil.which('ffprobe');ffmpeg=shutil.which('ffmpeg')
    if not ffprobe or not ffmpeg:p.error('ffmpeg/ffprobe unavailable')
    metadata=json.loads(subprocess.check_output([ffprobe,'-v','error','-show_format','-show_streams','-of','json',video]))
    duration=float(metadata['format']['duration'])
    if any(type(f['seconds']) not in (int,float) or not 0<=f['seconds']<duration or not isinstance(f['note'],str) for f in frames):p.error('Invalid frame timestamp or note')
    out.mkdir(parents=True)
    commands=[]
    for i,frame in enumerate(frames):
        path=out/f'frame-{i}.png';log=out/f'frame-{i}.log'
        command=[ffmpeg,'-hide_banner','-loglevel','error','-hwaccel','none','-ss',str(frame['seconds']),'-i',str(video),'-frames:v','1',str(path)]
        with log.open('wb') as stream:subprocess.run(command,stdout=stream,stderr=subprocess.STDOUT,check=True,timeout=60)
        commands.append({'command':command,'returncode':0,'log':str(log),'sha256':hash_file(log)})
        frame.update(path=str(path),sha256=hash_file(path))
    result={'schema':'rosette-white-orb-video-v1','video':str(video),'video_sha256':hash_file(video),
            'duration':duration,'frames':frames,'commands':commands,
            'source_hashes':{str(Path(__file__).resolve()):hash_file(Path(__file__))},
            'tool_hashes':{str(Path(t).resolve()):hash_file(Path(t)) for t in (ffmpeg,ffprobe)},
            'scope':'Extracted recording frames; human visual notes, no image correctness or runtime FPS certification.'}
    (out/'manifest.json').write_text(json.dumps(result,indent=2)+'\n')
    print(f'{len(frames)} frames extracted; video remains unchanged')

if __name__=='__main__':main()
