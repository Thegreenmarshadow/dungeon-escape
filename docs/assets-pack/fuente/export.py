import os, shutil
from lib import Canvas, Frame, save_strip
import archer, turret, mimic, mage
from preview import preview

OUT = 'out'
ENEMY_DIR = 'assets/enemies'
PROJ_DIR = 'assets/projectiles'
GODOT_NAME = {'idle': 'idle', 'movement': 'walk', 'attack': 'attack',
              'take_damage': 'hurt', 'death': 'death', 'wake': 'wake'}
LOOP = {'idle', 'walk'}

ENEMIES = {
    'archer': (archer, {'idle': 8, 'walk': 10, 'attack': 8, 'hurt': 15, 'death': 14}),
    'skull_turret': (turret, {'idle': 6, 'attack': 7, 'hurt': 12, 'death': 12}),
    'mimic': (mimic, {'idle': 4, 'wake': 10, 'walk': 10, 'attack': 7, 'hurt': 12, 'death': 12}),
    'mage': (mage, {'idle': 8, 'walk': 8, 'attack': 10, 'hurt': 15, 'death': 12}),
}


def arrow_frame():
    c = Canvas(16, 16)
    c.line(3, 8, 11, 8, 'n')
    c.set(12, 8, 'T'); c.set(13, 8, 'S'); c.set(12, 7, 'S'); c.set(12, 9, 'S')
    c.set(2, 7, 'r'); c.set(3, 7, 'r'); c.set(2, 9, 'r'); c.set(3, 9, 'r'); c.set(2, 8, 'p')
    return Frame(c)


def tres(entries, size):
    """entries: [(anim, res_path, n_frames, fps, loop)]; size = lado o (ancho, alto)"""
    w, h = size if isinstance(size, tuple) else (size, size)
    ext, subs, anims = [], [], []
    for i, (anim, path, n, fps, loop) in enumerate(entries):
        eid = f"{i + 1}_{anim}"
        ext.append(f'[ext_resource type="Texture2D" path="{path}" id="{eid}"]')
        frames = []
        for j in range(n):
            sid = f"AtlasTexture_{anim}_{j}"
            subs.append(f'[sub_resource type="AtlasTexture" id="{sid}"]\n'
                        f'atlas = ExtResource("{eid}")\n'
                        f'region = Rect2({j * w}, 0, {w}, {h})')
            frames.append('{\n"duration": 1.0,\n"texture": SubResource("%s")\n}' % sid)
        anims.append('{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %.1f\n}'
                     % (', '.join(frames), 'true' if loop else 'false', anim, fps))
    head = f'[gd_resource type="SpriteFrames" load_steps={len(ext) + len(subs) + 1} format=3]'
    return '\n\n'.join([head, '\n'.join(ext), '\n\n'.join(subs),
                        '[resource]\nanimations = [%s]' % ', '.join(anims)]) + '\n'


def main():
    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(f'{OUT}/{ENEMY_DIR}'); os.makedirs(f'{OUT}/{PROJ_DIR}'); os.makedirs(f'{OUT}/docs/vista_previa')
    for name, (mod, fps) in ENEMIES.items():
        anims = mod.build()
        entries = []
        for file_anim, frames in anims.items():
            g = GODOT_NAME[file_anim]
            fn = f'enemies-{name}_{file_anim}.png'
            save_strip(frames, f'{OUT}/{ENEMY_DIR}/{fn}')
            entries.append((g, f'res://{ENEMY_DIR}/{fn}', len(frames), fps[g], g in LOOP))
        if not any(e[0] == 'walk' for e in entries):  # torreta: walk = idle
            e = entries[0]
            entries.insert(1, ('walk', e[1], e[2], e[3], True))
        open(f'{OUT}/{ENEMY_DIR}/{name}_frames.tres', 'w').write(tres(entries, 32))
        preview(anims, f'{OUT}/docs/vista_previa/{name}.png')
    # proyectiles (16x16)
    projs = {
        'arrow': [arrow_frame()],
        'orb_blue': turret.orb_frames('W', 'U', 'u', 'v'),
        'orb_gold': turret.orb_frames('E', 'y', 'G', 'g'),
    }
    for name, frames in projs.items():
        fn = f'{name}.png'
        save_strip(frames, f'{OUT}/{PROJ_DIR}/{fn}', size=16)
        open(f'{OUT}/{PROJ_DIR}/{name}_frames.tres', 'w').write(
            tres([('default', f'res://{PROJ_DIR}/{fn}', len(frames), 10, True)], 16))
    preview(projs, f'{OUT}/docs/vista_previa/projectiles.png', scale=8, size=16)


if __name__ == '__main__':
    main()
