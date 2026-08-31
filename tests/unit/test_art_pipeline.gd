class_name TestArtPipeline
extends GdUnitTestSuite
## m2-t21 美术管线防回归：M2 批次导入失败时严禁执行陈旧清理（prune）。
## 旧实现 `except ImportError: pass` 后照常 _prune_stale()，会把 M1 SPEC 之外的
## 整棵 M2 子树（武器/敌人帧表/增益图标等数百文件）当"陈旧残留"静默删除。
## 行为断言由子进程跑 tests/unit/art_prune_guard.py（同 fnv_reference.py 惯例：
## Python 侧参考实现，期望随仓库走），全部 stub 生成器、零磁盘副作用。

const GUARD_SNIPPET := "res://tests/unit/art_prune_guard.py"

func _python_exe() -> String:
	for exe: String in ["python", "py"]:
		var out: Array = []
		if OS.execute(exe, ["--version"], out, true) == 0:
			return exe
	return ""

func test_m2_import_failure_hard_fails_and_skips_prune() -> void:
	var exe := _python_exe()
	assert_str(exe).is_not_empty()  # 美术管线运行时（Pillow）必须可用
	var args: PackedStringArray = [
		ProjectSettings.globalize_path(GUARD_SNIPPET),
		ProjectSettings.globalize_path("res://tools"),
	]
	var out: Array = []
	var code := OS.execute(exe, args, out, true)
	var stdout := "\n".join(PackedStringArray(out))
	assert_int(code).is_equal(0)
	assert_str(stdout).contains("PRUNE-GATE-OK")
