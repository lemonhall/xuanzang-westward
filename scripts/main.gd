extends Node2D
## Entry point. Level content is built from data (data/levels/*.json) rather than
## living only in the editor, so the same description drives tests and the game.

const LEVEL_DATA := "res://data/levels/l01.json"
const SPRITE_DIR := "res://assets/sprites/xuanzang"

var player: Sprite2D


func _ready() -> void:
	_show_placeholder()
	if ResourceLoader.exists(LEVEL_DATA):
		print("[main] level data found: %s" % LEVEL_DATA)
	else:
		print("[main] level data not written yet: %s" % LEVEL_DATA)


func _show_placeholder() -> void:
	# A single idle frame on screen: enough to prove the asset pipeline feeds the
	# engine, and to keep `--headless --quit` free of missing-resource errors.
	player = Sprite2D.new()
	player.name = "PlaceholderPlayer"
	player.texture = load("%s/idle_01.png" % SPRITE_DIR)
	player.position = Vector2(320, 420)
	add_child(player)

	var label := Label.new()
	label.text = "西行·玄奘 — v1 素材管线已接通（关卡与玩法待接）"
	label.position = Vector2(24, 24)
	add_child(label)
