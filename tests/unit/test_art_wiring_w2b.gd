class_name TestArtWiringW2b
extends GdUnitTestSuite
## m4p-w2b 可玩性收口 W2-b 卡（「图在盘、代码零引用」簇收尾）的接线回归——
## 1) Buff 图标：ArtLookup.BUFF_TEXTURES（data/buffs.json 行 id → ui/buffs/<id>.png，
##    已知空帧 5 张不接线）→ HUD buff 芯片行首小图标 + buff_pick 三选一卡顶图标，
##    空帧/表外 id 缺行回落既有纯文字 chip/卡片；
## 2) 饮料图标：ui/drinks/<id>.png 按 data/drinks.json 行 id 约定寻址（8/8 全名录）
##    → drink_machine 卡顶图标；
## 3) 天赋节点两态：ui/talents/node_filled.png（已购）/ node_empty.png（未购）
##    → talents 节点 Button.icon；
## 4) 表契约：BUFF_TEXTURES 全路径存在断言 + 空帧 tripwire（补图即提醒接线）。


## 已知空帧（全透明 72 字节占位）——对空帧不接线（显示空白比文字 chip 更糟）；
## 美术补图后：把行加回 ArtLookup.BUFF_TEXTURES 并把 id 移出本表。
const EMPTY_FRAMES: Array[String] = [
	"avenger", "energy_siphon", "glutton", "resonance_amp", "thorn_armor",
]
## 盘上另有 5 张非行 id 资产（按效果键命名的历史占位），GameDB.buffs 无行可寻址，
## 永不入 id 寻址表（test_buff_icon_table_covers_wired_roster_exactly 钉住）。
const NON_ROW_ASSETS: Array[String] = [
	"big_eater", "energy_leech", "resonance_amplify", "thorns", "vengeance",
]


# ---------------------------------------------------------------- 1) 表契约

func test_buff_texture_table_all_exist_on_disk() -> void:
	# 31 = data/buffs.json 36 行 − 已知空帧 5 张（表注释同口径）
	assert_int(ArtLookup.BUFF_TEXTURES.size()).is_equal(31)
	for id: String in ArtLookup.BUFF_TEXTURES:
		var path := ArtLookup.buff_texture_path(id)
		assert_str(path).is_not_empty()
		assert_bool(path.begins_with(ArtLookup.BASE)).is_true()
		assert_bool(FileAccess.file_exists(path)).is_true()
	assert_str(ArtLookup.buff_texture_path("no_such_buff")).is_empty()
	assert_str(ArtLookup.buff_texture_path("")).is_empty()


func test_buff_icon_table_keys_all_have_game_rows() -> void:
	# id 寻址表键 ⊆ GameDB.buffs 行 id（效果键命名的历史占位资产不可混入）
	for id: String in ArtLookup.BUFF_TEXTURES:
		assert_bool(GameDB.buffs.has(id)).override_failure_message(
			"BUFF_TEXTURES 键无行: " + id).is_true()


func test_buff_icon_table_covers_wired_roster_exactly() -> void:
	# 全量名册精确覆盖：行 id − 空帧 5 张 = 表全集（新增 buff 行缺图 → 此处报警）
	var expect: Dictionary = {}
	for id: String in GameDB.buffs:
		expect[id] = true
	for id: String in EMPTY_FRAMES + NON_ROW_ASSETS:
		expect.erase(id)
	assert_int(ArtLookup.BUFF_TEXTURES.size()).is_equal(expect.size())
	for id: String in expect:
		assert_bool(ArtLookup.BUFF_TEXTURES.has(id)).override_failure_message(
			"行 id 未接图标亦未登记空帧: " + id).is_true()


func test_known_empty_frames_stay_unwired_and_transparent() -> void:
	# tripwire 双向钉住：未补图必须保持缺行（回落文字 chip）；一旦盘上出现实图
	# （used_rect 非空）即失败，提醒把行加回 BUFF_TEXTURES。
	for id: String in EMPTY_FRAMES:
		assert_bool(ArtLookup.BUFF_TEXTURES.has(id)).override_failure_message(
			"空帧已接线（应先补图再接）: " + id).is_false()
		assert_str(ArtLookup.buff_texture_path(id)).is_empty()
		var tex := load(ArtLookup.BASE + "ui/buffs/%s.png" % id) as Texture2D
		assert_object(tex).is_not_null()
		var img := tex.get_image()
		assert_int(img.get_used_rect().get_area()) \
			.override_failure_message("空帧已有实图，请接线: " + id).is_equal(0)


func test_drink_icon_paths_cover_full_roster() -> void:
	# 8/8 全名录按行 id 约定寻址且盘上齐（映射齐度钉死，不齐此处先红）
	assert_int(GameDB.drinks.size()).is_equal(8)
	for id: String in GameDB.drinks:
		var path := ArtLookup.drink_texture_path(id)
		assert_str(path).is_equal(ArtLookup.BASE + "ui/drinks/%s.png" % id)
		assert_bool(FileAccess.file_exists(path)).override_failure_message(path).is_true()
	assert_str(ArtLookup.drink_texture_path("")).is_empty()


func test_talent_node_icons_registered_in_ui_table() -> void:
	for key: String in ["talent_node_filled", "talent_node_empty"]:
		var path := ArtLookup.ui_texture_path(key)
		assert_str(path).is_not_empty()
		assert_bool(FileAccess.file_exists(path)).is_true()


# ---------------------------------------------------------------- 2) HUD buff 芯片

func _chip_icon(chip: Control) -> TextureRect:
	for c in chip.find_children("*", "TextureRect", true, false):
		return c as TextureRect
	return null


func _chip_label(chip: Control) -> Label:
	for c in chip.find_children("*", "Label", true, false):
		return c as Label
	return null


func test_hud_buff_chips_wire_icons_with_text_fallback() -> void:
	var hud: HUD = auto_free(HUD.new())
	hud.player = auto_free(Player.new())
	add_child(hud)
	# vigor=已接线 / avenger=已知空帧（回落）/ no_such_buff=表外（回落）
	hud._apply_buffs({"buffs": ["vigor", "avenger", "no_such_buff"] as Array[String]})
	assert_int(hud._buff_row.get_child_count()).is_equal(3)
	var icons := hud._buff_row.find_children("*", "TextureRect", true, false)
	assert_array(icons).has_size(1)                       # 只有一枚接线成功
	var wired := hud._buff_row.get_child(0) as Control
	assert_str(String(wired.get_meta("buff_id"))).is_equal("vigor")
	var icon := _chip_icon(wired)
	assert_object(icon).is_not_null()
	assert_str(icon.texture.resource_path).contains("ui/buffs/vigor.png")
	assert_float(icon.custom_minimum_size.x).is_equal(12.0)   # 原生 12x12 零缩放
	assert_str(_chip_label(wired).text).is_equal("强健")   # 缩写文字与图标共存
	# 空帧/表外回落纯文字 chip（无 TextureRect 占位，缩写原样保留）
	var fallback := hud._buff_row.get_child(1) as Control
	assert_str(String(fallback.get_meta("buff_id"))).is_equal("avenger")
	assert_object(_chip_icon(fallback)).is_null()
	assert_str(_chip_label(fallback).text).is_equal("复仇")
	var unknown := hud._buff_row.get_child(2) as Control
	assert_object(_chip_icon(unknown)).is_null()
	assert_str(_chip_label(unknown).text).is_equal("no_such_buff")


# ---------------------------------------------------------------- 3) buff_pick 三选一卡

func test_buff_pick_cards_top_icon_with_fallback() -> void:
	var bp := (load("res://ui/buff_pick.tscn") as PackedScene).instantiate() as BuffPick
	auto_free(bp)
	add_child(bp)
	bp.open(["vigor", "avenger"])
	assert_bool(bp.visible).is_true()
	var wired := bp._cards[0] as PanelContainer
	var icon := _chip_icon(wired)
	assert_object(icon).is_not_null()
	assert_str(icon.texture.resource_path).contains("ui/buffs/vigor.png")
	assert_str(_chip_label(wired).text).is_equal("[1] 强健")
	# 空帧回落纯文字卡（无图标占位，名称行原样）
	var fallback := bp._cards[1] as PanelContainer
	assert_object(_chip_icon(fallback)).is_null()
	assert_str(_chip_label(fallback).text).is_equal("[2] 复仇者")


# ---------------------------------------------------------------- 4) drink_machine 卡片

class FakeWallet extends RefCounted:
	func spend_coins(_n: int) -> bool:
		return true


func test_drink_machine_cards_wire_icons() -> void:
	var dm: DrinkMachine = auto_free(DrinkMachine.new())
	add_child(dm)
	dm.open({"uses_left": DrinkMachine.USES_PER_FLOOR}, FakeWallet.new(), null)
	var ids := dm.drink_ids()
	assert_int(ids.size()).is_equal(8)
	for i in dm._cards.size():
		var card := dm._cards[i] as PanelContainer
		var icon := _chip_icon(card)
		assert_object(icon).override_failure_message("饮料卡缺图标: %s" % ids[i]).is_not_null()
		assert_str(icon.texture.resource_path).contains("ui/drinks/%s.png" % ids[i])
	# 售罄刷新：图标保留（灰化走 card.modulate，不摘图）
	dm.uses_left = 0
	dm._refresh_panel()
	for i in dm._cards.size():
		assert_object(_chip_icon(dm._cards[i] as PanelContainer)).is_not_null()


# ---------------------------------------------------------------- 5) talents 节点两态

## duck-typed 持久化后端（gems/add_gems/purchased_talents/record_talent_purchase 四方法
## 契约，同 TalentSystem 注入缝——_init 形参 typed Node，须继承 Node；不触真实档）。
class FakeTalentSave extends Node:
	var balance := 100
	var bought: Array[String] = []

	func gems() -> int:
		return balance

	func add_gems(n: int) -> void:
		balance += n

	func purchased_talents() -> Array[String]:
		return bought.duplicate()

	func record_talent_purchase(id: String) -> void:
		bought.append(id)


func test_talents_nodes_show_state_icons() -> void:
	var save := FakeTalentSave.new()
	auto_free(save)                                       # Node 须显式释放（防 orphan）
	var ts := TalentSystem.new(save)
	ts.purchased.assign(["red_sharpen"])                  # tier1 已购；其余未购（可购/锁定）
	var t := (load("res://ui/talents.tscn") as PackedScene).instantiate() as Talents
	t.system = ts
	auto_free(t)
	add_child(t)
	var filled := t._nodes["red_sharpen"] as Button       # 已购 → node_filled
	assert_object(filled.icon).is_not_null()
	assert_str(filled.icon.resource_path).contains("node_filled")
	for id: String in ["red_deadeye", "blue_vitality", "green_deep_cell"]:
		var btn := t._nodes[id] as Button                  # 未购（可购/锁定同口径）→ node_empty
		assert_object(btn.icon).override_failure_message("未购节点缺 node_empty: " + id).is_not_null()
		assert_str(btn.icon.resource_path).contains("node_empty")
	assert_bool(filled.text.contains("磨刃")).is_true()    # 文案不动（状态色/✓ 语义保留）
