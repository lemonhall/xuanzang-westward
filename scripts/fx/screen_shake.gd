class_name ScreenShake
extends Camera2D
## 摄像机跟随 + 震屏（REQ-0001-002）。
##
## Shake decays on real time (Time.get_ticks_msec), so the impact is still visible
## while Engine.time_scale is frozen by Hitstop — otherwise 打击感 disappears
## exactly during the frames that matter.

@export var follow_target_path: NodePath
@export var dead_zone := 28.0
@export var follow_speed := 6.0

## The camera sits this far above the character. Level and background geometry
## checks derive the visible vertical range from it, so it is a constant rather
## than a magic number buried in _process.
const FOLLOW_OFFSET_Y := 110.0

var _amplitude := 0.0
var _end_ms := 0
var _duration_ms := 1
var _target: Node2D


func _ready() -> void:
	position_smoothing_enabled = false
	make_current()
	if follow_target_path != NodePath():
		_target = get_node_or_null(follow_target_path)
	add_to_group("player_camera")


func shake(amplitude: float, duration: float) -> void:
	_amplitude = clampf(amplitude, 3.0, 6.0)
	_duration_ms = int(duration * 1000.0)
	_end_ms = Time.get_ticks_msec() + _duration_ms


func shake_active() -> bool:
	return Time.get_ticks_msec() < _end_ms


func current_amplitude() -> float:
	return _amplitude if shake_active() else 0.0


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if now < _end_ms:
		var remaining := float(_end_ms - now) / float(maxi(_duration_ms, 1))
		var amount := _amplitude * remaining
		offset = Vector2(randf_range(-amount, amount), randf_range(-amount, amount))
	else:
		offset = Vector2.ZERO

	if _target and is_instance_valid(_target):
		var desired := _target.global_position + Vector2(0, -FOLLOW_OFFSET_Y)
		global_position = global_position.lerp(desired, clampf(follow_speed * get_process_delta_time(), 0.0, 1.0))
