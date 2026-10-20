class_name BossHealthBar
extends VBoxContainer
## Barra de vida del jefe en el HUD: su nombre y la vida que le queda. Se ve
## solo mientras el jefe está vivo y en alerta (BossBase.is_alerted), como pide
## la sección 9.1 de la biblia; al morir se oculta sola.
##
## Estructura:
##   BossBar (VBoxContainer, este script)
##   ├── NameLabel (Label)
##   └── Bar (ProgressBar)

var boss: BossBase

@onready var name_label: Label = $NameLabel
@onready var bar: ProgressBar = $Bar


func _ready() -> void:
	refresh()


func _process(_delta: float) -> void:
	refresh()


## Empieza a mostrar a boss (null deja de mostrar a cualquiera).
func track(new_boss: BossBase) -> void:
	boss = new_boss
	refresh()


## true si la barra debe verse para ese jefe. Sin tipo: un jefe ya liberado no
## pasa por un parámetro tipado (ni como Object) y el chequeo tiene que poder
## recibirlo.
static func should_show(target) -> bool:
	return is_instance_valid(target) and (target as BossBase).is_alerted()


## Actualiza visibilidad, nombre y vida desde el jefe.
func refresh() -> void:
	# El jefe muerto se libera: se suelta la referencia para no tocarlo más.
	if boss != null and not is_instance_valid(boss):
		boss = null
	var showing := should_show(boss)
	visible = showing
	if not showing:
		return
	name_label.text = boss.display_name
	bar.max_value = maxi(boss.max_health, 1)
	bar.value = clampi(boss.health, 0, boss.max_health)
