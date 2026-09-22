class_name KeyboardInput
extends InputSource
## Real player input: keyboard (reference layout) or gamepad, both mapped by the
## Controls autoload.

func get_move_axis() -> float:
	return Input.get_axis("move_left", "move_right")


func is_jump_pressed() -> bool:
	return Input.is_action_pressed("jump")


func is_jump_just_pressed() -> bool:
	return Input.is_action_just_pressed("jump")


func is_attack_just_pressed() -> bool:
	return Input.is_action_just_pressed("attack")


func is_chant_pressed() -> bool:
	return Input.is_action_pressed("chant")
