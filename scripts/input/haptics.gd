class_name Haptics
extends RefCounted
## Vibración háptica en momentos clave (Input.vibrate_handheld). Solo vibra en
## Android e iOS y si el jugador no la apagó en Ajustes; en PC no hace nada.
## La llama GameFeel, que ya escucha esos momentos.
##
## Duraciones en milisegundos: cortas en lo frecuente (recoger, matar) y más
## largas en lo que conviene sentir (recibir daño, parry).

const DAMAGE_MS := 70
const PARRY_MS := 50
const PICKUP_MS := 30
const KILL_MS := 35
const BOSS_KILL_MS := 80

## Si vibra. TouchControls lo carga de Ajustes al arrancar y al cambiarlo.
static var enabled := true
## Última vibración pedida en ms, aunque el dispositivo no vibre (para las
## pruebas en PC). 0 si no se pidió ninguna.
static var last_requested_ms := 0


## Vibra ms milisegundos si está activo. Devuelve true si la pidió.
static func vibrate(ms: int) -> bool:
	if not enabled or ms <= 0:
		return false
	last_requested_ms = ms
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)
	return true
