extends Node
## Headless test scene (REQ-0001-001/002/003/006/010).
##
##   godot --headless --path . tests/test_scene.tscn
##
## Run as a scene rather than with `--script`: autoload singletons (GameState,
## Hitstop, Controls) are not registered in `--script` mode, so the gameplay
## scripts that reference them would not even compile.
##
## Prints "ALL TESTS PASSED" and exits 0, or lists failures and exits 1.

var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	await _test_movement()
	await _test_coyote_time()
	await _test_combat()
	await _test_parallax()
	await _test_save_roundtrip()
	await _test_real_level_ground()

	if failures.is_empty():
		print("ALL TESTS PASSED")
		get_tree().quit(0)
		return
	print("TESTS FAILED: %d" % failures.size())
	for failure in failures:
		print(" - %s" % failure)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _make_world(platforms: Array, extra: Dictionary = {}) -> Dictionary:
	var root := Node2D.new()
	get_tree().root.add_child(root)

	var level := LevelBuilder.new()
	root.add_child(level)
	var data := {
		"id": "test_level",
		"world_width": float(extra.get("world_width", 2400)),
		"spawn": [float(extra.get("spawn_x", 80)), 500.0],
		"platforms": platforms,
		"checkpoints": [],
		"enemies": [],
	}
	if extra.has("goal"):
		data["goal"] = extra["goal"]
	level.data = data
	var spawn: Vector2 = level.build()

	var player := Xuanzang.new()
	player.position = spawn
	root.add_child(player)
	var scripted := ScriptedInput.new()
	player.input_source = scripted
	await get_tree().physics_frame
	return { "root": root, "player": player, "input": scripted, "level": level }


func _test_movement() -> void:
	var world: Dictionary = await _make_world([{ "x": 0, "y": 500, "w": 2400, "h": 200 }])
	var player: Xuanzang = world["player"]
	var scripted: ScriptedInput = world["input"]
	scripted.axis = 1.0
	for i in range(90):
		await get_tree().physics_frame
	_check(absf(player.velocity.x - 220.0) <= 10.0, "run speed %.1f != 220±10" % player.velocity.x)

	var floor_y := player.global_position.y
	scripted.jump_held = true
	scripted.jump_pressed = true
	await get_tree().physics_frame
	var peak := floor_y
	for i in range(70):
		await get_tree().physics_frame
		peak = minf(peak, player.global_position.y)
	var height := floor_y - peak
	_check(absf(height - 103.0) <= 14.0, "jump height %.1f != 103±14" % height)
	world["root"].queue_free()
	await get_tree().physics_frame


func _test_coyote_time() -> void:
	var world: Dictionary = await _make_world([{ "x": 0, "y": 500, "w": 220, "h": 200 }], { "world_width": 900 })
	var player: Xuanzang = world["player"]
	var scripted: ScriptedInput = world["input"]
	scripted.axis = 1.0
	var left_floor := false
	for i in range(120):
		await get_tree().physics_frame
		if not player.is_on_floor():
			left_floor = true
			break
	_check(left_floor, "player never left the platform (coyote test setup broken)")
	scripted.jump_pressed = true
	scripted.jump_held = true
	await get_tree().physics_frame
	_check(player.velocity.y < -100.0, "coyote jump did not fire (vy=%.1f)" % player.velocity.y)
	world["root"].queue_free()
	await get_tree().physics_frame


func _test_combat() -> void:
	var world: Dictionary = await _make_world([{ "x": 0, "y": 500, "w": 2400, "h": 200 }])
	var player: Xuanzang = world["player"]
	var scripted: ScriptedInput = world["input"]
	var enemy := Guardi.new()
	enemy.position = Vector2(player.global_position.x + 46.0, 500.0)
	world["root"].add_child(enemy)
	await get_tree().physics_frame
	var hp_before := enemy.hp
	scripted.attack_pressed = true
	for i in range(40):
		await get_tree().physics_frame
	_check(enemy.hp < hp_before, "attack did not damage the enemy (hp %d -> %d)" % [hp_before, enemy.hp])
	_check(Hitstop.last_duration >= 0.06 and Hitstop.last_duration <= 0.09, "hitstop %.3f outside [0.06, 0.09]" % Hitstop.last_duration)
	_check(Engine.time_scale == 1.0, "Engine.time_scale not restored (%.2f)" % Engine.time_scale)
	world["root"].queue_free()
	await get_tree().physics_frame


func _test_parallax() -> void:
	var rig := ParallaxRig.new()
	get_tree().root.add_child(rig)
	rig.build()
	await get_tree().process_frame
	_check(rig.layers.size() == 4, "expected 4 parallax layers, got %d" % rig.layers.size())
	var expected: Array[float] = [0.05, 0.25, 0.50, 0.80]
	for i in range(rig.layers.size()):
		var layer := rig.layers[i]
		_check(absf(layer.scroll_scale.x - expected[i]) < 0.001, "layer %d scroll_scale %.2f != %.2f" % [i, layer.scroll_scale.x, expected[i]])
		_check(layer.repeat_size.x > 0.0, "layer %d has no repeat_size (tiling would show a seam)" % i)
		_check(layer.get_child_count() == 2, "layer %d should hold original + mirrored sprite" % i)

	var camera := ScreenShake.new()
	get_tree().root.add_child(camera)
	camera.limit_left = -100000
	camera.limit_right = 100000
	camera.position = Vector2.ZERO
	await get_tree().process_frame
	var before: Array[float] = []
	var before_node: Array[float] = []
	for layer in rig.layers:
		before.append(layer.get_child(0).global_position.x)
		before_node.append(layer.global_position.x)
	camera.position = Vector2(1000, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	var last_index := rig.layers.size() - 1
	var nearest_moved: float = rig.layers[last_index].global_position.x - before_node[last_index]
	for i in range(rig.layers.size()):
		var moved: float = rig.layers[i].get_child(0).global_position.x - before[i]
		var moved_node: float = rig.layers[i].global_position.x - before_node[i]
		print("[diag] layer %d scroll=%.2f child_moved=%.1f node_moved=%.1f" % [i, expected[i], moved, moved_node])
		# Parallax2D shifts its own node by (1 - scroll_scale) * camera_delta and
		# wraps it by whole repeat periods, so an absolute node position is not the
		# spec. What the player actually sees is the *relative* displacement between
		# layers: (0.80 - scroll_scale) * 1000 measured against the nearest layer.
		var relative: float = moved_node - nearest_moved
		var relative_want: float = (0.80 - expected[i]) * 1000.0
		_check(absf(relative - relative_want) <= 8.0, "layer %d relative displacement %.1f != %.1f for a 1000 px camera move" % [i, relative, relative_want])
	rig.queue_free()
	camera.queue_free()
	await get_tree().process_frame


func _test_save_roundtrip() -> void:
	var path := "user://test_save.json"
	GameState.unlocked_levels = ["l01"]
	GameState.completed_levels = []
	GameState.current_level = "l01"
	GameState.checkpoint_id = "cp_gate"
	GameState.collect("bead")
	_check(GameState.save_progress(path), "save_progress returned false")
	GameState.unlocked_levels = []
	GameState.completed_levels = []
	GameState.checkpoint_id = "start"
	GameState.collected = {}
	_check(GameState.load_progress(path), "load_progress returned false")
	_check(GameState.checkpoint_id == "cp_gate", "checkpoint not restored (%s)" % GameState.checkpoint_id)
	_check(int(GameState.collected.get("bead", 0)) == 1, "collected item not restored")
	GameState.complete_level("l01")
	_check(GameState.unlocked_levels.has("l02"), "completing l01 did not unlock l02")


func _test_real_level_ground() -> void:
	# Regression for "player falls through the world forever": run the real level
	# data, spawn the real character and require it to actually stand on the ground.
	var root := Node2D.new()
	get_tree().root.add_child(root)
	var level := LevelBuilder.new()
	root.add_child(level)
	level.load_data(LevelBuilder.LEVEL_PATH)
	var spawn: Vector2 = level.build()
	_check(not level.data.is_empty(), "l01.json did not load")

	var player := Xuanzang.new()
	player.position = spawn
	root.add_child(player)
	var scripted := ScriptedInput.new()
	player.input_source = scripted
	var ground_y := 0.0
	for platform in level.data.get("platforms", []):
		if float(platform["y"]) >= 500.0:
			ground_y = float(platform["y"])
			break
	for i in range(150):
		await get_tree().physics_frame
	_check(player.is_on_floor(), "player never landed on the ground (y=%.1f, ground=%.1f)" % [player.global_position.y, ground_y])
	_check(absf(player.global_position.y - ground_y) <= 6.0, "player rests at y=%.1f, expected %.1f" % [player.global_position.y, ground_y])

	scripted.axis = 1.0
	var start_x := player.global_position.x
	for i in range(90):
		await get_tree().physics_frame
	_check(player.global_position.x > start_x + 250.0, "player did not move right on real level data (dx=%.1f)" % (player.global_position.x - start_x))
	_check(player.is_on_floor(), "player lost the ground while running")
	root.queue_free()
	await get_tree().physics_frame
