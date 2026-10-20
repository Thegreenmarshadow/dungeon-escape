import os, math, shutil
from PIL import Image, ImageDraw, ImageFont
from lib import font, save_strip
from export import tres
import weapons2 as w2

OUT = 'out'

# Stats propuestos (la espada de player.gd es la referencia: daño 1, activo 0.2 s, enfriamiento 0.4 s)
STATS = {
    'katana': dict(desc='Corte rapidísimo y largo; a veces hace el doble.', rarity='rare', min_level=4,
                   damage=1, hitbox_size=(22, 8), hitbox_distance=14, active_time=0.12, cooldown=0.3,
                   knockback=8, crit_chance=0.2),
    'greatsword': dict(desc='Barrido enorme de 180° que hace 2 de daño. Muy lento.', rarity='rare', min_level=6,
                       damage=2, hitbox_distance=22, sweep_degrees=180, windup=0.3, active_time=0.25,
                       cooldown=1.0, knockback=20, move_speed_while_attacking=0.4),
    'rapier': dict(desc='Estocada fina y veloz; muchos críticos.', rarity='common', min_level=2,
                   damage=1, hitbox_size=(24, 4), hitbox_distance=16, active_time=0.08, cooldown=0.25,
                   knockback=4, crit_chance=0.3, pierce=False),
    'scythe': dict(desc='Barrido de 270°. Cada 6 enemigos eliminados cura 1 vida.', rarity='epic', min_level=10,
                   damage=1, hitbox_distance=21, sweep_degrees=270, windup=0.2, active_time=0.3, cooldown=0.9,
                   knockback=12, move_speed_while_attacking=0.6, heal_every_kills=6),
    'warhammer': dict(desc='Golpe al suelo que hace 2 de daño, aturde y rompe escudos.', rarity='epic', min_level=9,
                      damage=2, hitbox_radius=18, hitbox_distance=16, windup=0.4, active_time=0.1, cooldown=1.2,
                      knockback=28, stun_time=0.8, move_speed_while_attacking=0.2),
    'flail': dict(desc='Mantener el botón para girar: daña todo alrededor sin parar.', rarity='rare', min_level=7,
                  damage=1, hitbox_radius=20, hitbox_distance=0, active_time=0.1, cooldown=0.5, knockback=14,
                  move_speed_while_attacking=0.6, spin=True, spin_tick=0.35),
    'whip': dict(desc='El alcance más largo. Jala al enemigo hacia ti y lo aturde un momento.', rarity='common',
                 min_level=3, damage=1, hitbox_size=(30, 6), hitbox_distance=22, windup=0.1, active_time=0.12,
                 cooldown=0.6, knockback=-12, stun_time=0.3, pierce=False),
    'halberd': dict(desc='Largo alcance y un barrido ancho al final de la estocada.', rarity='rare', min_level=5,
                    damage=1, hitbox_size=(14, 26), hitbox_distance=22, windup=0.15, active_time=0.2,
                    cooldown=0.7, knockback=18, move_speed_while_attacking=0.7),
    'trident': dict(desc='Tres puntas en paralelo: atraviesa filas de enemigos.', rarity='rare', min_level=6,
                    damage=1, hitbox_size=(26, 12), hitbox_distance=20, windup=0.1, active_time=0.15,
                    cooldown=0.6, knockback=10),
    'claws': dict(desc='Combo de 3 zarpazos; cada uno puede hacer sangrar.', rarity='common', min_level=3,
                  damage=1, hitbox_size=(10, 14), hitbox_distance=10, active_time=0.08, cooldown=0.7,
                  knockback=4, combo_hits=3, combo_gap=0.15, status_effect='bleed', status_chance=0.25,
                  status_time=2.0),
    'boomerang': dict(desc='Se lanza, atraviesa enemigos y vuelve. Solo uno a la vez.', rarity='common',
                      min_level=2, damage=1, hitbox_size=(10, 10), hitbox_distance=0, active_time=0.0,
                      cooldown=0.2, knockback=8, projectile_speed=140, projectile_range=80,
                      projectile_returns=True, projectile_pierce=True),
    'crossbow': dict(desc='Virote rápido de largo alcance; hay que recargar.', rarity='rare', min_level=5,
                     damage=1, hitbox_size=(6, 4), hitbox_distance=0, windup=0.1, active_time=0.0, cooldown=0.9,
                     knockback=10, projectile_speed=220, projectile_range=160),
    'fire_staff': dict(desc='Bola de fuego que explota y quema.', rarity='epic', min_level=9,
                       damage=1, hitbox_size=(8, 8), hitbox_distance=0, windup=0.2, active_time=0.0,
                       cooldown=1.1, knockback=12, projectile_speed=110, projectile_range=140,
                       impact_radius=14, status_effect='burn', status_time=1.5),
    'frost_blade': dict(desc='Como la espada, pero cada golpe ralentiza al enemigo.', rarity='rare', min_level=5,
                        damage=1, hitbox_size=(12, 18), hitbox_distance=10, active_time=0.2, cooldown=0.45,
                        knockback=8, status_effect='slow', status_time=1.5),
    'vine_sickle': dict(desc='Hoz viva: cada 8 golpes acertados recupera 1 vida.', rarity='rare', min_level=13,
                        damage=1, hitbox_size=(14, 16), hitbox_distance=9, active_time=0.15, cooldown=0.35,
                        knockback=8, heal_every_hits=8),
}


def gd_value(v):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, tuple):
        return f'Vector2({v[0]}, {v[1]})'
    if isinstance(v, str):
        return f'&"{v}"'
    return f'{float(v)}'


INT_KEYS = {'damage', 'combo_hits', 'heal_every_hits', 'heal_every_kills', 'min_level'}


def weapon_tres(wid, name, d, grip, base, has_proj, has_hit):
    ext = [
        '[ext_resource type="Script" path="res://scripts/weapon_data.gd" id="1_script"]',
        f'[ext_resource type="Texture2D" path="{base}/{wid}_icon.png" id="2_icon"]',
        f'[ext_resource type="Texture2D" path="{base}/{wid}_held.png" id="3_held"]',
        f'[ext_resource type="SpriteFrames" path="{base}/{wid}_fx.tres" id="4_fx"]',
    ]
    if has_proj:
        ext.append(f'[ext_resource type="SpriteFrames" path="{base}/{wid}_projectile.tres" id="5_proj"]')
    if has_hit:
        ext.append(f'[ext_resource type="SpriteFrames" path="{base}/{wid}_impact.tres" id="6_hit"]')
    lines = [f'[gd_resource type="Resource" script_class="WeaponData" load_steps={len(ext) + 1} format=3]', '',
             *ext, '', '[resource]', 'script = ExtResource("1_script")',
             f'id = &"{wid}"', f'display_name = "{name}"', f'description = "{d["desc"]}"',
             'icon = ExtResource("2_icon")', 'held_texture = ExtResource("3_held")',
             f'held_grip = Vector2({grip[0]}, {grip[1]})', 'effect_frames = ExtResource("4_fx")']
    if has_proj:
        lines.append('projectile_frames = ExtResource("5_proj")')
    if has_hit:
        lines.append('impact_frames = ExtResource("6_hit")')
    for k, v in d.items():
        if k == 'desc':
            continue
        if k in INT_KEYS:
            lines.append(f'{k} = {int(v)}')
        else:
            lines.append(f'{k} = {gd_value(v)}')
    return '\n'.join(lines) + '\n'


# ---------------- GIF de catálogo ----------------
FONT = font(14, True)
RAR = {'common': (0xda, 0xe0, 0xea), 'rare': (0x62, 0xab, 0xd4), 'epic': (0xff, 0xd5, 0x69)}


def catalog_gif(path):
    T, S, CYCLE = 64, 3, 1600
    data = {}
    for wid, (name, held, w, grip, shaft, fx, fs, fps, proj) in w2.WEAPONS2.items():
        data[wid] = dict(name=name, icon=w2.icon(wid).render().image(), held=held_frame_img(wid), grip=grip,
                         fx=[f.render().image() for f in fx()], fps=fps,
                         proj=[f.render().image() for f in proj[0]()] if proj else None,
                         spin=STATS[wid].get('spin', False))
    frames = []
    ids = list(data)
    for t in range(0, CYCLE, 50):
        sheet = Image.new('RGB', (5 * (T * S + 6), 3 * (T * S + 36)), (0x25, 0x13, 0x1a))
        for i, wid in enumerate(ids):
            dd = data[wid]
            im = Image.new('RGBA', (T, T), (0x3d, 0x25, 0x3b, 255))
            d = ImageDraw.Draw(im)
            for g in range(0, T + 1, 16):
                d.line([(g, 0), (g, T)], fill=(0x36, 0x20, 0x30)); d.line([(0, g), (T, g)], fill=(0x36, 0x20, 0x30))
            c = T // 2
            d.ellipse([c - 4, c - 4, c + 4, c + 4], fill=(0x25, 0x13, 0x1a))
            im.alpha_composite(dd['held'], (c - dd['grip'][0], c - dd['grip'][1]))
            fi = int(t / (1000 / dd['fps']))
            if dd['spin']:
                fi %= len(dd['fx'])
            if fi < len(dd['fx']):
                fx = dd['fx'][fi]; im.alpha_composite(fx, (c - fx.width // 2, c - fx.height // 2))
            if dd['proj']:
                dist = int(t / 1000 * 70)
                if wid == 'boomerang' and dist > 26:
                    dist = max(0, 52 - dist)
                if 6 < dist < 30 or (wid == 'boomerang' and dist > 0):
                    p = dd['proj'][int(t / 80) % len(dd['proj'])]
                    im.alpha_composite(p, (min(T - 16, c + dist - 2), c - 8))
            big = im.resize((T * S, T * S), Image.NEAREST).convert('RGB')
            x, y = (i % 5) * (T * S + 6), (i // 5) * (T * S + 36)
            sheet.paste(big, (x, y))
            ib = dd['icon'].resize((32, 32), Image.NEAREST)
            sheet.paste(ib, (x + 2, y + T * S + 2), ib)
            ImageDraw.Draw(sheet).text((x + 38, y + T * S + 18), dd['name'], font=FONT,
                                       fill=RAR[STATS[wid]['rarity']], anchor='lm')
        frames.append(sheet.convert('P', palette=Image.ADAPTIVE, colors=96))
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=50, loop=0)
    return frames


def held_frame_img(wid):
    return w2.held_frame(wid).render().image()


def main():
    os.makedirs(f'{OUT}/scripts', exist_ok=True)
    shutil.copy('weapon_data.gd', f'{OUT}/scripts/weapon_data.gd')
    for wid, (name, held, w, grip, shaft, fx, fs, fps, proj) in w2.WEAPONS2.items():
        d = f'{OUT}/assets/weapons/{wid}'; base = f'res://assets/weapons/{wid}'
        os.makedirs(d, exist_ok=True)
        save_strip([w2.icon(wid)], f'{d}/{wid}_icon.png', 16)
        save_strip([w2.held_frame(wid)], f'{d}/{wid}_held.png', (w, 16))
        frames = fx()
        save_strip(frames, f'{d}/{wid}_fx.png', fs)
        open(f'{d}/{wid}_fx.tres', 'w').write(tres([('default', f'{base}/{wid}_fx.png', len(frames), fps,
                                                       bool(STATS[wid].get('spin')))], fs))
        has_hit = False
        if proj:
            pf = proj[0]()
            save_strip(pf, f'{d}/{wid}_projectile.png', 16)
            open(f'{d}/{wid}_projectile.tres', 'w').write(
                tres([('default', f'{base}/{wid}_projectile.png', len(pf), proj[1], True)], 16))
            if wid == 'fire_staff':
                hf = w2.proj_fire_hit(); has_hit = True
                save_strip(hf, f'{d}/{wid}_impact.png', 32)
                open(f'{d}/{wid}_impact.tres', 'w').write(
                    tres([('default', f'{base}/{wid}_impact.png', len(hf), 14, False)], 32))
        open(f'{d}/{wid}.tres', 'w').write(weapon_tres(wid, name, STATS[wid], grip, base, bool(proj), has_hit))
    os.makedirs(f'{OUT}/docs/vista_previa', exist_ok=True)
    catalog_gif(f'{OUT}/docs/vista_previa/armas_15.gif')


if __name__ == '__main__':
    main()
