class_name Hud
extends CanvasLayer
## 定力（三颗心）与心念条，数据来自 GameState，不自持状态。

var _composure := 3
var _focus := 100
var _action_status := ""
var _action_status_until_ms := 0
var _player: Xuanzang
var _chant_progress := 0.0


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
	call_deferred("_connect_player")
	set_process(true)


func _connect_player() -> void:
	if is_instance_valid(_player):
		return
	var player := get_tree().get_first_node_in_group("player") as Xuanzang
	if player == null:
		return
	_player = player
	player.attack_started.connect(_on_attack_started)
	player.attacked.connect(_on_attacked)
	player.chant_started.connect(_on_chant_started)
	player.chant_progress_changed.connect(_on_chant_progress)
	player.chant_completed.connect(_on_chant_completed)
	player.damaged.connect(_on_player_damaged)
	player.action_feedback.connect(_on_action_feedback)


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_connect_player()
	var canvas := get_node_or_null("HudDraw") as Control
	if canvas:
		canvas.queue_redraw()


func _on_composure(value: int) -> void:
	_composure = value


func _on_focus(value: int) -> void:
	_focus = value


func _show_action(text: String, seconds: float = 0.9) -> void:
	_action_status = text
	_action_status_until_ms = Time.get_ticks_msec() + int(seconds * 1000.0)


func _on_attack_started() -> void:
	_show_action("J：锡杖挥出，消耗 8 心念", 0.6)


func _on_attacked(_point: Vector2, _damage: int) -> void:
	_show_action("命中：心念 +12", 0.9)


func _on_chant_started() -> void:
	_show_action("K：站定诵经，0.8 秒回复 25 心念", 0.9)


func _on_chant_progress(progress: float) -> void:
	_chant_progress = progress
	_show_action("诵经中 %.0f%%" % (progress * 100.0), 0.2)


func _on_chant_completed(amount: int) -> void:
	_chant_progress = 0.0
	_show_action("诵经完成：心念 +%d" % amount, 1.2)


func _on_player_damaged() -> void:
	_show_action("受击：定力 -1", 0.9)


func _on_action_feedback(message: String) -> void:
	_show_action(message, 0.9)


func _draw_hud(canvas: Control) -> void:
	var font := ThemeDB.fallback_font
	canvas.draw_string(font, Vector2(28, 42), "定力 %d/3" % _composure, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#2E2A24"))
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
	canvas.draw_string(font, Vector2(28, 100), "A/D 移动  空格 跳", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.25, 0.22, 0.19, 0.75))
	var state_text := "动作：待机"
	if is_instance_valid(_player):
		state_text = "动作：%s" % _player.state_label()
	canvas.draw_string(font, Vector2(276, 100), state_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#6E4C2E"))
	_draw_key(canvas, font, Rect2(28, 146, 200, 32), "J", "锡杖攻击 · -8", _focus >= Xuanzang.ATTACK_COST)
	_draw_key(canvas, font, Rect2(238, 146, 222, 32), "K", "站定诵经 · +25", true)
	if is_instance_valid(_player) and _player.state == Xuanzang.State.CHANT:
		var chant_bar := Rect2(28, 188, 432, 10)
		canvas.draw_rect(chant_bar, Color(0.18, 0.16, 0.14, 0.25))
		canvas.draw_rect(Rect2(chant_bar.position, Vector2(chant_bar.size.x * _chant_progress, chant_bar.size.y)), Color("#D4A02A"))
		canvas.draw_rect(chant_bar, Color("#2E2A24"), false, 1.0)
	if Time.get_ticks_msec() < _action_status_until_ms:
		canvas.draw_string(font, Vector2(28, 218), _action_status, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#6E4C2E"))


func _draw_key(canvas: Control, font: Font, rect: Rect2, key: String, label: String, ready: bool) -> void:
	var fill := Color("#F3E7C8") if ready else Color("#D8D0C5")
	var ink := Color("#2E2A24") if ready else Color(0.25, 0.22, 0.19, 0.55)
	canvas.draw_rect(rect, fill)
	canvas.draw_rect(rect, ink, false, 1.5)
	canvas.draw_string(font, rect.position + Vector2(10, 22), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ink)
	canvas.draw_string(font, rect.position + Vector2(42, 21), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)
