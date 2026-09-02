class_name TestArtPipeline
extends GdUnitTestSuite
## m2-t21 美术管线防回归：M2 批次导入失败时严禁执行陈旧清理（prune）。
## 旧实现 `except ImportError: pass` 后照常 _prune_stale()，会把 M1 SPEC 之外的
## 整棵 M2 子树（武器/敌人帧表/增益图标等数百文件）当"陈旧残留"静默删除。
## 行为断言由子进程跑 tests/unit/art_prune_guard.py（同 fnv_reference.py 惯例：
## Python 侧参考实现，期望随仓库走），全部 stub 生成器、零磁盘副作用。
##
## m4-a2 追加两防：
## 1) prune keep-set：fx/trials/icon 子树与 *.import sidecar 豁免清理（P0 前置修复），
##    dry-run 清单断言三子树零删除（tests/unit/test_art_pipeline_prune_keepset.py）；
## 2) 美术 QA 三重校验（对比度/剪影/接缝，tools/art_qa_check.py）全库绿
##    （存量超阈按 tools/art_qa_baseline.json 棘轮放行，新增/恶化 fail-closed）。

const GUARD_SNIPPET := "res://tests/unit/art_prune_guard.py"
const KEEPSET_SNIPPET := "res://tests/unit/test_art_pipeline_prune_keepset.py"
const QA_SCRIPT := "res://tools/art_qa_check.py"

func _python_exe() -> String:
	# 优先托管隔离 venv（已装 Pillow；系统 python 不装包，避免污染环境）。
	var venv := "C:/Users/Administrator/.workbuddy/binaries/python/envs/default/Scripts/python.exe"
	if FileAccess.file_exists(venv) and OS.execute(venv, ["--version"], [], true) == 0:
		return venv
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

## m4-a2 P0 回归：dry-run prune 清单断言 fx/trials/icon 三子树与 *.import 零删除
## （真实库 worst-case SPEC 为空 + 合成目录端到端；全程零真实磁盘副作用）。
func test_prune_keepset_foreign_subtrees_zero_deletion() -> void:
	var exe := _python_exe()
	assert_str(exe).is_not_empty()
	var args: PackedStringArray = [
		ProjectSettings.globalize_path(KEEPSET_SNIPPET),
		ProjectSettings.globalize_path("res://tools"),
	]
	var out: Array = []
	var code := OS.execute(exe, args, out, true)
	var stdout := "\n".join(PackedStringArray(out))
	assert_int(code).is_equal(0)
	assert_str(stdout).contains("KEEPSET-GUARD-OK")

## m4-a2 主体：美术 QA 三重校验全库（默认棘轮口径）必须绿——
## 存量超阈按基线放行（清单 tools/art_qa_baseline.json 交编排者裁定），
## 新增/恶化 fail-closed（退出码 1）。
func test_art_qa_triple_check_full_library_green() -> void:
	var exe := _python_exe()
	assert_str(exe).is_not_empty()
	var args: PackedStringArray = [ProjectSettings.globalize_path(QA_SCRIPT)]
	var out: Array = []
	var code := OS.execute(exe, args, out, true)
	var stdout := "\n".join(PackedStringArray(out))
	assert_int(code).is_equal(0)
	assert_str(stdout).contains("ART-QA-CHECK-OK")

## m4-a2 fail-closed 自证：资产根缺失等结构错误必须退出码非 0（2），
## 不允许静默通过。
func test_art_qa_check_fails_closed_on_missing_root() -> void:
	var exe := _python_exe()
	assert_str(exe).is_not_empty()
	var args: PackedStringArray = [
		ProjectSettings.globalize_path(QA_SCRIPT),
		"--root", "res://art/generated/__definitely_missing__",
	]
	var out: Array = []
	var code := OS.execute(exe, args, out, true)
	assert_int(code).is_equal(2)
