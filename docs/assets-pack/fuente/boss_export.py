import os
from PIL import Image, ImageDraw, ImageFont
from lib import font, save_strip
from export import tres, GODOT_NAME
import bosses

OUT = 'out'
GODOT_NAME = dict(GODOT_NAME, attack2='attack2')
FPS = {
    'forge': {'idle': 6, 'walk': 7, 'attack': 8, 'attack2': 8, 'hurt': 12, 'death': 12},
    'lich': {'idle': 7, 'walk': 7, 'attack': 8, 'attack2': 8, 'hurt': 12, 'death': 12},
    'warden': {'idle': 6, 'walk': 6, 'attack': 8, 'attack2': 8, 'hurt': 12, 'death': 12},
}
TITLE = {'forge': 'Forjador de magma', 'lich': 'Reina liche de escarcha', 'warden': 'Guardián musgoso'}
FLOOR = {'forge': (0x2b, 0x1b, 0x1e), 'lich': (0x29, 0x34, 0x46), 'warden': (0x23, 0x2d, 0x21)}
LABEL = {'idle': 'reposo', 'walk': 'caminar', 'attack': 'habilidad 1', 'attack2': 'habilidad 2',
         'hurt': 'golpe', 'death': 'muerte'}
FONT = font(16, True)
S = 5
GIFDIR = 'out/docs/vista_previa'


def tile(img, name, label):
    W = 48 * S
    out = Image.new('RGB', (W, W + 44), (0x25, 0x13, 0x1a))
    bg = Image.new('RGB', (W, W), FLOOR[name]); d = ImageDraw.Draw(bg)
    for i in range(0, 49, 16):
        d.line([(i * S, 0), (i * S, W)], fill=tuple(max(0, c - 8) for c in FLOOR[name]), width=2)
        d.line([(0, i * S), (W, i * S)], fill=tuple(max(0, c - 8) for c in FLOOR[name]), width=2)
    b = img.resize((W, W), Image.NEAREST); bg.paste(b, (0, 0), b); out.paste(bg, (0, 0))
    d = ImageDraw.Draw(out)
    d.text((W // 2, W + 12), TITLE[name], fill=(0xda, 0xe0, 0xea), font=FONT, anchor='mm')
    d.text((W // 2, W + 31), LABEL[label], fill=(0xff, 0xd5, 0x69), font=FONT, anchor='mm')
    return out


def main():
    seqs = {}
    os.makedirs(GIFDIR, exist_ok=True)
    for name in ('forge', 'lich', 'warden'):
        d = f'{OUT}/assets/bosses/{name}'; os.makedirs(d, exist_ok=True)
        anims = getattr(bosses, 'build_' + name)()
        entries, seq = [], []
        for fa, frames in anims.items():
            g = GODOT_NAME[fa]
            fn = f'boss-{name}_{fa}.png'
            save_strip(frames, f'{d}/{fn}', 48)
            entries.append((g, f'res://assets/bosses/{name}/{fn}', len(frames), FPS[name][g], g in ('idle', 'walk')))
            reps = 2 if g in ('idle', 'walk') else 1
            for _ in range(reps):
                seq += [(fr.render().image(), g, 1000 / FPS[name][g]) for fr in frames]
            if g == 'death':
                seq.append((frames[-1].render().image(), g, 600))
        open(f'{d}/{name}_frames.tres', 'w').write(tres(entries, 48))
        for fxn, (fn_, size, fps, loop) in bosses.FX[name].items():
            frames = fn_()
            save_strip(frames, f'{d}/fx-{fxn}.png', size)
            open(f'{d}/fx-{fxn}_frames.tres', 'w').write(
                tres([('default', f'res://assets/bosses/{name}/fx-{fxn}.png', len(frames), fps, loop)], size))
        seqs[name] = seq
        ims = [tile(i, name, g) for i, g, _ in seq]
        pal = [im.convert('P', palette=Image.ADAPTIVE, colors=64) for im in ims]
        pal[0].save(f'{GIFDIR}/jefe_{name}.gif', save_all=True, append_images=pal[1:],
                    duration=[max(20, round(t / 10) * 10) for *_, t in seq], loop=0)
    # combinado
    def at(seq, t):
        for im, g, dur in seq:
            if t < dur: return im, g
            t -= dur
        return seq[-1][0], seq[-1][1]
    total = max(sum(x[2] for x in s) for s in seqs.values())
    frames = []
    for t in range(0, int(total), 50):
        row = Image.new('RGB', (3 * 48 * S + 16, 48 * S + 44), (0x25, 0x13, 0x1a))
        for i, n in enumerate(seqs):
            im, g = at(seqs[n], t); row.paste(tile(im, n, g), (i * (48 * S + 8), 0))
        frames.append(row.convert('P', palette=Image.ADAPTIVE, colors=96))
    frames[0].save(f'{GIFDIR}/jefes.gif', save_all=True, append_images=frames[1:], duration=50, loop=0)


if __name__ == '__main__':
    main()
