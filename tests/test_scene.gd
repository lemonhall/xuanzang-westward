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
	await _test_level_gaps_are_jumpable()
	await _test_level_is_reachable()
	await _test_first_gap_crossing()
	await _test_background_meets_the_ground()
	await _test_background_crop_edges_stay_out_of_view()
	await _test_ground_band_framing()
	await _test_ground_reaches_below_the_view()
	await _test_enemy_art_and_facing()

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
	var enemy := Enemy.new()
	enemy.actor_name = "wolf"
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
	for i in range(rig.layers.size()):
		var moved: float = rig.layers[i].get_child(0).global_position.x - before[i]
		var moved_node: float = rig.layers[i].global_position.x - before_node[i]
		print("[diag] layer %d scroll=%.2f child_moved=%.1f node_moved=%.1f" % [i, expected[i], moved, moved_node])
		# Parallax2D shifts its own node by (1 - scroll_scale) * camera_delta and wraps
		# it by whole repeat periods. Layers now have different periods (scale differs
		# per layer), so the check normalises each layer by its own period: the screen
		# space displacement is scroll_scale * camera_delta (PRD: 50/250/500/800 px).
		var period: float = rig.layers[i].repeat_size.x
		var want: float = (1.0 - expected[i]) * 1000.0
		var residual: float = fposmod(moved_node - want + period * 0.5, period) - period * 0.5
		_check(absf(residual) <= 8.0, "layer %d scrolled %.1f px (want %.1f, residual %.1f, period %.1f)" % [i, moved_node, want, residual, period])
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


func _test_level_gaps_are_jumpable() -> void:
	# 物理极限：滞空 0.590s × 220px/s = 129.8px，再减去角色宽度 36px。
	# 关卡里的坑必须留出余量，否则玩家会撞上"跳不过去的深坑"。
	var reach := Xuanzang.max_jump_distance() - Xuanzang.body_width()
	var budget := reach * 0.85
	var raw := FileAccess.get_file_as_string(LevelBuilder.LEVEL_PATH)
	var data: Dictionary = JSON.parse_string(raw)
	_check(not data.is_empty(), "l01.json unreadable for the gap check")
	var ground: Array = []
	for platform in data.get("platforms", []):
		if float(platform["y"]) >= 500.0:
			ground.append(platform)
	ground.sort_custom(func(a, b): return float(a["x"]) < float(b["x"]))
	for i in range(ground.size() - 1):
		var left_edge: float = float(ground[i]["x"]) + float(ground[i]["w"])
		var right_edge: float = float(ground[i + 1]["x"])
		var gap: float = right_edge - left_edge
		_check(gap <= budget, "gap %.0f px between platform %d and %d exceeds the jumpable budget %.0f px" % [gap, i, i + 1, budget])


func _test_level_is_reachable() -> void:
	# 关卡可达性：把平台建成图，按物理极限（跳高 103px、水平跨距 129.8px）做连通性检查，
	# 保证从出生点平台能一路跳到终点平台。"高台跳不上去"就是这条检查要抓的缺陷。
	var raw := FileAccess.get_file_as_string(LevelBuilder.LEVEL_PATH)
	var data: Dictionary = JSON.parse_string(raw)
	var spans: Array = []
	for platform in data.get("platforms", []):
		spans.append({
			"left": float(platform["x"]),
			"right": float(platform["x"]) + float(platform["w"]),
			"top": float(platform["y"]),
		})
	var height_budget := Xuanzang.max_jump_height() * 0.85
	var distance_budget := Xuanzang.max_jump_distance() * 0.85

	var spawn: Array = data.get("spawn", [0, 0])
	var start_index := _platform_under(spans, float(spawn[0]), float(spawn[1]))
	var goal: Dictionary = data.get("goal", {})
	var goal_index := _platform_under(spans, float(goal.get("x", 0.0)), float(goal.get("y", 0.0)))
	_check(start_index >= 0, "spawn point is not above any platform")
	_check(goal_index >= 0, "goal is not above any platform")
	if start_index < 0 or goal_index < 0:
		return

	var reached := { start_index: true }
	var queue: Array[int] = [start_index]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for i in range(spans.size()):
			if reached.has(i):
				continue
			if _can_hop(spans[current], spans[i], height_budget, distance_budget):
				reached[i] = true
				queue.append(i)
	_check(reached.has(goal_index), "goal unreachable with current jump physics (reached %d of %d platforms)" % [reached.size(), spans.size()])
	# 反作弊：不允许"孤儿平台"——任何一块地形都必须能从出生点跳上去，
	# 否则就是玩家看到的"高台跳不上去"这种缺陷。
	if reached.size() != spans.size():
		var orphans: Array[String] = []
		for i in range(spans.size()):
			if not reached.has(i):
				orphans.append("(x=%.0f..%.0f, top=%.0f)" % [spans[i]["left"], spans[i]["right"], spans[i]["top"]])
		_check(false, "unreachable platforms with current jump physics: %s" % ", ".join(orphans))


func _platform_under(spans: Array, x: float, y: float) -> int:
	var best := -1
	for i in range(spans.size()):
		var span: Dictionary = spans[i]
		if x >= float(span["left"]) - 8.0 and x <= float(span["right"]) + 8.0:
			if float(span["top"]) >= y - 12.0:
				if best == -1 or float(span["top"]) < float(spans[best]["top"]):
					best = i
	return best


func _can_hop(from_span: Dictionary, to_span: Dictionary, height_budget: float, distance_budget: float) -> bool:
	var rise: float = float(from_span["top"]) - float(to_span["top"])
	if rise > height_budget:
		return false
	var gap := 0.0
	if float(to_span["left"]) > float(from_span["right"]):
		gap = float(to_span["left"]) - float(from_span["right"])
	elif float(from_span["left"]) > float(to_span["right"]):
		gap = float(from_span["left"]) - float(to_span["right"])
	return gap <= distance_budget


func _test_first_gap_crossing() -> void:
	# 用户报过的缺陷："玄奘跳不过去"。这里用真实关卡数据真的跳一次第一个坑。
	var root := Node2D.new()
	get_tree().root.add_child(root)
	var level := LevelBuilder.new()
	root.add_child(level)
	level.load_data(LevelBuilder.LEVEL_PATH)
	var ground: Array = []
	for platform in level.data.get("platforms", []):
		if float(platform["y"]) >= 500.0:
			ground.append(platform)
	ground.sort_custom(func(a, b): return float(a["x"]) < float(b["x"]))
	_check(ground.size() >= 2, "level needs at least two ground platforms for the gap test")
	if ground.size() < 2:
		return
	var edge_x: float = float(ground[0]["x"]) + float(ground[0]["w"])
	var next_x: float = float(ground[1]["x"])

	level.data["spawn"] = [edge_x - 90.0, 480.0]
	var spawn: Vector2 = level.build()
	var player := Xuanzang.new()
	player.position = spawn
	root.add_child(player)
	var scripted := ScriptedInput.new()
	player.input_source = scripted
	scripted.axis = 1.0

	var jumped := false
	for i in range(120):
		if not jumped and player.is_on_floor() and player.global_position.x >= edge_x - 45.0:
			scripted.jump_pressed = true
			scripted.jump_held = true
			jumped = true
		await get_tree().physics_frame
	_check(jumped, "never reached the platform edge to attempt the jump")
	_check(player.is_on_floor(), "player was still airborne after the jump window (y=%.1f)" % player.global_position.y)
	_check(player.global_position.x > next_x - 20.0, "player did not clear the first gap (x=%.1f, next platform starts at %.1f)" % [player.global_position.x, next_x])
	root.queue_free()
	await get_tree().physics_frame


func _test_enemy_art_and_facing() -> void:
	# 敌人必须用真美术（不是剪影占位），且必须朝着行进方向转头：
	# 素材统一朝右画，向左巡逻时靠 flip_h 镜像。
	var world: Dictionary = await _make_world([{ "x": 0, "y": 500, "w": 2400, "h": 200 }])
	var enemy := Enemy.new()
	enemy.actor_name = "wolf"
	enemy.position = Vector2(1200, 500)
	world["root"].add_child(enemy)
	await get_tree().physics_frame
	_check(enemy.has_art, "wolf art missing: assets/sprites/wolf/ has no frames (enemy fell back to the silhouette placeholder)")
	var sprite := enemy.sprite_node()
	_check(sprite != null, "enemy built no sprite")
	if sprite == null:
		world["root"].queue_free()
		return
	var animation_count := sprite.sprite_frames.get_animation_names().size()
	_check(animation_count >= 4, "wolf sprite has only %d animations; expected idle/walk/run/attack/hurt" % animation_count)

	enemy.patrol_dir = 1.0
	await get_tree().physics_frame
	_check(sprite.flip_h == false, "wolf facing right should not be mirrored while moving right")
	enemy.patrol_dir = -1.0
	await get_tree().physics_frame
	_check(sprite.flip_h == true, "wolf did not turn around when moving left (head would point the wrong way)")
	print("[diag] enemy: art=%s animations=%d facing flip ok" % [str(enemy.has_art), animation_count])
	world["root"].queue_free()
	await get_tree().physics_frame


func _test_ground_reaches_below_the_view() -> void:
	# 用户实测缺陷："屏幕底部的地面竟然是悬空的"。
	# 规则：关卡自家的土必须延伸到可见下缘之外，绝不允许靠背景层去补地面。
	var view := _visible_vertical_range()
	var visible_bottom: float = view["bottom"]
	var raw := FileAccess.get_file_as_string(LevelBuilder.LEVEL_PATH)
	var data: Dictionary = JSON.parse_string(raw)
	var checked := 0
	for platform in data.get("platforms", []):
		var is_ground := float(platform["y"]) >= 500.0 and float(platform["h"]) > 60.0
		if not is_ground:
			continue
		checked += 1
		var collision_bottom: float = float(platform["y"]) + float(platform["h"])
		var fill_bottom: float = float(platform["y"]) + LevelBuilder.EARTH_FILL_HEIGHT
		_check(collision_bottom >= visible_bottom + 20.0, "ground platform at x=%.0f ends at y=%.0f, above the visible bottom %.0f (screen bottom would float)" % [float(platform["x"]), collision_bottom, visible_bottom])
		_check(fill_bottom >= visible_bottom + 20.0, "earth fill at x=%.0f only reaches y=%.0f, above the visible bottom %.0f" % [float(platform["x"]), fill_bottom, visible_bottom])
	_check(checked > 0, "no ground platform found to verify")
	print("[diag] ground coverage: %d platforms, visible bottom %.0f, collision+fill verified" % [checked, visible_bottom])


func _test_ground_band_framing() -> void:
	# 用户实测缺陷："地面那块咖啡色土地从屏幕底部顶到屏幕中部"。
	# 构图约束：站在地面时，脚下那条土带占屏 ≤30%，角色脚底落在屏幕 60%–80% 之间。
	var viewport_height: float = float(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
	var ground_y := _ground_line()
	var camera_y := ground_y - ScreenShake.FOLLOW_OFFSET_Y
	var visible_bottom := camera_y + viewport_height * 0.5
	var earth_band := visible_bottom - ground_y
	var ratio := earth_band / viewport_height
	_check(ratio <= 0.30, "earth band under the ground line is %.0f px (%.0f%% of the viewport); keep it under 30%%" % [earth_band, ratio * 100.0])
	var feet_ratio := (viewport_height * 0.5 + ScreenShake.FOLLOW_OFFSET_Y) / viewport_height
	_check(feet_ratio >= 0.60 and feet_ratio <= 0.80, "character feet sit at %.0f%% of the screen height; expected 60%%-80%%" % (feet_ratio * 100.0))
	print("[diag] framing: earth band %.0f px (%.0f%%), feet at %.0f%%" % [earth_band, ratio * 100.0, feet_ratio * 100.0])


func _test_background_crop_edges_stay_out_of_view() -> void:
	# 用户实测缺陷："一跳起来就露出贴图被裁剪的边"（柳枝正好画到贴图第 0 行）。
	# 规则：如果某层内容画到了贴图的上/下边界，那这条边界必须落在可见范围之外。
	var view := _visible_vertical_range()
	var margin := 20.0
	var rig := ParallaxRig.new()
	get_tree().root.add_child(rig)
	rig.build()
	await get_tree().process_frame
	for layer in rig.layers:
		var sprite: Sprite2D = layer.get_child(0)
		var texture: Texture2D = sprite.texture
		var height := float(texture.get_height())
		var half := height * 0.5
		var scale_y := sprite.scale.y
		var top_edge: float = sprite.position.y - half * scale_y
		var bottom_edge: float = sprite.position.y + half * scale_y
		if _content_top_row(texture, 16) <= 0:
			_check(top_edge <= view["top"] - margin, "layer %s has content cut at the texture top edge (%.0f) which enters the view (visible top %.0f) — jumping will expose the crop" % [layer.name, top_edge, view["top"]])
		if _content_bottom_row(texture, 16) >= int(height) - 4:
			_check(bottom_edge >= view["bottom"] + margin, "layer %s has content cut at the texture bottom edge (%.0f) which leaves the view (visible bottom %.0f)" % [layer.name, bottom_edge, view["bottom"]])
	rig.queue_free()
	await get_tree().process_frame


func _visible_vertical_range() -> Dictionary:
	# 可见范围由关卡的最高/最低平台、跳跃高度、相机偏移和视口高度共同决定。
	var raw := FileAccess.get_file_as_string(LevelBuilder.LEVEL_PATH)
	var data: Dictionary = JSON.parse_string(raw)
	var highest := 100000.0
	var lowest := -100000.0
	for platform in data.get("platforms", []):
		var top := float(platform["y"])
		highest = minf(highest, top)
		lowest = maxf(lowest, top)
	var viewport_height: float = float(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
	var half_view := viewport_height * 0.5
	var jump := Xuanzang.max_jump_height()
	var top := highest - jump - ScreenShake.FOLLOW_OFFSET_Y - half_view
	var bottom := lowest - ScreenShake.FOLLOW_OFFSET_Y + half_view
	return { "top": top, "bottom": bottom }


func _content_top_row(texture: Texture2D, threshold: int) -> int:
	var image := texture.get_image()
	if image.is_empty():
		return 0
	var step := 4
	for y in range(0, image.get_height(), step):
		for x in range(0, image.get_width(), step):
			if image.get_pixel(x, y).a * 255.0 > float(threshold):
				return y
	return image.get_height()


func _test_background_meets_the_ground() -> void:
	# 反作弊：不允许"背景悬在地面上方、中间留一条空带"——这是人工发现过的缺陷。
	var rig := ParallaxRig.new()
	get_tree().root.add_child(rig)
	rig.build()
	await get_tree().process_frame
	var ground_y := _ground_line()
	for layer in rig.layers:
		var sprite: Sprite2D = layer.get_child(0)
		var texture: Texture2D = sprite.texture
		var bottom_row := _content_bottom_row(texture, 16)
		var half := float(texture.get_height()) * 0.5
		# The authored vertical offset lives on the sprite; the Parallax2D node's own
		# position is engine-owned scroll state.
		var screen_bottom: float = sprite.position.y + (float(bottom_row) - half) * sprite.scale.y
		var image := texture.get_image()
		print("[diag] %s tex=%s img=%s bottom_row=%d pos_y=%.0f scale=%.2f screen_bottom=%.0f  a@1023=%s a@900=%s a@700=%s a@600=%s" % [
			layer.name, str(texture.get_size()), str(image.get_size()), bottom_row, sprite.position.y, sprite.scale.y, screen_bottom,
			str(image.get_pixel(512, image.get_height() - 1).a), str(image.get_pixel(512, 900).a),
			str(image.get_pixel(512, 700).a), str(image.get_pixel(512, 600).a)])
		_check(screen_bottom >= ground_y - 8.0, "layer %s only reaches y=%.0f, leaving a gap above the ground line %.0f" % [layer.name, screen_bottom, ground_y])
	rig.queue_free()
	await get_tree().process_frame


func _ground_line() -> float:
	var raw := FileAccess.get_file_as_string(LevelBuilder.LEVEL_PATH)
	var data: Dictionary = JSON.parse_string(raw)
	var ground_y := 560.0
	for platform in data.get("platforms", []):
		if float(platform["y"]) >= 500.0 and float(platform["y"]) < ground_y + 1.0:
			ground_y = float(platform["y"])
	return ground_y


func _content_bottom_row(texture: Texture2D, threshold: int) -> int:
	var image := texture.get_image()
	if image.is_empty():
		return texture.get_height()
	var step := 4
	for y in range(image.get_height() - 1, -1, -step):
		for x in range(0, image.get_width(), step):
			if image.get_pixel(x, y).a * 255.0 > float(threshold):
				return y
	return 0
