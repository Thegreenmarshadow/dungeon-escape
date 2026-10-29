@tool
extends RefCounted
## Arma TouchControls para las pruebas con su script y los nodos que buscan sus
## @onready (como TouchControls.tscn), creando cada script con new(): en el
## editor un script que no es @tool solo corre así, no instanciado desde la
## escena (ver player_rig.gd). La prueba debe rastrear (track) y agregar al
## árbol el nodo devuelto.

const CONTROLS_SCRIPT := preload("res://scripts/input/touch_controls.gd")
const JOYSTICK_SCRIPT := preload("res://scripts/input/touch_joystick.gd")
const BUTTON_SCRIPT := preload("res://scripts/input/touch_action_button.gd")


static func make_controls() -> CanvasLayer:
	var controls: CanvasLayer = CONTROLS_SCRIPT.new()
	var safe := Control.new()
	safe.name = "Safe"
	safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.add_child(safe)
	_own(safe, controls)
	var joystick: Control = JOYSTICK_SCRIPT.new()
	joystick.name = "Joystick"
	joystick.anchor_top = 0.3
	joystick.anchor_right = 0.45
	joystick.anchor_bottom = 1.0
	safe.add_child(joystick)
	_own(joystick, controls)
	var bottom_right := Control.new()
	bottom_right.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	safe.add_child(bottom_right)
	var top_right := Control.new()
	top_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	safe.add_child(top_right)
	for spec in [["AttackButton", &"attack", bottom_right], ["JumpButton", &"jump", bottom_right],
			["ParryButton", &"parry", bottom_right], ["PauseButton", &"pause", top_right]]:
		var button: TouchScreenButton = BUTTON_SCRIPT.new()
		button.name = spec[0]
		button.action = spec[1]
		spec[2].add_child(button)
		_own(button, controls)
	return controls


static func _own(node: Node, owner: Node) -> void:
	node.owner = owner
	node.unique_name_in_owner = true
