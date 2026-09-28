class_name WeaponRig
extends Node
## 双武器位射击（GDD §8.1）。数值全部来自 GameDB 行。

const SWITCH_LOCK_TICKS := 15      # 0.25s

signal weapon_changed(current_weapon: Dictionary, secondary_weapon: Dictionary)
signal weapon_fired(weapon: Dictionary, aim: Vector2, mirrored: bool)

## m4p-w2a：开火音按 weapons.json category 分音（表外 pistol/special 维持 shoot_player；
## 近战 is_melee 不经 try_fire，挥击音在 melee.gd 既有 melee_swing）。经 AudioMgr.play_once
## 消费——双持齐射同拍两枪仍只一声（卡约束「一拍一音源一次」）。
const CATEGORY_SHOOT_KEY := {
	"bow": "shoot_bow", "laser": "shoot_laser", "rifle": "shoot_rifle",
	"shotgun": "shoot_shotgun", "smg": "shoot_smg", "sniper": "shoot_sniper",
	"staff": "shoot_staff", "throw": "shoot_throw",
}

var combat: CombatSystem
var combat_rng: RandomNumberGenerator
var slots: Array[Dictionary] = []
var slot := 0
## 正式局注入 RunState 后，武器槽与 T15 聚合字段同源更新；测试/训练房可保持 null。
var run_state: Node = null
var dual_wield_until := -1         # m1-t2 狂潮：frame < 此值时双武器齐射且免蓝（技能写入）
var crit_boost_until := -1         # m1-t5 影袭：必暴状态窗（功能侧掷签在 CombatSystem.forced_crit_until）
var speed_boost_until := -1        # m1-t5 影袭：frame < 此值时弹速 ×1.2（技能写入）
var _next_fire_frame := 0
var _switch_until := 0
var _muzzle := Vector2(8, 0)       # 兼容旧测试/默认；正式射击以武器行 muzzle 为准
# 局内永久增益（BuffManager 写入，正式射击路径消费）。
var enchant_element: int = Elements.Id.NONE  # 附魔元素（Elements.Id）
var enchant_proc_chance: float = 0.0          # 永久附魔在有效命中时的触发概率
var bonus_projectiles: int = 0               # 追加弹丸数（散弹扩张）
var crit_detonate_pct: float = 0.0           # 暴击强制共鸣概率（暴虐回响）
var rate_mult: float = 1.0                   # 攻速倍率（迅捷扳机）
var bullet_speed_mult: float = 1.0           # 弹速倍率（弹速强化）
var temporary_enchant_element: int = Elements.Id.NONE
var temporary_enchant_until := -1

func _test_init() -> void:
	slots = [{}, {}]

func equip(weapon_id: String) -> void:
	var w := GameDB.get_weapon(weapon_id)
	if w.is_empty():
		push_error("WeaponRig: unknown weapon %s" % weapon_id)
		return
	if slots.size() < 2:
		slots.resize(2)
	# 填第一个空槽；两槽满则替换当前槽并保留另一槽
	#（brief 代码原为 `slots[slot] = w`，与自身 test_switch_lock 及控制器决议矛盾，按决议修正）。
	var target := slot
	for i in slots.size():
		if slots[i].is_empty():
			target = i
			break
	# m5-c 实例化拷贝点：GameDB 行是共享缓存（weapons/weapons_all 全局引用），配件
	# 状态若原地写行字典会污染全池——equip 是全部武器获取路径的共同 choke（掉落/
	# 商店/初始/熔铸均经此口），在此 deep-copy 成武器实例并初始化空配件表。
	# 消费端一律 w.get("attachments", {}) 读缺省，测试直塞共享行也零污染。
	slots[target] = w.duplicate(true)
	slots[target]["attachments"] = {}
	# m4-c3 codex_seen 写入方（获取点收口）：equip 是全部武器获取路径的共同 choke——
	# 默认池首取（floor_scene/inter_floor/training 初始枪 + HeroApplier）、掉落拾取
	# （loot station）、商店购买（shop._buy_weapon）、熔铸产物（forge 装备）均经本口；
	# 图鉴任务解锁侧在 CodexSystem.check_unlocks 内直写。幂等（已见过不重写盘）。
	CodexSystem.mark_weapon_seen(weapon_id)
	_sync_run_state()
	var alt := (slot + 1) % 2
	weapon_changed.emit(current(), slots[alt] if alt < slots.size() else {})

func current() -> Dictionary:
	return slots[slot] if slot < slots.size() else {}

func switch_slot(frame: int) -> void:
	if slots.size() < 2:
		return
	Fx.on_weapon_switched()   # J5：换武器重置连击
	slot = (slot + 1) % 2
	_sync_run_state()
	_switch_until = frame + SWITCH_LOCK_TICKS
	_next_fire_frame = frame
	var alt := (slot + 1) % 2
	weapon_changed.emit(current(), slots[alt] if alt < slots.size() else {})

## 清空指定槽的权威入口。设施不得再直接写 slots，否则 RunState 聚合会滞后。
func clear_slot(index: int) -> Dictionary:
	if index < 0 or index >= slots.size():
		return {}
	var removed: Dictionary = slots[index]
	slots[index] = {}
	_sync_run_state()
	var alt := (slot + 1) % 2
	weapon_changed.emit(current(), slots[alt] if alt < slots.size() else {})
	return removed

func bind_run_state(state: Node) -> void:
	run_state = state
	_sync_run_state()


# ================================================================ m5-c 武器配件（三槽 muzzle/mag/stock）

## 装配配件到**当前武器**同槽（拾取/商店购买共同入口；「掉落台换手」语义不适用——
## 配件即时生效不落台）。同槽已有件 = 替换且被替换件消失（不入背包/不掉落）。
## 返回新装配件行（非空 = 成功；空 = 失败：未知 id / 当前无武器（手刀态））。
func apply_attachment(att_id: String) -> Dictionary:
	var att := GameDB.get_attachment(att_id)
	if att.is_empty():
		return {}
	var w := current()
	if w.is_empty():
		return {}                       # 手刀态（空槽）不可装配，实体保留待装备后拾取
	if not w.has("attachments"):
		# 实例化兜底：run_root 对账路径会直写共享行进槽（rig.slots[i] = GameDB 行）。
		# 严禁把 attachments 键写进 GameDB 共享缓存——先 deep-copy 替换槽位再挂配件。
		w = w.duplicate(true)
		w["attachments"] = {}
		slots[slot] = w
	(w["attachments"] as Dictionary)[String(att["slot"])] = att_id   # 同槽重复拾取 = 直接覆写（旧件引用消失）
	return att


## 三槽 effects 合成（m5-c 消费入口）：跨槽同键**加法叠加**（当前每槽一件，为未来
## 同键多件预留）；element_inject 不可加，取最后写入（数据上仅 mag 槽持有）。
## exclude_muzzle：近战武器无枪口——melee 路径传 true，muzzle 槽全部效果无效
## （mag/stock 照常生效；披露：双子弹匣的 dmg_pct -0.20 惩罚对近战照收，
## projectiles_flat/energy_pct 对近战无消费面 = no-op）。
func _attachment_effects(w: Dictionary, exclude_muzzle := false) -> Dictionary:
	var out := {
		"dmg_pct": 0.0, "rate_pct": 0.0, "bullet_speed_pct": 0.0,
		"spread_pct": 0.0, "energy_pct": 0.0,
		"pierce_flat": 0, "bounce_flat": 0, "projectiles_flat": 0,
		"roll_boost_pct": 0.0, "roll_boost_ticks": 0,
		"element_inject": Elements.Id.NONE,
	}
	var atts: Dictionary = w.get("attachments", {})
	for slot_name: String in GameDB.ATTACHMENT_SLOTS:
		if exclude_muzzle and slot_name == "muzzle":
			continue
		var aid := String(atts.get(slot_name, ""))
		if aid.is_empty():
			continue
		var row := GameDB.get_attachment(aid)
		if row.is_empty():
			continue
		var eff: Dictionary = row.get("effects", {})
		for k: String in eff:
			if k == "element_inject":
				out[k] = Elements.from_name(String(eff[k]))
			else:
				out[k] = out.get(k, 0) + eff[k]   # 数值键跨槽加法
	return out


## 翻滚检测（m5-c 折跃枪托 roll_boost 触发端）：Player 归 D 卡所有（本卡不可改），
## 无翻滚信号可订阅——rig 侧轮询 Player 滚动帧计数（_roll_left，私有约定字段，
## 跨读披露），上升沿 = 翻滚起始帧，写 player.atk_speed_boost 共享窗（与战神像
## shrine 同款「后写者胜」覆写语义，折扣：同帧竞争时后触发者覆盖先触发者）。
var _roll_active_prev := false

func _physics_process(_delta: float) -> void:
	var player := get_parent() as Player
	if player == null:
		_roll_active_prev = false
		return
	var rolling := player._roll_left > 0
	if rolling and not _roll_active_prev:
		_trigger_roll_boost(player, Engine.get_physics_frames())
	_roll_active_prev = rolling

func _trigger_roll_boost(player: Player, frame: int) -> void:
	var w := current()
	if w.is_empty():
		return
	var eff := _attachment_effects(w, not w["is_melee"])
	# 近战当前武器时 muzzle 槽同样无效（口径与挥击消费一致；roll_boost 在 stock 槽，实不受影响）
	var pct := float(eff["roll_boost_pct"])
	if pct <= 0.0:
		return
	player.atk_speed_boost_pct = pct
	player.atk_speed_boost_until = frame + maxi(1, int(eff["roll_boost_ticks"]))

func _sync_run_state() -> void:
	if run_state == null:
		return
	run_state.set("selected_slot", slot)
	for i in slots.size():
		var id := "" if slots[i].is_empty() else String(slots[i].get("id", ""))
		if run_state.has_method("record_weapon"):
			run_state.call("record_weapon", i, id)

func try_fire(aim: Vector2, frame: int) -> bool:
	var w := current()
	if w.is_empty() or w["is_melee"]:
		return false
	if frame < _next_fire_frame or frame < _switch_until:
		return false
	var player := get_parent() as Player
	var dual := frame < dual_wield_until              # 狂潮双持窗（GDD §6）
	var energy_free := frame < player.energy_free_until
	# m3-fix1 试炼 energy_cost_mult 消费端：开火蓝耗 ceil(蓝耗×倍率)（规格 §3「所有
	# 武器蓝耗」；技能蓝耗不经此处）。倍率缺省 1.0 → TrialMods 恒等返回零漂移。
	# m5-c 乘区顺序：配件 energy_pct（1+pct，round 整数化、clamp ≥0）在先，试炼
	# ceil 倍率在后（蓝耗-25% 等配件 = 基础值修改，试炼层 = 整层终态漏斗）。
	var eff := _attachment_effects(w)
	var base_cost := maxi(0, int(round(float(int(w["energy_cost"])) \
		* (1.0 + float(eff["energy_pct"])))))
	var cost := 0 if dual or energy_free else TrialMods.player_energy_cost(base_cost)
	if cost > player.energy:
		return false                     # 空蓝禁远程（GDD §7.2）；双持期双武器免蓝
	player.energy -= cost
	var effective_rate := effective_attack_rate(w, player, frame)
	_next_fire_frame = frame + maxi(1, int(round(TimeConst.FPS / effective_rate)))
	weapon_fired.emit(w, aim, false)
	_fire_slot(w, aim, false, frame)
	if dual:
		# 副手齐射：镜像枪口（同 aim），副手空/近战则跳过；蓝耗已整体豁免
		var alt := (slot + 1) % 2
		if alt < slots.size():
			var aw: Dictionary = slots[alt]
			if not aw.is_empty() and not aw["is_melee"]:
				weapon_fired.emit(aw, aim, true)
				_fire_slot(aw, aim, true, frame)
	# m4p-w2a：开火音按武器 category 分音（表外回落 shoot_player；play_once 保证双持同拍一声）
	AudioMgr.play_once(String(CATEGORY_SHOOT_KEY.get(String(w.get("category", "")), "shoot_player")))
	return true

## 单侧齐射：mirrored 时枪口取反（副手位于朝向另一舷），弹道角与主手同源。
## 影袭速度窗（m1-t5）：frame < speed_boost_until 时弹速 ×1.2。
## m5-c 配件消费（乘区顺序总披露，全部为「基础值修改 → 玩家出口」两段）：
##   伤害   round(w.damage × (1+配件dmg_pct)) → talent_scaled_damage（天赋×祝福，
##          内部再 round）→ 暴击 roll 在命中层（DamageCalc）。
##   射速   w.rate × rate_mult × 临时窗 × (1+配件rate_pct)（effective_attack_rate）。
##   蓝耗   round(energy_cost × (1+配件energy_pct)) → 试炼 ceil（try_fire）。
##   弹速   w.bullet_speed × (1+配件speed_pct) × buff 弹速 ×1.2 影袭窗（并列相乘）。
##   散布   w.spread_deg × (1+配件spread_pct)（负值收束，clamp ≥0）。
##   弹丸   n = base_n + 散弹扩张(base_n>1 门槛) + 配件 projectiles_flat——配件弹丸
##          加在门槛判定**之后**：单发枪装三连发只变三连、不触发散弹扩张二次叠加。
##   穿透/反弹 行值 + 配件 flat 加算（clamp ≥0）；元素覆盖走 element_hit_profile。
func _fire_slot(w: Dictionary, aim: Vector2, mirrored: bool, frame: int) -> void:
	var player := get_parent() as Player
	var eff := _attachment_effects(w)
	var base_n := int(w["projectiles"])
	# 「散弹扩张」只强化原本就是多弹丸的武器，单发枪不凭空变双发。
	var n := base_n + (bonus_projectiles if base_n > 1 else 0) + int(eff["projectiles_flat"])
	var spread := maxf(0.0, float(w["spread_deg"]) * (1.0 + float(eff["spread_pct"])))
	var side := -1.0 if mirrored else 1.0
	var muzzle := Vector2(float(w.get("muzzle", _muzzle.x)), 0.0)
	var origin: Vector2 = player.global_position + side * muzzle.rotated(aim.angle())
	Fx.spawn_muzzle_flash(origin, aim.angle(), String(w.get("category", "")))   # J3 枪口焰（M3 J-C，池化）
	var speed := float(w["bullet_speed"]) * (1.0 + float(eff["bullet_speed_pct"])) * bullet_speed_mult
	if frame < speed_boost_until:
		speed *= 1.2
	# 伤害乘区顺序（披露）：配件 dmg_pct 先 round 整数化 → 玩家出口 scaled_damage
	#（天赋/祝福乘区，内部 round）。配件层最先 = 基础值修改，不吃出口层整数化前漂移。
	var base_damage := maxi(0, int(round(float(int(w["damage"])) * (1.0 + float(eff["dmg_pct"])))))
	var damage := talent_scaled_damage(base_damage, player)
	for i in n:
		var ang := aim.angle() + deg_to_rad(_fan_offset(n, i, spread)) + deg_to_rad(_jitter(spread))
		var element_profile := element_hit_profile(w, frame)
		_spawn({
			"pos": origin, "vel": Vector2.RIGHT.rotated(ang) * speed,
			"damage": damage,
			"faction": Projectile.Faction.PLAYER,
			"element": element_profile["element"], "pierce": maxi(0, int(w["pierce"]) + int(eff["pierce_flat"])),
			"enchant_element": element_profile["proc_element"],
			"enchant_proc_chance": element_profile["proc_chance"],
			"bounce": maxi(0, int(w["bounce"]) + int(eff["bounce_flat"])), "life_seconds": float(w.get("bullet_life", 1.2)),
			"radius": float(w.get("bullet_radius", 3.0)),
			"crit_detonate_pct": crit_detonate_pct,
			"source_type": "weapon", "source_id": String(w.get("id", "")),
			"source_name": String(w.get("name", w.get("id", ""))), "attack_name": "射击",
		})

## m2-t35 天赋伤害乘区（talent_dmg_pct）+ m4-c2 祝福叠层乘区：统一走玩家伤害出口
## 聚合点 player.scaled_damage（round 语义沿袭；meta/叠层缺省 = 原伤害零漂移）。
## m4-c2 起：近战挥击路径（core/player/melee.gd）同步接入同一出口（原披露的未接线收口）。
func talent_scaled_damage(base_damage: int, player: Player) -> int:
	return player.scaled_damage(base_damage)

func _spawn(cfg: Dictionary) -> void:
	combat.spawn_projectile(cfg)         # 测试以子类覆写 _spawn 捕获参数


## 远程与近战共享攻速结算：永久 Buff 与战神像临时倍率相乘，再乘配件 rate_pct
##（m5-c：加法叠入 1+pct；for_melee=true 时近战口径排除 muzzle 槽—— melee.gd
## 传 true，try_fire 缺省 false）。无配件时乘区恒 1.0，既有数零漂移。
func effective_attack_rate(w: Dictionary, player: Player, frame: int,
		for_melee := false) -> float:
	var temporary := 1.0 + (player.atk_speed_boost_pct \
		if frame < player.atk_speed_boost_until else 0.0)
	var att := 1.0 + float(_attachment_effects(w, for_melee)["rate_pct"])
	return float(w["rate"]) * rate_mult * temporary * att


## 远程与近战共享元素契约：
## - 武器原生元素始终是主元素；永久 Buff 是命中时额外 proc；
## - 星髓像为独立 100% 临时覆盖，激活时只使用临时元素且不掷永久 Buff；
## - m5-c 冰霜弹匣（element_inject）覆盖武器**原生**主元素（100% 冰弹），优先级
##   低于试炼 force_element 与星髓像临时附魔——后两者激活时元素身份被统一/覆盖，
##   注入失效（披露：覆盖率是 100% 主元素替换，非概率 proc）。
func element_hit_profile(w: Dictionary, frame: int) -> Dictionary:
	# m3-fix1 试炼 force_element 消费端（规格 §3 边界）：本层玩家一切元素附魔
	# （武器自带/增益/星髓像临时附魔）统一转为层元素——元素身份被统一，临时附魔
	# 的「独立覆盖、不掷永久 proc」结构与永久 proc 概率语义保留。NONE = 无因子零改动。
	var forced := TrialMods.floor_force_element(RunState.floor_idx)
	if frame < temporary_enchant_until and temporary_enchant_element != Elements.Id.NONE:
		return {"element": forced if forced != Elements.Id.NONE else temporary_enchant_element,
			"proc_element": Elements.Id.NONE, "proc_chance": 0.0}
	var native := Elements.from_name(String(w.get("element", "none")))
	var injected := int(_attachment_effects(w)["element_inject"])
	var main := injected if injected != Elements.Id.NONE else native
	return {"element": forced if forced != Elements.Id.NONE else main,
		"proc_element": forced if forced != Elements.Id.NONE else enchant_element,
		"proc_chance": enchant_proc_chance}

func _fan_offset(n: int, i: int, spread_deg: float) -> float:
	if n <= 1:
		return 0.0
	var step := spread_deg / float(n - 1)
	return -spread_deg / 2.0 + step * i

func _jitter(spread_deg: float) -> float:
	if combat_rng == null or spread_deg <= 0.0:
		return 0.0
	return combat_rng.randf_range(-spread_deg / 4.0, spread_deg / 4.0)
