class_name TestSaveSeal
extends RefCounted
## save_headless 共享档密闭器（m2-t33，裁定㉔）：池/档敏感套件的逐用例整体隔离。
##
## 背景（裁定㉒/㉔）：无头进程共享 user://save_headless.json——场景级测试经真解锁链
## 持久化（图鉴解锁武器回池 + CodexSystem 计数器快照 + 首杀标记 + 成就/蓝晶入账）。
## 磁盘残留跨 run 存活：下次进程启动 CodexSystem._ready 按档回池、恢复计数，令
## 「纯净引导」假设的用例假败（实证 test_black_stock_prefers_epic_then_rare；
## a87605f / df9691a 为逐用例密封先例）。
##
## 本密闭器把「共享档 + 运行时掉落池 + 图鉴计数器」整体换入隔离实例：
##   seal(tag)    → 存档换临时空档（磁盘残留无关）、GameDB.weapons 换 M2-T6 纯净池
##                  （locked 排除）、CodexSystem 计数器归零；返回还原令牌。
##   restore(tok) → 三者全数还原（引用级），隔离档删除——磁盘真档零写入。
## 用法：池/档敏感套件 before_test 调 seal、after_test 调 restore（套内顺序无关 +
## 跨 run 残留无关）。不触 TestX 套件自有的 stub/快照机制（两者叠加，restore 在后）。

static func seal(tag: String) -> Dictionary:
	var tmp := "user://seal_%s_%d.json" % [tag, absi(randi())]
	var token := {
		"save_path": SaveSystem.save_path,
		"data": SaveSystem.data.duplicate(true),
		"weapons": GameDB.weapons,
		"counters": CodexSystem.counters.duplicate(true),
		"tmp": tmp,
	}
	DirAccess.remove_absolute(tmp)
	DirAccess.remove_absolute(tmp + ".tmp")
	SaveSystem.save_path = tmp
	SaveSystem.load_save()                       # 全新默认档（与磁盘残留无关）
	CodexSystem._reset_counters()
	CodexSystem._restore_counters()              # 隔离空档 → 归零基线
	var pristine := {}
	for id: String in GameDB.weapons_all:
		if not bool((GameDB.weapons_all[id] as Dictionary).get("locked", false)):
			pristine[id] = GameDB.weapons_all[id]
	GameDB.weapons = pristine                    # M2-T6 纯净池（locked 已排除）
	return token


static func restore(token: Dictionary) -> void:
	GameDB.weapons = token["weapons"]
	CodexSystem.counters = token["counters"]
	SaveSystem.save_path = String(token["save_path"])
	SaveSystem.data = token["data"]
	DirAccess.remove_absolute(String(token["tmp"]))
	DirAccess.remove_absolute(String(token["tmp"]) + ".tmp")
