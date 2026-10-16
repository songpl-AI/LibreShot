from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import subprocess, json, shutil
R=Path(__file__).resolve().parent
OLD=R.parent/'x-demo-20261008'
W=R/'work'; W.mkdir(exist_ok=True)
OUT=R/'ready'; OUT.mkdir(exist_ok=True)
F='/System/Library/Fonts/Supplemental/Arial.ttf'; B='/System/Library/Fonts/Supplemental/Arial Bold.ttf'
def font(s,b=False): return ImageFont.truetype(B if b else F,s)
def run(args): subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y']+list(map(str,args)),check=True)
def cap(title,sub,key):
 im=Image.new('RGBA',(1280,960)); d=ImageDraw.Draw(im)
 d.rectangle((0,0,1280,88),fill='#edf1f6'); d.rectangle((0,898,1280,960),fill='#edf1f6')
 d.text((42,27),title,font=font(32,True),fill='#172333'); d.text((1100,34),'LibreShot',font=font(23,True),fill='#172333')
 d.text((42,920),sub,font=font(20),fill='#596a80'); p=W/(key+'.png'); im.save(p); return p
BASE='Free & open source · Native macOS · Real app footage'
COND='Translation: macOS 26+ · Download language packs first'
count=0
def clip(src,start,duration,title,sub=BASE,crop=None):
 global count; count+=1; p=W/f'{count:03}.mp4'; c=cap(title,sub,f'cap{count}')
 v=f'fps=30,trim=start={start}:duration={duration},setpts=PTS-STARTPTS,'+(f'crop={crop},' if crop else '')+'scale=1120:780:force_original_aspect_ratio=decrease,pad=1280:960:(ow-iw)/2:(oh-ih)/2:color=0xedf1f6'
 run(['-i',src,'-i',c,'-filter_complex',f'[0:v]{v}[v];[v][1:v]overlay=0:0:format=auto,format=yuv420p[o]','-map','[o]','-an','-r',30,'-c:v','libx264','-preset','fast','-crf',18,p]); return p
def still(src,duration,title,sub=BASE):
 global count; count+=1; im=Image.new('RGB',(1280,960),'#edf1f6'); s=Image.open(src).convert('RGBA'); s.thumbnail((1120,780)); im.paste(s,((1280-s.width)//2,(960-s.height)//2),s)
 c=Image.open(cap(title,sub,f'cap{count}')); im.paste(c,(0,0),c); png=W/f'still{count}.png'; im.save(png); p=W/f'{count:03}.mp4'
 run(['-loop',1,'-i',png,'-t',duration,'-r',30,'-an','-c:v','libx264','-preset','fast','-crf',18,'-pix_fmt','yuv420p',p]); return p
def end(): return still(OLD/'outro.png',2,'Try LibreShot. Tell us what to improve.')
def join(parts,name):
 txt=W/'concat.txt'; txt.write_text(''.join(f"file '{p.name}'\n" for p in parts)); dest=OUT/(name+'.mp4')
 run(['-f','concat','-safe',0,'-i',txt,'-c','copy','-movflags','+faststart',dest]); run(['-i',dest,'-f','null','-'])
 run(['-ss',0.2,'-i',dest,'-frames:v',1,OUT/(name+'-cover.png')]); return dest
raw=R/'raw'
join([still(R/'annotated-result.png',1.5,'A clearer screenshot. Less explaining.'),clip(raw/'daily.mov',2,7,'Number the things that need attention.'),clip(raw/'blur-arrow.mov',5,13,'Blur details. Point to the issue.'),still(R/'annotated-result.png',2,'Ready to share.'),end()],'01-launch-annotate')
join([still(OLD/'original.png',1,'Text in a screenshot…',COND),still(OLD/'translated.png',1.5,'…translated in place.',COND),clip(OLD/'raw-take-03.mov',23.5,7.7,'Translate in place.',COND,'1580:1100:160:140'),clip(OLD/'raw-take-03.mov',37.8,4.4,'Compare with the original.',COND,'1580:1100:160:140'),clip(OLD/'raw-take-03.mov',47,3,'Switch back to the translation.',COND,'1580:1100:160:140'),end()],'02-translate-in-place')
join([clip(raw/'ocr-selection.mov',6.5,6,'Select text inside a screenshot.'),clip(raw/'ocr-result.mov',0,5,'OCR turns pixels into editable text.'),clip(raw/'ocr-result.mov',5,6,'Copy the text in one click.'),end()],'03-ocr')
join([clip(raw/'customize.mov',7,9,'Hide tools you do not need.'),clip(raw/'customize.mov',16,6,'Put your tools in your preferred order.'),clip(raw/'customize.mov',33,8,'Choose your own screenshot shortcut.'),end()],'04-customize')
join([clip(raw/'pin.mov',12,7.5,'Capture a reference. Pin it on screen.'),clip(raw/'pin-drag.mov',0,6,'Keep the reference above another page.'),end()],'05-pin-reference')
print('Rendered five videos')
