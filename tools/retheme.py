"""Recolorea el tileset del calabozo a otro tema conservando el layout exacto
(mismas coordenadas de atlas y colisiones: solo cambia la textura).

Solo se tocan los tiles de suelo y pared (ENV_TILES). Puertas, cofres, llaves,
monedas, pociones, antorchas y demás objetos del atlas quedan idénticos: la
madera de puertas y cofres comparte tonos con las paredes, así que filtrar
solo por color no alcanza. Al terminar se comprueba que ningún píxel fuera de
ENV_TILES cambió.

Uso:
    python3 tools/retheme.py <origen.png> <destino.png> <ice|lava|moss>
"""
import sys
from PIL import Image

TILE = 16
## Tamaño esperado del atlas de Pixel_Poem (10 × 10 tiles de 16 px). La
## máscara de abajo está hecha para ese acomodo.
ATLAS_SIZE = (160, 160)


def _rect(cols, rows):
    return {(c, r) for c in cols for r in rows}


## Tiles (columna, fila) de suelo y pared que se recolorean:
## - 0..5 × 0..5: sala de muestra (paredes, esquinas y suelo).
## - 6..9 × 0..2 y 0..3 × 6..7: variantes de suelo.
## - 9:4, 9:5, 9:6, 9:7: parches de pared y suelo sueltos.
## Todo lo demás (puertas en 6..9 × 3..6, cofres y objetos en las filas 6..9)
## queda protegido.
ENV_TILES = (_rect(range(6), range(6)) | _rect(range(6, 10), range(3))
             | _rect(range(4), range(6, 8)) | {(9, 4), (9, 5), (9, 6), (9, 7)})

## Colores de suelo y paredes del tileset original. No incluye los tonos de la
## madera (523b40, 724736, 895a45, bf704d) ni el contorno 25131a, que se
## conserva en todos los temas.
ENV = ['1e1616', '362030', '3d253b', '422c3b', '483040', '4c2f49', '4f3740',
       '543740', '593756', '6e4a48', '78514f']

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


def is_env_pixel(x, y):
    return (x // TILE, y // TILE) in ENV_TILES


def changed_protected_pixels(original, themed):
    """Píxeles fuera de ENV_TILES que difieren entre las dos imágenes."""
    a, b = original.convert('RGBA').load(), themed.convert('RGBA').load()
    w, h = original.size
    return [(x, y) for y in range(h) for x in range(w)
            if not is_env_pixel(x, y) and a[x, y] != b[x, y]]


def retheme_image(im, theme, env=ENV):
    if im.size != ATLAS_SIZE:
        raise ValueError(f'el atlas mide {im.size}; la máscara espera {ATLAS_SIZE}')
    cmap = build_map(env, RAMPS[theme])
    out = im.convert('RGBA')
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            if not is_env_pixel(x, y):
                continue
            r, g, b, a = px[x, y]
            if a and (r, g, b) in cmap:
                px[x, y] = cmap[(r, g, b)] + (a,)
    return out


def retheme(src, dst, theme, env=ENV):
    original = Image.open(src).convert('RGBA')
    themed = retheme_image(original, theme, env)
    broken = changed_protected_pixels(original, themed)
    if broken:
        raise RuntimeError(f'{len(broken)} píxeles protegidos cambiaron, p. ej. {broken[:5]}')
    themed.save(dst)


if __name__ == '__main__':
    if len(sys.argv) != 4 or sys.argv[3] not in RAMPS:
        sys.exit(__doc__)
    retheme(sys.argv[1], sys.argv[2], sys.argv[3])
