class_name TestVersionConsistency
extends GdUnitTestSuite
## m4-k1 ①: 版本读点单源 + export_presets.cfg 三处一致性强测试。
##
## 单源方案（裁定：ProjectSettings 定制键，不加 autoload）：
##   - `application/config/version`（semver 字符串）——Godot 内建高级键，
##     `ProjectSettings.get_setting` 全局可读、无需节点依赖、M4「无新 autoload」约束下
##     最小机制面；
##   - `application/config/version_code`（int，Android versionCode 交付基线）——定制键，
##     同机制读取。
## 强一致口径（X-C m3-export-final §1 版本策略表「三处一致」样例 1.0.0 / 100 / 1.0.0.0）：
##   单源 → preset（正向：由单源值构造期望行，断言 preset 文本恰一次出现）与
##   preset → 单源（反向：从 preset 文本抽取值，断言与单源相等）双向断言；
##   Windows 四段版 = semver + ".0"（X-C 派生规则）；code 段位映射遵循 X-C 递增规则
##   （百位=主版本、十位=次版本段）。设置面板底部版本行（settings_panel.gd 构建的
##   VersionLabel）文本 `v1.0.0 (100)` 钉值——未来升版四处必须同卡同动。

const PRESET_PATH := "res://export_presets.cfg"
const PANEL_SCENE := "res://ui/settings_panel.tscn"
const KEY_VERSION := "application/config/version"
const KEY_CODE := "application/config/version_code"

## X-C 钉值（2026-09-02 交付基线）：升版时本行与 preset 三处 + 单源键同卡同改。
const PIN_LINE := "v1.0.0 (100)"

var _preset_text := ""


func before_test() -> void:
	_preset_text = FileAccess.get_file_as_string(PRESET_PATH)
	assert_int(_preset_text.length()).is_greater(0)


# ---------------------------------------------------------------- 单源键在位

func test_single_source_keys_exist_in_project_settings() -> void:
	var ver := str(ProjectSettings.get_setting(KEY_VERSION, ""))
	assert_str(ver).is_equal("1.0.0")
	var code := int(ProjectSettings.get_setting(KEY_CODE, -1))
	assert_int(code).is_equal(100)
	# 单源版本号必须是严格 semver 三段（防 "1.0" / "v1.0.0" 之类漂移进单源）
	var re := RegEx.new()
	re.compile("^\\d+\\.\\d+\\.\\d+$")
	assert_bool(re.search(ver) != null).is_true()


# ---------------------------------------------------------------- 正向：单源 → preset

func test_preset_contains_single_source_derived_lines_exactly_once() -> void:
	var ver := str(ProjectSettings.get_setting(KEY_VERSION, ""))
	var code := int(ProjectSettings.get_setting(KEY_CODE, -1))
	# 由单源值派生 Windows 四段版（X-C 规则：semver + ".0"）
	var win_ver := "%s.0" % ver
	# 正向期望行：每行在 preset 文本中恰出现一次（count==1 防重复键漂移）
	for line: String in [
		'version/name="%s"' % ver,
		"version/code=%d" % code,
		'application/file_version="%s"' % win_ver,
		'application/product_version="%s"' % win_ver,
	]:
		assert_int(_preset_text.count(line)).is_equal(1)


# ---------------------------------------------------------------- 反向：preset → 单源

func test_preset_values_extracted_match_single_source() -> void:
	var ver := str(ProjectSettings.get_setting(KEY_VERSION, ""))
	var code := int(ProjectSettings.get_setting(KEY_CODE, -1))
	assert_str(_preset_value("version/name")).is_equal(ver)
	assert_int(int(_preset_value("version/code"))).is_equal(code)
	# Windows 双字段恒一致且 = semver + ".0"（反向独立抽取比对）
	var file_ver := _preset_value("application/file_version")
	var product_ver := _preset_value("application/product_version")
	assert_str(file_ver).is_equal("%s.0" % ver)
	assert_str(product_ver).is_equal(file_ver)


func test_version_code_digit_mapping_follows_xc_rule() -> void:
	# X-C 递增规则 2：code 百位=主版本、十位=次版本段（100 = 1.0.0；1.1.x → ≥110）
	var ver := str(ProjectSettings.get_setting(KEY_VERSION, ""))
	var code := int(ProjectSettings.get_setting(KEY_CODE, -1))
	var parts := ver.split(".")
	assert_int(parts.size()).is_equal(3)
	assert_int(code / 100).is_equal(int(parts[0]))
	assert_int((code / 10) % 10).is_equal(int(parts[1]))


## 从 preset 文本抽取 `key=value`（首处）；找不到返回空串（断言侧判失败）。
## (?m)：逐行锚定（preset 为多行文本）；\s*$ 容纳行尾 \r（CRLF 检出）。
func _preset_value(key: String) -> String:
	var re := RegEx.new()
	re.compile("(?m)^%s=(\"?[^\"]*\"?)\\s*$" % key.replace("/", "\\/"))
	var m := re.search(_preset_text)
	if m == null:
		return ""
	return m.get_string(1).trim_prefix("\"").trim_suffix("\"")


# ---------------------------------------------------------------- 面板读点

## 设置面板实例（host/audio 注入替身，版本读点不依赖二者；_ready 构建版本行）。
func _panel() -> Node:
	var panel: Node = auto_free(load(PANEL_SCENE).instantiate())
	panel.set("settings_host", null)
	panel.set("audio", null)
	add_child(panel)
	return panel


func test_settings_panel_bottom_line_shows_pinned_version() -> void:
	var panel_node := _panel()
	var rows := panel_node.get_node("Center/Panel/Margin/Rows") as Node
	# 底部落点：VersionLabel 必须是 Rows 最后一个子节点（「底部一行」钉位）
	var last := rows.get_child(rows.get_child_count() - 1)
	assert_str(last.name).is_equal("VersionLabel")
	# 文本钉值 + 与单源派生值一致（读点必须来自 ProjectSettings 单源，非第三处硬编码）
	var label := (last as Label)
	assert_str(label.text).is_equal(PIN_LINE)
	assert_str(label.text).is_equal(panel_node.call("_version_text"))
	var expected := "v%s (%d)" % [
		str(ProjectSettings.get_setting(KEY_VERSION, "")),
		int(ProjectSettings.get_setting(KEY_CODE, -1)),
	]
	assert_str(label.text).is_equal(expected)
	# 版本行净增高度不得把面板推出 270 视口（独立路径；暂停菜单注入「按 键」行的
	# 最坏路径由 test_pause_menu 钉死）
	await get_tree().process_frame
	await get_tree().process_frame
	var panel := panel_node.get_node("Center/Panel") as Control
	var vp := panel_node.get_viewport().get_visible_rect().size
	assert_bool(panel.position.y + panel.size.y <= vp.y + 0.5).is_true()
