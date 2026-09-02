class_name TestEconomySim
extends GdUnitTestSuite
## m4-b4 经济模拟防回归：三点判定的纯计算函数与生产读点解析钉。
## 行为断言由子进程跑 tools/economy_sim.py --self-test（同 fnv_reference.py /
## art_prune_guard.py 惯例：Python 侧参考实现随仓库走，零磁盘副作用、确定性输出）。
##
## 自测覆盖（Python 侧断言，本套件只钉退出码与标记）：
##   1) 生产读点正则解析（run_state.gd FLOOR_GEMS/KILL_GEMS/BOSS_FIRST_KILL_GEMS、
##      inter_floor_flow.gd VICTORY_FLOOR、成就 defs、talents/unlock_tasks/enemies）；
##   2) 过层蓝晶纯函数（含 VICTORY_FLOOR=3 胜利短路——第 3 层份 +200 不可得）；
##   3) 终局结算纯函数（死亡 50% / 试炼 75% / 胜利全额 / 试炼 ×1.5 向下取整）；
##   4) 带判定与到达时点内插；
##   5) 消费侧实值（天赋 24 条合计 10000、60%=6000；成就 24 条全激活合计 4350；
##      Boss 6 只；GDD 最便宜角色锚点 2000）；
##   6) 图鉴解锁率（含 clear_floor_x 分桶与 cur==goal 边界）；
##   7) 三档曲线端到端（单调、悲观≤目标≤乐观）与确定性（两次判定逐字节一致）。

const SIM_SCRIPT := "res://tools/economy_sim.py"


func _python_exe() -> String:
	# 优先托管隔离 venv（与美术管线同一运行时约定；系统 python 不装包）。
	var venv := "C:/Users/Administrator/.workbuddy/binaries/python/envs/default/Scripts/python.exe"
	if FileAccess.file_exists(venv) and OS.execute(venv, ["--version"], [], true) == 0:
		return venv
	for exe: String in ["python", "py"]:
		var out: Array = []
		if OS.execute(exe, ["--version"], out, true) == 0:
			return exe
	return ""


## 自测绿：退出码 0 + 标记行（fail-closed：解析失败/纯函数回归/不确定性均退出码 1）。
func test_self_test_green() -> void:
	var exe := _python_exe()
	assert_str(exe).is_not_empty()
	var args: PackedStringArray = [
		ProjectSettings.globalize_path(SIM_SCRIPT),
		"--self-test",
		"--repo-root", ProjectSettings.globalize_path("res://"),
	]
	var out: Array = []
	var code := OS.execute(exe, args, out, true)
	var stdout := "\n".join(PackedStringArray(out))
	assert_int(code).is_equal(0)
	assert_str(stdout).contains("ECONOMY-SIM-SELFTEST-OK")


## 判定主流程可跑通且确定性（同输入两次运行 stdout 逐字节一致；零随机模型契约）。
func test_judgement_run_deterministic() -> void:
	var exe := _python_exe()
	assert_str(exe).is_not_empty()
	var args: PackedStringArray = [
		ProjectSettings.globalize_path(SIM_SCRIPT),
		"--repo-root", ProjectSettings.globalize_path("res://"),
	]
	var out1: Array = []
	var code1 := OS.execute(exe, args, out1, true)
	var out2: Array = []
	var code2 := OS.execute(exe, args, out2, true)
	assert_int(code1).is_equal(0)
	assert_int(code2).is_equal(0)
	var s1 := "\n".join(PackedStringArray(out1))
	var s2 := "\n".join(PackedStringArray(out2))
	assert_str(s1).is_equal(s2)
	assert_str(s1).contains("ECONOMY-SIM-OK")


## --help 齐全（任务规格）：退出码 0 且列出全部参数（argparse 自动维护）。
func test_help_lists_all_options() -> void:
	var exe := _python_exe()
	assert_str(exe).is_not_empty()
	var args: PackedStringArray = [
		ProjectSettings.globalize_path(SIM_SCRIPT), "--help",
	]
	var out: Array = []
	var code := OS.execute(exe, args, out, true)
	var stdout := "\n".join(PackedStringArray(out))
	assert_int(code).is_equal(0)
	for flag: String in ["--repo-root", "--bot-json", "--out-md", "--out-json", "--self-test"]:
		assert_str(stdout).contains(flag)
