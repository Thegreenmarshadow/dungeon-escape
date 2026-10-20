# Armas del caballero

## Las 6 armas base

Cada arma trae estos archivos:

| Archivo | Qué es |
|---|---|
| `<id>_icon.png` | ícono de 16 × 16 para recogerla del suelo y para el HUD |
| `<id>_held.png` | el arma en la mano, apuntando a la derecha; la empuñadura está en `held_grip` |
| `<id>_fx.png` + `<id>_fx.tres` | estela o impacto, sin loop; cada frame está **centrado en el jugador** y apunta a la derecha |
| `<id>.tres` | recurso `WeaponData` con los stats (requiere `scripts/weapon_data.gd`) |

### Stats propuestos

La espada usa los valores actuales de `player.gd`. Los demás son puntos de partida para probar en juego.

| Arma | Daño | Hitbox | Anticipación | Activo | Enfriamiento | Retroceso | Especial |
|---|---|---|---|---|---|---|---|
| Espada | 1 | 12 × 18 a 10 px | — | 0.2 s | 0.4 s | 10 | equilibrada |
| Daga | 1 | 10 × 10 a 9 px | — | 0.1 s | 0.2 s | 6 | el doble de golpes por segundo, poco alcance |
| Hacha | **2** | 20 × 30 a 12 px (arco amplio) | 0.15 s | 0.25 s | 0.8 s | 16 | el jugador va al 50 % de velocidad mientras golpea |
| Lanza | 1 | 26 × 6 a 20 px | 0.05 s | 0.15 s | 0.55 s | 12 | atraviesa a varios enemigos; buena contra el vampiro y el mímico |
| Maza | 1 | círculo de radio 14 a 14 px | 0.25 s | 0.1 s | 0.9 s | 24 | aturde 0.5 s; rompe el bloqueo del guardián acorazado |
| Escudo | 0 | 10 × 16 a 8 px (empujón) | — | 0.15 s | 1.0 s | 20 | mantener el botón bloquea el daño de frente (90°) al 50 % de velocidad |

El escudo funciona mejor como objeto de la otra mano, combinado con cualquier arma, que como arma principal.

### Cómo conectarlo con el caballero

El sprite actual del caballero (`priest3`) ya trae la espada dibujada. Para cambiar de arma hay que borrar esos píxeles de la espada en los 4 frames, en Aseprite o LibreSprite, o pasarme los PNG y los dejo listos.

Estructura sugerida en `Player.tscn`:

```
Player
├─ Sprite (caballero sin arma)
└─ WeaponPivot (Node2D, rota hacia la última dirección de movimiento)
   ├─ Held (Sprite2D)            texture = weapon.held_texture
   │                             offset  = held_texture.get_size() / 2 - weapon.held_grip
   ├─ Effect (AnimatedSprite2D)  sprite_frames = weapon.effect_frames, centrado en (0, 0)
   └─ Hitbox (Area2D)            forma según hitbox_size / hitbox_radius, en x = hitbox_distance
```

En el ataque, más o menos así:

```gdscript
func _attack() -> void:
    if _cooldown_left > 0.0: return
    _cooldown_left = weapon.cooldown
    if weapon.windup > 0.0:
        await get_tree().create_timer(weapon.windup).timeout
    $WeaponPivot/Effect.play(&"default")
    _hitbox_enable(weapon.active_time)   # aplicar weapon.damage y weapon.knockback a lo que toque
```

Notas:

- **Estela:** el color de las estelas es el `#dae0ea` de la guadaña y de la espada. Así no compiten con los tintes reservados (rojo = golpe, azul = aturdido).
- **Ataque actual:** con la espada, `fx_sword` reemplaza el arco hecho con `Line2D`. Si prefieres conservar el `Line2D`, el resto de las armas funciona igual.


## Las 15 armas nuevas

Usan los mismos tipos de archivo que las 6 armas anteriores. Cada una está en `assets/weapons/<id>/`:

- `<id>_icon.png`: ícono de 16 × 16 en diagonal;
- `<id>_held.png`: el arma en la mano, apuntando a la derecha; mide 16, 24 o 32 px de largo y la empuñadura está en `held_grip`;
- `<id>_fx.png` + `.tres`: el efecto de ataque;
- `<id>.tres`: el recurso `WeaponData`.

Las armas a distancia traen además `<id>_projectile.png` + `.tres`, y el báculo trae `<id>_impact.png` + `.tres`.

`scripts/weapon_data.gd` se amplió con campos nuevos:

- `rarity` y `min_level`;
- `sweep_degrees`, `crit_chance` y `pierce`;
- combo y giro: `combo_hits`, `combo_gap`, `spin` y `spin_tick`;
- proyectiles: `projectile_*`, `impact_radius` e `impact_frames`;
- efectos de estado: `status_effect` (`burn`, `slow`, `bleed`), `status_chance` y `status_time`;
- curación: `heal_every_hits` y `heal_every_kills`.

Los 6 `.tres` anteriores siguen siendo válidos.

| Arma | Rareza | Desde nivel | Daño | Alcance | Anticipación | Enfriamiento | Retroceso | Qué la hace distinta |
|---|---|---|---|---|---|---|---|---|
| Katana (`katana`) | rara | 4 | 1 | 22 × 8 a 14 px | — | 0.3 s | 8 | Corte rapidísimo y largo; a veces hace el doble. |
| Mandoble (`greatsword`) | rara | 6 | 2 | sector de 180°, radio 22 | 0.3 | 1.0 s | 20 | Barrido enorme de 180° que hace 2 de daño. Muy lento. |
| Estoque (`rapier`) | común | 2 | 1 | 24 × 4 a 16 px | — | 0.25 s | 4 | Estocada fina y veloz; muchos críticos. |
| Guadaña (`scythe`) | épica | 10 | 1 | sector de 270°, radio 21 | 0.2 | 0.9 s | 12 | Barrido de 270°. Cada 6 enemigos eliminados cura 1 vida. |
| Martillo de guerra (`warhammer`) | épica | 9 | 2 | círculo r 18 a 16 px | 0.4 | 1.2 s | 28 | Golpe al suelo que hace 2 de daño, aturde y rompe escudos. |
| Mangual (`flail`) | rara | 7 | 1 | giro, radio 20 | — | 0.5 s | 14 | Mantener el botón para girar: daña todo alrededor sin parar. |
| Látigo (`whip`) | común | 3 | 1 | 30 × 6 a 22 px | 0.1 | 0.6 s | -12 | El alcance más largo. Jala al enemigo hacia ti y lo aturde un momento. |
| Alabarda (`halberd`) | rara | 5 | 1 | 14 × 26 a 22 px | 0.15 | 0.7 s | 18 | Largo alcance y un barrido ancho al final de la estocada. |
| Tridente (`trident`) | rara | 6 | 1 | 26 × 12 a 20 px | 0.1 | 0.6 s | 10 | Tres puntas en paralelo: atraviesa filas de enemigos. |
| Garras (`claws`) | común | 3 | 1 | 10 × 14 a 10 px | — | 0.7 s | 4 | Combo de 3 zarpazos; cada uno puede hacer sangrar. |
| Bumerán (`boomerang`) | común | 2 | 1 | proyectil 140 px/s, 80 px | — | 0.2 s | 8 | Se lanza, atraviesa enemigos y vuelve. Solo uno a la vez. |
| Ballesta de mano (`crossbow`) | rara | 5 | 1 | proyectil 220 px/s, 160 px | 0.1 | 0.9 s | 10 | Virote rápido de largo alcance; hay que recargar. |
| Báculo ígneo (`fire_staff`) | épica | 9 | 1 | proyectil 110 px/s, 140 px | 0.2 | 1.1 s | 12 | Bola de fuego que explota y quema. |
| Espada de escarcha (`frost_blade`) | rara | 5 | 1 | 12 × 18 a 10 px | — | 0.45 s | 8 | Como la espada, pero cada golpe ralentiza al enemigo. |
| Hoz de enredadera (`vine_sickle`) | rara | 13 | 1 | 14 × 16 a 9 px | — | 0.35 s | 8 | Hoz viva: cada 8 golpes acertados recupera 1 vida. |

Notas de implementación:

- **Barridos** (mandoble, guadaña): golpean a todo enemigo cuyo ángulo respecto de la mirada del jugador esté dentro de `sweep_degrees / 2` y a menos de `hitbox_distance`. Se pueden hacer con un `Area2D` circular y un filtro por ángulo.
- **Mangual:** mientras se mantiene el botón, `fx` va en loop (`spin = true`) y se aplica daño cada `spin_tick` s a lo que esté dentro de `hitbox_radius`. Al soltar, entra el `cooldown`.
- **Látigo:** `knockback` negativo significa que jala al enemigo hacia el jugador. En `EnemyBase` alcanza con invertir la dirección del retroceso.
- **Garras:** son `combo_hits` golpes separados por `combo_gap`. El efecto trae los tres zarpazos uno detrás de otro.
- **Bumerán:** solo uno a la vez. Vuelve al jugador después de `projectile_range` y daña de ida y de vuelta.
- **Ballesta y báculo:** los proyectiles del jugador pueden ir más rápido que los 140 px/s de la regla 6.1, porque esa regla protege al jugador, no a los enemigos.
- **Estados:**
  - `burn` y `bleed` hacen 1 de daño extra pasados `status_time` segundos;
  - `slow` deja al enemigo al 50 % de velocidad.
  
  No usan los tintes reservados de la sección 2.3, así que conviene marcarlos con partículas pequeñas: brasas, gotas o copos.
- **Colores:** las armas elementales tienen la estela de su color (escarcha `#d8f0f8` / `#a7d1e6`, enredadera `#a8c84a` / `#6b8f3a`, fuego `#ffed56` / `#ff8a2a`). Las demás usan la estela blanca `#dae0ea` de siempre.
- **HUD y rareza:** colores sugeridos para el nombre en el HUD: común `#dae0ea`, rara `#62abd4`, épica `#ffd569`.
