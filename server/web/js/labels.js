// Spanish names of what the game sends, and the game sprite of each thing.

/** Run events (RunRecorder) and level telemetry events (TelemetryStore). */
export const EVENT_LABELS = {
  level_started: "Nivel iniciado",
  level_completed: "Nivel superado",
  enemy_killed: "Enemigo eliminado",
  enemy_dodged: "Enemigo esquivó",
  damage_taken: "Daño recibido",
  heart_picked: "Corazón recogido",
  key_picked: "Llave recogida",
  coin_picked: "Monedas recogidas",
  item_bought: "Compra en la tienda",
  player_died: "Muerte",
  player_respawned: "Reaparición",
  weapon_changed: "Cambio de arma",
  run_quit: "Partida abandonada",
  damage: "Daño",
  death: "Muerte",
  heart: "Corazón",
  key: "Llave",
  door: "Puerta",
  attack: "Ataque",
  revive: "Reaparición",
};

export const ENEMY_LABELS = {
  Skeleton: "Esqueleto",
  Vampire: "Vampiro",
  Skull: "Calavera",
  Reaper: "Parca",
  Archer: "Esqueleto arquero",
  SkullTurret: "Torre de calaveras",
  Mimic: "Cofre mímico",
  Mage: "Mago del orbe",
};

/** Weapon ids (assets/weapons/<id>) and their display_name in the game. */
export const WEAPON_LABELS = {
  axe: "Hacha",
  boomerang: "Bumerán",
  claws: "Garras",
  crossbow: "Ballesta de mano",
  dagger: "Daga",
  fire_staff: "Báculo ígneo",
  flail: "Mangual",
  frost_blade: "Espada de escarcha",
  greatsword: "Mandoble",
  halberd: "Alabarda",
  katana: "Katana",
  mace: "Maza",
  rapier: "Estoque",
  scythe: "Guadaña",
  shield: "Escudo",
  spear: "Lanza",
  sword: "Espada",
  trident: "Tridente",
  vine_sickle: "Hoz de enredadera",
  warhammer: "Martillo de guerra",
  whip: "Látigo",
};

export const ITEM_LABELS = {
  damage: "Mejora de daño",
  life: "Vida extra",
  ...WEAPON_LABELS,
};

export const OUTCOME_LABELS = {
  died: "Murió",
  quit: "Abandonó",
  in_progress: "En curso",
  completed: "Superado",
  abandoned: "Abandonó",
};

export const MODE_LABELS = { normal: "Normal", test: "Prueba", demo: "Demo" };

/** Damage sources and death causes, as analytics.SOURCE_NAMES on the server. */
export const SOURCE_LABELS = {
  spikes: "picos",
  Skeleton: "esqueletos",
  Vampire: "vampiros",
  Skull: "calaveras",
  Archer: "arqueros",
  SkullTurret: "torres de calaveras",
  Mimic: "mímicos",
  Mage: "magos",
  Reaper: "la parca",
  Forge: "el Forjador",
  forge: "peligros del Forjador",
  Lich: "el liche",
  lich: "peligros del liche",
  Warden: "el Guardián",
  warden: "peligros del Guardián",
  projectile: "proyectiles",
  boss_hazard: "peligros de jefe",
  unknown: "causa desconocida",
};

/** Sprite (assets/icons/<name>.png) of each damage source or enemy. */
export const SOURCE_ICONS = {
  spikes: "spikes",
  Skeleton: "skeleton",
  Vampire: "vampire",
  Skull: "skull",
  Archer: "archer",
  SkullTurret: "skull-turret",
  Mimic: "mimic",
  Mage: "mage",
  Reaper: "reaper",
  Forge: "forge",
  forge: "forge",
  Lich: "lich",
  lich: "lich",
  Warden: "warden",
  warden: "warden",
  projectile: "projectile",
  boss_hazard: "forge",
  unknown: "bones",
};

export function sourceLabel(source) {
  return SOURCE_LABELS[source] || source || SOURCE_LABELS.unknown;
}
