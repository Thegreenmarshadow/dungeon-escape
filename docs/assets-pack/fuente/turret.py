from lib import Canvas, Frame, death_frames

PEDESTAL = [
    "TTSSSSSSSSTs",
    "SSSSSSSSSSss",
    "kkkkkkkkkkkk",
    ".sSskTSsSks.",
    ".sssksssskk.",
    ".kkkkkkkkkk.",
    ".SsksSssksk.",
    ".sskssksksk.",
    "TSSSSSSSSSSs",
]
SKULL = [
    "..BWWWE..",
    ".BWWWWWE.",
    "BWWWWWWWW",
    "B12WWW12W",
    "b21WBW21B",
    ".bBWoWBB.",
    "..bWoWb..",
]
FLAMES = [
    [0, 1, 3, 2, 4, 2, 3, 1, 0],
    [0, 2, 2, 4, 3, 3, 2, 2, 0],
    [1, 1, 3, 3, 5, 2, 2, 1, 0],
    [0, 2, 3, 2, 4, 3, 2, 1, 1],
]


def turret(phase=0, charge=0, mouth=0, dx=0, flash=False):
    f, t = Canvas(), Canvas()
    f.stamp(PEDESTAL, 10 + dx, 20)
    # huesos sueltos al pie
    f.stamp(["W.E", "BWB"], 6, 27)
    f.stamp(["BW"], 23 + dx, 28)
    eye1, eye2 = [('u', 'v'), ('U', 'u'), ('W', 'u'), ('W', 'U')][charge]
    rows = [r.replace('1', eye1).replace('2', eye2) for r in SKULL]
    if mouth:
        rows[6] = "..bUuUb.." if mouth == 1 else ".bUWWWUb."
    f.stamp(rows, 11 + dx, 13)
    # llama espectral sobre el cráneo
    hs = FLAMES[phase % 4]
    for i, h in enumerate(hs):
        # al cargar, la llama crece solo en el centro
        h += ({3: 1, 4: 2, 5: 1}.get(i, 0) * charge + 1) // 2 if charge else 0
        for j in range(h):
            y = 12 - j
            k = ('W' if charge >= 2 and 3 <= i <= 5 and j < 2 else 'U') if j == 0 and 2 <= i <= 6 else ('u' if j < h - 1 else 'v')
            f.set(11 + dx + i, y, k)
    if flash:
        cx, cy = 15 + dx, 18
        for ox, oy in ((0, -10), (0, 10), (-10, 0), (10, 0)):
            t.set(cx + ox, cy + oy, 'W')
            for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                t.set(cx + ox + sx, cy + oy + sy, 'U')
    return Frame(f, t)


def orb_frames(core='W', mid='U', ring='u', edge='v'):
    out = []
    for r in (3, 4, 3, 2):
        c = Canvas(16, 16)
        for y in range(16):
            for x in range(16):
                d = ((x - 7.5) ** 2 + (y - 7.5) ** 2) ** 0.5
                if d <= r - 0.0:
                    k = core if d < r * 0.35 else (mid if d < r * 0.65 else ring)
                    c.set(x, y, k)
                elif d <= r + 0.7:
                    c.set(x, y, edge)
        c.set(6, 6, core)
        out.append(Frame(c))
    return out


def build():
    idle = [turret(phase=i) for i in range(4)]
    attack = [
        turret(phase=0, charge=1),
        turret(phase=1, charge=2, mouth=1),
        turret(phase=2, charge=3, mouth=1),
        turret(phase=3, charge=3, mouth=2, flash=True),  # 3: DISPARA
        turret(phase=0, charge=1, mouth=1),
        turret(phase=1),
    ]
    hurt = [turret(dx=-1, charge=2), turret(dx=1, charge=1), turret(dx=0)]
    return {
        'idle': idle,
        'attack': attack,
        'take_damage': hurt,
        'death': death_frames(turret(), 10, seed=7),
    }
