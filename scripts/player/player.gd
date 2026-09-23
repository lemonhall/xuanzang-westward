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
## 诵经（K）：站定持诵 N 秒回复心念。用户问过"K 到底是干啥的"，所以它必须有真实作用。
const CHANT_CHANNEL := 0.8
const CHANT_FOCUS_GAIN := 25
## 攻击时向前小冲一段，让"挥出去"这件事在位移上发生（画面之外的第二重打击感）。
const ATTACK_LUNGE := 130.0
## 走完一个完整行走循环前进的世界距离（像素）。动画播放速度由它与实际速度算出，
## 这样脚才不打滑（用户实测"像滑步"）。可在游戏里观察后微调这个数。
const WALK_STRIDE_PX := 150.0

const SPRITE_DIR := "res://assets/sprites/xuanzang"
## Normalized frame canvas (see tools/asset_pipeline.py ACTOR_SPECS). It is wider
## than it is tall so that wide poses (a swung staff) never get scaled down.
const CANVAS := Vector2(1024.0, 768.0)
const FEET_Y := 736.0
## 角色在贴图里的高度（与 tools/asset_pipeline.py 的 ACTOR_SPECS.height 对应）。
## 屏幕尺寸必须由它换算，而不是由画布高度——画布留了余量给高姿态。
const TEXTURE_HEIGHT := 430.0
## 角色在屏幕上的身高。用户实测反馈"玄奘整体太小了"，从 150 px 提到 190 px
## （约屏幕高度的 26%）；碰撞体随之自动等比例变大。
const ON_SCREEN_HEIGHT := 225.0

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
var _chant_time := 0.0
var _walk_phase := 0.0


func _ready() -> void:
	add_to_group("player")
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
	var scale_factor := ON_SCREEN_HEIGHT / TEXTURE_HEIGHT
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = _load_frames()
	# 行走动画由代码按实际位移驱动（speed_scale 直接等于每秒帧数），基准速度设 1。
	if _sprite.sprite_frames.has_animation("walk"):
		_sprite.sprite_frames.set_animation_speed("walk", 1.0)
	_sprite.scale = Vector2(scale_factor, scale_factor)
	# 贴图里脚底位于 FEET_Y 行；把这一行对齐到节点原点，碰撞/相机/地形才对得上。
	_sprite.offset = Vector2(0, CANVAS.y * 0.5 - FEET_Y)
	add_child(_sprite)
	_sprite.play("idle")


func _load_frames() -> SpriteFrames:
	var frames := SpriteFramesLoader.load_frames(SPRITE_DIR)
	if not frames.has_animation("idle"):
		push_error("no frames found in %s (run tools/asset_pipeline.py)" % SPRITE_DIR)
		frames.add_animation("idle")
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
	elif state == State.CHANT:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
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
		_chant_time += delta
		if _chant_time >= CHANT_CHANNEL:
			_chant_time = 0.0
			GameState.gain_focus(CHANT_FOCUS_GAIN)
			print("[player] 诵经完成，心念 +%d（当前 %d）" % [CHANT_FOCUS_GAIN, GameState.focus])
		return
	_chant_time = 0.0
	if not is_on_floor():
		_set_state(State.JUMP if velocity.y < 0.0 else State.FALL)
	elif absf(velocity.x) > 12.0:
		_set_state(State.RUN)
	else:
		_set_state(State.IDLE)
	if state == State.RUN:
		# 脚不打滑：走完一个循环应当前进 WALK_STRIDE_PX，于是
		# 每秒帧数 = 实际速度 / 步幅 * 循环帧数；speed_scale 就是每秒帧数本身。
		var cycle_frames := 1
		if _sprite.sprite_frames.has_animation("walk"):
			cycle_frames = maxi(1, _sprite.sprite_frames.get_frame_count("walk"))
		var fps := absf(velocity.x) / WALK_STRIDE_PX * float(cycle_frames)
		_sprite.speed_scale = clampf(fps, 1.0, 20.0)
		# 走路/奔跑时加一点上下起伏，缓解三帧动画的顿挫感。
		_walk_phase += delta * fps * TAU / float(cycle_frames)
		_sprite.offset.y = CANVAS.y * 0.5 - FEET_Y + sin(_walk_phase) * 2.5
	else:
		_sprite.speed_scale = 1.0
		_walk_phase = 0.0
		_sprite.offset.y = CANVAS.y * 0.5 - FEET_Y
	delta = delta  # keep the signature explicit for future state work


func _set_state(next: State) -> void:
	if state == next:
		return
	state = next
	match next:
		State.IDLE:
			_play("idle")
		State.RUN:
			_play("walk")
		State.JUMP:
			_play("jump")
		State.FALL:
			_play("fall", ["jump"])
		State.CHANT:
			_play("chant", ["idle"])
		State.HURT:
			_play("hurt", ["idle"])


func _play(animation: String, fallbacks: Array = []) -> void:
	## 素材里缺某个动作时退回可用动作，而不是让引擎报"动画不存在"。
	if _sprite.sprite_frames.has_animation(animation):
		_sprite.play(animation)
		return
	for candidate in fallbacks:
		if _sprite.sprite_frames.has_animation(candidate):
			_sprite.play(candidate)
			return


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
	velocity.x = _facing * ATTACK_LUNGE
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
			_spawn_slash(point)
			attacked.emit(point, 1)
			GameState.gain_focus(ATTACK_FOCUS_GAIN)
			Hitstop.freeze(0.07)
			if _camera and _camera.has_method("shake"):
				_camera.shake(5.0, 0.2)
			break


func _spawn_slash(point: Vector2) -> void:
	## 挥砍弧线特效：命中位置叠一道弧，攻击的"挥出去"才有画面。
	var slash := SlashArc.new()
	slash.position = point + Vector2(_facing * -18.0, 0)
	slash.facing = _facing
	get_parent().add_child(slash)


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
