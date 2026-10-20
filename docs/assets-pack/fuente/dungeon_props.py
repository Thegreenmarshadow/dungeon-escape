"""Objetos y símbolos de los tres temas nuevos de mazmorra (16x16, arte original)."""
import math, random
from lib import Canvas, Frame

THEMES = {
    'lava': dict(
        name='Fragua de lava',
        flame=('r', 'l', 'y'), cloth=('R', 'a', 'g'), banner_sym='FIRE',
        stone=('A', 'c', 'C'), carve='a', glow=('g', 'l', 'y'), rune='TRI',
    ),
    'ice': dict(
        name='Cripta helada',
        flame=('v', 'u', 'J'), cloth=('i', 'k', 'j'), banner_sym='SNOW',
        stone=('i', 'I', 'j'), carve='i', glow=('v', 'u', 'J'), rune='INV',
    ),
    'moss': dict(
        name='Ruinas con musgo',
        flame=('z', 'Z', 'E'), cloth=('f', 'e', 'x'), banner_sym='LEAF',
        stone=('k', 's', 'S'), carve='e', glow=('z', 'Z', 'E'), rune='SPIRAL',
    ),
}

SYMBOLS = {
    'FIRE': ["..1..", ".12..", ".121.", "12321", ".222."],
    'SNOW': ["1.1.1", ".121.", "12321", ".121.", "1.1.1"],
    'LEAF': ["...11", "..121", ".121.", "121..", "1...."],
    'TRI': ["..1..", ".1.1.", ".121.", "1...1", "11111"],      # fuego alquímico
    'INV': ["11111", "1...1", ".121.", ".1.1.", "..1.."],      # agua / hielo
    'SPIRAL': ["11111", "1...1", "1.1.1", "1.111", "1...."],
}

FLAMES = [
    ["..1..", ".11..", ".121.", "12221", "12321", "12321", ".111."],
    ["...1.", "..11.", ".121.", ".1221", "12321", "12321", ".111."],
    [".....", "..1..", ".121.", "11221", "12321", "12321", ".111."],
    [".1...", ".11..", "1221.", "12221", "12321", "12321", ".111."],
]


def sym(rows, cols):
    return [''.join(cols[int(ch) - 1] if ch.isdigit() else '.' for ch in r) for r in rows]


# ---------- antorcha de pared (4 frames) ----------
def torch(t):
    out = []
    for fr in FLAMES:
        c = Canvas(16, 16)
        c.stamp(["Sssk", ".sk."], 6, 9)       # copa
        c.line(7, 11, 7, 13, 'n'); c.line(8, 11, 8, 13, 'm')
        c.stamp(["kssk"], 6, 12)              # placa en la pared
        c.stamp(sym(fr, t['flame']), 5, 2)
        out.append(Frame(c))
    return out


# ---------- estandarte con símbolo ----------
def banner(t):
    c = Canvas(16, 16)
    main, shade, trim = t['cloth']
    c.line(2, 1, 13, 1, 'q'); c.set(2, 1, 'G'); c.set(13, 1, 'G')
    for y in range(2, 13):
        for x in range(3, 13):
            c.set(x, y, shade if x in (3, 12) else main)
    for x in range(3, 13):
        c.set(x, 3, trim)
    for x in (3, 4, 5, 10, 11, 12):
        c.set(x, 13, main if x not in (3, 12) else shade)
    c.set(3, 14, shade); c.set(4, 14, main); c.set(11, 14, main); c.set(12, 14, shade)
    c.stamp(sym(SYMBOLS[t['banner_sym']], t['glow'] if t['banner_sym'] != 'LEAF' else ('F', 'x', 'Z')), 5, 6)
    return [Frame(c)]


# ---------- emblema de piedra tallado (con brillo que late) ----------
def plaque(t):
    out = []
    lo, mid, hi = t['stone']
    for n in range(4):
        c = Canvas(16, 16)
        for y in range(16):
            for x in range(16):
                d = math.hypot(x - 7.5, y - 7.5)
                if d <= 6.6:
                    k = mid
                    if d > 5.6:
                        k = hi if y < 7 else lo
                    c.set(x, y, k)
        glow = t['glow'][(0, 1, 2, 1)[n]]
        rows = SYMBOLS[t['rune']]
        for dy, r in enumerate(rows):
            for dx, ch in enumerate(r):
                if ch.isdigit():
                    c.set(5 + dx, 5 + dy, glow if ch == '2' else t['carve'])
        out.append(Frame(c))
    return out


# ---------- runa en el suelo (calcomanía sin contorno, late) ----------
def floor_rune(t):
    out = []
    for n in range(4):
        top = Canvas(16, 16)
        k = t['glow'][(0, 1, 2, 1)[n]]
        for i in range(0, 360, 12):
            top.set(round(7.5 + 6.5 * math.cos(math.radians(i))), round(7.5 + 6.5 * math.sin(math.radians(i))),
                    t['glow'][0])
        for dy, r in enumerate(SYMBOLS[t['rune']]):
            for dx, ch in enumerate(r):
                if ch.isdigit():
                    top.set(5 + dx, 5 + dy, k if n % 2 == 0 or ch == '2' else t['glow'][0])
        out.append(Frame(Canvas(16, 16), top))
    return out


# ---------- manchas de suelo propias de cada tema (sin contorno) ----------
def floor_patch(t, theme):
    rnd = random.Random({'lava': 1, 'ice': 2, 'moss': 3}[theme])
    out = []
    if theme == 'lava':  # grieta con lava que late
        path = [(2, 12), (4, 11), (5, 9), (7, 8), (8, 6), (10, 5), (12, 3), (13, 2)]
        branch = [(7, 8), (9, 9), (11, 10)]
        for n in range(4):
            top = Canvas(16, 16)
            core = ('g', 'l', 'y', 'l')[n]
            for seg in (path, branch):
                for (x0, y0), (x1, y1) in zip(seg, seg[1:]):
                    top.line(x0, y0, x1, y1, core)
            for x, y in path[1:-1:2]:
                top.set(x + 1, y + 1, 'R'); top.set(x - 1, y, 'a')
            out.append(Frame(Canvas(16, 16), top))
    elif theme == 'ice':  # escarcha con destello
        pts = [(x, y) for y in range(16) for x in range(16)
               if math.hypot(x - 7.5, (y - 8) * 1.3) < 6.5 and rnd.random() < 0.45]
        for n in range(4):
            top = Canvas(16, 16)
            for x, y in pts:
                top.set(x, y, 'j' if (x + y) % 3 else 'J')
            sx, sy = [(4, 6), (10, 5), (8, 10), (5, 9)][n]
            top.set(sx, sy, 'E'); top.set(sx + 1, sy, 'U'); top.set(sx - 1, sy, 'U')
            top.set(sx, sy + 1, 'U'); top.set(sx, sy - 1, 'U')
            out.append(Frame(Canvas(16, 16), top))
    else:  # musgo con florcitas
        top = Canvas(16, 16)
        for y in range(16):
            for x in range(16):
                d = math.hypot(x - 7.5, y - 8.5) + rnd.uniform(-1.5, 1.5)
                if d < 6:
                    top.set(x, y, 'F' if d < 3 else 'f')
                elif d < 7 and rnd.random() < 0.5:
                    top.set(x, y, 'e')
        for x, y in ((5, 6), (9, 9), (11, 6)):
            top.set(x, y, 'x')
        top.set(6, 10, 'G'); top.set(10, 4, 'p')
        out.append(Frame(Canvas(16, 16), top))
    return out


# ---------- objeto con colisión (4 frames) ----------
def big_prop(t, theme):
    out = []
    for n in range(4):
        c = Canvas(16, 16)
        if theme == 'lava':  # brasero
            fr = FLAMES[n]
            c.stamp(sym(fr[2:], t['flame']), 5, 1)
            c.stamp([
                "SsssssssS",
                "skkkkkkks",
                ".skkkkks.",
                "..sskss..",
                "...sks...",
                "..k.k.k..",
                ".k..k..k.",
            ], 3, 7)
            for x in (5, 7, 9):  # brasas
                c.set(x, 8, ('g', 'l', 'y', 'l')[(n + x) % 4])
        elif theme == 'ice':  # cristal de hielo
            c.stamp([
                "......J.....",
                ".....JjI....",
                "..J..jjI.J..",
                ".Jj..jjIJjI.",
                ".jjI.jjIjjI.",
                ".jjIJjjIjjI.",
                "IjjIjjjIjjII",
                "IIjIjjjIjII.",
                ".IIiIIIiII..",
                "..iiiiiii...",
            ], 2, 4)
            sx, sy = [(8, 6), (4, 9), (11, 8), (8, 10)][n]
            c.set(sx, sy, 'E')
        else:  # seta luminosa
            cap = ('z', 'Z', 'Z', 'z')[n]
            c.stamp([
                "...zzzzz...",
                "..zZZZZZz..",
                ".zZEZZZEZz.",
                "zZZZZZZZZZz",
                "zzzzzzzzzzz",
                "...MMMMM...",
                "....MMM....",
                "....MBM....",
                "...MMMMM...",
                "..fFFFFFf..",
            ], 2, 3)
            for x, y in ((4, 4), (8, 4), (10, 6), (6, 5)):
                c.set(x + 0, y + 1, 'E' if cap == 'Z' else 'Z')
        out.append(Frame(c))
    return out


# ---------- detalles sueltos de suelo (3 variantes, sin colisión) ----------
def scatter(t, theme):
    out = []
    if theme == 'lava':
        shapes = [
            (["..aA..", ".aAAc.", "aAAccC", ".aaAc."], 5, 6),
            (["aA.", "Aa."], 6, 7),
            ([".A.", "aAc", ".a."], 7, 7),
        ]
        extra = [[(4, 10, 'l'), (11, 5, 'g')], [(10, 9, 'g'), (4, 4, 'l'), (9, 4, 'a')], [(5, 10, 'y')]]
    elif theme == 'ice':
        shapes = [
            (["J...J", "jJ.jJ", "jj.jj", "Ij.Ij"], 5, 6),
            (["..WW..", ".WBBW.", "WoBBoW", ".JWWJ."], 5, 6),   # calavera escarchada
            ([".J.", "JjJ", "jIj"], 6, 7),
        ]
        extra = [[], [(4, 10, 'J')], [(10, 5, 'J')]]
    else:
        shapes = [
            (["x.x..", "Fx.xF", ".FFF."], 5, 7),             # pasto
            (["G.p", "FGF", ".F."], 6, 7),                   # flores
            (["n...n", "mn.nm", ".mnm.", "..m.."], 5, 6),    # raíz
        ]
        extra = [[], [(10, 6, 'p'), (4, 10, 'G')], []]
    for (rows, x, y), ex in zip(shapes, extra):
        c = Canvas(16, 16)
        c.stamp(rows, x, y)
        top = Canvas(16, 16)
        for ex_x, ex_y, k in ex:
            top.set(ex_x, ex_y, k)
        out.append(Frame(c, top))
    return out


def build(theme):
    t = THEMES[theme]
    return {
        'torch': (torch(t), 8, True),
        'banner': (banner(t), 1, False),
        'emblem': (plaque(t), 4, True),
        'floor_rune': (floor_rune(t), 4, True),
        'floor_patch': (floor_patch(t, theme), 4, True),
        'prop': (big_prop(t, theme), 6, True),
        'scatter': (scatter(t, theme), 1, False),
    }
