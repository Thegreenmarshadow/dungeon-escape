from lib import Canvas, Frame, hurt_frames, death_frames

HOOD = [
    "...uvv...",
    "..uvvvV..",
    ".uvvvvvV.",
    ".vvvVoooV",
    "vvvVroroV",
    "vvVVoooo.",
    ".vVVVVVV.",
]
ROBE = [
    "..uvvvvv..",
    ".Vuvvvvvv.",
    ".VvvVvvvvv",
    ".NqqqGqqqq",
    "VVvvVvvVvv",
    "VVvvVvvVvv",
    "VVvvVvvvVvv",
    "VVVvVvvvVvv",
    "kVVVVkVVVkVV",
]


def mage(bob=0, feet=0, sy=0, sdx=0, glow=1, sparks=False):
    f, t = Canvas(), Canvas()
    u = bob
    # pies (debajo de la túnica)
    f.set(13 - feet, 28, 'N'); f.set(14 - feet, 28, 'N')
    f.set(17 + feet, 28, 'N'); f.set(18 + feet, 28, 'N')
    f.stamp(ROBE, 10, 19 + u)
    f.stamp(HOOD, 11, 12 + u)
    # bastón
    sx = 22 + sdx
    f.line(sx, 12 + u + sy, sx, 27, 'n')
    f.set(sx, 13 + u + sy, 'm')
    # brazo / manga sosteniendo el bastón
    f.stamp(["vvv", "vVv"], sx - 3, 21 + u + sy // 2)
    f.set(sx - 1, 21 + u + sy // 2, 'b')  # mano
    # garra que sostiene el orbe
    oy = 9 + u + sy
    f.set(sx - 1, oy + 2, 'q'); f.set(sx + 1, oy + 2, 'q'); f.set(sx, oy + 2, 'q')
    if glow > 0:
        orb = {1: ["g"], 2: ["gGg", "GyG", "gGg"], 3: ["GyG", "yEy", "GyG"]}[glow]
        if glow == 1:
            f.set(sx, oy + 1, 'g')
        else:
            f.stamp(orb, sx - 1, oy - 1)
    if sparks:
        for dx, dy in ((-3, -2), (3, -1), (-2, 3), (2, -4), (4, 2)):
            t.set(sx + dx, oy + dy, 'y')
    return Frame(f, t)


def build():
    idle = [mage(bob=b, glow=2) for b in (0, 0, 1, 1, 1, 0)]
    walk = [mage(bob=b, feet=fe, glow=2) for b, fe in
            ((0, 1), (0, 0), (-1, -1), (-1, 0), (0, 1), (0, 0), (-1, -1), (-1, 0))]
    cast = [
        mage(glow=2),
        mage(sy=-1, glow=2),
        mage(sy=-2, glow=3),
        mage(sy=-2, glow=3, sparks=True),
        mage(sy=-3, glow=3),
        mage(sy=-3, glow=3, sparks=True),
        mage(sdx=2, glow=0),           # 6: LANZA el orbe
        mage(sdx=2, glow=0),
        mage(sdx=1, glow=0),
        mage(glow=1),
    ]
    base = mage(glow=2)
    return {
        'idle': idle,
        'movement': walk,
        'attack': cast,
        'take_damage': hurt_frames(base, 5),
        'death': death_frames(base, 10, seed=5),
    }
