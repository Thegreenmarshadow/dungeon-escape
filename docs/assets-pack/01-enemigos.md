# Enemigos y proyectiles

Cuatro enemigos nuevos (versión 2, con más detalle) y tres proyectiles. Estilo de la biblia de personajes:

- frames de 32 × 32 en tiras horizontales; los proyectiles e íconos son de 16 × 16;
- contorno de 1 px `#25131a`;
- colores de la paleta 2.2, con sombreado de 2–3 tonos;
- alfa binario;
- miran a la derecha;
- pies en la fila 29.

Todo es arte original hecho por código: no se copió ni se modificó nada del pack de Pixel_Poem.

## Cómo usarlos

En la escena del enemigo (copia de `Vampire.tscn`), asignar el `*_frames.tres` al `AnimatedSprite2D` y dejar `offset = Vector2(0, -5)`. Los pasos completos están en la sección 7 de la biblia de personajes.

## Enemigos (`assets/enemies/`)

Los `.tres` ya traen los nombres que espera `EnemyBase` (`idle`, `walk`, `hurt`, `death`, `attack`), con `hurt` y `death` sin loop. Los FPS también están puestos en los `.tres`.

La posición de salida del proyectil es relativa al nodo raíz y ya incluye el `offset (0, -5)`. Si `flip_h` está activo, hay que invertir la X.

| Enemigo | Detalle | Animaciones (frames) | Frame de impacto | Aviso | Salida del proyectil |
|---|---|---|---|---|---|
| `archer`: esqueleto arquero | capucha de cuero, taparrabos rojo, aljaba con 3 flechas, arco con empuñadura envuelta | idle 6, walk 8, attack 8 (8 FPS), hurt 5, death 12 | **5**: suelta la flecha | 625 ms | `(8, -2)` |
| `skull_turret`: torre de calaveras | pedestal de ladrillo, huesos al pie, llama espectral | idle 4, walk = idle, attack 6 (7 FPS), hurt 3, death 10 | **3**: dispara | 430 ms | `(0, -3)` |
| `mimic`: cofre mímico | tablones con nudos, esquinas y remaches de metal, cerradura dorada | idle 6, wake 5, walk 6, attack 8 (7 FPS), hurt 3, death 8 | **4–5**: mordida | 570 ms | — |
| `mage`: mago del orbe | capucha con brillo, cinturón dorado, pliegues en la túnica | idle 6, walk 8, attack 10 (10 FPS), hurt 5, death 10 | **6**: lanza el orbe | 600 ms | `(6, -15)` |

Notas:

- **Mímico:** reproducir `wake` al descubrirlo y no hacer daño por contacto mientras está en `idle`. El frame 4 de `idle` deja ver un ojo: es la pista para el jugador atento.
- **Torre y mímico:** el aviso de la torre (430 ms) y el del mímico (570 ms) quedan por debajo de los 600 ms que pide la sección 6.1. Si quieres cumplirla, sube la `duration` de los primeros frames de `attack`.
- **Proyectiles (`assets/projectiles/`):**
  - `arrow.png`: apunta a la derecha; rotarla con `rotation = dir.angle()`.
  - `orb_blue.png`: el de la torre.
  - `orb_gold.png`: el del mago. Cuando el jugador lo devuelve, se puede teñir con `modulate = Color(0.7, 0.9, 1.0)`.
