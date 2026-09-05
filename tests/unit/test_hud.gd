class_name TestHUD
extends GdUnitTestSuite
## m1-t24：HUD 完整版。纯逻辑抽取的字段映射钉死（GDD §19 数据纪律：HUD 每帧经
## hud_snapshot 从 RunState/Player/Skill 读数，不缓存）——金币/层/种子、双武器名、
## 当前槽、技能 CD 比例（cd_ratio 纯函数）、翻滚就绪、Buff 列表拷贝、低血量阈值边界。
## 注：RunState-like 实例直接 new 脚本（不走 autoload 单例、不调 start_run），
## 避免污染全局 RngSvc 种子（无跨测试顺序耦合）。

func _run_like() -> Node:
	# auto_free 返回 Variant，:= 无法推断类型（同 test_skills.gd 既定决议），需显式标注
	var r: Node = auto_free(load("res://autoload/run_state.gd").new())
	return r

func _player() -> Player:
	var p: Player = auto_free(Player.new())
	p._test_init()
	return p

func _rig(p: Player) -> WeaponRig:
	var r: WeaponRig = auto_free(WeaponRig.new())
	r._test_init()
	p.add_child(r)
	p.weapon_rig = r
	return r

func _skill(p: Player, cooldown_ticks: int) -> SkillBase:
	var sk := SkillBase.new()
	sk.name = "Skill"                      # snapshot 按名寻址（同 player.tscn / hero_applier 契约）
	sk.setup(p, {"id": "t24_test", "cooldown_ticks": cooldown_ticks, "energy_cost": 0})
	p.add_child(sk)                        # 随 p（auto_free）释放，不产生孤儿
	return sk

# ---- hud_snapshot：RunState 字段映射 ----

func test_snapshot_maps_coins_floor_seed() -> void:
	var r := _run_like()
	r.set("coins", 42)
	r.set("floor_idx", 2)
	r.set("run_seed", 987654321)
	var snap := HUD.hud_snapshot(_player(), r, 100)
	assert_int(snap["coins"]).is_equal(42)
	assert_int(snap["floor_idx"]).is_equal(2)
	assert_int(snap["run_seed"]).is_equal(987654321)

func test_snapshot_maps_hp_shield_energy() -> void:
	var p := _player()
	p.hp = 5
	p.hp_max = 8
	p.shield = 3
	p.shield_max = 4
	p.energy = 55
	p.energy_max = 100
	var snap := HUD.hud_snapshot(p, _run_like(), 100)
	assert_int(snap["hp"]).is_equal(5)
	assert_int(snap["hp_max"]).is_equal(8)
	assert_int(snap["shield"]).is_equal(3)
	assert_int(snap["shield_max"]).is_equal(4)
	assert_int(snap["energy"]).is_equal(55)
	assert_int(snap["energy_max"]).is_equal(100)

func test_snapshot_buffs_list_is_copy() -> void:
	var r := _run_like()
	r.get("buffs").append("vigor")
	r.get("buffs").append("deadly")
	var snap := HUD.hud_snapshot(_player(), r, 100)
	assert_array(snap["buffs"]).is_equal(["vigor", "deadly"])
	snap["buffs"].append("polluted")       # 快照为拷贝：改快照不回写局状态
	assert_int(r.get("buffs").size()).is_equal(2)

func test_snapshot_tolerates_null_run_and_player() -> void:
	var snap := HUD.hud_snapshot(null, null, 100)
	assert_int(snap["coins"]).is_equal(0)
	assert_int(snap["floor_idx"]).is_equal(0)
	assert_bool(snap["low_hp"]).is_true()   # 无玩家即 hp=0：红晕按低血量口径点亮
	assert_bool(snap["roll_ready"]).is_true()
	assert_array(snap["weapon_names"]).is_equal(["", ""])

# ---- hud_snapshot：双武器槽（rig 为活真值，无 rig 回退 RunState.weapons） ----

func test_snapshot_weapon_names_from_rig_via_gamedb() -> void:
	var p := _player()
	var rig := _rig(p)
	rig.equip("laohuoji")
	rig.equip("tiejian")
	var snap := HUD.hud_snapshot(p, _run_like(), 100)
	assert_array(snap["weapon_names"]).is_equal(["老伙计", "铁剑"])

func test_snapshot_empty_weapon_slot_blank_name() -> void:
	var p := _player()
	_rig(p).equip("laohuoji")
	var snap := HUD.hud_snapshot(p, _run_like(), 100)
	assert_array(snap["weapon_names"]).is_equal(["老伙计", ""])

func test_snapshot_current_slot_follows_rig() -> void:
	var p := _player()
	var rig := _rig(p)
	rig.equip("laohuoji")
	rig.equip("tiejian")
	rig.slot = 1
	var snap := HUD.hud_snapshot(p, _run_like(), 100)
	assert_int(snap["current_slot"]).is_equal(1)

func test_snapshot_falls_back_to_run_weapons_without_rig() -> void:
	var p := _player()                     # 无 weapon_rig（weapon_rig 默认 null）
	var r := _run_like()
	r.set("current_slot", 1)
	r.get("weapons").append("duangong")
	r.get("weapons").append("")
	var snap := HUD.hud_snapshot(p, r, 100)
	assert_array(snap["weapon_names"]).is_equal(["短弓", ""])
	assert_int(snap["current_slot"]).is_equal(1)

func test_snapshot_carries_weapon_ids_for_icon_lookup() -> void:
	# m4p-ui5：槽位图标寻址需要 id（names 只有中文名，无法拼图标路径）。rig 路径与
	# run 回落路径都必须带出 id，且与 names 索引对位。
	var p := _player()
	var rig := _rig(p)
	rig.equip("laohuoji")
	rig.equip("tiejian")
	var snap := HUD.hud_snapshot(p, _run_like(), 100)
	assert_array(snap["weapon_ids"]).is_equal(["laohuoji", "tiejian"])
	assert_array(snap["weapon_names"]).is_equal(["老伙计", "铁剑"])
	var bare := _player()                  # 无 rig：走 run.weapons 回落路径
	var r := _run_like()
	r.get("weapons").append("duangong")
	r.get("weapons").append("")
	var snap2 := HUD.hud_snapshot(bare, r, 100)
	assert_array(snap2["weapon_ids"]).is_equal(["duangong", ""])

func test_hud_weapon_slot_shows_icon_and_hides_text() -> void:
	# m4p-ui5 用户反馈「武器那里还是方框写着短弓」：115 把图标早已在盘（图鉴页接线），
	# HUD 却只画中文名。断言图标命中时显示图标且文字清空；空槽两者都不显示。
	var hud: HUD = auto_free(HUD.new())
	add_child(hud)
	var p := _player()
	var rig := _rig(p)
	rig.equip("duangong")                  # 短弓：art/generated/ui/weapons/duangong.png 在盘
	hud._apply_bottom(HUD.hud_snapshot(p, _run_like(), 100))
	assert_bool(hud._slot_icons[0].visible).override_failure_message(
		"槽 0 应显示武器图标（duangong.png 在盘）").is_true()
	assert_object(hud._slot_icons[0].texture).is_not_null()
	assert_str(hud._slot_labels[0].text).override_failure_message(
		"图标命中时不应再画中文名（否则就是用户看到的『方框写着短弓』）").is_equal("")
	assert_bool(hud._slot_icons[1].visible).is_false()   # 空槽：无图标
	assert_str(hud._slot_labels[1].text).is_equal("")
	# 缺图回落：表外 id 无图标文件 → 隐藏图标、回落显示文字（同 codex 缺图口径）
	hud._apply_bottom({"weapon_names": ["no_such_gun", ""], "weapon_ids": ["no_such_gun", ""],
		"current_slot": 0, "skill_cd_ratio": 0.0, "skill_ready": true, "roll_ready": true})
	assert_bool(hud._slot_icons[0].visible).is_false()
	assert_str(hud._slot_labels[0].text).is_equal("no_such_gun")

func test_weapon_display_name_fallbacks() -> void:
	assert_str(HUD.weapon_display_name("laohuoji")).is_equal("老伙计")
	assert_str(HUD.weapon_display_name("no_such_gun")).is_equal("no_such_gun")  # 未知 id 原样回显
	assert_str(HUD.weapon_display_name("")).is_equal("")                        # 空槽空名

# ---- cd_ratio：CD 环比例纯函数 ----

func test_cd_ratio_bounds_and_clamps() -> void:
	assert_float(HUD.cd_ratio(0, 840)).is_equal_approx(0.0, 0.0001)       # 就绪：环空
	assert_float(HUD.cd_ratio(840, 840)).is_equal_approx(1.0, 0.0001)     # 刚施放：环满
	assert_float(HUD.cd_ratio(210, 840)).is_equal_approx(0.25, 0.0001)
	assert_float(HUD.cd_ratio(-5, 840)).is_equal_approx(0.0, 0.0001)      # 负剩余钳为 0
	assert_float(HUD.cd_ratio(5, 0)).is_equal_approx(0.0, 0.0001)         # 无 CD 技能：恒就绪
	assert_float(HUD.cd_ratio(5, -1)).is_equal_approx(0.0, 0.0001)

func test_snapshot_skill_cd_ratio_lifecycle() -> void:
	var p := _player()
	_skill(p, 100)
	var r := _run_like()
	assert_bool(HUD.hud_snapshot(p, r, 900)["skill_ready"]).is_true()     # 未施放
	assert_float(HUD.hud_snapshot(p, r, 900)["skill_cd_ratio"]).is_equal_approx(0.0, 0.0001)
	assert_bool(p.get_node("Skill").cast(1000)).is_true()
	var full := HUD.hud_snapshot(p, r, 1000)
	assert_float(full["skill_cd_ratio"]).is_equal_approx(1.0, 0.0001)
	assert_bool(full["skill_ready"]).is_false()
	var half := HUD.hud_snapshot(p, r, 1050)
	assert_float(half["skill_cd_ratio"]).is_equal_approx(0.5, 0.0001)
	var ready := HUD.hud_snapshot(p, r, 1100)
	assert_float(ready["skill_cd_ratio"]).is_equal_approx(0.0, 0.0001)
	assert_bool(ready["skill_ready"]).is_true()

func test_snapshot_without_skill_node_is_ready() -> void:
	var snap := HUD.hud_snapshot(_player(), _run_like(), 100)   # player.tscn 外无 Skill 节点
	assert_float(snap["skill_cd_ratio"]).is_equal_approx(0.0, 0.0001)
	assert_bool(snap["skill_ready"]).is_true()

# ---- 翻滚 CD 点（player.roll_ready_at → 点亮/灰） ----

func test_snapshot_roll_ready_boundary() -> void:
	var p := _player()
	p.start_roll(Vector2.RIGHT, 100)      # CD 至 100+13+42 = 155（同 test_player_state 口径）
	var snap_cd := HUD.hud_snapshot(p, _run_like(), 154)
	assert_bool(snap_cd["roll_ready"]).is_false()
	var snap_ok := HUD.hud_snapshot(p, _run_like(), 155)
	assert_bool(snap_ok["roll_ready"]).is_true()

# ---- 低血量阈值边界（hp ≤ 2 红晕，spec：hp==2 true / hp==3 false） ----

func test_is_low_hp_boundary() -> void:
	assert_bool(HUD.is_low_hp(2)).is_true()
	assert_bool(HUD.is_low_hp(3)).is_false()
	assert_bool(HUD.is_low_hp(1)).is_true()
	assert_bool(HUD.is_low_hp(0)).is_true()

func test_snapshot_low_hp_flag_boundary() -> void:
	var p := _player()
	p.hp = 2
	assert_bool(HUD.hud_snapshot(p, _run_like(), 100)["low_hp"]).is_true()
	p.hp = 3
	assert_bool(HUD.hud_snapshot(p, _run_like(), 100)["low_hp"]).is_false()

# ---- Buff 缩写（中文名前 2 字，色块 tooltip 用全名） ----

func test_buff_abbrev_uses_chinese_name_prefix() -> void:
	assert_str(HUD.buff_abbrev("fire_enchant")).is_equal("火焰")     # 火焰附魔
	assert_str(HUD.buff_abbrev("vigor")).is_equal("强健")           # 强健（2 字全名）
	assert_str(HUD.buff_abbrev("no_such_buff")).is_equal("no_such_buff")  # 表外 id 原样回显
	assert_str(HUD.buff_abbrev("")).is_equal("")
