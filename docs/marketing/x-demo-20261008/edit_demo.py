from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import subprocess
root=Path(__file__).resolve().parent
regular='/System/Library/Fonts/Supplemental/Arial.ttf'
bold='/System/Library/Fonts/Supplemental/Arial Bold.ttf'
def font(size, heavy=False): return ImageFont.truetype(bold if heavy else regular,size)
def caption(title, subtitle, name):
    im=Image.new('RGBA',(1280,960),(0,0,0,0)); d=ImageDraw.Draw(im)
    d.rectangle((0,0,1280,84),fill='#edf1f6'); d.rectangle((0,900,1280,960),fill='#edf1f6')
    d.text((52,24),title,font=font(32,True),fill='#172333')
    d.text((52,923),subtitle,font=font(18),fill='#596a80')
    d.text((1114,30),'LibreShot',font=font(22,True),fill='#172333')
    im.save(root/name)
def still(img,title,subtitle,name):
    im=Image.new('RGB',(1280,960),'#edf1f6')
    source=Image.open(root/img).convert('RGBA'); source.thumbnail((1120,740))
    im.paste(source,((1280-source.width)//2,120+(740-source.height)//2),source)
    caption(title,subtitle,'temp-caption.png'); im.paste(Image.open(root/'temp-caption.png'),(0,0),Image.open(root/'temp-caption.png'))
    im.save(root/name)
base='Free & open source · Native macOS · Real app footage'
condition='Translation: macOS 26+ · Download language packs first · Real app footage'
still('original.png','Text inside a screenshot…',condition,'intro-before.png')
still('translated.png','…translated right where it was.',condition,'intro-after.png')
caption('Capture. Annotate.',base,'caption-annotate.png')
caption('Translate in place.',condition+' · 1.4x playback','caption-translate.png')
caption('Switch between original and translation.',condition,'caption-compare.png')
out=Image.new('RGB',(1280,960),'#edf1f6'); d=ImageDraw.Draw(out)
d.text((110,270),'LibreShot',font=font(106,True),fill='#172333')
d.text((116,410),'Free. Open source. Native macOS.',font=font(38),fill='#172333')
d.text((116,510),'Try it. Tell us what to improve.',font=font(30),fill='#596a80')
d.text((116,665),'github.com/songpl-AI/LibreShot',font=font(29),fill='#172333')
out.save(root/'outro.png')
def run(args):subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y']+args,check=True)
def static(img,seconds,name):
    run(['-loop','1','-i',str(root/img),'-t',str(seconds),'-r','30','-c:v','libx264','-preset','fast','-crf','18','-pix_fmt','yuv420p',str(root/name)])
def clip(start,duration,rate,cap,name):
    vf=f'[0:v]setpts=(PTS-STARTPTS)/{rate},crop=1580:1100:160:140,scale=1060:738,pad=1280:960:110:112:color=0xedf1f6[v];[v][1:v]overlay=0:0:format=auto,format=yuv420p[out]'
    run(['-ss',str(start),'-t',str(duration),'-i',str(root/'raw-take-03.mov'),'-i',str(root/cap),'-filter_complex',vf,'-map','[out]','-an','-r','30','-c:v','libx264','-preset','fast','-crf','18',str(root/name)])
static('intro-before.png',1.2,'part-01.mp4'); static('intro-after.png',1.8,'part-02.mp4')
clip(5.7,6.5,1,'caption-annotate.png','part-03.mp4')
clip(23.5,7.7,1.4,'caption-translate.png','part-04.mp4')
clip(37.8,4.4,1,'caption-compare.png','part-05.mp4')
clip(47,3,1,'caption-compare.png','part-06.mp4')
static('outro.png',3,'part-07.mp4')
(root/'concat.txt').write_text(''.join(f"file 'part-{i:02}.mp4'\n" for i in range(1,8)))
run(['-f','concat','-safe','0','-i',str(root/'concat.txt'),'-c','copy','-movflags','+faststart',str(root/'LibreShot-X-demo-v1.mp4')])
