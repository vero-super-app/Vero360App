from PIL import Image
from pathlib import Path

root = Path(r"c:\dev\Vero360App\assets\icons")
src = Image.open(root / "logo_mark.png").convert("RGBA")
px = src.load()
w, h = src.size


def is_bg(x: int, y: int) -> bool:
    r, g, b, a = px[x, y]
    return a < 10 or (r < 18 and g < 18 and b < 18)


minx, miny, maxx, maxy = w, h, 0, 0
step = 2
for y in range(0, h, step):
    for x in range(0, w, step):
        if not is_bg(x, y):
            minx = min(minx, x)
            miny = min(miny, y)
            maxx = max(maxx, x)
            maxy = max(maxy, y)

pad = 12
minx = max(0, minx - pad)
miny = max(0, miny - pad)
maxx = min(w - 1, maxx + pad)
maxy = min(h - 1, maxy + pad)
crop = src.crop((minx, miny, maxx + 1, maxy + 1))
print("content bbox", (minx, miny, maxx, maxy), "crop", crop.size)

size = 1024
# White app icon with safe padding (normal launcher look)
canvas = Image.new("RGBA", (size, size), (255, 255, 255, 255))
target = int(size * 0.70)
cw, ch = crop.size
scale = min(target / cw, target / ch)
nw, nh = int(cw * scale), int(ch * scale)
logo = crop.resize((nw, nh), Image.Resampling.LANCZOS)
ox = (size - nw) // 2
oy = (size - nh) // 2
canvas.paste(logo, (ox, oy), logo)
(canvas.convert("RGB")).save(root / "app_icon.png", "PNG")
print("wrote app_icon.png")

# Adaptive foreground: same padded logo on transparent
fg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
full = src.resize((nw, nh), Image.Resampling.LANCZOS)
fg.paste(full, (ox, oy), full)
fg.save(root / "app_icon_foreground.png", "PNG")
print("wrote app_icon_foreground.png")

# Soft orange splash backdrop mark (white card style source)
splash = Image.new("RGBA", (size, size), (255, 255, 255, 255))
target2 = int(size * 0.78)
scale2 = min(target2 / cw, target2 / ch)
nw2, nh2 = int(cw * scale2), int(ch * scale2)
logo2 = crop.resize((nw2, nh2), Image.Resampling.LANCZOS)
splash.paste(logo2, ((size - nw2) // 2, (size - nh2) // 2), logo2)
(splash.convert("RGB")).save(root / "splash_logo.png", "PNG")
print("wrote splash_logo.png")
