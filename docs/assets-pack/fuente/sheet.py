from lib import font
"""Hoja general con una muestra de todos los assets."""
from PIL import Image, ImageDraw, ImageFont
import archer, turret, mimic, mage, bosses, weapons, weapons2, dungeon_props as dp
from export import arrow_frame

F = font(22, True)
F2 = font(11)
BG, CARD, TXT, SUB = (0x25, 0x13, 0x1a), (0x3d, 0x25, 0x3b), (0xda, 0xe0, 0xea), (0xb1, 0x9d, 0x83)
W = 1400


def img(fr):
    return fr.render().image()


def main(paths):
    en = [(img(m.build()['idle'][0]), n) for m, n in ((archer, 'Esqueleto arquero'), (turret, 'Torre de calaveras'),
                                                       (mimic, 'Cofre mímico'), (mage, 'Mago del orbe'))]
    pr = [(img(arrow_frame()), 'Flecha'), (img(turret.orb_frames('W', 'U', 'u', 'v')[1]), 'Orbe azul'),
          (img(turret.orb_frames('E', 'y', 'G', 'g')[1]), 'Orbe dorado')]
    bs = [(img(bosses.build_forge()['idle'][0]), 'Forjador de magma'), (img(bosses.build_lich()['idle'][0]), 'Reina liche'),
          (img(bosses.build_warden()['idle'][0]), 'Guardián musgoso')]
    w6 = [(img(f()), n) for f, n in ((weapons.icon_sword, 'Espada'), (weapons.icon_dagger, 'Daga'), (weapons.icon_axe, 'Hacha'),
                                     (weapons.icon_spear, 'Lanza'), (weapons.icon_mace, 'Maza'), (weapons.icon_shield, 'Escudo'))]
    w15 = [(img(weapons2.icon(k)), v[0]) for k, v in weapons2.WEAPONS2.items()]
    th = []
    for t, nm in (('ice', 'Cripta'), ('lava', 'Fragua'), ('moss', 'Ruinas')):
        b = dp.build(t)
        for key in ('torch', 'banner', 'emblem', 'floor_rune', 'prop'):
            th.append((img(b[key][0][0]), nm))
    groups = [('Enemigos', en, 5), ('Jefes temáticos', bs, 4), ('Proyectiles', pr, 5), ('Armas base (6)', w6, 5),
              ('Armas nuevas (15)', w15, 5), ('Objetos de mazmorra (3 temas, 5 de muestra c/u)', th, 5)]
    layout, y = [], 70
    for title, items, sc in groups:
        cell = max(max(i.width, i.height) for i, _ in items) * sc + 20
        per = max(1, (W - 40) // (cell + 10))
        rows = (len(items) + per - 1) // per
        layout.append((title, items, sc, cell, per, y))
        y += 40 + rows * (cell + 30)
    out = Image.new('RGB', (W, y + 20), BG)
    d = ImageDraw.Draw(out)
    d.text((20, 18), 'Dungeon Escape · assets nuevos', font=F, fill=(0xff, 0xd5, 0x69))
    for title, items, sc, cell, per, y0 in layout:
        d.text((20, y0), title, font=F, fill=TXT)
        for i, (im, name) in enumerate(items):
            x = 20 + (i % per) * (cell + 10)
            yy = y0 + 36 + (i // per) * (cell + 30)
            d.rectangle([x, yy, x + cell, yy + cell], fill=CARD)
            b = im.resize((im.width * sc, im.height * sc), Image.NEAREST)
            out.paste(b, (x + (cell - b.width) // 2, yy + (cell - b.height) // 2), b)
            d.text((x + cell // 2, yy + cell + 12), name, font=F2, fill=SUB, anchor='mm')
    for p in paths:
        out.save(p)


if __name__ == '__main__':
    main(['out/docs/vista_previa/hoja_general.png'])
