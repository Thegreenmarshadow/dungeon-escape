"""Mini librería de pixel art para Dungeon Escape.

Se dibuja solo el relleno; el contorno de 1 px (#25131a) se agrega solo.
"""
import random
from PIL import Image

PAL = {
    'o': '25131a',  # contorno
    # hueso
    'W': 'dae0ea', 'B': 'b3b2a1', 'b': '827860', 'E': 'e6e6e6',
    # rojo
    'r': 'be2b25', 'R': '79191d', 'p': 'bc4c51', 'P': '9b534a',
    # marrón
    'n': '79593f', 'N': '4b3726', 'm': '5e4e3a', 'M': 'b19d83', 'h': '827860', 'H': '676057',
    # oro / fuego
    'g': 'd9701a', 'G': 'ffd569', 'y': 'ffed56', 'q': 'd1851e',
    # azul espectral
    'u': '62abd4', 'U': 'a7d1e6', 'v': '577ea1', 'V': '56587b',
    # metal / piedra gris
    'k': '3e4652', 's': '6d758d', 'S': '989eb3', 'T': 'b3b9d1',
    # tema fragua de lava
    'a': '2b1b1e', 'A': '45282a', 'c': '6b3a30', 'C': '8e4a3a', 'l': 'ff8a2a',
    # tema cripta helada
    'i': '2c3a52', 'I': '4a6a8a', 'j': '8fb8d0', 'J': 'd8f0f8',
    # tema ruinas con musgo
    'e': '23331f', 'f': '3d5a2c', 'F': '6b8f3a', 'x': 'a8c84a', 'z': '3fa88a', 'Z': '9ff0c0',
}
RGB = {k: tuple(int(v[i:i + 2], 16) for i in (0, 2, 4)) for k, v in PAL.items()}

FLOOR_ROW = 28  # última fila de relleno; el contorno cae en la 29


class Canvas:
    def __init__(self, w=32, h=32):
        self.w, self.h = w, h
        self.px = {}  # (x, y) -> clave de color

    def copy(self):
        c = Canvas(self.w, self.h)
        c.px = dict(self.px)
        return c

    def set(self, x, y, k):
        if k in ('.', ' ', None):
            return
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[(x, y)] = k

    def stamp(self, rows, x0, y0, flip=False):
        if isinstance(rows, str):
            rows = [r for r in rows.strip('\n').split('\n')]
        for dy, row in enumerate(rows):
            row = row.strip() if False else row
            if flip:
                row = row[::-1]
            for dx, ch in enumerate(row):
                self.set(x0 + dx, y0 + dy, ch)

    def line(self, x0, y0, x1, y1, k):
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            self.set(x0, y0, k)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def rect(self, x, y, w, h, k):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.set(xx, yy, k)

    def shift(self, dx, dy):
        c = Canvas(self.w, self.h)
        for (x, y), k in self.px.items():
            c.set(x + dx, y + dy, k)
        return c

    def outlined(self):
        c = self.copy()
        for (x, y) in list(self.px):
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if (nx, ny) not in self.px:
                    c.set(nx, ny, 'o')
        return c

    def overlay(self, other):
        c = self.copy()
        c.px.update(other.px)
        return c

    def image(self):
        im = Image.new('RGBA', (self.w, self.h), (0, 0, 0, 0))
        for (x, y), k in self.px.items():
            im.putpixel((x, y), RGB[k] + (255,))
        return im


class Frame:
    """Relleno (se contornea) + capa encima sin contorno (cuerdas, chispas)."""

    def __init__(self, fill=None, top=None):
        self.fill = fill or Canvas()
        self.top = top or Canvas()

    def render(self):
        return self.fill.outlined().overlay(self.top)


# ---------- transformaciones genéricas ----------

def hurt_frames(base, n=5, floor=FLOOR_ROW, height=16):
    """Retroceso: el cuerpo se inclina hacia atrás (izquierda) y vuelve."""
    leans = [2, 3, 2, 1, 0][:n] if n >= 5 else [2, 3, 1][:n]
    out = []
    for lean in leans:
        f = Canvas(base.fill.w, base.fill.h)
        for (x, y), k in base.fill.px.items():
            t = (floor - y) / float(height)
            f.set(x - round(lean * t), y - (1 if lean >= 3 and y < floor - 2 else 0), k)
        out.append(Frame(f))
    return out


def death_frames(base, n=10, seed=1, cx=16, floor=FLOOR_ROW):
    """Se desmorona hasta un montón y luego se deshace por píxeles."""
    rnd = random.Random(seed)
    pts = list(base.fill.px.items())
    jitter = {p: rnd.uniform(-1, 1) for p, _ in pts}
    order = {p: rnd.random() for p, _ in pts}
    collapse = max(3, n - 4)
    out = []
    for i in range(n):
        f = Canvas(base.fill.w, base.fill.h)
        if i < collapse:
            s = 1 - 0.7 * (i + 1) / collapse  # escala vertical
            spread = 1 + 0.6 * (i + 1) / collapse
            keep = 1.0
        else:
            s, spread = 0.3, 1.6
            keep = 1 - (i - collapse + 1) / (n - collapse + 1)
        # ordenar de abajo hacia arriba para que lo de arriba tape
        for (x, y), k in sorted(pts, key=lambda it: it[0][1]):
            if order[(x, y)] > keep:
                continue
            ny = floor - round((floor - y) * s)
            nx = cx + round((x - cx) * spread + jitter[(x, y)] * (1 - s) * 2)
            f.set(nx, ny, k)
        out.append(Frame(f))
    return out


def save_strip(frames, path, size=32):
    w, h = size if isinstance(size, tuple) else (size, size)
    im = Image.new('RGBA', (w * len(frames), h), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        im.paste(fr.render().image() if isinstance(fr, Frame) else fr.image(), (i * w, 0))
    im.save(path)
    return im


def font(size, bold=False):
    """Fuente para las vistas previas; si no está DejaVu, usa la de Pillow."""
    from PIL import ImageFont
    for name in (('DejaVuSans-Bold.ttf', 'arialbd.ttf') if bold else ('DejaVuSans.ttf', 'arial.ttf')):
        for base in ('/usr/share/fonts/truetype/dejavu/', ''):
            try:
                return ImageFont.truetype(base + name, size)
            except OSError:
                pass
    return ImageFont.load_default()
