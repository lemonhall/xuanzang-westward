class_name ScriptedInput
extends InputSource
## Deterministic input for headless tests: the same code path a player drives.

var axis := 0.0
var jump_held := false
var jump_pressed := false
var attack_pressed := false
var chant_held := false


func get_move_axis() -> float:
	return axis


func is_jump_pressed() -> bool:
	return jump_held


func is_jump_just_pressed() -> bool:
	return jump_pressed


func is_attack_just_pressed() -> bool:
	return attack_pressed


func is_chant_pressed() -> bool:
	return chant_held


func tick(_delta: float) -> void:
	jump_pressed = false
	attack_pressed = false
