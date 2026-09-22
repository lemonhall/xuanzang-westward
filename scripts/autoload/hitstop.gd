extends Node
## Frame freeze used for combat impact (打击感).
##
## Runs on unscaled time so the freeze can end while Engine.time_scale is 0.
## Hard bounds come from PRD REQ-0001-002: 0.06–0.09 s.

const MIN_DURATION := 0.06
const MAX_DURATION := 0.09
const FREEZE_SCALE := 0.05

signal hitstop_started(duration: float)
signal hitstop_finished

var is_frozen: bool = false
var last_duration: float = 0.0
var _token: int = 0


func freeze(duration: float = 0.07) -> void:
	var clamped := clampf(duration, MIN_DURATION, MAX_DURATION)
	last_duration = clamped
	_token += 1
	var my_token := _token
	is_frozen = true
	Engine.time_scale = FREEZE_SCALE
	hitstop_started.emit(clamped)
	# ignore_time_scale = true keeps this timer honest while the world is frozen.
	await get_tree().create_timer(clamped, true, false, true).timeout
	if my_token != _token:
		return
	is_frozen = false
	Engine.time_scale = 1.0
	hitstop_finished.emit()
