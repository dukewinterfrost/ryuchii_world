extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): quit(1); return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[-1]))
	if not parsed is Dictionary: quit(1); return
	GameBalance._data = parsed
	var loaded := MobContent.load_tables()
	if not loaded.ok:
		printerr(loaded.error)
		quit(1)
		return
	for id: String in MobCatalog.creatures():
		var problem := BattleSimulator.validate_snapshot(MobCatalog.snapshot(id, id, loaded.config))
		if not problem.is_empty():
			printerr("Creatures " + id + ": " + problem)
			quit(1)
			return
	print("BALANCE_VALID")
	quit()
