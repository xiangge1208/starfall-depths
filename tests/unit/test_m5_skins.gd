extends GdUnitTestSuite
## M5-H 皮肤（纯外观）：SaveSystem skins 存档三件套（set_skin/skin_of/归一化）+
## HeroApplier 运行态着色（SKINS tint → 玩家 Sprite.modulate）+ SKINS 表完备性。
## 纪律：零数值面——着色只碰 Sprite.modulate，HP/盾/蓝/速度/伤害原样。

const HERO_ID := "vanguard"


func before_test() -> void:
	_seal = TestSaveSeal.seal("m5h")


func after_test() -> void:
	if not _seal.is_empty():
		TestSaveSeal.restore(_seal)
		_seal = {}


const PLAYER_SCENE := preload("res://core/player/player.tscn")
var _seal: Dictionary = {}


# —— 存档三件套 ——

func test_set_and_query_skin() -> void:
	assert_str(SaveSystem.skin_of(HERO_ID)).is_equal("")    # 缺省默认
	SaveSystem.set_skin(HERO_ID, "nightfrost")
	assert_str(SaveSystem.skin_of(HERO_ID)).is_equal("nightfrost")


func test_set_empty_skin_returns_default() -> void:
	SaveSystem.set_skin(HERO_ID, "nightfrost")
	SaveSystem.set_skin(HERO_ID, "")
	assert_str(SaveSystem.skin_of(HERO_ID)).is_equal("")


func test_set_skin_rejects_unknown_hero() -> void:
	SaveSystem.set_skin("no_such_hero", "nightfrost")
	assert_str(SaveSystem.skin_of("no_such_hero")).is_equal("")


func test_skins_survive_merge_normalization() -> void:
	SaveSystem.set_skin(HERO_ID, "nightfrost")
	var arr: Array = SaveSystem.data.get("skins", {}).keys()
	assert_array(arr).contains(HERO_ID)
	# 脏形状防御：_merge_saved 对非 String 键值丢弃——构造脏档直灌
	SaveSystem.data["skins"] = {"mage": 42, 7: "x", HERO_ID: "nightfrost"}
	var merged: Dictionary = SaveSystem._merge_saved(SaveSystem.data)
	assert_int(merged["skins"].get("mage", -1)).is_equal(-1)
	assert_int(merged["skins"].get(7, -1)).is_equal(-1)
	assert_str(String(merged["skins"].get(HERO_ID, ""))).is_equal("nightfrost")


# —— 运行态着色 ——

func test_applier_tints_sprite_when_skin_selected() -> void:
	SaveSystem.set_skin(HERO_ID, "nightfrost")
	var p: Player = auto_free(PLAYER_SCENE.instantiate() as Player)
	HeroApplier.apply(GameDB.get_hero(HERO_ID), p)
	var spr := p.get_node("Sprite") as Sprite2D
	var want: Color = (HeroApplier.SKINS[HERO_ID] as Dictionary)["tint"]
	assert_object(spr).is_not_null()
	assert_bool(spr.modulate.is_equal_approx(want)).is_true()


func test_applier_default_skin_stays_white() -> void:
	var p: Player = auto_free(PLAYER_SCENE.instantiate() as Player)
	HeroApplier.apply(GameDB.get_hero(HERO_ID), p)
	var spr := p.get_node("Sprite") as Sprite2D
	assert_bool(spr.modulate.is_equal_approx(Color.WHITE)).is_true()


func test_skin_has_zero_stat_impact() -> void:
	var hero: Dictionary = GameDB.get_hero(HERO_ID)
	var p1: Player = auto_free(PLAYER_SCENE.instantiate() as Player)
	HeroApplier.apply(hero, p1)
	SaveSystem.set_skin(HERO_ID, "nightfrost")
	var p2: Player = auto_free(PLAYER_SCENE.instantiate() as Player)
	HeroApplier.apply(hero, p2)
	assert_int(p2.hp_max).is_equal(p1.hp_max)
	assert_int(p2.shield_max).is_equal(p1.shield_max)
	assert_int(p2.energy_max).is_equal(p1.energy_max)
	assert_float(p2.move_speed).is_equal_approx(p1.move_speed, 0.001)


# —— 表完备性 ——

func test_skins_table_covers_foundling_six_no_orphans() -> void:
	# 口径（Appendix L 分工）：SKINS 表覆盖 M5 时点的 6 名元老英雄；14 名新英雄的
	# 专属外观归 roster T2 美术参数表（该卡持有配色配置），本表只保证——
	# ① 元老六人全覆盖 ② 无孤儿条目 ③ 条目形状合法可辨。
	for id: String in ["vanguard", "ranger", "mage", "assassin", "engineer", "guardian"]:
		assert_bool(HeroApplier.SKINS.has(id)).override_failure_message(
			"foundling hero %s has no skin entry" % id).is_true()
	for id: String in HeroApplier.SKINS:
		var skin: Dictionary = HeroApplier.SKINS[id]
		assert_bool(GameDB.heroes.has(id)).override_failure_message(
			"skin orphan hero %s" % id).is_true()
		assert_str(String(skin["name"])).is_not_empty()
		assert_bool(skin["tint"] is Color).is_true()
		assert_bool(skin["tint"] != Color.WHITE).is_true()   # 换色必须可辨
