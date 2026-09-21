extends SceneTree
## Explicit one-time re-grounding; preserves every authored XZ/scale/flip/color.
const SCENES := ["care_oval_foliage", "care_transition_woodland"]
const SCALE := 4.0/3.0
var sampler := preload("res://scripts/environment/care_sloped_ground.gd").new()

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if "--test-mode" not in OS.get_cmdline_user_args() or "--replace" not in OS.get_cmdline_user_args():
		push_error("Explicit --test-mode --replace required to re-ground authored home cards.")
		sampler.free()
		quit(1)
		return
	for label: String in SCENES:
		var path := "res://scenes/environment_workshop/%s.tscn" % label
		var scene := (load(path) as PackedScene).instantiate()
		var count := 0
		for card: Sprite3D in scene.find_children("*","Sprite3D",true,false):
			var point := Vector2(card.position.x,card.position.z)*SCALE
			var ground_height: float = sampler.height_at_ground(point)
			var bury := float(card.get_meta("buried_root",-0.025))
			card.position.y = (ground_height-bury)/SCALE
			count += 1
		var records: Array = []
		for card: Sprite3D in scene.find_children("*","Sprite3D",true,false):
			records.append([String(scene.get_path_to(card)),card.position,card.region_rect,card.pixel_size,card.flip_h,card.modulate])
		scene.set_meta("layout_sha256",JSON.stringify(records).sha256_text())
		scene.set_meta("layout_hash_format","path-position-region-size-flip-color-v1")
		scene.set_meta("terrain_profile","sheer-ledge-2026-09-17")
		var packed := PackedScene.new()
		if packed.pack(scene) != OK or ResourceSaver.save(packed,path) != OK:
			push_error("Unable to save " + path)
			quit(1)
			return
		print("PASS: re-grounded %d cards, preserving XZ in %s" % [count,label])
		scene.free()
	sampler.free()
	quit(0)
