class_name LevelBuilder
extends Node2D
## 关卡装配器：从 data/levels/*.json 构建地形、存档点、终点与敌人。
##
## The level lives in data, not only in the editor, so tests, the game and future
## tooling all read the same description (设计哲学：显式优于隐式）。

const LEVEL_PATH := "res://data/levels/l01.json"
const INK := Color("#3A322B")
const INK_LIGHT := Color("#6B5B4A")
const EMBER := Color("#D4762A")
const GOLD := Color(0.83, 0.63, 0.16, 0.35)

var data: Dictionary = {}
var world_width := 6400.0

var _respawn_point := Vector2(120, 520)
var _checkpoints := {}


func load_data(path: String = LEVEL_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("level data missing: %s" % path)
		return {}
	data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data


func build() -> Vector2:
	add_to_group("level")
	if data.is_empty():
		return _respawn_point
	world_width = float(data.get("world_width", 6400.0))
	var spawn: Array = data.get("spawn", [120, 520])
	_respawn_point = Vector2(spawn[0], spawn[1])
	for platform in data.get("platforms", []):
		_make_platform(Rect2(platform["x"], platform["y"], platform["w"], platform["h"]))
	for checkpoint in data.get("checkpoints", []):
		_make_checkpoint(checkpoint)
	for enemy in data.get("enemies", []):
		_make_enemy(enemy)
	if data.has("goal"):
		_make_goal(data["goal"])
	return _respawn_point


func respawn_position() -> Vector2:
	return _respawn_point


func _make_platform(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = rect.position
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.size * 0.5
	body.add_child(shape)

	var fill := Polygon2D.new()
	fill.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(rect.size.x, 0),
		Vector2(rect.size.x, rect.size.y), Vector2(0, rect.size.y),
	])
	fill.color = INK
	body.add_child(fill)

	var top := Line2D.new()
	top.points = PackedVector2Array([Vector2(0, 1), Vector2(rect.size.x, 1)])
	top.width = 3.0
	top.default_color = INK_LIGHT
	body.add_child(top)
	add_child(body)


func _make_checkpoint(spec: Dictionary) -> void:
	var area := Area2D.new()
	area.position = Vector2(spec["x"], spec["y"])
	area.collision_layer = 0
	area.collision_mask = 1
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 52.0
	shape.shape = circle
	area.add_child(shape)

	var pole := ColorRect.new()
	pole.color = INK
	pole.position = Vector2(-2, -46)
	pole.size = Vector2(4, 46)
	area.add_child(pole)
	var flame := Polygon2D.new()
	flame.polygon = PackedVector2Array([
		Vector2(0, -72), Vector2(9, -58), Vector2(0, -46), Vector2(-9, -58),
	])
	flame.color = EMBER
	area.add_child(flame)

	var id: String = spec.get("id", "cp")
	_checkpoints[id] = area.position
	area.body_entered.connect(_on_checkpoint_entered.bind(id))
	add_child(area)


func _on_checkpoint_entered(body: Node, id: String) -> void:
	if not body is Xuanzang:
		return
	if GameState.checkpoint_id == id:
		return
	GameState.checkpoint_id = id
	_respawn_point = _checkpoints[id]
	GameState.save_progress()
	print("[level] checkpoint: %s" % id)


func _make_enemy(spec: Dictionary) -> void:
	var enemy := Guardi.new()
	enemy.position = Vector2(spec["x"], spec["y"])
	if spec.has("patrol_range"):
		enemy.patrol_range = float(spec["patrol_range"])
	add_child(enemy)


func _make_goal(spec: Dictionary) -> void:
	var area := Area2D.new()
	area.position = Vector2(spec["x"], spec["y"])
	area.collision_layer = 0
	area.collision_mask = 1
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(90, 240)
	shape.shape = box
	shape.position = Vector2(0, -120)
	area.add_child(shape)

	var beam := ColorRect.new()
	beam.color = GOLD
	beam.position = Vector2(-40, -420)
	beam.size = Vector2(80, 420)
	area.add_child(beam)

	area.body_entered.connect(_on_goal_entered.bind(String(spec.get("id", "goal"))))
	add_child(area)


func _on_goal_entered(body: Node, id: String) -> void:
	if not body is Xuanzang:
		return
	print("[level] goal reached: %s" % id)
	GameState.complete_level(String(data.get("id", "l01")))
