import os, shutil
from lib import save_strip
from export import tres
from weapons import WEAPONS

OUT = 'out'

STATS = {
    'sword': dict(name='Espada', desc='Equilibrada. La que ya usa el caballero.',
                  damage=1, hitbox_size=(12, 18), hitbox_distance=10, active_time=0.2, cooldown=0.4),
    'dagger': dict(name='Daga', desc='Muy rápida y de poco alcance. Para golpear y salir.',
                   damage=1, hitbox_size=(10, 10), hitbox_distance=9, active_time=0.1, cooldown=0.2,
                   knockback=6, move_speed_while_attacking=1.0),
    'axe': dict(name='Hacha', desc='Lenta, barre un arco amplio y hace 2 de daño.',
                damage=2, hitbox_size=(20, 30), hitbox_distance=12, windup=0.15, active_time=0.25,
                cooldown=0.8, knockback=16, move_speed_while_attacking=0.5),
    'spear': dict(name='Lanza', desc='Estocada larga y angosta; atraviesa a varios enemigos.',
                  damage=1, hitbox_size=(26, 6), hitbox_distance=20, windup=0.05, active_time=0.15,
                  cooldown=0.55, knockback=12, move_speed_while_attacking=0.7),
    'mace': dict(name='Maza', desc='Golpe al suelo con onda: empuja y aturde a todo lo cercano.',
                 damage=1, hitbox_size=(0, 0), hitbox_distance=14, hitbox_radius=14, windup=0.25,
                 active_time=0.1, cooldown=0.9, knockback=24, move_speed_while_attacking=0.3,
                 stun_time=0.5),
    'shield': dict(name='Escudo', desc='Mantener el botón bloquea el daño de frente. Empujón sin daño.',
                   damage=0, hitbox_size=(10, 16), hitbox_distance=8, active_time=0.15, cooldown=1.0,
                   knockback=20, block_angle=90, move_speed_while_blocking=0.5),
}


def weapon_tres(wid, d, grip, base):
    def v2(t):
        return f'Vector2({t[0]}, {t[1]})'
    lines = [
        '[gd_resource type="Resource" script_class="WeaponData" load_steps=6 format=3]', '',
        '[ext_resource type="Script" path="res://scripts/weapon_data.gd" id="1_script"]',
        f'[ext_resource type="Texture2D" path="{base}/{wid}_icon.png" id="2_icon"]',
        f'[ext_resource type="Texture2D" path="{base}/{wid}_held.png" id="3_held"]',
        f'[ext_resource type="SpriteFrames" path="{base}/{wid}_fx.tres" id="4_fx"]', '',
        '[resource]',
        'script = ExtResource("1_script")',
        f'id = &"{wid}"',
        f'display_name = "{d["name"]}"',
        f'description = "{d["desc"]}"',
        'icon = ExtResource("2_icon")',
        'held_texture = ExtResource("3_held")',
        f'held_grip = {v2(grip)}',
        'effect_frames = ExtResource("4_fx")',
        f'damage = {d["damage"]}',
        f'hitbox_size = {v2(d["hitbox_size"])}',
        f'hitbox_distance = {float(d["hitbox_distance"])}',
    ]
    for k in ('hitbox_radius', 'windup', 'active_time', 'cooldown', 'knockback',
              'move_speed_while_attacking', 'stun_time', 'block_angle', 'move_speed_while_blocking'):
        if k in d:
            lines.append(f'{k} = {float(d[k])}')
    return '\n'.join(lines) + '\n'


def main():
    os.makedirs(f'{OUT}/scripts', exist_ok=True)
    shutil.copy('weapon_data.gd', f'{OUT}/scripts/weapon_data.gd')
    for wid, (ic, held, hs, grip, fx, fs, fps) in WEAPONS.items():
        d = f'{OUT}/assets/weapons/{wid}'
        base = f'res://assets/weapons/{wid}'
        os.makedirs(d, exist_ok=True)
        save_strip([ic()], f'{d}/{wid}_icon.png', 16)
        save_strip([held()], f'{d}/{wid}_held.png', hs)
        frames = fx()
        save_strip(frames, f'{d}/{wid}_fx.png', fs)
        open(f'{d}/{wid}_fx.tres', 'w').write(
            tres([('default', f'{base}/{wid}_fx.png', len(frames), fps, False)], fs))
        open(f'{d}/{wid}.tres', 'w').write(weapon_tres(wid, STATS[wid], grip, base))


if __name__ == '__main__':
    main()
