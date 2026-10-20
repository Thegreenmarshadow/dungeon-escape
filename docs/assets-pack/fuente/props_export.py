import os
from lib import save_strip
from export import tres
import dungeon_props as dp

OUT = 'out'


def main():
    for t in dp.THEMES:
        d = f'{OUT}/assets/dungeon_themes/{t}'
        os.makedirs(d, exist_ok=True)
        for name, (frames, fps, loop) in dp.build(t).items():
            fn = f'{t}_{name}.png'
            save_strip(frames, f'{d}/{fn}', 16)
            if len(frames) > 1 and name != 'scatter':
                open(f'{d}/{t}_{name}_frames.tres', 'w').write(
                    tres([('default', f'res://assets/dungeon_themes/{t}/{fn}', len(frames), fps, loop)], 16))
    os.makedirs(f'{OUT}/tools', exist_ok=True)
    import shutil
    shutil.copy('retheme.py', f'{OUT}/tools/retheme.py')


if __name__ == '__main__':
    main()
