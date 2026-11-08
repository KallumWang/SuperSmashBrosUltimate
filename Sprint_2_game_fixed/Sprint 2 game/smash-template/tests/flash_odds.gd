extends SceneTree
## Checks every victory flash is wired in and shows how often each is picked.
## Run:  godot --headless --path . -s tests/flash_odds.gd
const TRIALS := 12000

func _initialize() -> void:
	await process_frame
	var VF = load("res://scripts/victory_flash.gd")
	var src: String = FileAccess.get_file_as_string("res://scripts/victory_flash.gd")
	var ok := true
	for kind in VF.KINDS:
		var wired: bool = src.contains('"%s":\n\t\t\tawait' % kind) or kind == "nah"
		var has_fn: bool = src.contains("func _%s(" % ("nah_id_win" if kind == "nah" else ("slot_machine" if kind == "slot" else kind)))
		print("%-7s needs %d fighters | in play(): %s | function exists: %s" % [kind, VF.KINDS[kind], wired, has_fn])
		ok = ok and wired and has_fn
	for count in [2, 3, 4]:
		var kinds: Array = VF.eligible_kinds(count)
		var tally := {}
		for k in kinds: tally[k] = 0
		for i in TRIALS:
			tally[VF.kind_for(count, randi())] += 1
		var line := "%d fighters (%d flashes): " % [count, kinds.size()]
		var expect: float = 1.0 / kinds.size()
		for k in kinds:
			var share: float = float(tally[k]) / TRIALS
			line += "%s %.1f%%  " % [k, share * 100.0]
			if absf(share - expect) > 0.02: ok = false
		print(line, "(fair = %.1f%% each)" % (expect * 100.0))
	# Online: the pick comes from a name hash, so check it spreads across many different groups.
	var tally4 := {}
	for i in 4000:
		var k: String = VF.kind_for(4, absi(hash("group%d|Zed|Amy|Bo" % i)))
		tally4[k] = int(tally4.get(k, 0)) + 1
	print("online (hash of names), 4 fighters over 4000 groups: ", tally4)
	for k in VF.eligible_kinds(4):
		if not tally4.has(k): ok = false
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
