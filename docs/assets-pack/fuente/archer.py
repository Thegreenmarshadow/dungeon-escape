"""Esqueleto arquero (v2, más detalle): capucha de cuero, taparrabos rojo,
aljaba con tres flechas, arco con empuñadura envuelta."""
from lib import Canvas, Frame, hurt_frames, death_frames

HEAD = [  # capucha + cráneo, mira a la derecha
    "...NmmmN..",
    "..NmnnnmN.",
    ".NmnMMMnnN",
    ".mnnbBWWWE",
    ".mnbBWWWWW",
    ".mnbWRrWRr",
    ".mmbBWWWWW",
    "..mNbWoWoW",
    "...N.oWoW.",
]
RIBS = [
    "nMBWWE",
    "nMoWoW",
    "mnBWWW",
    ".boWoW",
]
LOIN = [
    "NBWWN",
    ".rrR.",
    ".rR..",
]
BOW = [(-1, -6), (0, -5), (1, -4), (2, -3), (2, -2), (2, -1), (2, 0), (2, 1), (2, 2),
       (2, 3), (1, 4), (0, 5), (-1, 6)]
BOW_COL = ['N', 'm', 'n', 'M', 'M', 'n', 'R', 'n', 'n', 'm', 'm', 'm', 'N']


def leg(f, hip, foot_x, top_y, lift, light):
    fy = 28 - lift
    knee_y = (top_y + fy) // 2
    knee_x = (hip + foot_x) // 2 + (1 if foot_x >= hip else 0)
    f.line(hip, top_y, knee_x, knee_y, 'W' if light else 'B')
    f.set(knee_x, knee_y, 'E' if light else 'W')
    f.line(knee_x, knee_y + 1, foot_x, fy - 1, 'B' if light else 'b')
    f.set(foot_x, fy, 'W' if light else 'B'); f.set(foot_x + 1, fy, 'B' if light else 'b')


def archer(bob=0, lf=0, rf=0, lift=0, draw=0, arrow=False, twang=0, bow_dy=0):
    f, t = Canvas(), Canvas()
    u = bob
    # capa corta detrás
    f.stamp(["Nm", "Nmm", "Nmm", "NNm", ".N"], 10, 19 + u)
    # aljaba en la espalda, inclinada
    for i in range(7):
        f.set(9 + i // 3, 15 + u + i, 'm' if i % 3 == 0 else 'n')
        f.set(10 + i // 3, 15 + u + i, 'n' if i < 6 else 'N')
    f.set(9, 14 + u, 'N'); f.set(10, 14 + u, 'N')
    f.set(8, 12 + u, 'r'); f.set(9, 13 + u, 'E'); f.set(10, 12 + u, 'r'); f.set(11, 13 + u, 'p')
    # piernas (la de atrás más oscura)
    top = 25 + u
    leg(f, 14, 13 + lf, top, max(0, -lift), False)
    leg(f, 16, 16 + rf, top, max(0, lift), True)
    # cuerpo
    f.stamp(LOIN, 12, 23 + u)
    f.stamp(RIBS, 12, 19 + u)
    f.set(15, 18 + u, 'B')  # cuello
    f.stamp(HEAD, 11, 10 + u)
    # hombrera de cuero
    f.stamp(["Mn", "nm"], 17, 19 + u)
    # arco
    gx, gy = 21, 20 + u + bow_dy
    for (dx, dy), k in zip(BOW, BOW_COL):
        f.set(gx + dx + (twang if abs(dy) >= 5 else 0), gy + dy, k)
    f.line(18, 20 + u, gx + 1, gy, 'W')     # brazo del arco
    f.set(gx + 1, gy, 'B')                  # mano
    hx = gx - 1 - draw
    if draw > 0 or arrow:
        f.line(13, 21 + u, hx, gy, 'B')     # brazo que tensa
        f.set(hx, gy, 'W')
    else:
        f.line(12, 21 + u, 12, 24 + u, 'B')
        f.set(12, 25 + u, 'W')
    # cuerda y flecha (sin contorno)
    top_tip, bot_tip = (gx - 1 + twang, gy - 6), (gx - 1 + twang, gy + 6)
    mid = (hx, gy) if (draw > 0 or arrow) else (gx - 1 + twang, gy)
    t.line(*top_tip, *mid, 'H')
    t.line(*mid, *bot_tip, 'H')
    if arrow:
        t.line(hx, gy, gx + 3, gy, 'M')
        t.set(gx + 3, gy, 'S'); t.set(gx + 4, gy, 'T'); t.set(gx + 5, gy, 'o')
        t.set(gx + 3, gy - 1, 'o'); t.set(gx + 3, gy + 1, 'o')
        t.set(hx - 1, gy - 1, 'r'); t.set(hx - 1, gy + 1, 'r'); t.set(hx, gy - 1, 'p')
    return Frame(f, t)


def build():
    idle = [archer(bob=b) for b in (0, 0, 1, 1, 1, 0)]
    steps = [(-2, 2, 0, 0), (-1, 1, 0, 0), (0, 0, 1, -1), (1, -1, 0, 0),
             (2, -2, 0, 0), (1, -1, 0, 0), (0, 0, -1, -1), (-1, 1, 0, 0)]
    walk = [archer(lf=a, rf=b, lift=l, bob=bb) for a, b, l, bb in steps]
    attack = [
        archer(),
        archer(draw=0, arrow=True, bow_dy=-1),
        archer(draw=2, arrow=True, bow_dy=-1),
        archer(draw=4, arrow=True, bow_dy=-1),
        archer(draw=5, arrow=True, bow_dy=-1),   # 4: tensado al máximo
        archer(twang=1, bow_dy=-1),              # 5: SUELTA la flecha
        archer(twang=-1, bow_dy=0),
        archer(),
    ]
    base = archer()
    return {
        'idle': idle,
        'movement': walk,
        'attack': attack,
        'take_damage': hurt_frames(base, 5),
        'death': death_frames(base, 12, seed=3),
    }
