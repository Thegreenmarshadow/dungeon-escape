"""Crea los frames del caballero sin la espada dibujada, para que el arma la
muestre el WeaponPivot del jugador.

El sprite original (priest3 v1 de Pixel_Poem) es casi simétrico: el brazo
derecho es el reflejo del izquierdo respecto de la columna MIRROR_X. La espada
sale de la mano derecha hacia arriba a la derecha, así que en las filas del
brazo se copia el reflejo del brazo izquierdo y lo que queda más a la derecha
(la hoja) se borra. Las filas del yelmo no se tocan.

Uso: python3 tools/remove_knight_sword.py   (desde la raíz del proyecto)
No pisa los originales: escribe en priest3/v1_unarmed/.
"""
import os
from PIL import Image

SRC_DIR = 'assets/dungeon/character_animation/priests_idle/priest3/v1'
OUT_DIR = 'assets/dungeon/character_animation/priests_idle/priest3/v1_unarmed'
FRAMES = 4
# x del brazo derecho = MIRROR_X - x del brazo izquierdo.
MIRROR_X = 12
# Columna desde la que se reemplaza: la 10 ya coincide con el reflejo y de la
# 11 en adelante están la mano, el brazo y la hoja.
FIRST_X = 11
# Última fila del brazo; debajo solo hay piernas, que no tocan la espada.
LAST_ROW = 12
# La punta de la hoja es lo único que pasa de esta columna: la primera fila
# donde aparece marca dónde empieza el brazo (más arriba está el yelmo).
TIP_X = 13


def remove_sword(im):
    im = im.convert('RGBA')
    w, h = im.size
    out = im.copy()
    first_row = next(y for y in range(h) if any(im.getpixel((x, y))[3] for x in range(TIP_X, w)))
    for y in range(first_row, LAST_ROW + 1):
        for x in range(FIRST_X, w):
            mx = MIRROR_X - x
            out.putpixel((x, y), im.getpixel((mx, y)) if mx >= 0 else (0, 0, 0, 0))
    return out


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for i in range(1, FRAMES + 1):
        src = os.path.join(SRC_DIR, f'priest3_v1_{i}.png')
        dst = os.path.join(OUT_DIR, f'priest3_v1_unarmed_{i}.png')
        remove_sword(Image.open(src)).save(dst)
        print(dst)


if __name__ == '__main__':
    main()
