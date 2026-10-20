"""Jefes temáticos (frames de 48x48, pies en la fila 44 + contorno en la 45)."""
import math, random
from lib import Canvas, Frame, hurt_frames, death_frames

SZ, FLOOR = 48, 44


def blob(c, cx, cy, rx, ry, ramp, clip_floor=True):
    """Elipse sombreada con luz de arriba a la izquierda. ramp: oscuro -> claro."""
    n = len(ramp)
    for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            nx, ny = (x - cx) / rx, (y - cy) / ry
            if nx * nx + ny * ny > 1 or (clip_floor and y > FLOOR):
                continue
            light = -(nx * 0.55 + ny * 0.85)
            i = 0 if light < -0.45 else 1 if light < 0.1 else 2 if light < 0.55 else 3
            c.set(x, y, ramp[min(i, n - 1)])


def poly(c, pts, k):
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        c.line(x0, y0, x1, y1, k)


def rnd_pts(seed, n, box):
    r = random.Random(seed)
    x0, y0, x1, y1 = box
    return [(r.randint(x0, x1), r.randint(y0, y1)) for _ in range(n)]


# =====================================================================
#  1. FORJADOR DE MAGMA (fragua de lava)
# =====================================================================
ROCK = ('a', 'A', 'c', 'C')
CRACKS = [[(15, 26), (18, 28), (20, 27), (23, 30)],
          [(21, 35), (24, 33), (27, 35), (30, 33)],
          [(25, 23), (27, 26), (26, 28)],
          [(30, 27), (32, 29)]]


def forge(u=0, legs=(0, 0), pose='rest', glow=0, roar=False, embers=0):
    f, t = Canvas(SZ, SZ), Canvas(SZ, SZ)
    hot = ('g', 'l', 'y', 'l')[glow % 4]
    # brazo de atrás
    blob(f, 14, 30 + u, 4, 6, ('a', 'a', 'A', 'c'))
    # piernas
    blob(f, 19 + legs[0], 40, 4, 5, ROCK)
    blob(f, 28 + legs[1], 40, 4, 5, ROCK)
    # torso
    blob(f, 23, 29 + u, 11, 10, ROCK)
    # púas de obsidiana en los hombros
    for x, h in ((16, 3), (19, 4), (22, 2)):
        for j in range(h):
            f.set(x, 20 + u - j, 'a'); f.set(x + 1, 20 + u - j + 1, 'A')
    # grietas con lava
    for seg in CRACKS:
        poly(f, [(x, y + u) for x, y in seg], hot)
        mx, my = seg[len(seg) // 2]
        f.set(mx, my + u, 'y' if glow % 2 == 0 else 'l')
    if pose == 'raise':  # el brazo levantado va detrás de la cabeza
        blob(f, 31, 24 + u, 4, 6, ('A', 'c', 'C', 'C'))
        blob(f, 31, 15 + u, 3, 3, ROCK)
        f.line(30, 13 + u, 24, 7 + u, 'n'); f.line(31, 13 + u, 25, 7 + u, 'm'); f.line(32, 13 + u, 26, 7 + u, 'n')
        f.stamp(["kSSSSSSk", "kssssssk", "kssssssk", "kssssssk", "kkkkkkkk"], 18, 2 + u)
        for y in range(3, 6):
            f.set(18, y + u, hot)
    # cabeza (hacia adelante, encorvada)
    hy = 18 + u - (2 if roar else 0)
    blob(f, 29, hy, 5, 4, ('A', 'c', 'C'))
    f.line(26, hy - 1, 33, hy - 1, 'a')                 # ceja
    f.set(31, hy, 'y'); f.set(33, hy, 'y'); f.set(32, hy, 'a')
    if roar:
        f.stamp(["oooo", "lyyl"], 30, hy + 2)
    else:
        f.line(30, hy + 2, 33, hy + 2, hot)
    # brazo de adelante + martillo
    if pose == 'rest':
        blob(f, 34, 31 + u, 4, 6, ('A', 'c', 'C', 'C'))
        blob(f, 36, 37 + u, 3, 3, ROCK)
        f.line(37, 38 + u, 39, 40, 'n'); f.line(38, 38 + u, 40, 40, 'm')
        f.stamp(["kSSSSSSk", "kssssssk", "kssssssk", "kkkkkkkk"], 37, 40)
        f.line(44, 41, 44, 42, hot)
    elif pose == 'raise':
        pass
    else:  # slam: martillo contra el suelo, adelante
        blob(f, 35, 32 + u, 4, 5, ('A', 'c', 'C', 'C'))
        blob(f, 38, 37 + u, 3, 3, ROCK)
        f.line(39, 38 + u, 41, 38, 'n'); f.line(39, 39 + u, 41, 39, 'm')
        f.stamp(["kSSSSSSk", "kssssssk", "kssssssk", "kssssssk", "kkkkkkkk"], 39, 39)
        f.line(46, 40, 46, 42, 'y')
        for dx, dy in ((-2, -2), (1, -3), (4, -2), (6, -1), (-3, 0)):
            t.set(43 + dx, 38 + dy, 'y' if dx % 2 else 'l')
    # brasas que suben
    for i in range(embers):
        x, y = [(12, 14), (36, 12), (24, 9), (16, 7), (33, 6), (28, 3)][i % 6]
        t.set(x, y - (glow % 3), ('l', 'y', 'g')[i % 3])
    return Frame(f, t)


def build_forge():
    idle = [forge(u=b, glow=i, embers=2) for i, b in enumerate((0, 0, 1, 1, 1, 0))]
    walk = [forge(u=b, legs=l, glow=i, embers=1) for i, (b, l) in enumerate(
        ((0, (-2, 2)), (0, (-1, 1)), (-1, (0, 0)), (0, (1, -1)), (0, (2, -2)), (-1, (0, 0))))]
    slam = [forge(), forge(pose='raise', glow=1), forge(pose='raise', glow=2, u=-1),
            forge(pose='raise', glow=2, u=-1, embers=3), forge(pose='raise', glow=3, u=-1, embers=4),
            forge(pose='slam', glow=2, u=1, embers=6),   # 5: IMPACTO
            forge(pose='slam', glow=1, u=1, embers=4), forge(pose='slam', glow=0, u=1),
            forge(glow=3), forge(glow=0)]
    roar = [forge(glow=0), forge(glow=1, roar=True), forge(glow=2, roar=True, embers=2),
            forge(glow=3, roar=True, embers=4), forge(glow=2, roar=True, embers=6),  # 4: LANZA BRASAS
            forge(glow=1, roar=True, embers=6), forge(glow=0, embers=3), forge(glow=0)]
    base = forge()
    return {
        'idle': idle, 'movement': walk, 'attack': slam, 'attack2': roar,
        'take_damage': hurt_frames(base, 3, floor=FLOOR, height=26),
        'death': death_frames(base, 12, seed=21, cx=24, floor=FLOOR),
    }


# =====================================================================
#  2. REINA LICHE DE ESCARCHA (cripta helada)
# =====================================================================

def lich(u=0, lean=0, staff='side', glow=0, arms_up=False, spin=0, crack=False):
    f, t = Canvas(SZ, SZ), Canvas(SZ, SZ)
    cx = 23 + lean
    # sombra en el suelo (flota)
    for x in range(16, 33):
        for y in (43, 44):
            if abs(x - 24) < (8 if y == 43 else 6):
                f.set(x, y, 'o')
    # túnica: trapecio con pliegues, luz desde la izquierda
    top, bot = 20 + u, 37 + u
    for y in range(top, bot + 1):
        w = 5 + (y - top) * 0.55
        for x in range(round(cx - w), round(cx + w) + 1):
            rel = (x - (cx - w)) / (2 * w)
            k = 'j' if rel < 0.1 else ('I' if rel < 0.7 else 'i')
            if (x - round(cx)) % 4 == 0 and y > top + 3 and 0.1 <= rel:
                k = 'i'
            f.set(x, y, k)
    # bajo deshilachado con carámbanos
    w = 5 + (bot - top) * 0.55
    for i, x in enumerate(range(round(cx - w), round(cx + w) + 1)):
        h = (2, 0, 3, 1, 0, 2, 1, 3, 0, 2)[i % 10]
        for j in range(h):
            f.set(x, bot + 1 + j, 'J' if j == h - 1 else 'j')
    # escarcha en hombros
    for x in range(round(cx - 6), round(cx + 7)):
        f.set(x, top, 'J' if x % 3 else 'E')
    # brazos
    if arms_up:
        blob(f, cx - 9, top + 1, 3, 4, ('i', 'I', 'j'))
        blob(f, cx + 9, top + 1, 3, 4, ('i', 'I', 'j'))
        f.stamp(["W.W", "WWW"], round(cx) - 11, top - 5)
        f.stamp(["W.W", "WWW"], round(cx) + 8, top - 5)
    else:
        blob(f, cx - 7, top + 6, 3, 5, ('i', 'I', 'j'))
        blob(f, cx + 7, top + 6, 3, 5, ('i', 'I', 'j'))
        f.stamp(["WW", "BW"], round(cx) + 7, top + 10)
    # capucha + cráneo
    hy = top - 6
    blob(f, cx, hy + 2, 6, 6, ('i', 'I', 'j'))
    f.stamp([
        ".WWWW.",
        "WWWWWB",
        "W12W12",
        "BWWWWB",
        ".BoBo.",
    ], round(cx) - 2, hy + 1)
    eye = ('U', 'E', 'U', 'u')[glow % 4]
    for k_, v in (('1', eye), ('2', 'o')):
        pass
    for dx in (0, 3):
        f.set(round(cx) - 2 + dx + 1, hy + 3, eye)
        f.set(round(cx) - 2 + dx + 2, hy + 3, 'u')
    # corona de hielo
    for dx, h in ((-4, 2), (-2, 4), (0, 6), (2, 4), (4, 2)):
        for j in range(h):
            f.set(round(cx) + dx, hy - 3 - j, 'E' if j == h - 1 else 'J')
            if j < h - 2:
                f.set(round(cx) + dx + 1, hy - 3 - j, 'j')
    # báculo con cristal
    if staff == 'side':
        sx, sy0, sy1 = round(cx) + 11, top - 6, bot + 2
    elif staff == 'up':
        sx, sy0, sy1 = round(cx) + 10, top - 14, bot - 6
    else:  # 'down': clavado en el suelo adelante
        sx, sy0, sy1 = round(cx) + 13, top - 2, 44
    f.line(sx, sy0 + 4, sx, sy1, 'I'); f.line(sx + 1, sy0 + 4, sx + 1, sy1, 'i')
    gem = {0: ['.J.', 'JUj', 'jUi', '.j.'], 1: ['.E.', 'EUJ', 'JUj', '.j.']}[1 if glow >= 2 else 0]
    f.stamp(gem + ['.J.'], sx - 1, sy0)
    if glow >= 2:
        for dx, dy in ((-3, 1), (3, 0), (0, -3), (-2, -2), (3, 3)):
            t.set(sx + dx, sy0 + 1 + dy, 'E' if glow == 3 else 'U')
    # copos que orbitan
    for i in range(3):
        a = math.radians(spin * 30 + i * 120)
        t.set(round(24 + 14 * math.cos(a)), round(26 + u + 5 * math.sin(a)), 'J')
    if crack:
        for (x0, y0, x1, y1) in ((sx, 44, sx + 4, 43), (sx, 44, sx - 3, 43)):
            t.line(x0, y0, x1, y1, 'J')
    return Frame(f, t)


def build_lich():
    wave = (0, -1, -2, -2, -1, 0)
    idle = [lich(u=w, glow=i, spin=i) for i, w in enumerate(wave)]
    move = [lich(u=w, lean=1, glow=i, spin=i * 2) for i, w in enumerate(wave)]
    spikes = [lich(), lich(staff='up', glow=1, u=-1), lich(staff='up', glow=2, u=-2),
              lich(staff='up', glow=3, u=-2), lich(staff='up', glow=3, u=-2),
              lich(staff='down', glow=3, u=0, crack=True),      # 5: CLAVA el báculo -> picos
              lich(staff='down', glow=2, u=0, crack=True), lich(staff='down', glow=1), lich(glow=0)]
    nova = [lich(), lich(arms_up=True, glow=1, u=-1, spin=1), lich(arms_up=True, glow=2, u=-2, spin=3),
            lich(arms_up=True, glow=3, u=-3, spin=6), lich(arms_up=True, glow=3, u=-3, spin=9),
            lich(arms_up=False, glow=3, u=0, spin=12),            # 5: ONDA de escarcha
            lich(glow=2, spin=13), lich(glow=0, spin=14)]
    base = lich()
    return {
        'idle': idle, 'movement': move, 'attack': spikes, 'attack2': nova,
        'take_damage': hurt_frames(base, 3, floor=FLOOR, height=30),
        'death': death_frames(base, 12, seed=22, cx=24, floor=FLOOR),
    }


# =====================================================================
#  3. GUARDIÁN MUSGOSO (ruinas con musgo)
# =====================================================================

def stone_rect(c, x0, y0, x1, y1, seed):
    r = random.Random(seed)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            k = 's'
            if y == y0 or x == x0:
                k = 'S'
            if x == x1 or y == y1:
                k = 'k'
            c.set(x, y, k)
    for _ in range((x1 - x0) // 4):  # grietas
        x, y = r.randint(x0 + 2, x1 - 2), r.randint(y0 + 2, y1 - 2)
        c.set(x, y, 'k'); c.set(x + 1, y + 1, 'k')


def moss_on(c, x0, y0, x1, seed, depth=3):
    r = random.Random(seed)
    for x in range(x0, x1 + 1):
        d = r.choice((1, 1, 2, 2, 3, depth + 2))
        for j in range(d):
            c.set(x, y0 + j, 'x' if j == 0 and r.random() < 0.4 else ('F' if j < 2 else 'f'))


def warden(u=0, roots=(0, 0), arms='down', glow=0, spores=0, sway=0):
    f, t = Canvas(SZ, SZ), Canvas(SZ, SZ)
    eye = ('z', 'Z', 'E', 'Z')[glow % 4]
    # raíces / piernas
    for (x0, x1), dx in zip(((18, 13), (21, 19), (27, 29), (30, 35)), (roots[0], roots[0], roots[1], roots[1])):
        f.line(x0, 37, x1 + dx, 44, 'n'); f.line(x0 + 1, 37, x1 + dx + 1, 44, 'm')
        f.set(x1 + dx - 1, 44, 'N')
    # brazo de atrás
    ay = {'down': 21, 'up': 9, 'slam': 26}[arms] + u
    stone_rect(f, 9 + sway, ay, 14 + sway, ay + 12, 31)
    moss_on(f, 9 + sway, ay, 14 + sway, 32, 2)
    # cuerpo
    stone_rect(f, 16, 32 + u, 31, 38, 33)
    stone_rect(f, 14 + sway, 19 + u, 33 + sway, 32 + u, 34)
    moss_on(f, 14 + sway, 19 + u, 33 + sway, 35, 4)
    moss_on(f, 16, 32 + u, 31, 36, 1)
    # runa espiral en el pecho
    for dy, row in enumerate(["11111", "1...1", "1.1.1", "1.111", "1...."]):
        for dx, ch in enumerate(row):
            if ch == '1':
                f.set(21 + sway + dx, 24 + u + dy, eye if glow % 2 == 0 else 'z')
    # cabeza con un solo ojo
    hx = 19 + sway + (1 if arms == 'slam' else 0)
    stone_rect(f, hx, 10 + u, hx + 10, 18 + u, 37)
    moss_on(f, hx, 10 + u, hx + 10, 38, 3)
    f.stamp(["kkkk", "k" + eye + "Ek", "kkkk"], hx + 5, 13 + u)
    # setas luminosas en el hombro
    f.stamp([".zZZz.", "zZEZZz", "zzzzzz", "..MM..", "..MB.."], 10 + sway, 13 + u)
    f.stamp([".zZ.", "zZZz", ".MM."], 16 + sway, 16 + u)
    # brazo de adelante
    stone_rect(f, 33 + sway, ay + 1, 38 + sway, ay + 13, 39)
    moss_on(f, 33 + sway, ay + 1, 38 + sway, 40, 2)
    for i, x in enumerate((34, 36, 38)):     # dedos-raíz
        f.line(x + sway, ay + 14, x + sway + (i - 1), ay + 16, 'n')
    # lianas colgando (sin contorno)
    for x, ln in ((17, 5), (25, 3), (30, 6), (10, 4)):
        for j in range(ln):
            t.set(x + sway, 33 + u + j - (14 if x != 10 else 0), 'F' if j % 2 else 'f')
    # esporas
    r = random.Random(spores)
    for i in range(spores * 3):
        x, y = 14 + r.randint(-6, 8) + sway, 13 + u - r.randint(1, 4 + spores * 2)
        t.set(x, y, ('Z', 'x', 'z')[i % 3])
    if arms == 'slam':
        for dx in (-3, -1, 2, 4):
            t.set(36 + dx, 43, 'm'); t.set(36 + dx, 42, 'n')
    return Frame(f, t)


def build_warden():
    idle = [warden(u=b, glow=i) for i, b in enumerate((0, 0, 1, 1, 1, 0))]
    walk = [warden(u=b, roots=r, glow=i, sway=s) for i, (b, r, s) in enumerate(
        ((0, (-1, 1), 0), (0, (-2, 2), 1), (1, (0, 0), 0), (0, (1, -1), 0), (0, (2, -2), -1), (1, (0, 0), 0)))]
    slam = [warden(), warden(arms='up', glow=1, u=-1), warden(arms='up', glow=2, u=-2),
            warden(arms='up', glow=3, u=-2), warden(arms='up', glow=2, u=-2),
            warden(arms='slam', glow=2, u=1),     # 5: GOLPE -> raíces bajo el jugador
            warden(arms='slam', glow=1, u=1), warden(arms='down', glow=0), warden(glow=1)]
    spore = [warden(), warden(glow=1, sway=-1), warden(glow=2, sway=-1, spores=1),
             warden(glow=3, sway=0, spores=2), warden(glow=2, sway=1, spores=4),   # 4: SUELTA esporas
             warden(glow=1, spores=3), warden(glow=0, spores=1), warden()]
    base = warden()
    return {
        'idle': idle, 'movement': walk, 'attack': slam, 'attack2': spore,
        'take_damage': hurt_frames(base, 3, floor=FLOOR, height=32),
        'death': death_frames(base, 12, seed=23, cx=24, floor=FLOOR),
    }


# =====================================================================
#  Efectos de habilidades
# =====================================================================

def _ring(c, cx, cy, r, k, step=6):
    for i in range(0, 360, step):
        c.set(round(cx + r * math.cos(math.radians(i))), round(cy + r * math.sin(math.radians(i))), k)


def fx_shockwave(cols, debris):
    """64x64, centro (32, 32): onda que se expande desde el punto de impacto."""
    out = []
    for n, r in enumerate((5, 10, 15, 20)):
        top = Canvas(64, 64)
        _ring(top, 32, 32, r, cols[min(n, len(cols) - 1)], 3)
        if n < 2:
            _ring(top, 32, 32, r - 1, cols[0], 9)
        for i in range(0, 360, 45):
            d = r * 0.7
            top.set(round(32 + d * math.cos(math.radians(i + 20))), round(32 + d * math.sin(math.radians(i + 20))), debris)
        out.append(Frame(Canvas(64, 64), top))
    return out


def fx_lava_pool():
    """16x16, charco que burbujea (dura en el suelo)."""
    out = []
    r = random.Random(4)
    base = [(x, y) for y in range(16) for x in range(16)
            if math.hypot(x - 7.5, (y - 8) * 1.4) + r.uniform(-0.8, 0.8) < 6.5]
    for n in range(4):
        top = Canvas(16, 16)
        for x, y in base:
            d = math.hypot(x - 7.5, (y - 8) * 1.4)
            top.set(x, y, 'R' if d > 5.2 else ('g' if d > 3 else 'l'))
        bx, by = [(5, 7), (9, 9), (7, 6), (10, 7)][n]
        top.set(bx, by, 'y'); top.set(bx + 1, by, 'G')
        out.append(Frame(Canvas(16, 16), top))
    return out


def fx_mark_burst(ring_c, center_c, burst):
    """32x32: aviso que se cierra (frames 0-3) y estallido (4-5). Radio útil ~12 px."""
    out = []
    for n, r in enumerate((13, 11, 9, 7)):
        top = Canvas(32, 32)
        _ring(top, 16, 16, 12, ring_c, 15)
        _ring(top, 16, 16, r, center_c, 8)
        top.set(16, 16, center_c); top.set(15, 16, ring_c); top.set(17, 16, ring_c)
        out.append(Frame(Canvas(32, 32), top))
    for n in range(2):
        top = Canvas(32, 32)
        R = 9 if n == 0 else 12
        for y in range(32):
            for x in range(32):
                d = math.hypot(x - 15.5, y - 15.5)
                if d < R and (n == 0 or (x + y) % 2 == 0):
                    top.set(x, y, burst[0] if d < R * 0.4 else burst[1] if d < R * 0.75 else burst[2])
        out.append(Frame(Canvas(32, 32), top))
    return out


def fx_spike(kind):
    """16x32: grieta de aviso (0-1), sale el pico (2-4), se rompe (5). Base en la fila 30."""
    out = []
    if kind == 'ice':
        tele, shape_cols, shard = 'J', ('i', 'I', 'j', 'J', 'E'), 'J'
    else:
        tele, shape_cols, shard = 'm', ('N', 'm', 'n', 'n', 'F'), 'F'
    for n in range(2):
        top = Canvas(16, 32)
        for (x0, y0, x1, y1) in ((4, 30, 8, 29), (8, 29, 12, 30), (7, 28, 9, 31)):
            top.line(x0, y0, x1, y1, tele)
        if n == 1:
            top.set(6, 27, shard); top.set(10, 28, shard)
        out.append(Frame(Canvas(16, 32), top))
    for h in (8, 16, 20):
        f = Canvas(16, 32)
        for y in range(30 - h, 31):
            w = max(0, round((y - (30 - h)) / h * 4))
            for x in range(8 - w, 8 + w + 1):
                rel = (x - (8 - w)) / max(1, 2 * w)
                f.set(x, y, shape_cols[2] if rel < 0.35 else shape_cols[1] if rel < 0.75 else shape_cols[0])
        f.set(8, 30 - h, shape_cols[4])
        if kind == 'moss':  # hojitas en la raíz
            f.set(5, 30 - h // 2, 'F'); f.set(11, 30 - h // 3, 'x')
        else:
            f.set(7, 31 - h + 3, shape_cols[3])
        out.append(Frame(f))
    top = Canvas(16, 32)
    for x, y in ((4, 20), (11, 18), (6, 26), (10, 25), (8, 14), (3, 28), (13, 27)):
        top.set(x, y, shard)
    out.append(Frame(Canvas(16, 32), top))
    return out


def fx_spore_cloud():
    """32x32: nube de esporas que crece, se queda y se disipa (6 frames)."""
    out = []
    r = random.Random(9)
    puffs = [(r.uniform(8, 24), r.uniform(9, 23), r.uniform(3, 6)) for _ in range(7)]
    for n, s in enumerate((0.4, 0.7, 1.0, 1.0, 0.9, 0.7)):
        top = Canvas(32, 32)
        for y in range(32):
            for x in range(32):
                for px_, py_, pr in puffs:
                    d = math.hypot(x - px_, y - py_)
                    if d < pr * s:
                        if n >= 4 and (x + y + n) % 2:
                            break
                        top.set(x, y, 'z' if d > pr * s * 0.6 else 'F' if (x * 3 + y) % 5 else 'x')
                        break
        for i in range(5):
            top.set(r.randint(4, 28), r.randint(4, 28), 'Z')
        out.append(Frame(Canvas(32, 32), top))
    return out


def fx_spore_pod():
    """16x16: vaina que late; si no se rompe a tiempo, cura al jefe."""
    out = []
    for n in range(4):
        c = Canvas(16, 16)
        s = (0, 1, 0, -1)[n]
        c.stamp(["..fFFf..", ".fFxxFf.", "fFzZZzFf", "fFzZEZzf", "fFzZZzFf", ".fFFFFf.", "..mnnm.."][:7], 4, 5 - (1 if s > 0 else 0))
        out.append(Frame(c))
    return out


FX = {
    'forge': {
        'shockwave': (lambda: fx_shockwave(('y', 'l', 'g', 'R'), 'A'), (64, 64), 12, False),
        'lava_pool': (fx_lava_pool, (16, 16), 6, True),
        'ember_mark': (lambda: fx_mark_burst('g', 'l', ('y', 'l', 'g')), (32, 32), 6, False),
    },
    'lich': {
        'ice_spike': (lambda: fx_spike('ice'), (16, 32), 8, False),
        'frost_nova': (lambda: fx_shockwave(('E', 'J', 'U', 'j'), 'U'), (64, 64), 12, False),
        'frost_mark': (lambda: fx_mark_burst('U', 'J', ('E', 'J', 'j')), (32, 32), 6, False),
    },
    'warden': {
        'root_spike': (lambda: fx_spike('moss'), (16, 32), 8, False),
        'spore_cloud': (fx_spore_cloud, (32, 32), 4, False),
        'spore_pod': (fx_spore_pod, (16, 16), 4, True),
    },
}
