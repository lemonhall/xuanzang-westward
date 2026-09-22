class_name InputSource
extends RefCounted
## Abstract player input.
##
## Keyboard, gamepad and scripted test input are equivalent sources (设计哲学：等价多态）,
## so gameplay code never reads Input directly — headless tests inject a scripted
## source and drive the exact same code path a human does.

func get_move_axis() -> float:
	return 0.0


func is_jump_pressed() -> bool:
	return false


func is_jump_just_pressed() -> bool:
	return false


func is_attack_just_pressed() -> bool:
	return false


func is_chant_pressed() -> bool:
	return false


func tick(_delta: float) -> void:
	pass
