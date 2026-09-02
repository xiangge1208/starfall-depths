class_name TestLogoVariants
extends GdUnitTestSuite
## m4-k1 ③: LOGO 方向变体（gen_icon.py）管线锁。
## 口径：gen_icon.py 单脚本内建 QA（尺寸/扩展调色板封口/变体确定性/预览页尺寸），
## 本套件做进程级防回归——
##   1) 脚本运行退出码 0 + LOGO-VARIANTS-OK 标记（QA 全过的自证）；
##   2) 跨进程确定性：连跑两次，三方向变体 + 预览页 SHA256 逐文件一致；
##   3) canonical 五产物零漂移：变体生成不得触碰已入导出 preset 的正式图标
##      （X-C 口径——变体仅供选型，替换 icon.svg/config 是用户定稿后的跟进卡）。
## Python 运行时同 test_art_pipeline.gd：优先托管隔离 venv（Pillow）。

const GEN_ICON := "res://tools/gen_icon.py"
const ICON_DIR := "res://art/generated/icon"
## 变体产物 + canonical 五产物（防漂移名单）。
const VARIANT_FILES: Array[String] = [
	"logo_variant_a_gate_256.png",
	"logo_variant_b_crystal_256.png",
	"logo_variant_c_knight_256.png",
	"logo_variants_preview.png",
]
const CANONICAL_FILES: Array[String] = [
	"icon_256.png", "icon_192.png",
	"adaptive_background_432.png", "adaptive_foreground_432.png",
	"adaptive_monochrome_432.png",
]


func _python_exe() -> String:
	var venv := "C:/Users/Administrator/.workbuddy/binaries/python/envs/default/Scripts/python.exe"
	if FileAccess.file_exists(venv) and OS.execute(venv, ["--version"], [], true) == 0:
		return venv
	for exe: String in ["python", "py"]:
		var out: Array = []
		if OS.execute(exe, ["--version"], out, true) == 0:
			return exe
	return ""


func _run_gen_icon() -> String:
	var exe := _python_exe()
	assert_str(exe).is_not_empty()  # 美术管线运行时（Pillow）必须可用
	var out: Array = []
	var code := OS.execute(exe, [ProjectSettings.globalize_path(GEN_ICON)], out, true)
	assert_int(code).is_equal(0)
	return "\n".join(PackedStringArray(out))


func _sha256(file_name: String) -> String:
	var bytes := FileAccess.get_file_as_bytes("%s/%s" % [ICON_DIR, file_name])
	assert_int(bytes.size()).is_greater(0)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


func _hash_map(files: Array[String]) -> Dictionary:
	var map := {}
	for f in files:
		map[f] = _sha256(f)
	return map


func test_gen_icon_runs_green_with_variants_marker() -> void:
	var stdout := _run_gen_icon()
	assert_str(stdout).contains("LOGO-VARIANTS-OK")
	assert_str(stdout).contains("VARIANT QA PASS")
	assert_str(stdout).contains("logo_variants_preview.png")


func test_variants_deterministic_across_processes_and_canonical_undrifted() -> void:
	_run_gen_icon()   # 第一次运行（工作树可能已是产物，哈希为基线）
	var variants_before := _hash_map(VARIANT_FILES)
	var canonical_before := _hash_map(CANONICAL_FILES)
	_run_gen_icon()   # 第二次运行（全新进程）
	# 跨进程确定性：变体产物逐文件字节一致
	for f in VARIANT_FILES:
		assert_str(_sha256(f)).is_equal(variants_before[f])
	# canonical 零漂移：变体管线不改变正式图标
	for f in CANONICAL_FILES:
		assert_str(_sha256(f)).is_equal(canonical_before[f])


func test_variant_preview_page_contains_three_panels() -> void:
	# 预览页横向并排三面板：宽 = 3x256 + 边距/间隔（脚本常量 24x4 + 24x2 = 864）
	var img := Image.load_from_file(ProjectSettings.globalize_path(
		"%s/logo_variants_preview.png" % ICON_DIR))
	assert_that(img).is_not_null()
	assert_int(img.get_width()).is_equal(864)
	assert_int(img.get_height()).is_greater_equal(320)
