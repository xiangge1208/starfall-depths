extends SceneTree
## M4-C1 敌人派味特技行为键独立校验（无头，fail-closed）：
##   godot --headless --path . --script res://tools/validate_enemies.gd
## 对 data/enemies.json 全行执行 SignatureSchema（基础键镜像 + 派味特技键类型/语义域
## + 跨行引用）校验：全部通过打印 "N/52 PASS" 退出 0；任一错误列出明细退出 1。
## 与 tests/unit/test_signature_moves.gd 的 schema 断言共用同一校验逻辑单点。
## （--script 模式 autoload 不可解析，故校验器为无 autoload 纯静态——见 signature_schema.gd 头注。）

const ENEMIES_PATH := "res://data/enemies.json"


func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ENEMIES_PATH))
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		print("ENEMIES SCHEMA: bad json: %s" % ENEMIES_PATH)
		quit(1)
		return
	var table: Dictionary = parsed
	var errors: Array[String] = SignatureSchema.validate_table(table)
	if errors.is_empty():
		print("ENEMIES SCHEMA: %d/%d PASS" % [table.size(), table.size()])
		quit(0)
		return
	print("ENEMIES SCHEMA: %d error(s):" % errors.size())
	for e: String in errors:
		print("  - " + e)
	quit(1)
