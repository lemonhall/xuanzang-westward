class_name Xuanzang
extends CharacterBody2D
## 玄奘：平台跳跃控制器。
##
## Feel constants come from PRD REQ-0001-001/002/003 and are asserted in
## tests/test_runner.gd. Sprites are normalized canvases (512×512, character
## 430 px tall, feet on a fixed baseline), so the visual offset is a constant.

const MAX_SPEED := 220.0
const ACCEL := 1800.0
const FRICTION := 2200.0
const GRAVITY := 1800.0
const FALL_GRAVITY_MULT := 1.35
const JUMP_VELOCITY := -610.0          # ≈3.2 tiles (32 px) of jump height
const JUMP_CUT := 0.45
const COYOTE_TIME := 0.10
const JUMP_BUFFER := 0.12
const ATTACK_COST := 8
const ATTACK_FOCUS_GAIN := 12
const INVULN_TIME := 0.5
const ATTACK_ACTIVE := Vector2(0.16, 0.30)   # start / end of the hit window
const ATTACK_TOTAL := 0.34
const COMBO_WINDOW := 0.45
const KNOCKBACK := 240.0
const FALL_RESPAWN_DELAY := 0.6

const SPRITE_DIR := "res://assets/sprites/xuanzang"
const TEXTURE_CANVAS := 512.0
const FEET_Y := 480.0
const ON_SCREEN_HEIGHT := 150.0

enum State { IDLE, RUN, JUMP, FALL, ATTACK, HURT, CHANT }

signal attacked(hit_point: Vector2, damage: int)
signal damaged

var input_source: InputSource = KeyboardInput.new()
var state: State = State.IDLE

var _sprite: AnimatedSprite2D
var _shape: CollisionShape2D
var _coyote := 0.0
var _buffer := 0.0
var _attack_time := -1.0
var _attack_index := 0
var _last_attack_end := -10.0
var _invuln := 0.0
var _facing := 1
var _camera: Node
var _hit_consumed := false
var _respawn_cooldown := 0.0


func _ready() -> void:
	collision_layer = 1
	# Collide with terrain only (layer 1). Enemies live on layer 2 and are reached
	# through the attack query, so they never body-block the character.
	collision_mask = 1
	_build_collision()
	_build_sprite()
	_camera = get_tree().get_first_node_in_group("player_camera")


func _build_collision() -> void:
	var capsule := CapsuleShape2D.new()
	capsule.radius = 18.0
	capsule.height = ON_SCREEN_HEIGHT
	_shape = CollisionShape2D.new()
	_shape.shape = capsule
	_shape.position = Vector2(0, -ON_SCREEN_HEIGHT * 0.5)
	add_child(_shape)


func _build_sprite() -> void:
	var scale_factor := ON_SCREEN_HEIGHT / (TEXTURE_CANVAS - 32.0)
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = _load_frames()
	_sprite.scale = Vector2(scale_factor, scale_factor)
	# The canvas bottom sits 32 px below the character's feet; keep the feet on
	# the node origin so collision, camera and platforms all agree.
	_sprite.offset = Vector2(0, -(TEXTURE_CANVAS * 0.5 - (TEXTURE_CANVAS - FEET_Y)))
	add_child(_sprite)
	_sprite.play("idle")


func _load_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var by_alias := {}
	var dir := DirAccess.open(SPRITE_DIR)
	if dir == null:
		push_error("sprite directory missing: %s" % SPRITE_DIR)
		frames.add_animation("idle")
		return frames
	for file_name in dir.get_files():
		if not file_name.ends_with(".png"):
			continue
		var stem := file_name.get_basename()
		var split := stem.rsplit("_", true, 1)
		if split.size() != 2:
			continue
		var alias := split[0]
		var texture: Texture2D = load("%s/%s" % [SPRITE_DIR, file_name])
		# Precise animations (used by combat) and grouped animations (used by locomotion).
		if not frames.has_animation(stem):
			frames.add_animation(stem)
			frames.set_animation_speed(stem, 1.0)
			frames.set_animation_loop(stem, false)
		frames.add_frame(stem, texture)
		if not by_alias.has(alias):
			by_alias[alias] = []
		by_alias[alias].append(stem)
	for alias in by_alias.keys():
		var names: Array = by_alias[alias]
		names.sort()
		if not frames.has_animation(alias):
			frames.add_animation(alias)
			frames.set_animation_speed(alias, 8.0 if names.size() > 1 else 1.0)
			frames.set_animation_loop(alias, names.size() > 1 and alias != "attack")
		for name in names:
			for i in frames.get_frame_count(name):
				frames.add_frame(alias, frames.get_frame_texture(name, i))
	return frames


func _physics_process(delta: float) -> void:
	_invuln = maxf(0.0, _invuln - delta)
	_respawn_cooldown = maxf(0.0, _respawn_cooldown - delta)
	_coyote = maxf(0.0, _coyote - delta)
	_buffer = maxf(0.0, _buffer - delta)

	var axis := input_source.get_move_axis()
	if input_source.is_jump_just_pressed():
		_buffer = JUMP_BUFFER

	_handle_attack(delta)

	if state == State.ATTACK:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta * 0.6)
	else:
		if absf(axis) > 0.01:
			velocity.x = move_toward(velocity.x, axis * MAX_SPEED, ACCEL * delta)
			_facing = signi(int(sign(axis)))
			_sprite.flip_h = _facing < 0
		else:
			velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	if is_on_floor():
		_coyote = COYOTE_TIME

	var gravity := GRAVITY * (FALL_GRAVITY_MULT if velocity.y > 0.0 else 1.0)
	velocity.y += gravity * delta

	if _buffer > 0.0 and _coyote > 0.0 and state != State.ATTACK and state != State.HURT:
		velocity.y = JUMP_VELOCITY
		_buffer = 0.0
		_coyote = 0.0
	if velocity.y < 0.0 and not input_source.is_jump_pressed():
		velocity.y *= JUMP_CUT

	move_and_slide()
	_update_state(delta)
	_world_bounds()
	if global_position.y > 1400.0:
		_respawn()
	# Edges ("just pressed") are cleared at the end of the frame, after every
	# reader has seen them.
	input_source.tick(delta)


func _world_bounds() -> void:
	# Keep the character inside the level horizontally so it cannot walk out of
	# the level data (platforms are authored, not endless).
	global_position.x = clampf(global_position.x, 40.0, 6360.0)


func _update_state(delta: float) -> void:
	if state == State.HURT:
		if not _sprite.is_playing():
			state = State.IDLE
		return
	if state == State.ATTACK:
		return
	if input_source.is_chant_pressed() and is_on_floor():
		_set_state(State.CHANT)
		return
	if not is_on_floor():
		_set_state(State.JUMP if velocity.y < 0.0 else State.FALL)
	elif absf(velocity.x) > 12.0:
		_set_state(State.RUN)
	else:
		_set_state(State.IDLE)
	if state == State.RUN:
		_sprite.speed_scale = clampf(absf(velocity.x) / MAX_SPEED, 0.6, 1.6)
	else:
		_sprite.speed_scale = 1.0
	delta = delta  # keep the signature explicit for future state work


func _set_state(next: State) -> void:
	if state == next:
		return
	state = next
	match next:
		State.IDLE:
			_sprite.play("idle")
		State.RUN:
			_sprite.play("walk")
		State.JUMP:
			_sprite.play("jump")
		State.FALL:
			_sprite.play("fall")
		State.CHANT:
			_sprite.play("chant")
		State.HURT:
			_sprite.play("hurt")


func _handle_attack(delta: float) -> void:
	if _attack_time >= 0.0:
		_attack_time += delta
		if _attack_time >= ATTACK_ACTIVE.x and _attack_time <= ATTACK_ACTIVE.y and not _hit_consumed:
			_query_hit()
			_hit_consumed = true
		if _attack_time >= ATTACK_TOTAL:
			_attack_time = -1.0
			_last_attack_end = Time.get_ticks_msec() / 1000.0
			state = State.IDLE
		return
	if not input_source.is_attack_just_pressed():
		return
	if GameState.focus < ATTACK_COST:
		return
	if not GameState.spend_focus(ATTACK_COST):
		return
	var now := Time.get_ticks_msec() / 1000.0
	_attack_index = 1 if now - _last_attack_end <= COMBO_WINDOW else 0
	_attack_time = 0.0
	_hit_consumed = false
	state = State.ATTACK
	_sprite.play("attack_0%d" % (_attack_index + 1))


func _query_hit() -> void:
	if _sprite.animation.begins_with("attack") == false:
		return
	var space := get_world_2d().direct_space_state
	var shape := RectangleShape2D.new()
	shape.size = Vector2(74, ON_SCREEN_HEIGHT * 0.6)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position + Vector2(_facing * 46.0, -ON_SCREEN_HEIGHT * 0.55))
	query.collision_mask = 2
	query.collide_with_bodies = true
	var hits := space.intersect_shape(query, 8)
	for hit in hits:
		var body = hit.get("collider")
		if body and body.has_method("take_hit"):
			var point: Vector2 = body.global_position + Vector2(0, -20)
			body.take_hit(1, signf(body.global_position.x - global_position.x))
			attacked.emit(point, 1)
			GameState.gain_focus(ATTACK_FOCUS_GAIN)
			Hitstop.freeze(0.07)
			if _camera and _camera.has_method("shake"):
				_camera.shake(5.0, 0.2)
			break


func take_damage(from_x: float) -> void:
	if _invuln > 0.0 or state == State.HURT:
		return
	_invuln = INVULN_TIME
	GameState.damage_composure(1)
	damaged.emit()
	velocity = Vector2(KNOCKBACK * signf(global_position.x - from_x), -220.0)
	_sprite.play("hurt")
	state = State.HURT
	Hitstop.freeze(0.08)
	if _camera and _camera.has_method("shake"):
		_camera.shake(6.0, 0.25)


func _respawn() -> void:
	if _respawn_cooldown > 0.0:
		return
	_respawn_cooldown = FALL_RESPAWN_DELAY
	var level := get_tree().get_first_node_in_group("level")
	if level and level.has_method("respawn_position"):
		global_position = level.respawn_position()
		velocity = Vector2.ZERO
		push_warning("[player] 掉出世界，已回到最近存档点 %s" % GameState.checkpoint_id)


static func max_jump_distance() -> float:
	## Horizontal reach of a full-speed jump, straight from the movement constants.
	## Used to keep level gaps honest: PRD 要求关卡不能设计出跳不过去的坑。
	var rise_time: float = absf(JUMP_VELOCITY) / GRAVITY
	var fall_time: float = absf(JUMP_VELOCITY) / (GRAVITY * FALL_GRAVITY_MULT)
	return (rise_time + fall_time) * MAX_SPEED


static func max_jump_height() -> float:
	## Apex height of a full jump: v² / 2g = 610² / 3600 ≈ 103 px (≈3.2 tiles).
	return (JUMP_VELOCITY * JUMP_VELOCITY) / (2.0 * GRAVITY)


static func body_width() -> float:
	return 36.0
