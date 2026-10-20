from lib import Canvas, Frame, death_frames

LID = [
    ".SMMMMMMMMMMS.",
    "STnnnMnnnnnnTs",
    "snnmnnnnnmnnss",
    "smnnnnmnnnnnms",
    "kkkkkqGGqkkkkk",
]
BODY = [
    "snnnnqGoqnnnns",
    "Snnmnnnnnnmnns",
    "kTkkkkkkkkkkTk",
    "SmmnmmmmmnmmmS",
    "smmmmNmmmmmmms",
    "kNNNNNNNNNNNNk",
]


def mimic(open_=0, dx=0, dy=0, tell=False):
    f = Canvas()
    x0 = 9 + dx
    body_y = 23 + dy
    f.stamp(BODY, x0, body_y)
    lid_y = 18 + dy - open_
    gap = list(range(lid_y + 5, body_y))  # filas de boca entre tapa y cuerpo
    for gi, y in enumerate(gap):
        for x in range(x0 + 1, x0 + 13):
            if len(gap) == 1:
                k = 'y' if (tell and x == x0 + 10) else 'o'
            elif gi == 0:
                k = 'W' if (x - x0) % 3 == 1 else 'R'  # colmillos de arriba
            elif gi == len(gap) - 1:
                k = 'W' if (x - x0) % 3 == 2 else 'R'  # colmillos de abajo
            else:
                k = 'R'
                if gi == len(gap) - 2 and x0 + 6 <= x <= x0 + 10:
                    k = 'p'                             # lengua
                if gi == 1 and x in (x0 + 9, x0 + 11) and len(gap) >= 4:
                    k = 'y'                             # ojos
            f.set(x, y, k)
    lid = [r for r in LID]
    f.stamp(lid, x0 - (open_ // 3), lid_y)
    return Frame(f)


def build():
    idle = [mimic() for _ in range(4)] + [mimic(open_=1, tell=True), mimic()]
    wake = [mimic(dx=-1), mimic(dx=1, open_=1, tell=True), mimic(dx=-1),
            mimic(open_=2), mimic(open_=4)]
    hop = [(0, -1), (-2, 2), (-4, 3), (-3, 3), (-1, 2), (0, -1)]
    walk = [mimic(dy=d, open_=o) for d, o in hop]
    atk = [(0, 4), (-1, 5), (-1, 6), (0, 6), (2, 2), (3, 0), (1, 1), (0, 2)]
    attack = [mimic(dx=d, open_=o) for d, o in atk]
    hurt = [mimic(dx=-1, open_=2), mimic(dx=-2, open_=3), mimic(dx=0, open_=1)]
    return {
        'idle': idle,
        'wake': wake,
        'movement': walk,
        'attack': attack,
        'take_damage': hurt,
        'death': death_frames(mimic(open_=4), 8, seed=11),
    }
