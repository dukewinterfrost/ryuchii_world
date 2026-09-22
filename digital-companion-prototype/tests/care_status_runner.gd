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

func requested(kind: String) -> Dictionary:
	var s := CareRules.make_new_state(1000)
	s.care.happiness = 40.0
	s.care.status.wish = kind
	s.care.status.wish_expires_at = 1120.0
	return s

func run() -> void:
	var game := root.get_node("GameState")
	if not game.isolated_mode: quit(1); return
	game.set_process(false)
	var fresh := CareRules.make_new_state(1000)
	check(CareRules.state_is_valid(fresh), "fresh status state validates")
	var legacy := fresh.duplicate(true)
	legacy.battle.erase("mob_wins")
	legacy.care.erase("status")
	legacy.inventory.items.erase("barrier")
	legacy.inventory.items.erase("haste")
	var migrated := CareRules.migrate_state_v6(legacy)
	check(CareRules.state_is_valid(migrated) and migrated.care.food == legacy.care.food and migrated.identity == legacy.identity and migrated.inventory == fresh.inventory, "v6 migration preserves food identity and grants tactical starter supplies once")
	check(CareRules.migrate_state_v6(migrated) == migrated, "status migration idempotent")
	var path := "/tmp/care-status-%d.json" % Time.get_ticks_usec()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"schemaVersion": 6, "savedAt": 1000, "companion": legacy}))
	file.close()
	var repo := SaveRepository.new(path)
	check(CareRules.state_is_valid(repo.load_state().state), "v6 envelope migrates through repository")
	var bad := fresh.duplicate(true)
	bad.care.status.sleep_remaining = NAN
	check(not CareRules.state_is_valid(bad), "invalid sleep timer rejected")
	bad = fresh.duplicate(true)
	bad.care.status.wish = "bogus"
	check(not CareRules.state_is_valid(bad), "unknown wish rejected")
	var offline := CareRules.advance_time(fresh, 1300, 0)
	check(offline.care.status.wish == "" and offline.care.status.sleep_need == 0, "offline awake time does not invent wishes or sleepiness")
	var want := requested("play")
	check(CareStatusRules.bubble(want) == "play", "play wish appears")
	var played := CareRules.apply_command(want, "play", "", 1000)
	check(played.bond_gain == 7 and played.state.care.happiness == 56 and played.state.care.status.wish == "", "requested play adds bonuses and consumes wish")
	check(CareRules.apply_command(played.state, "play", "", 1000).bond_gain < 4, "repeat play cannot repeat wish bonus")
	check(CareRules.apply_command(want, "pet", "", 1000).state.care.status.wish == "play", "petting is distinct from requested play")
	check(CareRules.advance_time(want, 1121, 0).care.status.wish == "", "wish expires harmlessly")
	var cadence := fresh.duplicate(true)
	cadence.care.food.wait_seconds = 420.0
	cadence = CareRules.advance_time(cadence, 1180, 180)
	check(cadence.care.status.wish == "play", "engaged care creates first play wish")
	cadence.care.status.wish = ""
	cadence.care.status.wish_expires_at = 0.0
	cadence.care.status.wish_wait = 1.0
	cadence = CareRules.advance_time(cadence, 1181, 1)
	check(cadence.care.status.wish == "train", "wish sequence alternates to training")
	for stat: String in GameDefinitions.TRAINING:
		var trained := CareRules.complete_training(requested("train"), stat, "motivated-" + stat, 30)
		var expected := 25 if stat in ["hp", "mp"] else 3
		check(trained.ok and trained.gain == expected and trained.state.care.status.wish == "", "motivated " + stat + " receives exactly one boost")
		check(not CareRules.complete_training(trained.state, stat, "motivated-" + stat, 30).ok, "duplicate " + stat + " reward rejected")
	var tired := fresh.duplicate(true)
	tired.care.fatigue = 60.0
	check(CareStatusRules.bubble(tired) == "tired" and CareRules.training_readiness(tired, "hp").ok, "tired warning precedes exhaustion lock")
	var sick_count := 0
	var sick_sequence := 0
	for i: int in 40:
		tired.care.status.risk_sequence = i
		var a := CareRules.complete_training(tired, "hp", "risk", 30)
		var b := CareRules.complete_training(tired, "hp", "risk", 30)
		check(a.state == b.state, "sickness roll stable across completion retry " + str(i))
		if a.became_sick:
			sick_count += 1
			sick_sequence = i
	check(sick_count > 0 and sick_count < 40, "overtraining can cause sickness but not always")
	tired.care.status.sick = true
	check(not CareRules.training_readiness(tired, "hp").ok, "sick creature cannot continue training")
	check(not CareRules.apply_command(tired, "play").accepted, "sick creature rests instead of playing")
	var sleeping: Dictionary = CareRules.apply_command(tired, "sleep").state
	check(CareStatusRules.bubble(sleeping) == "sleeping" and sleeping.care.status.sleep_reward, "sleep overrides sickness bubble and qualifies for discipline")
	check(not CareRules.apply_command(sleeping, "sleep").accepted, "repeated sleep cannot reset or re-award")
	check(not CareRules.apply_command(sleeping, "feed", "pudding").accepted, "sleep blocks incompatible care")
	var partial := CareRules.advance_time(sleeping, 1060, 60)
	check(partial.care.fatigue < sleeping.care.fatigue and partial.progression.active_seconds == sleeping.progression.active_seconds, "sleep recovers fatigue without engaged progression")
	var early: Dictionary = CareRules.apply_command(partial, "wake").state
	check(early.care.status.sick and early.care.discipline == tired.care.discipline and not early.care.status.sleep_reward, "early wake does not cure sickness or award discipline")
	check(repo.save_state(partial), "partial sleep saves")
	var reloaded: Dictionary = repo.load_state().state
	var rested := CareRules.advance_time(reloaded, 1120, 0)
	check(not rested.care.status.sick and not rested.care.status.sleeping and rested.care.discipline == tired.care.discipline + 2, "offline/reloaded full sleep cures and rewards once")
	check(CareRules.advance_time(rested, 1240, 0).care.discipline == rested.care.discipline, "completed sleep never repeats reward")
	var unnecessary: Dictionary = CareRules.apply_command(fresh, "sleep").state
	check(CareRules.advance_time(unnecessary, 1120).care.discipline == fresh.care.discipline, "unneeded repeated naps cannot farm discipline")
	# Exercise pinned motivation and activity exclusion through GameState.
	game.state = requested("train")
	game._test_clock = 1100
	check(game.start_training("offense").ok, "GameState starts motivated training")
	check(not game.execute_command("sleep").accepted, "cannot sleep during active training")
	game._training.elapsed = 30.0
	game.state = CareRules.advance_time(game.state, 1130, 30, true)
	game._test_clock = 1130
	check(game.complete_training(game._training.id).ok and game.state.battle_profile.offense == 11, "motivation pinned at start survives deadline during valid session")
	game.state = requested("train")
	game._test_clock = 1000
	game.start_training("offense")
	game.cancel_training()
	check(game.state.battle_profile.offense == 8, "cancelled motivated session has no reward")
	# Save failure must not start sleep or consume a wish.
	var original_repo = game._repository
	game._repository = SaveRepository.new("/dev/null/status-save.json")
	game.state = requested("play")
	game.isolated_mode = false
	check(not game.execute_command("play").accepted and game.state.care.status.wish == "play" and game.state.care.bond == 0, "failed play save preserves wish and rewards")
	check(not game.execute_command("sleep").accepted and not game.state.care.status.sleeping, "failed sleep save rolls back bedtime")
	game.state = fresh.duplicate(true)
	game.state.care.fatigue = 60.0
	game.state.care.status.risk_sequence = sick_sequence
	game.start_training("hp")
	game._training.elapsed = 30.0
	var failed_session: String = game._training.id
	check(not game.complete_training(failed_session).ok and not game.state.care.status.sick and game.state.care.status.risk_sequence == sick_sequence and game.state.battle_profile.hp == 100, "failed risky training save rolls back sickness, roll and stats together")
	game.isolated_mode = true
	game._repository = original_repo
	check(game.complete_training(failed_session).ok and game.state.care.status.sick and game.state.battle_profile.hp == 120, "retry preserves sickness result and awards once")
	check(not game.complete_training(failed_session).ok, "retry cannot grant training twice")
	game.persistence_notice = ""
	game.state = fresh.duplicate(true)
	game._home_package = HabitatAssetLibrary.resolve_region("green-shade", false)
	var care = load("res://scenes/care_scene.tscn").instantiate()
	root.add_child(care)
	for dimensions: Vector2i in [Vector2i(360, 640), Vector2i(390, 844)]:
		root.content_scale_size = dimensions
		root.size = dimensions
		for frame: int in 5: await process_frame
		for kind: String in ["sleepy", "sleeping", "tired", "sick", "play", "train"]:
			var sample := fresh.duplicate(true)
			match kind:
				"sleepy": sample.care.status.sleep_need = 45.0
				"sleeping": sample = CareRules.apply_command(tired, "sleep").state
				"tired": sample.care.fatigue = 60.0
				"sick": sample.care.status.sick = true
				_: sample = requested(kind)
			game.state = sample
			care._on_state_changed(sample)
			care.habitat.environment_3d.advance_camera(10)
			care._update_craving_bubble()
			check(care._craving_bubble.visible and care._craving_bubble.status_kind == kind, "visible " + kind + " at " + str(dimensions))
			if "--capture" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("/tmp/care-status-%s-%d.png" % [kind, dimensions.y])
				if kind in ["play", "train"] and dimensions.y == 844:
					care._craving_bubble.set_process(false)
					for phase: float in [0.25, 0.75]:
						care._craving_bubble.phase = phase
						care._craving_bubble.queue_redraw()
						await RenderingServer.frame_post_draw
						root.get_texture().get_image().save_png("/tmp/care-status-%s-phase-%d.png" % [kind, int(phase * 100)])
					care._craving_bubble.set_process(true)
			if kind == "sleeping": check(care.habitat.sleeping, "sleep pauses roaming")
			care._craving_bubble.reduced_motion = true
			care._craving_bubble._process(0.1)
			check(care._craving_bubble.phase == 0 or kind not in ["play", "train", "sleepy", "sleeping"], "reduced motion freezes status icon")
	care._craving_bubble.pressed.emit()
	check(care._pages.Training.visible and care._modal.visible, "training thought opens training picker")
	care._modal.hide()
	game.state = requested("play")
	care._on_state_changed(game.state)
	care._craving_bubble.pressed.emit()
	check(game.state.care.bond == 7 and game.state.care.status.wish == "", "play thought grants bonus through GameState")
	care.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	repo.clear()
	print("Care statuses: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
