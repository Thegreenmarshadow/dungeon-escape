# Dungeon Escape: paquete de assets nuevos

Esta es la recopilación de todo lo creado para el juego: enemigos, jefes temáticos, armas del caballero y objetos para tres mazmorras nuevas. Hay 138 imágenes y 79 recursos de Godot (`.tres`).

![Hoja general](docs/vista_previa/hoja_general.png)

## Contenido

| Categoría | Qué trae | Carpeta | Archivos | Guía |
|---|---|---|---|---|
| Enemigos | esqueleto arquero, torre de calaveras, cofre mímico, mago del orbe | `assets/enemies/` | 20 PNG + 4 `SpriteFrames` | [docs/01-enemigos.md](docs/01-enemigos.md) |
| Proyectiles | flecha, orbe azul, orbe dorado | `assets/projectiles/` | 3 PNG + 3 `SpriteFrames` | [docs/01-enemigos.md](docs/01-enemigos.md) |
| Armas del caballero | 6 base + 15 nuevas: ícono, arma en mano, efecto de ataque, proyectil (si es a distancia) y stats | `assets/weapons/<id>/` | 67 PNG + 46 `.tres` | [docs/02-armas.md](docs/02-armas.md) |
| Jefes temáticos | Forjador de magma, Reina liche de escarcha, Guardián musgoso + 9 efectos de habilidades | `assets/bosses/<id>/` | 27 PNG + 12 `SpriteFrames` | [docs/03-jefes.md](docs/03-jefes.md) |
| Temas de mazmorra | cripta helada, fragua de lava, ruinas con musgo: 7 objetos por tema | `assets/dungeon_themes/<tema>/` | 21 PNG + 14 `SpriteFrames` | [docs/04-temas-mazmorra.md](docs/04-temas-mazmorra.md) |
| Código | `WeaponData` (recurso de armas) | `scripts/weapon_data.gd` | 1 | [docs/02-armas.md](docs/02-armas.md) |
| Herramienta | recolorear el tileset a cada tema | `tools/retheme.py` | 1 | [docs/04-temas-mazmorra.md](docs/04-temas-mazmorra.md) |

La lista completa de archivos, con tamaños y cantidad de frames, está en [docs/inventario.md](docs/inventario.md). Los GIF y las hojas de vista previa están en `docs/vista_previa/`.

## Estructura

```
assets/
├─ enemies/          enemies-<id>_<anim>.png  +  <id>_frames.tres
├─ projectiles/      arrow, orb_blue, orb_gold (.png + _frames.tres)
├─ weapons/<id>/     <id>_icon.png, <id>_held.png, <id>_fx.png(.tres), <id>.tres
│                    [+ <id>_projectile.png(.tres), <id>_impact.png(.tres)]
├─ bosses/<id>/      boss-<id>_<anim>.png, <id>_frames.tres, fx-<efecto>.png(.tres)
└─ dungeon_themes/<tema>/  <tema>_<objeto>.png  [+ _frames.tres]
scripts/weapon_data.gd
tools/retheme.py
docs/                guías, inventario y vista previa
fuente/              código Python que genera todo (python3 build_all.py)
```

Las rutas dentro de los `.tres` son `res://assets/...` y `res://scripts/...`. Copiando las carpetas en la raíz del proyecto funcionan sin cambios. Se comprobó que las 79 referencias apuntan a archivos que existen.

## Cómo incorporarlo (orden recomendado)

1. **Copiar** `assets/` y `scripts/` en la raíz del proyecto. No pisan ningún archivo que ya exista.
2. **Abrir Godot** para que importe los PNG. El proyecto ya usa filtro Nearest y no hace falta tocar nada.
3. **Agregar `scripts/weapon_data.gd`** antes de abrir los `.tres` de armas, porque dependen de él.
4. **Enemigos.** Duplicar `Vampire.tscn` o `Skull.tscn`, asignar el `<id>_frames.tres` al `AnimatedSprite2D` con `offset = (0, -5)` y seguir la sección 7 de la biblia (generador, `LevelBuilder`, `DifficultyCurve`, pruebas). Los frames de impacto y las posiciones de salida de los proyectiles están en `01-enemigos.md`.
5. **Armas.** Preparar al caballero sin espada dibujada, armar el `WeaponPivot` y cargar las armas con `load("res://assets/weapons/<id>/<id>.tres")`. Para empezar alcanza con espada, daga y lanza. Después vienen las mecánicas nuevas (barridos, giro, proyectiles, estados), explicadas en `02-armas.md`.
6. **Jefes.** Un jefe por tema en los niveles 8, 12 y 16. Pegar `03-jefes.md` como sección 9 de la biblia y programarlos con las mecánicas de la sección 9.5. El más sencillo para arrancar es el Forjador.
7. **Temas de mazmorra.** Generar los tilesets con `tools/retheme.py` y cambiar la textura según el nivel (esquema en `04-temas-mazmorra.md`). Después colocar las antorchas, los estandartes y los objetos del tema.

## Lista de comprobación

- [ ] `assets/` y `scripts/` copiados; Godot importó sin errores.
- [ ] Los 4 enemigos tienen escena y aparecen en el generador.
- [x] El caballero tiene su sprite sin espada y `WeaponPivot`.
- [x] El arma inicial (`sword.tres`) funciona igual que antes.
- [ ] Armas nuevas: rareza y `min_level` conectados al botín.
- [ ] Jefes: barra de vida, fase 2 al 50 % y efectos de habilidades.
- [ ] Tilesets de los 3 temas generados y cambio por nivel.
- [ ] Créditos agregados a `assets/CREDITS.md`.

## Pendiente

| Qué | Por qué | Qué hace falta |
|---|---|---|
| Tilesets recoloreados de los 3 temas | hay que partir del tileset real para no teñir la madera de puertas y cofres | adjuntar `Dungeon_Tileset.png`, `dungeon_tileset.tres` y `level_builder.gd` |
| Ajuste de stats | todos los números son propuestas | probar en juego y ajustar con `difficulty_playtest.csv` |

## Para `assets/CREDITS.md`

```
- Enemigos (archer, skull_turret, mimic, mage), proyectiles (arrow, orb_blue, orb_gold),
  21 armas del caballero, jefes temáticos (forge, lich, warden) y objetos de los temas
  ice, lava y moss: arte original generado por código (Python + Pillow) con Claude,
  octubre de 2026. Paleta basada en el estilo del juego. Sin restricciones de licencia
  de terceros.
```

Los tilesets recoloreados con `retheme.py` son modificaciones del pack de **Pixel_Poem** y siguen con su licencia: se usan dentro del juego, pero no se publican sueltos.

## Regenerar o modificar

Desde `fuente/`, `python3 build_all.py` vuelve a crear todo en `out/`; usa Python 3 y Pillow. Cada personaje, arma u objeto es una función con plantillas de texto: cada letra es un color de `lib.py`, y el contorno se agrega solo.
