extends GutTest
## Каждый способ обработки — хотя бы один тест.

var H := TestHelpers
var pl: Planet

func before_each():
	pl = H.planet()

func _ctx(extra: Dictionary = {}) -> Dictionary:
	var c := {"db": pl.db, "pressure": 1.0, "compress_bonus": 0.0, "target_t": 900.0, "ambient": 15.0, "reagent": null, "filter_tag": ""}
	c.merge(extra, true)
	return c

func _out_tags(res: Dictionary, idx: int = 0) -> Array:
	for o in res.outs:
		if o[1] == idx:
			return o[0].substance.tags
	return []

func test_crusher_makes_powder():
	var s := H.sub(pl, ["brittle", "crystalline"])
	var r := Processor.run("crusher", Portion.new(s, 2.0), _ctx())
	assert_true("porous" in _out_tags(r))
	assert_false("crystalline" in _out_tags(r))

func test_crusher_metal_powder_is_pyrophoric():
	var s := H.sub(pl, ["metallic", "dense"])
	var r := Processor.run("crusher", Portion.new(s, 2.0), _ctx())
	assert_true("pyrophoric" in _out_tags(r))

func test_crusher_ignores_elastic():
	var s := H.sub(pl, ["elastic", "organic"])
	var r := Processor.run("crusher", Portion.new(s, 2.0), _ctx())
	assert_eq(_out_tags(r), s.tags)

func test_furnace_burns_flammable_into_gas():
	var s := H.sub(pl, ["flammable", "dense"])
	var r := Processor.run("furnace", Portion.new(s, 2.0), _ctx())
	assert_gt(r.gas, 0.5)
	assert_false("flammable" in _out_tags(r))
	assert_almost_eq(r.outs[0][0].temp, 900.0, 0.1)

func test_furnace_thermo_inverted_freezes():
	var s := H.sub(pl, ["thermo_inverted", "dense"])
	var r := Processor.run("furnace", Portion.new(s, 2.0, 15.0), _ctx())
	assert_lt(r.outs[0][0].temp, 15.0)
	assert_true("phase_inverted" in _out_tags(r))

func test_condenser_quench_makes_brittle():
	var s := H.sub(pl, ["metallic"])
	var hot := Portion.new(s, 2.0, s.melt + 50.0)
	var r := Processor.run("condenser", hot, _ctx())
	assert_eq(r.outs[0][0].phase(), Substance.Phase.SOLID)
	assert_true("brittle" in _out_tags(r))

func test_compressor_densifies_and_overpressure():
	var s := H.sub(pl, ["porous", "metallic"])
	var r := Processor.run("compressor", Portion.new(s, 2.0), _ctx({"pressure": 4.0}))
	assert_true("dense" in _out_tags(r))
	var d := H.sub(pl, ["dense", "metallic"])
	var r2 := Processor.run("compressor", Portion.new(d, 2.0), _ctx({"pressure": 9.5}))
	assert_true("radioactive" in _out_tags(r2))
	assert_true("crystalline" in _out_tags(r2))

func test_decompressor_splits_volatile():
	var s := H.sub(pl, ["organic", "toxic"])
	var r := Processor.run("decompressor", Portion.new(s, 2.0), _ctx())
	assert_true("volatile" in _out_tags(r, 1))
	assert_false("volatile" in _out_tags(r, 0))

func test_treater_applies_reagent():
	var target := H.sub(pl, ["alkaline", "porous"])
	var acid := H.sub(pl, ["acidic", "crystalline"])
	var rg := Portion.new(acid, 5.0)
	var r := Processor.run("treater", Portion.new(target, 2.0), _ctx({"reagent": rg}))
	assert_true("hygroscopic" in _out_tags(r))
	assert_false("acidic" in _out_tags(r))
	assert_true("acidic>alkaline" in r.keys)
	assert_gt(r.reagent_used, 0.0)

func test_treater_waits_for_reagent():
	var target := H.sub(pl, ["flammable", "organic"])
	var ox := H.sub(pl, ["oxidizer"])
	var r := Processor.run("treater", Portion.new(target, 10.0), _ctx({"reagent": Portion.new(ox, 0.1)}))
	assert_true(r.get("wait", false))

func test_distiller_fractions():
	var s := H.sub(pl, ["organic", "toxic"])
	var r := Processor.run("distiller", Portion.new(s, 2.0), _ctx())
	assert_true("volatile" in _out_tags(r, 1))
	assert_eq(r.outs.size(), 2)

func test_centrifuge_fractions():
	var s := H.sub(pl, ["organic"])
	var r := Processor.run("centrifuge", Portion.new(s, 2.0), _ctx())
	assert_true("dense" in _out_tags(r, 0))
	assert_true("porous" in _out_tags(r, 1))

func test_magnet_sep_routes():
	var m := H.sub(pl, ["magnetic"])
	var n := H.sub(pl, ["organic"])
	assert_eq(Processor.run("magnet_sep", Portion.new(m, 1.0), _ctx()).outs[0][1], 0)
	assert_eq(Processor.run("magnet_sep", Portion.new(n, 1.0), _ctx()).outs[0][1], 1)

func test_filter_routes_by_tag():
	var a := H.sub(pl, ["dense", "metallic"])
	var b := H.sub(pl, ["porous"])
	assert_eq(Processor.run("filter", Portion.new(a, 1.0), _ctx({"filter_tag": "dense"})).outs[0][1], 0)
	assert_eq(Processor.run("filter", Portion.new(b, 1.0), _ctx({"filter_tag": "dense"})).outs[0][1], 1)

func test_electrolyzer_needs_liquid():
	var s := H.sub(pl, ["conductive", "metallic"])
	var cold := Processor.run("electrolyzer", Portion.new(s, 2.0, 15.0), _ctx())
	assert_ne(cold.note, "")
	var hot := Processor.run("electrolyzer", Portion.new(s, 2.0, s.melt + 10.0), _ctx())
	assert_true("alkaline" in _out_tags(hot, 0))
	assert_true("oxidizer" in _out_tags(hot, 1))

func test_sinter_powder():
	var s := H.sub(pl, ["porous", "metallic"])
	var r := Processor.run("sinter", Portion.new(s, 2.0), _ctx())
	assert_true("dense" in _out_tags(r))
	assert_true("crystalline" in _out_tags(r))
	assert_true("magnetic" in _out_tags(r))

func test_irradiator_luminous_and_antigravity():
	var s := H.sub(pl, ["magnetic", "toxic"])
	var r := Processor.run("irradiator", Portion.new(s, 2.0), _ctx())
	assert_true("luminous" in _out_tags(r))
	assert_true("antigravitic" in _out_tags(r))
	assert_false("toxic" in _out_tags(r))

func test_loom_fibers():
	var s := H.sub(pl, ["fibrous", "alkaline"])
	var r := Processor.run("loom", Portion.new(s, 2.0), _ctx())
	assert_true("elastic" in _out_tags(r))
	assert_true("insulating" in _out_tags(r))

func test_every_process_has_a_building():
	var have := {}
	for k in Buildings.KINDS:
		if Buildings.KINDS[k].has("process"):
			have[Buildings.KINDS[k].process] = true
	for pid in Processes.PROCESSES:
		assert_true(have.has(pid), pid)
