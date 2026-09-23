class_name SlashArc
extends Node2D
## 挥砍弧线：命中瞬间叠出的墨色扇弧，让"锡杖横抡出去"这件事有画面。
##
## 用程序化的弧（Polygon2D）而不是贴图：弧随攻击方向镜像、随命中点摆放，
## 不需要为不同朝向生成多套素材；若 assets/fx/fx_slash_arc.png 存在则优先用它。

const DURATION := 0.16
const ASSET := "res://assets/fx/fx_slash_arc.png"

var facing := 1
var _life := 0.0
var _sprite: Sprite2D
var _arc: Polygon2D


func _ready() -> void:
	if ResourceLoader.exists(ASSET):
		_sprite = Sprite2D.new()
		_sprite.texture = load(ASSET)
		_sprite.scale = Vector2(0.55 * facing, 0.55)
		_sprite.rotation = deg_to_rad(-18.0 * facing)
		add_child(_sprite)
	else:
		_arc = Polygon2D.new()
		var points := PackedVector2Array()
		var outer := 78.0
		var inner := 46.0
		for i in range(13):
			var t := float(i) / 12.0
			var angle := deg_to_rad(-58.0 + 116.0 * t)
			points.append(Vector2(cos(angle) * outer * facing, sin(angle) * outer))
		for i in range(12, -1, -1):
			var t := float(i) / 12.0
			var angle := deg_to_rad(-58.0 + 116.0 * t)
			points.append(Vector2(cos(angle) * inner * facing, sin(angle) * inner))
		_arc.polygon = points
		_arc.color = Color(0.98, 0.96, 0.9, 0.85)
		add_child(_arc)
	z_index = 20


func _process(delta: float) -> void:
	_life += delta
	var t := clampf(_life / DURATION, 0.0, 1.0)
	modulate.a = 1.0 - t
	scale = Vector2(0.85 + 0.35 * t, 0.85 + 0.35 * t)
	rotation = deg_to_rad(-14.0 * t * facing)
	if _life >= DURATION:
		queue_free()
