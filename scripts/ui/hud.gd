class_name Hud
extends CanvasLayer
## 定力（三颗心）与心念条，数据来自 GameState，不自持状态。

var _composure := 3
var _focus := 100


func _ready() -> void:
	layer = 10
	GameState.composure_changed.connect(_on_composure)
	GameState.focus_changed.connect(_on_focus)
	_composure = GameState.composure
	_focus = GameState.focus
	var canvas := Control.new()
	canvas.name = "HudDraw"
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.draw.connect(_draw_hud.bind(canvas))
	add_child(canvas)


func _on_composure(value: int) -> void:
	_composure = value


func _on_focus(value: int) -> void:
	_focus = value


func _draw_hud(canvas: Control) -> void:
	var font := ThemeDB.fallback_font
	canvas.draw_string(font, Vector2(28, 42), "定力", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#2E2A24"))
	for i in range(3):
		var center := Vector2(96 + i * 34, 34)
		var filled := i < _composure
		canvas.draw_circle(center, 11.0, Color("#B3402F") if filled else Color(0.7, 0.66, 0.6, 0.45))
		canvas.draw_arc(center, 11.0, 0.0, TAU, 24, Color("#2E2A24"), 2.0, true)
	var bar := Rect2(Vector2(28, 62), Vector2(240, 12))
	canvas.draw_rect(bar, Color(0.18, 0.16, 0.14, 0.35))
	var filled_ratio := clampf(float(_focus) / float(GameState.MAX_FOCUS), 0.0, 1.0)
	canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * filled_ratio, bar.size.y)), Color("#D4A02A"))
	canvas.draw_rect(bar, Color("#2E2A24"), false, 2.0)
	canvas.draw_string(font, Vector2(276, 74), "心念 %d" % _focus, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#2E2A24"))
	canvas.queue_redraw()
