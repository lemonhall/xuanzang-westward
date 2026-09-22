class_name ParallaxRig
extends Node2D
## 四层视差背景（REQ-0001-006）。
##
## Each layer is a Parallax2D holding the texture twice: the original and a
## horizontally flipped copy. Mirroring makes the strip tile seamlessly by
## construction, so we never need a seamless source image or a "repeat" hack.

const LAYERS := [
	{ "file": "bg_l1_sky.png", "scroll": 0.05, "y": 280.0, "scale": 1.20 },
	# Offsets are derived from where each texture's painted content actually sits
	# (measured per row-band, see docs/art/ART-BIBLE.md): the far ridge occupies
	# rows 512–819, so at 0.75 scale the node must sit at y=330 for the ridge base
	# to meet the ground line (y=560). Mid and near layers are bottom-anchored and
	# reach below the ground so pits show earth instead of sky.
	{ "file": "bg_l1_far.png", "scroll": 0.25, "y": 346.0, "scale": 0.75 },
	{ "file": "bg_l1_mid.png", "scroll": 0.50, "y": 280.0, "scale": 1.20 },
	{ "file": "bg_l1_near.png", "scroll": 0.80, "y": 300.0, "scale": 1.20 },
]

const BG_DIR := "res://assets/backgrounds/l1"

var layers: Array[Parallax2D] = []


func build() -> void:
	for cfg in LAYERS:
		var path := "%s/%s" % [BG_DIR, cfg["file"]]
		if not ResourceLoader.exists(path):
			push_warning("missing background layer: %s" % path)
			continue
		layers.append(_make_layer(cfg, load(path)))


func _make_layer(cfg: Dictionary, texture: Texture2D) -> Parallax2D:
	var parallax := Parallax2D.new()
	parallax.name = cfg["file"].get_basename()
	parallax.scroll_scale = Vector2(cfg["scroll"], 1.0)
	# NOTE: a Parallax2D's own position is written by the engine from the camera
	# scroll, so the vertical placement must live on the child sprites instead —
	# putting it on the node silently disappears at runtime.
	var scale_factor: float = cfg["scale"]
	var half_width := texture.get_width() * 0.5 * scale_factor
	parallax.repeat_size = Vector2(texture.get_width() * 2.0 * scale_factor, 0.0)
	parallax.repeat_times = 3
	add_child(parallax)

	for mirrored in [false, true]:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.scale = Vector2(scale_factor, scale_factor)
		sprite.flip_h = mirrored
		# Centred sprites: original spans [-w/2, w/2], the flipped copy sits one
		# width to the right and mirrors the shared edge, so the seam matches.
		sprite.position = Vector2(0.0 if not mirrored else half_width * 2.0, cfg["y"])
		parallax.add_child(sprite)
	return parallax
