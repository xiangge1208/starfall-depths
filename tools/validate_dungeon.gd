extends SceneTree
## M1-T7 地牢装配 1000 种子校验（无头）：
##   godot --headless --path . --script res://tools/validate_dungeon.gd
## seed_i = RngSvc.stable_hash(i, 777)（经 DungeonBuilder.seed_at 包装——--script 模式下
## autoload 标识符编译期不可解析，见 dungeon_builder.gd 头注）。
## 逐种子 build + validate_build：全部通过打印 "N/1000 PASS" 退出 0；否则列出失败
## 种子序号、错误类别统计与样本，退出 1。
## m2-t34：可参数化 `--seeds=N --floors=1,2,3`（无参 = M1 契约 1000×floor1 不变；
## 门禁口径 3000 种子 × 3 生态 = 每层各验一遍，A2/A3 池自 T26 起在库）。

const DEFAULT_SEED_COUNT := 1000
const DEFAULT_FLOORS := [1]


func _init() -> void:
	var seed_count := DEFAULT_SEED_COUNT
	var floors: Array[int] = []
	for f in DEFAULT_FLOORS:
		floors.append(f)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			seed_count = int(arg.substr(8))
		elif arg.begins_with("--floors="):
			floors = []
			for part in arg.substr(9).split(","):
				var f := int(part)
				if f >= 1 and not floors.has(f):
					floors.append(f)
	var total := seed_count * floors.size()
	var pass_n := 0
	var failed: Array[String] = []
	var categories := {}
	var samples := {}
	for i in seed_count:
		var seed := DungeonBuilder.seed_at(i)
		for fl in floors:
			var build := DungeonBuilder.build(seed, fl)
			var errs := DungeonBuilder.validate_build(build)
			if errs.is_empty():
				pass_n += 1
				continue
			var key := "seed#%d/floor%d" % [i, fl]
			failed.append(key)
			if samples.size() < 5:
				samples[key] = errs
			for e in errs:
				var tag := e.substr(0, maxi(e.find(":"), 0))
				categories[tag] = int(categories.get(tag, 0)) + 1
	print("%d/%d PASS (seeds=%d floors=%s)" % [pass_n, total, seed_count, str(floors)])
	DungeonBuilder.cleanup_fallbacks()
	if failed.is_empty():
		quit(0)
		return
	print("failing builds (%d): %s" % [failed.size(), ", ".join(failed.slice(0, 20))])
	print("failure categories: ", categories)
	for k in samples:
		print("sample %s: %s" % [k, str(samples[k])])
	DungeonBuilder.cleanup_fallbacks()
	quit(1)
