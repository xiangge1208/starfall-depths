extends GdUnitTestSuite
## M5-D 技能强化接线（Appendix L 裁定：购买流关闭、强化 1500/名维持）：
##   SaveSystem.buy_skill_upgrade —— 扣 1500 / 重复购买拒绝 / 余额不足拒绝 / 未知
##   英雄拒绝 / skill_upgrades 名录入库；
##   skill_upgraded 只读；
##   HeroApplier 运行态覆盖 —— heroes 行 upgraded=false 仍按存档名录注入 true；
##   刺客残影分支 —— 升级版突进终点残影：0.5s 引信 / 20 伤 / 80px / 一次清窗；
##   非升级版无残影。
## 档隔离：TestSaveSeal（裁定㉔，共享 save_headless.json 逐用例密闭）。
## 残影直驱 _detonate_afterimage（绕墙钟，同 life_tide「测试可注入任意帧直驱」口径）。

const PLAYER_SCENE := preload("res://core/player/player.tscn")
var _seal: Dictionary = {}


func before_test() -> void:
	_seal = TestSaveSeal.seal("m5d")


func after_test() -> void:
	if not _seal.is_empty():
		TestSaveSeal.restore(_seal)
		_seal = {}


const HERO_ID := "assassin"


# —— 购买语义 ——

func test_buy_deducts_1500_and_records() -> void:
	SaveSystem.add_gems(2000)
	assert_bool(SaveSystem.buy_skill_upgrade(HERO_ID)).is_true()
	assert_int(SaveSystem.gems()).is_equal(500)
	assert_bool(SaveSystem.skill_upgraded(HERO_ID)).is_true()


func test_buy_rejects_insufficient_gems() -> void:
	SaveSystem.add_gems(1499)
	assert_bool(SaveSystem.buy_skill_upgrade(HERO_ID)).is_false()
	assert_int(SaveSystem.gems()).is_equal(1499)
	assert_bool(SaveSystem.skill_upgraded(HERO_ID)).is_false()


func test_buy_rejects_duplicate() -> void:
	SaveSystem.add_gems(4000)
	assert_bool(SaveSystem.buy_skill_upgrade(HERO_ID)).is_true()
	assert_bool(SaveSystem.buy_skill_upgrade(HERO_ID)).is_false()
	assert_int(SaveSystem.gems()).is_equal(2500)          # 只扣一次


func test_buy_rejects_unknown_hero() -> void:
	SaveSystem.add_gems(4000)
	assert_bool(SaveSystem.buy_skill_upgrade("no_such_hero")).is_false()
	assert_int(SaveSystem.gems()).is_equal(4000)


# —— HeroApplier 注入覆盖 ——

func test_applier_injects_upgraded_from_save() -> void:
	SaveSystem.add_gems(1500)
	assert_bool(SaveSystem.buy_skill_upgrade(HERO_ID)).is_true()
	var hero: Dictionary = GameDB.get_hero(HERO_ID)
	assert_bool(bool(hero.get("upgraded", false))).is_false()   # 行字段不动（纸面锚点）
	var p: Player = auto_free(PLAYER_SCENE.instantiate() as Player)
	HeroApplier.apply(hero, p)
	var skill := p.get_node("Skill")
	assert_bool(bool(skill.get("upgraded"))).is_true()          # 运行态覆盖生效


func test_applier_defaults_not_upgraded() -> void:
	var hero: Dictionary = GameDB.get_hero(HERO_ID)
	var p: Player = auto_free(PLAYER_SCENE.instantiate() as Player)
	HeroApplier.apply(hero, p)
	var skill := p.get_node("Skill")
	assert_bool(bool(skill.get("upgraded"))).is_false()


# —— 刺客残影分支 ——

class HitProbe extends EnemyBase:
	## 真实 EnemyBase 子类（_detonate_afterimage 组扫描按 `as EnemyBase` 强转——
	## 裸 Node2D 探针会被 cast-null 跳过）。ctx 记录 + 透传 super（真实伤害结算）。
	## place() 同时写 position 与 brain_pos——EnemyBase 两字段独立，测试同值镜像。
	var hits: Array = []

	func _init() -> void:
		_test_init({"id": "m5_dummy", "hp": 100, "radius": 6.0})

	func place(at: Vector2) -> void:
		position = at
		brain_pos = at

	func take_hit(ctx: Dictionary) -> void:
		hits.append(ctx.duplicate(true))
		super.take_hit(ctx)


func _assassin_skill(upgraded: bool) -> Array:
	# player.tscn 实例化（Skill 节点在场景内，HeroApplier.apply 依赖它——同 test_skills 先例）
	var p: Player = auto_free(PLAYER_SCENE.instantiate() as Player)
	add_child(p)                                           # _activate/爆炸要 is_inside_tree
	var m: ShadowstepAssassin = auto_free(ShadowstepAssassin.new())
	p.add_child(m)
	m.player = p
	m.upgraded = upgraded
	return [p, m]


func _probe(at: Vector2) -> HitProbe:
	var e: HitProbe = auto_free(HitProbe.new())
	add_child(e)                                           # EnemyBase._ready 组注册需要树
	e.place(at)
	e.add_to_group("enemies")
	return e


func test_upgraded_dash_schedules_afterimage() -> void:
	var r := _assassin_skill(true)
	var m: ShadowstepAssassin = r[1]
	m._activate(1000)
	assert_int(m._afterimage_boom_frame).is_equal(1030)    # 0.5s 引信


func test_non_upgraded_has_no_afterimage() -> void:
	var r := _assassin_skill(false)
	var m: ShadowstepAssassin = r[1]
	m._activate(1000)
	assert_int(m._afterimage_boom_frame).is_equal(-1)      # 非升级无残影


func test_detonation_damage_once_and_window_cleared() -> void:
	var r := _assassin_skill(true)
	var p: Player = r[0]
	var m: ShadowstepAssassin = r[1]
	p.position = Vector2.ZERO
	var probe := _probe(Vector2.ZERO)
	m._activate(1000)
	probe.place(m._afterimage_pos + Vector2(40, 0))        # 残影终点 40px（≤80）
	# 残影锚点 = 突进终点（GDD「突进终点留下残影」；影袭已把玩家位移 dash 距离）
	for node in p.get_tree().get_nodes_in_group("enemies"):
		print("DBGGRP member=%s valid=%s brain=%s state=%s" % [node.name, node.is_inside_tree(), str(node.get("brain_pos")), str(node.get("state"))])
	print("DBGANCHOR afterimage=%s probe.brain=%s" % [m._afterimage_pos, probe.brain_pos])
	var hits := m._detonate_afterimage(1030)
	print("DBGHITS hits=%s probe_hits=%s" % [hits, probe.hits.size()])
	assert_int(hits).is_equal(1)
	assert_int(probe.hits.size()).is_equal(1)
	assert_int(probe.hits[0]["amount"]).is_equal(20)
	assert_str(String(probe.hits[0]["attack_name"])).is_equal("残影爆炸")
	assert_bool(bool(probe.hits[0]["player_damage"])).is_true()
	assert_int(m._afterimage_boom_frame).is_equal(-1)      # 一次性：窗已清，_physics_process 驱动层不再触发


func test_detonation_radius_filter() -> void:
	var r := _assassin_skill(true)
	var p: Player = r[0]
	var m: ShadowstepAssassin = r[1]
	p.position = Vector2.ZERO
	var near := _probe(Vector2.ZERO)
	var far := _probe(Vector2.ZERO)
	m._activate(1000)
	near.place(m._afterimage_pos + Vector2(60, 0))         # ≤80
	far.place(m._afterimage_pos + Vector2(200, 0))         # >80
	assert_int(m._detonate_afterimage(1030)).is_equal(1)
	assert_int(near.hits.size()).is_equal(1)
	assert_int(far.hits.size()).is_equal(0)
