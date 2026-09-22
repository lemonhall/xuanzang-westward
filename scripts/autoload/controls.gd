extends Node
## Registers the input map at runtime.
##
## Keyboard is the reference layout, a gamepad mirrors it, and tests drive the
## player through an injected input source rather than through Input at all.

const ACTIONS := {
	"move_left": { "keys": [KEY_A, KEY_LEFT], "axis": [JOY_AXIS_LEFT_X, -1.0] },
	"move_right": { "keys": [KEY_D, KEY_RIGHT], "axis": [JOY_AXIS_LEFT_X, 1.0] },
	"move_up": { "keys": [KEY_W, KEY_UP], "axis": [JOY_AXIS_LEFT_Y, -1.0] },
	"move_down": { "keys": [KEY_S, KEY_DOWN], "axis": [JOY_AXIS_LEFT_Y, 1.0] },
	"jump": { "keys": [KEY_SPACE, KEY_W, KEY_UP], "buttons": [JOY_BUTTON_A] },
	"attack": { "keys": [KEY_J], "buttons": [JOY_BUTTON_X] },
	"chant": { "keys": [KEY_K], "buttons": [JOY_BUTTON_Y] },
	"interact": { "keys": [KEY_E, KEY_ENTER], "buttons": [JOY_BUTTON_B] },
	"debate_1": { "keys": [KEY_1] },
	"debate_2": { "keys": [KEY_2] },
	"debate_3": { "keys": [KEY_3] },
	"debate_4": { "keys": [KEY_4] },
	"pause": { "keys": [KEY_ESCAPE], "buttons": [JOY_BUTTON_START] },
	"debug_toggle": { "keys": [KEY_F3] },
}


func _ready() -> void:
	for action_name in ACTIONS.keys():
		ensure_action(action_name)


func ensure_action(action_name: String) -> void:
	var spec: Dictionary = ACTIONS[action_name]
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for keycode in spec.get("keys", []):
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		_add_if_missing(action_name, event)
	for button in spec.get("buttons", []):
		var pad := InputEventJoypadButton.new()
		pad.button_index = button
		_add_if_missing(action_name, pad)
	if spec.has("axis"):
		var axis := InputEventJoypadMotion.new()
		axis.axis = spec["axis"][0]
		axis.axis_value = spec["axis"][1]
		_add_if_missing(action_name, axis)


func _add_if_missing(action_name: String, event: InputEvent) -> void:
	for existing in InputMap.action_get_events(action_name):
		if existing.as_text() == event.as_text():
			return
	InputMap.action_add_event(action_name, event)
