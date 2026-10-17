extends SceneTree
## World saves for dedicated servers: godot --headless --path . -s res://scripts/test_save.gd
## Run a server world, save it, shut it down, start a new server (with a different seed) on
## the same world name: it must resume the saved planet exactly where it left off.

func _init() -> void:
	var ok := true
	var world_name := "e2e-save-%d" % randi()
	var port := 25700 + randi() % 300

	var a := Session.new()
	root.add_child(a)
	await process_frame
	ok = ok and a.start_dedicated(77, port, "Save test", world_name) == OK
	a.set_process(false) # drive its clock by hand, so the save on exit matches the one we check
	for _i in 600:
		a.world.step()
	a._saved_players["Zed"] = {"germline": a.world.creatures[0].dna, "charges": 3}
	var tick := a.world.tick
	var count := a.world.creatures.size()
	var first: World.Creature = a.world.creatures[0]
	var snapshot := [first.id, first.dna, first.pos, first.gen, a.world.foods.size(), a.world.era, a.world.temp]
	ok = ok and a.save_world() == OK
	var path := ProjectSettings.globalize_path(a.save_path)
	print("saved %s: tick %d, %d creatures, %d bytes" % [path, tick, count, FileAccess.get_file_as_bytes(a.save_path).size()])
	a.shutdown()
	a.queue_free()
	await process_frame

	var b := Session.new()
	root.add_child(b)
	await process_frame
	ok = ok and b.start_dedicated(12345, port, "Save test", world_name) == OK
	var w := b.world
	var again: World.Creature = w.creatures[0] if w.creatures.size() > 0 else World.Creature.new()
	var restored := [again.id, again.dna, again.pos, again.gen, w.foods.size(), w.era, w.temp]
	print("loaded: seed %d, tick %d, %d creatures, first creature matches=%s, Zed remembered=%s" % [
		w.planet.seed, w.tick, w.creatures.size(), str(restored == snapshot), str(b._saved_players.has("Zed"))])
	ok = ok and w.planet.seed == 77 and w.tick == tick and w.creatures.size() == count and restored == snapshot
	ok = ok and b._saved_players.has("Zed") and b._saved_players["Zed"]["charges"] == 3
	for _i in 200: # and it keeps running
		w.step()
	ok = ok and w.tick == tick + 200 and w.creatures.size() > 0
	b.shutdown()
	b.save_path = "" # do not write it again on exit
	DirAccess.remove_absolute(path)
	print("PASS" if ok else "FAIL")
	quit(0 if ok else 1)
