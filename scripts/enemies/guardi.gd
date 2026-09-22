class_name Guardi
extends CharacterBody2D
## 关吏：巡逻型敌人占位实现。
##
## Art is a placeholder ink silhouette until the enemy sprite set is produced with
## the reference-locked route (see ECN-0001). Behaviour is already final-shape:
## patrol, three hits to down, contact damage, knockback, flash on hit.

const SPEED := 60.0
const HP_MAX := 3
const GRAVITY := 1500.0
const HIT_FLASH := 0.08

var hp := HP_MAX
var patrol_dir := 1.0
var home_x := 0.0
var patrol_range := 120.0

var _flash := 0.0
var _body: Polygon2D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	home_x = global_position.x
	_build_visual()
	_build_collision()
	var hurt := Area2D.new()
	var hurt_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 26.0
	hurt_shape.shape = circle
	hurt.add_child(hurt_shape)
	hurt.body_entered.connect(_on_body_entered)
	add_child(hurt)


func _build_visual() -> void:
	# ink silhouette placeholder: torso + head + halberd
	_body = Polygon2D.new()
	_body.polygon = PackedVector2Array([
		Vector2(-16, 0), Vector2(16, 0), Vector2(18, -58), Vector2(8, -74),
		Vector2(-8, -74), Vector2(-18, -58),
	])
	_body.color = Color("#4A4038")
	add_child(_body)
	var head := Polygon2D.new()
	head.polygon = PackedVector2Array([
		Vector2(-11, -74), Vector2(11, -74), Vector2(9, -96), Vector2(-9, -96),
	])
	head.color = Color("#5B4E43")
	add_child(head)
	var pole := ColorRect.new()
	pole.color = Color("#2E2A24")
	pole.position = Vector2(20, -104)
	pole.size = Vector2(4, 104)
	add_child(pole)


func _build_collision() -> void:
	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 16.0
	capsule.height = 96.0
	shape.shape = capsule
	shape.position = Vector2(0, -48)
	add_child(shape)


func _physics_process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		modulate = Color(1.0, 1.0, 1.0) if _flash <= 0.0 else Color(2.2, 2.2, 2.2)
	velocity.y += GRAVITY * delta
	velocity.x = patrol_dir * SPEED
	if absf(global_position.x - home_x) > patrol_range:
		patrol_dir = signf(home_x - global_position.x)
	move_and_slide()
	if is_on_wall():
		patrol_dir = -patrol_dir


func take_hit(damage: int, direction: float) -> void:
	if hp <= 0:
		return
	hp -= damage
	_flash = HIT_FLASH
	velocity = Vector2(direction * 180.0, -140.0)
	if hp <= 0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if body.has_method("take_damage"):
		body.take_damage(global_position.x)
