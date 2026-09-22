class_name SpriteFramesLoader
extends RefCounted
## Builds SpriteFrames from a directory of normalized frames.
##
## Naming convention (enforced by tools/asset_pipeline.py):
##   <alias>_<frame>.png      e.g. idle_01.png, walk_02.png, attack_01.png
##
## Two animations are registered per file: the precise one named after the file
## stem ("walk_02", used by combat/one-shots) and the grouped one named after the
## alias ("walk", used by locomotion). One loader for player and enemies keeps the
## convention in exactly one place.


static func load_frames(dir_path: String, default_speed: float = 8.0) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return frames

	var by_alias := {}
	for file_name in dir.get_files():
		if not file_name.ends_with(".png"):
			continue
		var stem := file_name.get_basename()
		var split := stem.rsplit("_", true, 1)
		if split.size() != 2:
			continue
		var alias := split[0]
		var texture: Texture2D = load("%s/%s" % [dir_path, file_name])
		if texture == null:
			continue
		if not frames.has_animation(stem):
			frames.add_animation(stem)
			frames.set_animation_speed(stem, 1.0)
			frames.set_animation_loop(stem, false)
		frames.add_frame(stem, texture)
		if not by_alias.has(alias):
			by_alias[alias] = []
		by_alias[alias].append(stem)

	for alias in by_alias.keys():
		var names: Array = by_alias[alias]
		names.sort()
		if not frames.has_animation(alias):
			frames.add_animation(alias)
			frames.set_animation_speed(alias, default_speed if names.size() > 1 else 1.0)
			frames.set_animation_loop(alias, names.size() > 1 and not alias.begins_with("attack"))
		for name in names:
			for i in frames.get_frame_count(name):
				frames.add_frame(alias, frames.get_frame_texture(name, i))
	return frames


static func has_art(dir_path: String) -> bool:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return false
	for file_name in dir.get_files():
		if file_name.ends_with(".png"):
			return true
	return false
