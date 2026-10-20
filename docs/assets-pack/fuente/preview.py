import sys, importlib
from PIL import Image, ImageDraw
from lib import save_strip, Frame

FLOOR = (0x3d, 0x25, 0x3b)


def preview(anims, path, scale=6, size=32):
    rows = []
    for name, frames in anims.items():
        strip = Image.new('RGBA', (size * len(frames), size), (0, 0, 0, 0))
        for i, fr in enumerate(frames):
            strip.paste(fr.render().image(), (i * size, 0))
        rows.append((name, strip))
    W = max(s.width for _, s in rows) * scale + 110
    H = sum(size * scale + 6 for _ in rows)
    out = Image.new('RGB', (W, H), FLOOR)
    d = ImageDraw.Draw(out)
    y = 0
    for name, s in rows:
        d.text((4, y + 10), name, fill=(255, 255, 255))
        big = s.resize((s.width * scale, s.height * scale), Image.NEAREST)
        out.paste(big, (110, y), big)
        for i in range(s.width // size + 1):
            d.line([(110 + i * size * scale, y), (110 + i * size * scale, y + size * scale)], fill=(80, 60, 80))
        y += size * scale + 6
    out.save(path)


if __name__ == '__main__':
    mod = importlib.import_module(sys.argv[1])
    preview(mod.build(), sys.argv[2])
