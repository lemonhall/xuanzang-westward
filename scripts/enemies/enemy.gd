class_name Enemy
extends CharacterBody2D
## 通用敌人：巡逻、受击、接触伤害。美术由 actor_name 决定，来自
## assets/sprites/<actor_name>/；美术缺失时退回水墨剪影占位，保证游戏永远能跑。

const GRAVITY := 1500.0
const HIT_FLASH := 0.08
const SPRITE_CANVAS := 384.0
## Matches the pipeline spec in tools/asset_pipeline.py (wolf: width-normalized to
## 300 px of body length inside its canvas). Quadruped frames keep one zoom level,
## so the in-game scale is a constant ratio rather than a fit-to-height.
const REFERENCE_LENGTH := 300.0

@export var actor_name := "wolf"
@export var patrol_speed := 60.0
@export var hp_max := 3
@export var patrol_range := 120.0
@export var on_screen_height := 96.0
@export var on_screen_length := 170.0

var hp := 3
var patrol_dir := 1.0
var home_x := 0.0
var has_art := false

var _flash := 0.0
var _sprite: AnimatedSprite2D
var _fallback: Node2D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	hp = hp_max
	home_x = global_position.x
	_build_visual()
	_build_collision()
	_build_hurt_box()


func _build_visual() -> void:
	var dir_path := "res://assets/sprites/%s" % actor_name
	has_art = SpriteFramesLoader.has_art(dir_path)
	if has_art:
		_sprite = AnimatedSprite2D.new()
		_sprite.sprite_frames = SpriteFramesLoader.load_frames(dir_path)
		var scale_factor := on_screen_length / REFERENCE_LENGTH
		_sprite.scale = Vector2(scale_factor, scale_factor)
		# The canvas keeps 32 px below the feet; anchor the feet on the node origin.
		_sprite.offset = Vector2(0, -(SPRITE_CANVAS * 0.5 - 34.0))
		add_child(_sprite)
		if _sprite.sprite_frames.has_animation("idle"):
			_sprite.play("idle")
		return
	_fallback = _make_silhouette()
	add_child(_fallback)


func _make_silhouette() -> Node2D:
	var holder := Node2D.new()
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-34, 0), Vector2(30, 0), Vector2(38, -30), Vector2(20, -46),
		Vector2(-14, -48), Vector2(-36, -30),
	])
	body.color = Color("#4A4038")
	holder.add_child(body)
	var head := Polygon2D.new()
	head.polygon = PackedVector2Array([
		Vector2(24, -44), Vector2(52, -54), Vector2(56, -40), Vector2(30, -32),
	])
	head.color = Color("#5B4E43")
	holder.add_child(head)
	var tail := Polygon2D.new()
	tail.polygon = PackedVector2Array([
		Vector2(-34, -30), Vector2(-60, -44), Vector2(-56, -28), Vector2(-34, -14),
	])
	tail.color = Color("#3F362E")
	holder.add_child(tail)
	return holder


func _build_collision() -> void:
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(on_screen_height * 1.5, on_screen_height * 0.75)
	shape.shape = box
	shape.position = Vector2(0, -on_screen_height * 0.375)
	add_child(shape)


func _build_hurt_box() -> void:
	var hurt := Area2D.new()
	var hurt_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = on_screen_height * 0.45
	hurt_shape.shape = circle
	hurt_shape.position = Vector2(0, -on_screen_height * 0.4)
	hurt.add_child(hurt_shape)
	hurt.body_entered.connect(_on_body_entered)
	add_child(hurt)


func _physics_process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		modulate = Color(1.0, 1.0, 1.0) if _flash <= 0.0 else Color(2.2, 2.2, 2.2)
	velocity.y += GRAVITY * delta
	velocity.x = patrol_dir * patrol_speed
	if absf(global_position.x - home_x) > patrol_range:
		patrol_dir = signf(home_x - global_position.x)
	move_and_slide()
	if is_on_wall():
		patrol_dir = -patrol_dir
	if _sprite:
		_sprite.flip_h = patrol_dir < 0.0
		if _sprite.animation.begins_with("hurt") == false and _sprite.animation != "attack":
			var wanted := "walk" if absf(velocity.x) > 4.0 else "idle"
			if _sprite.sprite_frames.has_animation(wanted) and _sprite.animation != wanted:
				_sprite.play(wanted)


func take_hit(damage: int, direction: float) -> void:
	if hp <= 0:
		return
	hp -= damage
	_flash = HIT_FLASH
	velocity = Vector2(direction * 180.0, -140.0)
	if _sprite and _sprite.sprite_frames.has_animation("hurt"):
		_sprite.play("hurt")
	if hp <= 0:
		queue_free()


func sprite_node() -> AnimatedSprite2D:
	## Exposed for tests: the visual is built at runtime, so tests need a handle.
	return _sprite


func _on_body_entered(body: Node) -> void:
	if body.has_method("take_damage"):
		body.take_damage(global_position.x)
