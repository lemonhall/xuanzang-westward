extends Node2D
## 入口：装配视差背景 → 关卡 → 玩家 → 相机 → HUD。

const LEVEL_PATH := "res://data/levels/l01.json"

var player: Xuanzang
var level: LevelBuilder
var camera: ScreenShake


func _ready() -> void:
	GameState.reset_run()
	GameState.current_level = "l01"
	GameState.load_progress()

	var rig := ParallaxRig.new()
	rig.name = "Parallax"
	add_child(rig)
	rig.build()

	level = LevelBuilder.new()
	level.name = "Level"
	add_child(level)
	level.load_data(LEVEL_PATH)
	var spawn := level.build()

	player = Xuanzang.new()
	player.name = "Xuanzang"
	player.position = spawn
	add_child(player)

	camera = ScreenShake.new()
	camera.name = "GameCamera"
	camera.follow_target_path = player.get_path()
	camera.limit_left = 0
	camera.limit_right = int(level.world_width)
	camera.limit_top = -320
	camera.limit_bottom = 900
	camera.position = spawn
	add_child(camera)

	var hud := Hud.new()
	hud.name = "Hud"
	add_child(hud)

	print("[main] level '%s' ready — 方向键/AD 移动，空格跳，J 挥杖，K 诵经" % level.data.get("name", "?"))
