from lib import font
from PIL import Image, ImageDraw, ImageFont
import archer, turret, mimic, mage
from export import ENEMIES, GODOT_NAME

FLOOR = (0x3d, 0x25, 0x3b); S = 6
TITLES = {'archer': 'Esqueleto arquero', 'skull_turret': 'Torre de calaveras',
          'mimic': 'Cofre mímico', 'mage': 'Mago del orbe'}
LABEL = {'idle': 'reposo', 'walk': 'caminar', 'wake': 'despertar', 'attack': 'ataque',
         'hurt': 'golpe', 'death': 'muerte'}
FONT = font(15, True)

def tile(fr, title, label):
    W, H = 32 * S, 32 * S + 44
    im = Image.new('RGB', (W, H), FLOOR)
    # cuadrícula de suelo de 16 px para dar escala
    d = ImageDraw.Draw(im)
    for i in range(0, 33, 16):
        d.line([(i * S, 0), (i * S, 32 * S)], fill=(0x36, 0x20, 0x30), width=2)
        d.line([(0, i * S), (W, i * S)], fill=(0x36, 0x20, 0x30), width=2)
    sp = fr.render().image().resize((32 * S, 32 * S), Image.NEAREST)
    im.paste(sp, (0, 0), sp)
    d.rectangle([0, 32 * S, W, H], fill=(0x25, 0x13, 0x1a))
    d.text((W // 2, 32 * S + 12), title, fill=(0xda, 0xe0, 0xea), font=FONT, anchor='mm')
    d.text((W // 2, 32 * S + 31), label, fill=(0xff, 0xd5, 0x69), font=FONT, anchor='mm')
    return im

def sequence(name):
    mod, fps = ENEMIES[name]
    anims = mod.build()
    order = [a for a in ('idle', 'wake', 'movement', 'attack', 'take_damage', 'death') if a in anims]
    seq = []
    for a in order:
        g = GODOT_NAME[a]
        reps = 2 if g in ('idle', 'walk') else 1
        if g == 'attack': reps = 2
        for _ in range(reps):
            for fr in anims[a]:
                seq.append((fr, g, 1000 / fps[g]))
        if g == 'death':
            seq.append((anims[a][-1], g, 700))  # pausa al final
    return seq

def save(frames, durs, path):
    pal = [f.convert('P', palette=Image.ADAPTIVE, colors=64) for f in frames]
    pal[0].save(path, save_all=True, append_images=pal[1:], duration=[max(20, round(d / 10) * 10) for d in durs],
                loop=0, disposal=1, optimize=False)

out = 'out/docs/vista_previa'
import os; os.makedirs(out, exist_ok=True)
seqs = {}
for name in ENEMIES:
    seq = sequence(name); seqs[name] = seq
    save([tile(f, TITLES[name], LABEL[g]) for f, g, _ in seq], [d for *_, d in seq], f'{out}/{name}.gif')

# GIF combinado: los cuatro a la vez, muestreado cada 40 ms
step = 40
def at(seq, t):
    for f, g, d in seq:
        if t < d: return f, g
        t -= d
    return seq[-1][0], seq[-1][1]
total = max(sum(d for *_, d in s) for s in seqs.values())
frames = []
for t in range(0, int(total), step):
    row = Image.new('RGB', (4 * 32 * S + 3 * 8, 32 * S + 44), (0x25, 0x13, 0x1a))
    for i, name in enumerate(seqs):
        f, g = at(seqs[name], t)
        row.paste(tile(f, TITLES[name], LABEL[g]), (i * (32 * S + 8), 0))
    frames.append(row)
save(frames, [step] * len(frames), f'{out}/todos.gif')
print(len(frames), total)
