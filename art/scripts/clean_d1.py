from PIL import Image, ImageDraw, ImageFilter
src=Image.open('d1-raw.png').convert('RGB'); w,h=src.size
inset=4; r=133-inset
inside=Image.new('L',(w,h),0)
ImageDraw.Draw(inside).rounded_rectangle((30+inset,29+inset,994-inset,995-inset),radius=r,fill=255)
work=src.copy(); MARK=(255,0,255)
seeds=[(900,120),(600,700),(950,950),(700,300),(845,745)]
for x in range(34,60):
    for y in (400,600,800):
        if min(src.getpixel((x,y)))>225: seeds.append((x,y))
for s in seeds:
    if min(work.getpixel(s))>225: ImageDraw.floodfill(work,s,MARK,thresh=60)
bg=Image.new('L',(w,h),0); bp=bg.load(); wp=work.load()
for y in range(h):
    for x in range(w):
        if wp[x,y]==MARK: bp[x,y]=255
near=bg.filter(ImageFilter.MaxFilter(5))
out=Image.new('RGBA',(w,h)); op=out.load(); sp=src.load(); np_=near.load(); ip=inside.load()
for y in range(h):
    for x in range(w):
        if not ip[x,y] or bp[x,y]: op[x,y]=(0,0,0,0); continue
        r_,g_,b_=sp[x,y]
        if np_[x,y] and min(r_,g_,b_)>60 and abs(r_-g_)<25 and abs(g_-b_)<25:
            op[x,y]=(0,0,0,255-min(r_,g_,b_))
        else: op[x,y]=(r_,g_,b_,255)
bbox=out.getchannel('A').point(lambda a:255 if a>8 else 0).getbbox()
c=out.crop(bbox); cw,ch=c.size; side=int(max(cw,ch)*1.01)
sq=Image.new('RGBA',(side,side)); sq.paste(c,((side-cw)//2,(side-ch)//2))
sq.resize((1024,1024),Image.LANCZOS).save('d1-clean-1024.png')
sq.resize((512,512),Image.LANCZOS).save('d1-clean.png')
def on(bgc,size):
    b=Image.new('RGBA',(size,size),bgc); b.alpha_composite(sq.resize((size,size),Image.LANCZOS)); return b.convert('RGB')
chk=Image.new('RGBA',(512,512)); d=ImageDraw.Draw(chk)
for i in range(0,512,32):
    for j in range(0,512,32): d.rectangle((i,j,i+31,j+31),fill=(200,200,200,255) if (i+j)//32%2 else (255,255,255,255))
chk.alpha_composite(sq.resize((512,512),Image.LANCZOS))
P=Image.new('RGB',(512*3+20,512+60),'#888')
P.paste(chk.convert('RGB'),(0,0)); P.paste(on('#1e1e1e',512),(522,0)); P.paste(on('#ececec',512),(1044,0))
for j,s in enumerate((16,22,32)):
    P.paste(on('#1e1e1e',s),(10+j*50,520)); P.paste(on('#ececec',s),(530+j*50,520))
P.save('d1-preview.png')
