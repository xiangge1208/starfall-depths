extends SceneTree
## M1-T7 地牢装配 1000 种子校验（无头）：
##   godot --headless --path . --script res://tools/validate_dungeon.gd
## seed_i = RngSvc.stable_hash(i, 777)（经 DungeonBuilder.seed_at 包装——--script 模式下
## autoload 标识符编译期不可解析，见 dungeon_builder.gd 头注）。
## 逐种子 build + validate_build：全部通过打印 "N/1000 PASS" 退出 0；否则列出失败
## 种子序号、错误类别统计与样本，退出 1。

const SEED_COUNT := 1000


func _init() -> void:
	var pass_n := 0
	var failed: Array[int] = []
	var categories := {}
	var samples := {}
	for i in SEED_COUNT:
		var seed := DungeonBuilder.seed_at(i)
		var build := DungeonBuilder.build(seed, 1)
		var errs := DungeonBuilder.validate_build(build)
		if errs.is_empty():
			pass_n += 1
			continue
		failed.append(i)
		if samples.size() < 5:
			samples[i] = errs
		for e in errs:
			var tag := e.substr(0, maxi(e.find(":"), 0))
			categories[tag] = int(categories.get(tag, 0)) + 1
	print("%d/%d PASS" % [pass_n, SEED_COUNT])
	DungeonBuilder.cleanup_fallbacks()
	if failed.is_empty():
		quit(0)
		return
	print("failing seeds (%d): %s" % [failed.size(), str(failed)])
	print("failure categories: ", categories)
	for i in samples:
		print("sample seed #%d: %s" % [i, str(samples[i])])
	DungeonBuilder.cleanup_fallbacks()
	quit(1)
