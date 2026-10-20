"""Recolorea el tileset del calabozo a otro tema conservando el layout exacto
(mismas coordenadas de atlas y colisiones: solo cambia la textura)."""
import sys, colorsys
from PIL import Image

# Colores de suelo y paredes del tileset original (sección 2.2 + los que aparecen en el pack)
ENV = ['1e1616', '362030', '3d253b', '422c3b', '483040', '4c2f49', '4f3740', '523b40',
       '543740', '593756', '6e4a48', '724736', '78514f', '895a45']

RAMPS = {  # oscuro -> claro
    'lava': ['1a1012', '2b1b1e', '3a2224', '45282a', '512c2b', '5a2f2c', '6b3a30', '7a4232', '8e4a3a', 'a85a3c'],
    'ice':  ['1b2230', '222b3b', '293446', '303c50', '36445a', '3d4d64', '475a73', '56697f', '68798e', '7b8ea3'],
    'moss': ['191f17', '1e261c', '232d21', '293427', '2f3b2c', '364333', '3e4b39', '4b5a43', '5a6b4c', '6b7d55'],
}


def hexrgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def lum(rgb):
    r, g, b = rgb
    return 0.299 * r + 0.587 * g + 0.114 * b


def build_map(env, ramp):
    env_sorted = sorted(env, key=lambda h: lum(hexrgb(h)))
    n, m = len(env_sorted), len(ramp)
    return {hexrgb(h): hexrgb(ramp[round(i * (m - 1) / max(1, n - 1))]) for i, h in enumerate(env_sorted)}


def retheme(src, dst, theme, env=ENV):
    cmap = build_map(env, RAMPS[theme])
    im = Image.open(src).convert('RGBA')
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a and (r, g, b) in cmap:
                px[x, y] = cmap[(r, g, b)] + (a,)
    im.save(dst)


if __name__ == '__main__':
    retheme(sys.argv[1], sys.argv[2], sys.argv[3])
