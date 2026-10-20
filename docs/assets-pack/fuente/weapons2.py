"""15 armas nuevas del caballero: sprite en mano (apunta a la derecha), ícono 16x16
en diagonal, efecto de ataque y, si es a distancia, proyectil."""
import math
from collections import Counter
from PIL import Image
from lib import Canvas, Frame
from weapons import arc as _arc_std


# ---------------------------------------------------------------------
# utilidades
# ---------------------------------------------------------------------

def tmpl(w, rows, y0):
    c = Canvas(w, 16)
    c.stamp(rows, 0, y0)
    return c


def arc(w, h, cx, cy, r_in, r_out, a0, a1, fade=1.0, cols=('E', 'W', 'T')):
    """Como weapons.arc pero con colores propios (armas elementales)."""
    fr = _arc_std(w, h, cx, cy, r_in, r_out, a0, a1, fade)
    if cols != ('E', 'W', 'T'):
        m = dict(zip(('E', 'W', 'T'), cols))
        fr.top.px = {p: m[k] for p, k in fr.top.px.items()}
    return fr


def compress(c, x_from, x_to, target_w):
    """Quita columnas del mango (x_from..x_to) hasta que el arma mida target_w."""
    xs = sorted({x for x, _ in c.px})
    w = xs[-1] - xs[0] + 1
    drop = max(0, w - target_w)
    span = list(range(x_from, x_to + 1))
    if drop == 0 or not span:
        return c
    step = len(span) / drop
    remove = {span[int(i * step)] for i in range(min(drop, len(span)))}
    out = Canvas(c.w, c.h)
    for (x, y), k in c.px.items():
        if x in remove:
            continue
        out.set(x - sum(1 for r in remove if r < x), y, k)
    return out


def rotate_icon(fill, angle=45, size=16):
    """Rotación tipo RotSprite: agranda x8, gira, y vuelve a reducir por mayoría."""
    keys = sorted(set(fill.px.values()))
    xs = [x for x, _ in fill.px]; ys = [y for _, y in fill.px]
    x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
    im = Image.new('L', (x1 - x0 + 1, y1 - y0 + 1), 0)
    for (x, y), k in fill.px.items():
        im.putpixel((x - x0, y - y0), keys.index(k) + 1)
    K = 8
    big = im.resize((im.width * K, im.height * K), Image.NEAREST)
    big = big.rotate(angle, resample=Image.NEAREST, expand=True)
    best = None
    for off in (0, 2, 4, 6):
        W, H = (big.width - off) // K, (big.height - off) // K
        px = big.load()
        res = {}
        for by in range(H):
            for bx in range(W):
                cnt = Counter(px[off + bx * K + i, off + by * K + j] for i in range(K) for j in range(K))
                solid = sum(v for k, v in cnt.items() if k)
                if solid >= 22:
                    k = max((k for k in cnt if k), key=lambda k: cnt[k])
                    res[(bx, by)] = keys[k - 1]
        if best is None or len(res) > len(best):
            best = res
    bx = [x for x, _ in best]; by = [y for _, y in best]
    w, h = max(bx) - min(bx) + 1, max(by) - min(by) + 1
    ox, oy = (size - w) // 2 - min(bx), (size - h) // 2 - min(by)
    c = Canvas(size, size)
    for (x, y), k in best.items():
        c.set(x + ox, y + oy, k)
    return Frame(c)


# ---------------------------------------------------------------------
# sprites en mano (eje en la fila 8; empuñadura en GRIP)
# ---------------------------------------------------------------------

def held_katana():
    return tmpl(24, [
        ".......g........SSSTE...",
        ".......q.SSSSSSSEEE.....",
        "GrkrkrkqGEEEEEEE........",
        ".......q................",
        ".......g................",
    ], 6)


def held_greatsword():
    return tmpl(32, [
        "......TS........................",
        "......Ss........................",
        "......Ss.TTTTTTTTTTTTTTTTTTTT...",
        "......Ss.EEkkkkkkkkkkkkkkkEEEEE.",
        "SNmNmNSsqSSSSSSSSSSSSSSSSSSSSSST",
        "......Ss.sssssssssssssssssssss..",
        "......Ss........................",
        "......ss........................",
        "......kk........................",
    ], 4)


def held_rapier():
    return tmpl(24, [
        ".....qGGq...............",
        "....q....G..............",
        "....q....G.S............",
        "GmNmNqGGGTEEEEEEEEEEEET.",
        "....q....q..............",
        ".....qqqq...............",
    ], 5)


def held_scythe():
    return tmpl(24, [
        ".....................kk.",
        "NnnnmnnnnmnnnnmnnnnnnkSk",
        "..................ESSSSk",
        ".................ESSSsk.",
        "................ESSrsk..",
        "...............ESSsk....",
        "..............ESsk......",
        ".............EE.........",
    ], 7)


def held_warhammer():
    return tmpl(24, [
        "..............TTTTT.....",
        ".............kSSSSSk....",
        ".............ksssssk....",
        ".............ksgggsk....",
        ".............ksssssk.S..",
        "NnnnmnnnnmnnnksssssqSTT.",
        ".............ksssssk.S..",
        ".............ksgggsk....",
        ".............ksssssk....",
        ".............kkkkkkk....",
    ], 3)


def held_flail():
    c = Canvas(24, 16)
    c.line(0, 8, 5, 8, 'n'); c.set(0, 8, 'N'); c.set(3, 8, 'm'); c.set(6, 8, 'q')
    for (x, y, k) in ((7, 8, 'S'), (8, 9, 'k'), (9, 9, 'S'), (10, 10, 'k'), (11, 10, 'S'), (12, 10, 'k'), (13, 9, 'S')):
        c.set(x, y, k)
    for y in range(16):
        for x in range(24):
            d = math.hypot(x - 17, y - 9)
            if d <= 3.2:
                c.set(x, y, 'S' if (x - 17) + (y - 9) < -1 else ('s' if d < 2.5 else 'k'))
    for x, y in ((17, 5), (21, 9), (17, 13), (20, 6), (20, 12), (14, 6), (14, 12)):
        c.set(x, y, 'T')
    return c


def held_whip():
    c = Canvas(32, 16)
    c.set(0, 8, 'G'); c.line(1, 8, 6, 8, 'N'); c.set(3, 8, 'm'); c.set(5, 8, 'm'); c.set(7, 8, 'q')
    prev = (7, 8)
    for x in range(8, 31):
        y = 8 + round(2.2 * math.sin((x - 8) / 3.2)) - (x - 8) // 10
        c.line(prev[0], prev[1], x, y, 'n' if x % 3 else 'm')
        prev = (x, y)
    c.set(prev[0] + 1, prev[1], 'r')
    return c


def held_halberd():
    return tmpl(32, [
        "......................EEEE......",
        ".....................ESSSSE.....",
        ".....................TSSSSk.....",
        "......................TSSk......",
        "......................kSk.......",
        "......................kkk...TS..",
        "nnnnmnnnnmnnnnmnnnnmnnkkkkkSSTTT",
        "......................k.....TS..",
        "......................kS........",
        ".....................kS.........",
    ], 2)


def held_trident():
    return tmpl(32, [
        "......................qGGGGGGy..",
        "......................q.....G...",
        "......................q.........",
        "......................q.........",
        "nnnnqnnnnnnnnnnnnnnnqnqGGGGGGGGy",
        "......................q.........",
        "......................q.........",
        "......................q.....G...",
        "......................qGGGGGGy..",
    ], 4)


def held_claws():
    c = Canvas(24, 16)
    c.stamp([
        "rkkkkk.",
        "rSSSSsq",
        "rssssks",
        "rSSSSsq",
        "rssssks",
        "rSSSSsq",
        "rkkkkk.",
    ], 0, 5)
    for r in (6, 8, 10):
        c.line(7, r, 13, r, 'T')
        c.set(14, r - 1, 'E'); c.set(15, r - 1, 'E'); c.set(16, r - 2, 'E')
    return c


def held_boomerang():
    return tmpl(16, [
        "....Mn..........",
        "....nnN.........",
        "....rrN.........",
        "....nnN.........",
        "....nnN.........",
        "....nnnnnrrnnnM.",
        "....NnnnnnnnnnN.",
        ".....NNNNNNNNN..",
    ], 3)


def held_crossbow():
    c = Canvas(16, 16)
    c.line(1, 8, 13, 8, 'n'); c.line(2, 9, 10, 9, 'm'); c.set(1, 8, 'N')
    c.line(1, 9, 1, 12, 'N'); c.line(2, 10, 2, 12, 'm')          # culata
    pts = [(10, 2), (11, 3), (12, 5), (12, 8), (12, 11), (11, 13), (10, 14)]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        c.line(x0, y0, x1, y1, 's')
    c.set(12, 7, 'S'); c.set(12, 8, 'k')
    c.line(4, 7, 13, 7, 'M'); c.set(14, 7, 'T'); c.set(15, 7, 'T')
    return c


def held_fire_staff():
    c = Canvas(24, 16)
    c.line(0, 8, 17, 8, 'N'); c.line(2, 8, 16, 8, 'm')
    for x in (5, 11):
        c.set(x, 8, 'q')
    c.stamp([
        "..aA..",
        ".a..A.",
        "a.lyl.",
        "A.yGyA",
        "a.lyl.",
        ".a..A.",
        "..aA..",
    ], 17, 5)
    c.set(17, 8, 'A')
    return c


def held_frost_blade():
    return tmpl(24, [
        "......j.....J...J.......",
        "......j..JjjJIjjJjJ.....",
        "iIiIijUjJEEEEEEEEEEJE...",
        "......j..IjjIjjIjjI.....",
        "......j....I...I........",
    ], 6)


def held_vine_sickle():
    return tmpl(16, [
        "...........xZ...",
        "............Zz..",
        "............zZ..",
        "...........zZ...",
        "..F..F....zZz...",
        "nFnnFnnFnnzz....",
        ".F...F..........",
    ], 3)


# ---------------------------------------------------------------------
# efectos (centrados en el jugador, apuntan a la derecha)
# ---------------------------------------------------------------------

def fx_katana():
    s = [(-60, -20), (-60, 40), (-30, 60)]
    out = [arc(32, 32, 16, 16, 12, 15, a, b, 1.0 if i < 2 else 0.5) for i, (a, b) in enumerate(s)]
    return out


def fx_greatsword():
    s = [(-110, -70), (-110, -10), (-110, 50), (-100, 110), (-30, 110)]
    return [arc(48, 48, 24, 24, 12, 22, a, b, 1.0 if i < 4 else 0.4) for i, (a, b) in enumerate(s)]


def fx_rapier():
    out = []
    for n, (x0, x1) in enumerate(((20, 25), (21, 30), (27, 31))):
        top = Canvas(32, 32)
        top.line(x0, 16, x1, 16, 'E')
        if n == 1:
            for dx, dy in ((1, -1), (1, 1), (2, 0)):
                top.set(x1 + dx - 1, 16 + dy, 'W')
            top.set(x1, 13, 'T'); top.set(x1, 19, 'T')
        out.append(Frame(Canvas(32, 32), top))
    return out


def fx_scythe():
    s = [(-150, -100), (-150, -20), (-150, 70), (-140, 150), (-40, 150)]
    return [arc(48, 48, 24, 24, 14, 21, a, b, 1.0 if i < 4 else 0.4, ('E', 'T', 'S'))
            for i, (a, b) in enumerate(s)]


def _ring(c, cx, cy, r, k, step=4):
    for i in range(0, 360, step):
        c.set(round(cx + r * math.cos(math.radians(i))), round(cy + r * math.sin(math.radians(i))), k)


def fx_warhammer():
    out = [arc(64, 64, 32, 32, 10, 17, -110, -60), arc(64, 64, 32, 32, 10, 17, -110, 0)]
    ix, iy = 48, 32
    for n, r in enumerate((4, 9, 14, 18)):
        top = Canvas(64, 64)
        _ring(top, ix, iy, r, ('E', 'W', 'T', 'T')[n], 4 if n < 3 else 8)
        for a in (20, 100, 160, 230, 300):  # grietas en el suelo
            L = min(r, 10)
            top.line(ix, iy, round(ix + L * math.cos(math.radians(a))), round(iy + L * math.sin(math.radians(a))), 'k')
        out.append(Frame(Canvas(64, 64), top))
    return out


def spin_arc(w, h, cx, cy, r_in, r_out, lead, length):
    """Arco que admite cruzar los 180° (para giros completos)."""
    top = Canvas(w, h)
    for y in range(h):
        for x in range(w):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            r = math.hypot(dx, dy)
            diff = (lead - math.degrees(math.atan2(dy, dx))) % 360
            if diff > length:
                continue
            t = 1 - diff / length
            if r_out - (r_out - r_in) * (0.25 + 0.75 * t) <= r <= r_out:
                top.set(x, y, 'E' if r > r_out - 1.2 else ('W' if t > 0.45 else 'T'))
    return Frame(Canvas(w, h), top)


def fx_flail():  # giro de 360°, en loop mientras se mantiene el botón
    return [spin_arc(48, 48, 24, 24, 15, 20, n * 60, 150) for n in range(6)]


def fx_whip():
    out = []
    for n, L in enumerate((10, 22, 30, 30)):
        top = Canvas(64, 16)
        prev = (34, 8)
        for x in range(35, 34 + L):
            y = 8 + round(2 * math.sin((x - 34) / 3.0 + n))
            top.line(prev[0], prev[1], x, y, 'W' if n < 3 else 'T')
            prev = (x, y)
        if n == 2:  # chasquido
            ex, ey = prev
            for dx, dy in ((1, 0), (-1, -1), (1, -2), (2, 1), (0, 2)):
                top.set(ex + dx, ey + dy, 'E')
        out.append(Frame(Canvas(64, 16), top))
    return out


def fx_halberd():
    s = [(-60, -30), (-60, 20), (-50, 60), (0, 60)]
    out = []
    for i, (a, b) in enumerate(s):
        fr = arc(64, 64, 32, 32, 18, 26, a, b, 1.0 if i < 3 else 0.4)
        out.append(fr)
    return out


def fx_trident():
    out = []
    for n, (x0, x1) in enumerate(((44, 50), (46, 60), (52, 62), (58, 62))):
        top = Canvas(64, 16)
        for dy in (-4, 0, 4):
            top.line(x0 + (0 if dy == 0 else 2), 8 + dy, x1 - (0 if dy == 0 else 2), 8 + dy, 'E' if n < 3 else 'T')
        out.append(Frame(Canvas(64, 16), top))
    return out


def fx_claws():  # combo de 3 zarpazos
    out = []
    marks = [((20, 9), (27, 14)), ((19, 15), (28, 17)), ((20, 23), (27, 18))]
    for n in range(4):
        top = Canvas(32, 32)
        for i, ((x0, y0), (x1, y1)) in enumerate(marks[:min(n + 1, 3)]):
            k = 'E' if i == n else ('W' if i == n - 1 else 'T')
            for o in (-1, 0, 1):
                top.line(x0, y0 + o * 2, x1, y1 + o * 2, k)
        out.append(Frame(Canvas(32, 32), top))
    return out


def fx_throw():  # ráfaga corta al lanzar (bumerán)
    out = [arc(32, 32, 16, 16, 9, 12, -40, 0), arc(32, 32, 16, 16, 9, 12, -40, 40, 0.5)]
    return out


def fx_crossbow():
    out = []
    for n in range(2):
        top = Canvas(32, 32)
        for dx, dy in ((1, 0), (2, -1), (2, 1), (3, 0)) if n == 0 else ((3, -2), (3, 2), (4, 0)):
            top.set(28 + dx - 3, 16 + dy, 'E' if n == 0 else 'T')
        out.append(Frame(Canvas(32, 32), top))
    return out


def fx_fire_cast():
    out = []
    for n, r in enumerate((3, 5, 7)):
        top = Canvas(32, 32)
        _ring(top, 26, 16, r, ('y', 'l', 'g')[n], 20)
        top.set(26, 16, 'y' if n < 2 else 'g')
        out.append(Frame(Canvas(32, 32), top))
    return out


def fx_frost():
    s = [(-70, -30), (-70, 20), (-60, 70), (-10, 70)]
    out = []
    for i, (a, b) in enumerate(s):
        fr = arc(32, 32, 16, 16, 10, 15, a, b, 1.0 if i < 3 else 0.5, ('E', 'J', 'U'))
        if i >= 1:
            for dx, dy in ((26, 6), (28, 22), (24, 27))[:i]:
                fr.top.set(dx, dy, 'J'); fr.top.set(dx + 1, dy, 'U'); fr.top.set(dx, dy + 1, 'U')
        out.append(fr)
    return out


def fx_vine():
    s = [(-70, -30), (-70, 20), (-60, 70), (-10, 70)]
    out = []
    for i, (a, b) in enumerate(s):
        fr = arc(32, 32, 16, 16, 10, 15, a, b, 1.0 if i < 3 else 0.5, ('x', 'F', 'f'))
        for j, (dx, dy) in enumerate(((27, 8), (29, 18), (25, 26))[:i]):
            fr.top.set(dx, dy, 'F'); fr.top.set(dx + 1, dy - 1, 'x')
        out.append(fr)
    return out


# ---------------------------------------------------------------------
# proyectiles (16x16, apuntan a la derecha)
# ---------------------------------------------------------------------

def proj_boomerang():
    base = held_boomerang()
    out = []
    for n in range(4):
        c = Canvas(16, 16)
        for (x, y), k in base.px.items():
            dx, dy = x - 8, y - 7
            for _ in range(n):
                dx, dy = -dy, dx
            c.set(8 + dx, 8 + dy, k)
        out.append(Frame(c))
    return out


def proj_bolt():
    c = Canvas(16, 16)
    c.line(3, 8, 11, 8, 'M'); c.set(12, 8, 'S'); c.set(13, 8, 'T'); c.set(12, 7, 's'); c.set(12, 9, 's')
    c.set(3, 7, 'k'); c.set(3, 9, 'k'); c.set(4, 7, 's'); c.set(4, 9, 's')
    return [Frame(c)]


def proj_fireball():
    out = []
    for n in range(4):
        c = Canvas(16, 16)
        for y in range(16):
            for x in range(16):
                d = math.hypot(x - 10, y - 8)
                if d <= 3.3:
                    c.set(x, y, 'y' if d < 1.5 else 'l' if d < 2.6 else 'g')
        for i, L in enumerate((3, 5, 4)):  # cola de fuego
            yy = 7 + i
            L2 = L + (1 if (n + i) % 2 else 0)
            c.line(6 - L2, yy, 6, yy, 'g' if i != 1 else 'l')
        c.set(9, 7, 'E')
        out.append(Frame(c))
    return out


def proj_fire_hit():
    out = []
    for n, R in enumerate((4, 7, 9, 10)):
        top = Canvas(32, 32)
        for y in range(32):
            for x in range(32):
                d = math.hypot(x - 15.5, y - 15.5)
                if d < R and (n < 2 or (x + y + n) % 2 == 0):
                    top.set(x, y, 'y' if d < R * 0.35 else 'l' if d < R * 0.7 else 'g')
        out.append(Frame(Canvas(32, 32), top))
    return out


# ---------------------------------------------------------------------
# catálogo
# ---------------------------------------------------------------------
# id: (nombre, held_fn, ancho, grip, icon_shaft(rango de columnas comprimibles), fx_fn, tamaño fx, fps,
#      proyectil (fn, fps) o None)
WEAPONS2 = {
    'katana':      ('Katana', held_katana, 24, (3, 8), (1, 6), fx_katana, (32, 32), 24, None),
    'greatsword':  ('Mandoble', held_greatsword, 32, (3, 8), (1, 5), fx_greatsword, (48, 48), 16, None),
    'rapier':      ('Estoque', held_rapier, 24, (3, 8), (1, 4), fx_rapier, (32, 32), 30, None),
    'scythe':      ('Guadaña', held_scythe, 24, (3, 8), (0, 17), fx_scythe, (48, 48), 16, None),
    'warhammer':   ('Martillo de guerra', held_warhammer, 24, (3, 8), (0, 12), fx_warhammer, (64, 64), 14, None),
    'flail':       ('Mangual', held_flail, 24, (3, 8), (0, 5), fx_flail, (48, 48), 18, None),
    'whip':        ('Látigo', held_whip, 32, (3, 8), (8, 28), fx_whip, (64, 16), 20, None),
    'halberd':     ('Alabarda', held_halberd, 32, (3, 8), (0, 20), fx_halberd, (64, 64), 16, None),
    'trident':     ('Tridente', held_trident, 32, (3, 8), (0, 20), fx_trident, (64, 16), 20, None),
    'claws':       ('Garras', held_claws, 24, (3, 8), (0, 0), fx_claws, (32, 32), 18, None),
    'boomerang':   ('Bumerán', held_boomerang, 16, (5, 8), (0, 0), fx_throw, (32, 32), 20, (proj_boomerang, 16)),
    'crossbow':    ('Ballesta de mano', held_crossbow, 16, (3, 9), (0, 0), fx_crossbow, (32, 32), 20, (proj_bolt, 1)),
    'fire_staff':  ('Báculo ígneo', held_fire_staff, 24, (3, 8), (0, 15), fx_fire_cast, (32, 32), 16, (proj_fireball, 12)),
    'frost_blade': ('Espada de escarcha', held_frost_blade, 24, (3, 8), (0, 4), fx_frost, (32, 32), 18, None),
    'vine_sickle': ('Hoz de enredadera', held_vine_sickle, 16, (3, 8), (0, 0), fx_vine, (32, 32), 18, None),
}


def icon(wid):
    name, held, w, grip, shaft, *_ = WEAPONS2[wid]
    c = held()
    if shaft != (0, 0):
        c = compress(c, shaft[0], shaft[1], 18)
    return rotate_icon(c)


def held_frame(wid):
    return Frame(WEAPONS2[wid][1]())
