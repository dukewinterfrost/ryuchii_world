extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var game := root.get_node("GameState")
	if not game.isolated_mode:
		quit(1)
		return
	game.set_process(false)
	var state := CareRules.make_new_state(1000)
	check(CareRules.state_is_valid(state), "schema v6 fresh save validates")
	var old := state.duplicate(true)
	old.battle.erase("mob_wins")
	old.care.erase("food")
	old.care.erase("status")
	old.inventory.items.erase("barrier")
	old.inventory.items.erase("haste")
	var upgraded := CareRules.migrate_state_v5(old)
	check(CareRules.state_is_valid(upgraded) and upgraded.identity == old.identity and upgraded.inventory == state.inventory and upgraded.care.poop_slots == old.care.poop_slots, "v5 migration preserves identity and waste, adding tactical starters once")
	check(CareRules.migrate_state_v5(upgraded) == upgraded, "food migration is idempotent")
	for species: String in CareRules.SPECIES_NAMES:
		check(FoodRules.FOODS.has(FoodRules.favorite(species)), species + " has a valid favorite")
	for food: String in FoodRules.FOODS:
		check(FoodRules.icon(food) != null, food + " uses a real exported icon")
	var offline := CareRules.advance_time(state, 1100, 0)
	check(offline.care.food.wait_seconds == 120 and FoodRules.active(offline).is_empty(), "offline time does not generate cravings")
	var training := CareRules.advance_time(state, 1120, 120, true)
	check(training.care.food.wait_seconds == 120, "training does not generate care cravings")
	var hungry := CareRules.advance_time(state, 1120, 120)
	check(FoodRules.active(hungry) == "pudding" and hungry.care.food.expires_at == 1240, "engaged time creates a favorite craving with a deadline")
	var full := state.duplicate(true)
	full.care.hunger = 100
	full = CareRules.advance_time(full, 1001, 120)
	check(FoodRules.active(full).is_empty(), "full companions never request food")
	var expired := CareRules.advance_time(hungry, 1241, 0)
	check(FoodRules.active(expired).is_empty() and expired.care.bond == hungry.care.bond and expired.care.happiness == hungry.care.happiness, "missed cravings expire without happiness or bond penalties")
	var invalid := CareRules.apply_command(hungry, "feed", "unknown", 1120)
	check(not invalid.accepted and invalid.state == hungry, "unknown food is rejected without state changes")
	var fulfilled := CareRules.apply_command(hungry, "feed", "pudding", 1120)
	check(fulfilled.accepted and fulfilled.state.care.food.satisfied == 1 and FoodRules.active(fulfilled.state).is_empty(), "matching snack clears craving once")
	check(fulfilled.bond_gain == 8 and fulfilled.state.care.happiness == minf(100, hungry.care.happiness + 14), "favorite and craving bonuses apply through normal reward accounting")
	var repeated := CareRules.apply_command(fulfilled.state, "feed", "pudding", 1120)
	check(not repeated.accepted and repeated.state.care.food.satisfied == 1, "full/repeated input does not double claim reward")
	var repository := SaveRepository.new("/tmp/food-care-%d.json" % Time.get_ticks_usec())
	check(repository.save_state(hungry), "active craving saves")
	var loaded_food: Dictionary = repository.load_state().state.care.food
	check(loaded_food.craving == hungry.care.food.craving and float(loaded_food.expires_at) == float(hungry.care.food.expires_at) and float(loaded_food.wait_seconds) == float(hungry.care.food.wait_seconds) and int(loaded_food.sequence) == int(hungry.care.food.sequence), "reload preserves craving, deadline, sequence and cooldown")
	var broken := hungry.duplicate(true)
	broken.care.food.craving = "bad-id"
	check(not CareRules.state_is_valid(broken), "unknown persisted craving fails validation")
	broken = hungry.duplicate(true)
	broken.care.food.wait_seconds = NAN
	check(not CareRules.state_is_valid(broken), "nonfinite timer fails validation")
	game.state = hungry.duplicate(true)
	game._test_clock = 1120.0
	game._home_package = HabitatAssetLibrary.resolve_region("green-shade", false)
	var original_repo = game._repository
	game._repository = SaveRepository.new("/dev/null/food-save.json")
	game.isolated_mode = false
	var rejected: Dictionary = game.execute_command("feed", "pudding")
	game.isolated_mode = true
	check(not rejected.accepted and game.state.care.food == hungry.care.food and game.state.care.bond == hungry.care.bond, "save failure rolls back meal and craving bonus")
	game._repository = original_repo
	game.persistence_notice = ""
	var care = load("res://scenes/care_scene.tscn").instantiate()
	root.add_child(care)
	care.habitat.set_process(false)
	for dimensions: Vector2i in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(1280, 720)]:
		root.content_scale_size = dimensions
		root.size = dimensions
		for frame: int in 5: await process_frame
		care.habitat.environment_3d.advance_camera(10)
		care._update_craving_bubble()
		check(care._craving_bubble.visible and care._craving_bubble.food_id == "pudding", "thought bubble visible above hungry companion at " + str(dimensions))
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/food-care-%dx%d.png" % [dimensions.x, dimensions.y])
		care._open_page("Food")
		await process_frame
		check(care._food_buttons.size() == 9 and not care._craving_bubble.visible, "picker shows nine foods and hides world bubble behind modal")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/food-picker-%dx%d.png" % [dimensions.x, dimensions.y])
		care._modal.hide()
	care._food_buttons.pudding.pressed.emit()
	check(game.state.care.food.satisfied == 1 and not care._modal.visible, "picker feeds through GameState and closes after selection")
	care.queue_free()
	await process_frame
	# Let the audio mixer release the stopped eating stream after scene teardown.
	await create_timer(0.1).timeout
	print("Food care: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
