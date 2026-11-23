"""Draws the Classic FPS loading-screen wordmark and the crosshair icon as SVG.

Run from the repository root: python3 deploy/branding/make_brand.py deploy/branding, then
rsvg-convert deploy/branding/splash.svg -o game/assets/branding/splash.png and
rsvg-convert -w 256 -h 256 deploy/branding/icon.svg -o game/assets/branding/icon.png.
"""
import sys
out = sys.argv[1]
AMBER, DIM, BG = "#ffb000", "#bc7000", "#121110"
W, H, T, C = 4.4, 6.5, 1.35, 0.55  # letter width, height, bar thickness, corner chamfer

def bars(ch):
    top=(0,0,W,T); mid=(0,(H-T)/2,W,T); bot=(0,H-T,W,T)
    left=(0,0,T,H); right=(W-T,0,T,H)
    ul=(0,0,T,H/2+T/2); ur=(W-T,0,T,H/2+T/2); lr=(W-T,H/2-T/2,T,H/2+T/2)
    return {"C":[top,bot,left],"L":[left,bot],"A":[top,mid,left,right],
            "S":[top,mid,bot,ul,lr],"I":[(0,0,T,H)],"F":[top,(0,(H-T)/2,W*0.8,T),left],
            "P":[top,mid,left,ur]}[ch]

def width(ch): return T if ch=="I" else W

def word(text, gap=1.1, space=2.6):
    parts, x, n = [], 0.0, 0
    for ch in text:
        if ch==" ": x += space; continue
        w = width(ch); n += 1
        clip = f"c{n}"
        poly = f"{x+C},0 {x+w-C},0 {x+w},{C} {x+w},{H-C} {x+w-C},{H} {x+C},{H} {x},{H-C} {x},{C}" if w>T else f"{x},0 {x+w},0 {x+w},{H} {x},{H}"
        rects = "".join(f'<rect x="{x+a:.3f}" y="{b:.3f}" width="{c:.3f}" height="{d:.3f}"/>' for a,b,c,d in bars(ch))
        parts.append(f'<clipPath id="{clip}"><polygon points="{poly}"/></clipPath><g clip-path="url(#{clip})">{rects}</g>')
        x += w + gap
    return "".join(parts), x - gap

def splash():
    body, ww = word("CLASSIC FPS")
    s = 760 / ww  # fit the wordmark to 760 px
    tw, th = ww*s, H*s
    x0, y0 = (1280-tw)/2, (720-th)/2 - 30
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="720" viewBox="0 0 1280 720">
<defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="0" y2="{H}"><stop offset="0" stop-color="#ffc640"/><stop offset="1" stop-color="{AMBER}"/></linearGradient>
<filter id="glow" filterUnits="userSpaceOnUse" x="-5" y="-5" width="{ww+10:.1f}" height="{H+10}"><feGaussianBlur stdDeviation="0.45"/></filter></defs>
<rect width="1280" height="720" fill="{BG}"/>
<g transform="translate({x0:.2f},{y0:.2f}) scale({s})" fill="{DIM}" opacity="0.6" filter="url(#glow)">{body}</g>
<g transform="translate({x0:.2f},{y0:.2f}) scale({s})" fill="url(#g)">{body}</g>
</svg>'''

def icon():
    # Classic open crosshair: four bars around a gap, on a dark rounded tile.
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
<rect width="256" height="256" rx="48" fill="{BG}"/>
<g fill="{AMBER}"><rect x="114" y="28" width="28" height="70"/><rect x="114" y="158" width="28" height="70"/>
<rect x="28" y="114" width="70" height="28"/><rect x="158" y="114" width="70" height="28"/></g>
<rect x="118" y="118" width="20" height="20" fill="{AMBER}"/>
</svg>'''

open(f"{out}/splash.svg","w").write(splash())
open(f"{out}/icon.svg","w").write(icon())
