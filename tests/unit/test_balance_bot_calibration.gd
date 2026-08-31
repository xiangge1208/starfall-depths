class_name TestBalanceBotCalibration
extends GdUnitTestSuite
## m2-t28 Balance Bot 校准点复核（裁定①②③④⑤⑥的机器可验半边）。
## 这些断言把「校准点的当前落地值」钉死：Balance Bot 报告引用这些值对照
## 裁定口径。数值漂移时本套件先红，报告不会带过期值出库。
## 裁定出处：docs/superpowers/reports/m2-progress.md「编排者裁定记录」1/6/17/19 +
## 移交表「LOOT_RARITY_WEIGHTS 绿→rare 映射漂移（T6 → T28 校准）」。
## 注：本基线（main c676657）A2/A3 层模板在 T26（并行在途）——先知隐藏门需 A3
## 层，对局动态半边不可采；⑥按「数据行 + 生产结算函数」口径机器复核。


# ================================================================ ① 炮台 DPS（裁定①口径：射速 2/s × 伤 4 = 8 DPS）

func test_turret_thorn_cycle_and_dps() -> void:
	# 荆棘炮台：3 连发 ×4 伤，稳态周期 = cd(150) + 连发间隙 2×(6-1) = 160t
	# → 持续 DPS = 12 / (160/60) = 4.5（裁定①口径 8 DPS 的 56%）。
	var out := BalanceBotDecisions.turret_cycle_dps(GameDB.get_enemy("thorn_turret"))
	assert_int(out["cycle_ticks"]).is_equal(160)
	assert_int(out["shots_per_cycle"]).is_equal(3)
	assert_int(out["first_shot_ticks"]).is_equal(30)
	assert_float(out["sustained_dps"]).is_equal_approx(4.5, 0.01)


func test_turret_lava_fan_cycle_and_dps() -> void:
	# 岩浆喷吐炮台：扇形 5 发一次性齐发（齐射不占周期）→ 周期 = cd(180)，
	# 最大暴露 DPS = 40 / 3.0s ≈ 13.33。
	var out := BalanceBotDecisions.turret_cycle_dps(GameDB.get_enemy("lava_turret"))
	assert_int(out["cycle_ticks"]).is_equal(180)
	assert_int(out["shots_per_cycle"]).is_equal(5)
	assert_float(out["sustained_dps"]).is_equal_approx(13.33, 0.01)


func test_turret_rock_crystal_laser_cycle_and_dps() -> void:
	# 岩晶炮台（蓄能单发激光）：周期 = cd(180)，单发 6 伤 → 2.0 DPS。
	var out := BalanceBotDecisions.turret_cycle_dps(GameDB.get_enemy("rock_crystal_turret"))
	assert_int(out["cycle_ticks"]).is_equal(180)
	assert_int(out["shots_per_cycle"]).is_equal(1)
	assert_float(out["sustained_dps"]).is_equal_approx(2.0, 0.01)


# ================================================================ ② LOOT_RARITY_WEIGHTS 绿→rare 映射漂移（T6 移交复核）

## 复核②的密封前提（裁定㉒口径）：GameDB.weapons 是**运行时池**——共享
## save_headless.json 的图鉴解锁会经 CodexSystem.grant_to_pool 把 locked 行回池
## （产品正确行为，跨进程累积）。静态漂移复核必须对「初始掉落池」= weapons_all
## 中 locked 未标记者做推导，与档状态解耦。
func _pristine_drop_pool() -> Dictionary:
	var out := {}
	for wid: String in GameDB.weapons_all:
		var row: Dictionary = GameDB.weapons_all[wid]
		if not bool(row.get("locked", false)):
			out[wid] = row
	return out


func test_loot_pool_sizes_per_rarity_key() -> void:
	# 初始掉落池（locked 已排除，= GameDB._ready 装载语义）：
	# 白9 + 绿21 + 蓝36 = 66；紫/橙（locked 49）在 weapons_all 而不在池。
	var by_rarity := {}
	var pristine := _pristine_drop_pool()
	for wid: String in pristine:
		var r := String((pristine[wid] as Dictionary).get("rarity", ""))
		by_rarity[r] = int(by_rarity.get(r, 0)) + 1
	assert_int(int(by_rarity.get("common", 0))).is_equal(9)
	assert_int(int(by_rarity.get("uncommon", 0))).is_equal(21)
	assert_int(int(by_rarity.get("rare", 0))).is_equal(36)
	assert_int(int(by_rarity.get("epic", 0))).is_equal(0)      # 池内无紫
	assert_int(int(by_rarity.get("legend", 0))).is_equal(0)    # 池内无橙
	assert_int(pristine.size()).is_equal(66)


func test_loot_weights_green_tier_unreachable() -> void:
	# 漂移实证①：LOOT_RARITY_WEIGHTS 只含 common/rare/epic 三键（注释称 白60/绿30/蓝10），
	# 但「绿」=uncommon 无权重键——绿 21 把不可能被直接抽中；30% 走的 rare 键抽的是蓝 36。
	var keys := FloorScene.LOOT_RARITY_WEIGHTS.keys()
	assert_bool(keys.has("uncommon")).is_false()
	assert_bool(keys.has("legend")).is_false()
	assert_int(int(FloorScene.LOOT_RARITY_WEIGHTS.get("common", 0))).is_equal(60)
	assert_int(int(FloorScene.LOOT_RARITY_WEIGHTS.get("rare", 0))).is_equal(30)
	assert_int(int(FloorScene.LOOT_RARITY_WEIGHTS.get("epic", 0))).is_equal(10)


func test_loot_epic_key_is_dead_branch_falling_back_to_full_pool() -> void:
	# 漂移实证②：epic 键（10% 权重）在初始池内 0 命中——_roll_weapon 的空池兜底
	# 会退化为「全池均匀」（66 把任抽），绿装只能经这条 10% 兜底路径以
	# 21/66 ≈ 3.2% 的综合概率出现（设计意图 30%）。
	var pristine := _pristine_drop_pool()
	var epic_ids: Array[String] = []
	for wid: String in pristine:
		if String((pristine[wid] as Dictionary).get("rarity", "")) == "epic":
			epic_ids.append(wid)
	assert_int(epic_ids.size()).is_equal(0)
	# 全量表复核（weapons_all 含 locked）：紫 33 + 橙 16 = 49 全 locked（裁定②口径）。
	var locked_epic := 0
	var locked := 0
	for wid: String in GameDB.weapons_all:
		var row: Dictionary = GameDB.weapons_all[wid]
		if bool(row.get("locked", false)):
			locked += 1
			if String(row.get("rarity", "")) == "epic":
				locked_epic += 1
	assert_int(GameDB.weapons_all.size()).is_equal(115)
	assert_int(locked).is_equal(49)
	assert_int(locked_epic).is_equal(33)


# ================================================================ ③ 熔铸费用阶梯（裁定⑰：30~390）

func test_forge_cost_ladder_30_to_390() -> void:
	# fuse_cost = 较高稀有度基准价 ×1.5 取整到 5：
	# 白20→30 / 绿42→65 / 蓝85→130 / 紫155→235 / 橙260→390。
	assert_int(ForgeLogic.fuse_cost("common", "common")).is_equal(30)
	assert_int(ForgeLogic.fuse_cost("common", "uncommon")).is_equal(65)
	assert_int(ForgeLogic.fuse_cost("uncommon", "rare")).is_equal(130)
	assert_int(ForgeLogic.fuse_cost("rare", "epic")).is_equal(235)
	assert_int(ForgeLogic.fuse_cost("epic", "legend")).is_equal(390)
	assert_int(ForgeLogic.fuse_cost("legend", "common")).is_equal(390)   # 高阶主导


# ================================================================ ④ 守护者史诗星辉杖无弱化（裁定⑥）

func test_guardian_wields_unweakened_epic_staff() -> void:
	# 守护者 start_weapons 直指 epic 星辉杖原行（damage 4 / rate 3.0），
	# 无任何「弱化版」数据行——裁定⑥「无弱化」的落地事实。
	var hero := GameDB.get_hero("guardian")
	assert_array(hero.get("start_weapons")).is_equal(["xinghuizhang"])
	var staff := GameDB.get_weapon("xinghuizhang")
	assert_str(staff.get("rarity", "")).is_equal("epic")
	assert_int(int(staff.get("damage", 0))).is_equal(4)
	assert_float(float(staff.get("rate", 0.0))).is_equal(3.0)
	# 全表不存在守护者弱化变体（xinghuizhang_* 派生 id）。
	for wid: String in GameDB.weapons:
		assert_str(wid).is_not_equal("xinghuizhang_weak")


# ================================================================ ⑤ 生命潮汐法阵 3s 实落 1HP（裁定⑥）

func test_life_tide_circle_lands_exactly_1_hp_over_3s() -> void:
	# 法阵口径：3s × 0.5HP/s 名义 1.5HP，整数累加器只在第 2 秒拍落 1 HP，
	# 余 0.5 随法阵消散且不跨施放携带——无头直驱 tick（帧注入模式）。
	var player: Player = auto_free(Player.new())
	player.hp = 5
	var tide: LifeTide = auto_free(LifeTide.new())
	tide.player = player
	tide._activate(0)
	assert_int(player.hp).is_equal(7)             # 施放立即回 2 HP（INSTANT_HEAL）
	for f in range(1, 181):                       # 法阵全程 180t 逐拍推进
		tide.tick(f)
	assert_int(player.hp).is_equal(8)             # 法阵全程只再落 1 HP（第 2 秒拍）
	assert_bool(tide.circle_active(180)).is_true()    # 末拍含
	assert_bool(tide.circle_active(181)).is_false()
	# 常量与裁定⑥逐项对齐：立即回 2HP / 法阵 3s / 0.5HP/s。
	assert_int(LifeTide.INSTANT_HEAL).is_equal(2)
	assert_int(LifeTide.DURATION_TICKS).is_equal(180)
	assert_float(LifeTide.HEAL_PER_TICK).is_equal(0.5)
	# 法阵结束后余 0.5 消散：再推 300 拍无新增治疗（不跨施放携带）。
	for f2 in range(181, 481):
		tide.tick(f2)
	assert_int(player.hp).is_equal(8)


func test_life_tide_outside_circle_heals_nothing() -> void:
	# 阵外节拍空转（治疗以站在阵内为前提）——累加器不推进。
	var player: Player = auto_free(Player.new())
	player.hp = 5
	var tide: LifeTide = auto_free(LifeTide.new())
	tide.player = player
	tide._activate(0)                    # 法阵锚定施放位置（原点）
	player.global_position = Vector2(500, 500)    # 施放后走远（> 60px 半径）
	for f in range(1, 181):
		tide.tick(f)
	assert_int(player.hp).is_equal(7)   # 仅施放立即回 2 HP


# ================================================================ ⑥ 先知击杀经济（裁定⑲：+53 / +353 首杀）
## 本基线 prophet 数据行已在库（m2-t24 先知卡已合入 main）；隐藏门需 A3 层
## （floor_scene.A3_FLOOR_IDX），而 A2/A3 层模板在 T26（并行在途）——
## 「对局内击杀先知」动态半边本批不可采，报告按未覆盖披露；
## 此处以数据行 + 生产结算函数（RunState.settle_kill_gems）为机器口径。

const PROPHET_ID := "starfall_prophet"


func test_prophet_row_is_hidden_boss_with_gems3_drop() -> void:
	var row := GameDB.get_enemy(PROPHET_ID)
	assert_bool(row.is_empty()).is_false()
	assert_str(String(row.get("archetype", ""))).is_equal("boss")
	assert_int(int(row.get("hp", 0))).is_equal(3200)
	assert_bool(String(row.get("boss_script", "")).ends_with("starfall_prophet.gd")).is_true()
	# +3 半边的落地：行内 drops 契约含 gems3（3 蓝晶实体掉落，拾取各 +1 入局内账）。
	assert_bool(String(row.get("drops", "")).contains("gems3")).is_true()


func test_prophet_kill_economy_settle_side() -> void:
	# 生产结算函数口径：Boss 档 +50；首杀（SaveSystem 无标记时）再 +300 = 350。
	# 档内快照/还原：不把首杀标记/蓝晶差值泄漏进共享 save_headless.json。
	var saved_kills: Array = (SaveSystem.data.get("boss_first_kills", []) as Array).duplicate()
	var had_mark := saved_kills.has(PROPHET_ID)
	var gems0 := RunState.gems
	if had_mark:                                  # 临时摘除首杀标记（快照已留底）
		var without: Array = saved_kills.duplicate()
		without.erase(PROPHET_ID)
		SaveSystem.data["boss_first_kills"] = without
	RunState.gems = 0
	var first := RunState.settle_kill_gems("boss", PROPHET_ID)
	assert_int(first).is_equal(350)               # 50 + 300 首杀
	assert_int(RunState.gems).is_equal(350)
	var second := RunState.settle_kill_gems("boss", PROPHET_ID)
	assert_int(second).is_equal(50)               # 幂等：非首杀仅 +50
	# 裁定⑲合计口径：击杀合计 = 结算 + gems3 实体 3 = 50+3 = +53；首杀 350+3 = +353。
	# （gems3 的 +1×3 拾取路径 = FloorScene._spawn_gem → RunState.add_gems，生产接线。）
	# 还原：档内首杀标记与局内蓝晶均回滚，不污染 bot 批次与其它套件。
	SaveSystem.data["boss_first_kills"] = saved_kills
	SaveSystem.save_now()
	RunState.gems = gems0
