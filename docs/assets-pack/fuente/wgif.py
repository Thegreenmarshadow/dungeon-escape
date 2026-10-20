from lib import font
from PIL import Image, ImageDraw, ImageFont
from weapons import WEAPONS
from weapon_export import STATS
S, T = 4, 64
FONT = font(15, True)
FLOOR = (0x3d, 0x25, 0x3b)
data = {w: (ic().render().image(), held().render().image(), grip, [f.render().image() for f in fx()], fps)
        for w, (ic, held, hs, grip, fx, fs, fps) in WEAPONS.items()}
CYCLE = 1400  # ms
def tile(w, t):
    icon, held, grip, fxs, fps = data[w]
    im = Image.new('RGBA', (T, T), FLOOR + (255,))
    d = ImageDraw.Draw(im)
    for i in range(0, T + 1, 16):
        d.line([(i, 0), (i, T)], fill=(0x36, 0x20, 0x30)); d.line([(0, i), (T, i)], fill=(0x36, 0x20, 0x30))
    c = T // 2
    d.ellipse([c - 4, c - 4, c + 4, c + 4], fill=(0x25, 0x13, 0x1a))  # marca del caballero
    im.alpha_composite(held, (c - grip[0], c - grip[1]))
    fi = int(t / (1000 / fps))
    if fi < len(fxs):
        fx = fxs[fi]; im.alpha_composite(fx, (c - fx.width // 2, c - fx.height // 2))
    big = im.resize((T * S, T * S), Image.NEAREST).convert('RGB')
    out = Image.new('RGB', (T * S, T * S + 40), (0x25, 0x13, 0x1a)); out.paste(big, (0, 0))
    ib = icon.resize((32, 32), Image.NEAREST); out.paste(ib, (8, T * S + 4), ib)
    ImageDraw.Draw(out).text((48, T * S + 20), STATS[w]['name'], fill=(0xda, 0xe0, 0xea), font=FONT, anchor='lm')
    return out
names = list(WEAPONS); frames = []
for t in range(0, CYCLE, 40):
    sheet = Image.new('RGB', (3 * T * S + 16, 2 * (T * S + 40) + 8), (0x25, 0x13, 0x1a))
    for i, w in enumerate(names):
        sheet.paste(tile(w, t), ((i % 3) * (T * S + 8), (i // 3) * (T * S + 48)))
    frames.append(sheet.convert('P', palette=Image.ADAPTIVE, colors=64))
frames[0].save('out/docs/vista_previa/armas.gif', save_all=True, append_images=frames[1:], duration=40, loop=0)

