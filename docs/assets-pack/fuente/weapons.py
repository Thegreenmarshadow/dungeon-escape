"""Armas del caballero: ícono 16x16, sprite en mano (apunta a la derecha) y efecto de ataque."""
import math
from lib import Canvas, Frame


def diag(c, x, y, n, cols):
    """Tira diagonal hacia arriba-derecha; cols = colores de izquierda a derecha."""
    for i in range(n):
        for j, k in enumerate(cols):
            c.set(x + i + j, y - i, k)


# ---------------- íconos 16x16 (diagonal, punta arriba-derecha) ----------------

def icon_sword():
    c = Canvas(16, 16)
    c.set(2, 13, 'G')
    diag(c, 3, 12, 2, ['m'])
    for p in ((3, 9), (4, 10), (5, 11), (6, 12)):
        c.set(*p, 'g')
    c.set(3, 9, 'q'); c.set(6, 12, 'q')
    diag(c, 5, 10, 8, ['E', 'S'])
    c.set(13, 2, 'T'); c.set(14, 2, '.')
    c.px.pop((14, 2), None)
    return Frame(c)


def icon_dagger():
    c = Canvas(16, 16)
    c.set(4, 12, 'g')
    diag(c, 5, 11, 2, ['N'])
    c.set(6, 8, 'q'); c.set(7, 9, 'g'); c.set(8, 10, 'q')
    diag(c, 7, 8, 5, ['E', 'S'])
    c.px.pop((12, 4), None)
    return Frame(c)


def icon_axe():
    c = Canvas(16, 16)
    diag(c, 2, 14, 10, ['n', 'm'])
    c.set(2, 14, 'N')
    c.stamp([
        "...TE...",
        "..TSSk..",
        ".TSSSkk.",
        "ESSSkkk.",
        ".SSskk..",
        "..s.k...",
    ], 5, 1)
    return Frame(c)


def icon_spear():
    c = Canvas(16, 16)
    diag(c, 1, 14, 10, ['n'])
    c.set(1, 14, 'N'); c.set(5, 10, 'm'); c.set(8, 7, 'm')
    c.set(9, 7, 'r'); c.set(9, 8, 'R'); c.set(10, 7, 'r')     # borla roja
    c.stamp([
        "...T",
        "..EE",
        ".ESS",
        "kSs.",
    ], 11, 1)
    return Frame(c)


def icon_mace():
    c = Canvas(16, 16)
    diag(c, 2, 13, 6, ['n', 'm'])
    c.set(2, 13, 'g')
    c.stamp([
        "...T...",
        "..SEE..",
        ".SSSET.",
        "TSSSSS.",
        ".sSSSs.",
        "..sss..",
        "...T...",
    ], 7, 1)
    c.set(11, 2, 'T'); c.set(8, 6, 'k')
    return Frame(c)


SHIELD = [
    "SSTTTTTTSS",
    "SrrrGGrrRS",
    "SrrrGGrrRS",
    "SGGGGGGGGS",
    "SGGGGGGGqS",
    "SrrrGGrrRS",
    "SrrrGGrRRS",
    ".SrrGGrRS.",
    ".SrrGqRRS.",
    "..SrGqRS..",
    "...SqRS...",
    "....SS....",
]


def icon_shield():
    c = Canvas(16, 16)
    c.stamp(SHIELD, 3, 2)
    return Frame(c)


# ---------------- sprite en la mano (apunta a la derecha) ----------------
# La empuñadura queda en el píxel GRIP: poner Sprite2D.offset = -GRIP + tamaño/2.

def held_sword():
    c = Canvas(16, 16)
    c.set(1, 8, 'G'); c.set(2, 8, 'm'); c.set(3, 8, 'm')
    c.line(4, 6, 4, 10, 'g'); c.set(4, 6, 'q'); c.set(4, 10, 'q')
    c.line(5, 7, 13, 7, 'E'); c.line(5, 8, 13, 8, 'S'); c.set(14, 8, 'T')
    c.px.pop((13, 7), None)
    return Frame(c)


def held_dagger():
    c = Canvas(16, 16)
    c.set(2, 8, 'g'); c.set(3, 8, 'N'); c.set(4, 8, 'N')
    c.line(5, 7, 5, 9, 'g')
    c.line(6, 7, 9, 7, 'E'); c.line(6, 8, 9, 8, 'S'); c.set(10, 8, 'T')
    c.px.pop((9, 7), None)
    return Frame(c)


def held_axe():
    c = Canvas(16, 16)
    c.line(1, 8, 11, 8, 'n'); c.set(1, 8, 'N'); c.line(3, 8, 9, 8, 'n')
    c.stamp([
        ".TE.",
        "TSSE",
        "SSSE",
        "kSSs",
        "kkk.",
        "kk..",
    ], 10, 3)
    c.set(12, 9, 'k'); c.set(11, 9, 'k')
    return Frame(c)


def held_spear():
    c = Canvas(32, 16)
    c.line(1, 8, 24, 8, 'n'); c.set(1, 8, 'N')
    for x in (6, 12, 18):
        c.set(x, 8, 'm')
    c.set(23, 9, 'r'); c.set(22, 9, 'r'); c.set(23, 10, 'R'); c.set(21, 10, 'r')  # borla
    c.set(25, 8, 'k')
    c.stamp([
        ".EE..",
        "ESSSE",
        ".ss..",
    ], 26, 7)
    c.set(31, 8, 'T')
    c.px.pop((31, 8), None); c.set(30, 8, 'T')
    return Frame(c)


def held_mace():
    c = Canvas(16, 16)
    c.line(1, 8, 8, 8, 'n'); c.set(1, 8, 'g'); c.set(4, 8, 'm')
    c.stamp([
        "...T...",
        "..SEE..",
        ".SSSET.",
        "TSSSSST",
        ".sSSSs.",
        "..sss..",
        "...T...",
    ], 8, 5)
    c.set(8, 8, 'k')
    return Frame(c)


def held_shield():
    c = Canvas(16, 16)
    c.stamp(SHIELD, 3, 2)
    return Frame(c)


# ---------------- efectos de ataque (sin contorno, color de estela #dae0ea) ----------------

def arc(w, h, cx, cy, r_in, r_out, a_tail, a_lead, fade=1.0):
    c = Canvas(w, h)
    if a_lead <= a_tail:
        return c
    for y in range(h):
        for x in range(w):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            r = math.hypot(dx, dy)
            a = math.degrees(math.atan2(dy, dx))
            if not (a_tail <= a <= a_lead):
                continue
            t = (a - a_tail) / (a_lead - a_tail)  # 1 = borde que avanza
            thick = (r_out - r_in) * (0.25 + 0.75 * t) * fade
            if r_out - thick <= r <= r_out:
                if r > r_out - 1.2:
                    k = 'E'
                elif t > 0.45:
                    k = 'W'
                else:
                    k = 'T'
                c.set(x, y, k)
    return Frame(Canvas(w, h), c)


def ring(c, cx, cy, r, k, step=1):
    for i in range(0, 360, step):
        x = round(cx + r * math.cos(math.radians(i)))
        y = round(cy + r * math.sin(math.radians(i)))
        c.set(x, y, k)


def fx_sword():  # 32x32, centro = caballero
    s = [(-75, -40), (-75, 5), (-70, 70), (-10, 75)]
    return [arc(32, 32, 16, 16, 9, 15, a, b, 1.0 if i < 3 else 0.5) for i, (a, b) in enumerate(s)]


def fx_dagger():  # 32x32, estocada rápida
    out = []
    for n, (x0, x1) in enumerate(((19, 23), (20, 28), (24, 29))):
        c = Canvas(32, 32)
        c.line(x0, 16, x1, 16, 'E')
        if n < 2:
            c.line(x0 + 1, 15, x1 - 2, 15, 'W'); c.line(x0 + 1, 17, x1 - 2, 17, 'T')
        if n == 1:
            c.set(x1 + 1, 16, 'W')
        out.append(Frame(Canvas(32, 32), c))
    return out


def fx_axe():  # 48x48, barrido amplio y pesado
    s = [(-105, -80), (-105, -20), (-105, 50), (-100, 105), (-30, 105)]
    return [arc(48, 48, 24, 24, 13, 21, a, b, 1.0 if i < 4 else 0.45) for i, (a, b) in enumerate(s)]


def fx_spear():  # 64x16, centro (32, 8); alcance hasta x=62
    out = []
    for n, (x0, x1) in enumerate(((40, 48), (42, 60), (46, 62), (54, 62))):
        c = Canvas(64, 16)
        c.line(x0, 8, x1, 8, 'E')
        if n in (1, 2):
            c.line(x0 + 2, 7, x1 - 4, 7, 'W'); c.line(x0 + 2, 9, x1 - 4, 9, 'W')
            c.line(x0, 6, x0 + 5, 6, 'T'); c.line(x0, 10, x0 + 5, 10, 'T')
        if n == 2:
            c.set(x1, 7, 'W'); c.set(x1, 9, 'W')
        out.append(Frame(Canvas(64, 16), c))
    return out


def fx_mace():  # 64x64, centro (32, 32); impacto en (46, 32)
    out = [arc(64, 64, 32, 32, 9, 15, -100, -60), arc(64, 64, 32, 32, 9, 15, -100, -5)]
    ix, iy = 46, 32
    # impacto
    c = Canvas(64, 64)
    for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
        c.set(ix + dx, iy + dy, 'E')
    for dx, dy in ((2, 2), (-2, 2), (2, -2), (-2, -2), (3, 0), (-3, 0), (0, 3), (0, -3)):
        c.set(ix + dx, iy + dy, 'W')
    out.append(Frame(Canvas(64, 64), c))
    # onda expansiva + piedritas
    for r, k, deb in ((6, 'E', 4), (10, 'W', 7), (13, 'T', 10)):
        c = Canvas(64, 64)
        ring(c, ix, iy, r, k)
        if k == 'E':
            ring(c, ix, iy, r - 1, 'W', 30)
        for i in range(0, 360, 60):
            c.set(round(ix + deb * math.cos(math.radians(i + 25))),
                  round(iy + deb * math.sin(math.radians(i + 25))), 'M' if r < 13 else 'b')
        out.append(Frame(Canvas(64, 64), c))
    return out


def fx_shield():  # 16x16, chispa de bloqueo
    out = []
    for n in range(3):
        c = Canvas(16, 16)
        L = (2, 4, 3)[n]
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            for i in range(1, L + 1):
                c.set(8 + dx * i, 8 + dy * i, 'E' if i < L else ('G' if n < 2 else 'W'))
        if n == 1:
            for dx, dy in ((2, 2), (-2, 2), (2, -2), (-2, -2)):
                c.set(8 + dx, 8 + dy, 'y')
        if n < 2:
            c.set(8, 8, 'E')
        out.append(Frame(Canvas(16, 16), c))
    return out


WEAPONS = {
    # id: (ícono, en mano, (w, h) en mano, grip, efecto, (w, h) efecto, fps efecto)
    'sword': (icon_sword, held_sword, (16, 16), (3, 8), fx_sword, (32, 32), 20),
    'dagger': (icon_dagger, held_dagger, (16, 16), (3, 8), fx_dagger, (32, 32), 30),
    'axe': (icon_axe, held_axe, (16, 16), (3, 8), fx_axe, (48, 48), 20),
    'spear': (icon_spear, held_spear, (32, 16), (6, 8), fx_spear, (64, 16), 26),
    'mace': (icon_mace, held_mace, (16, 16), (3, 8), fx_mace, (64, 64), 20),
    'shield': (icon_shield, held_shield, (16, 16), (8, 8), fx_shield, (16, 16), 20),
}
