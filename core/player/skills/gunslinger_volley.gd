class_name GunslingerVolley
extends SkillBase
## 火枪手·铳 主动技「齐射」+ 被动「精炼火药」（M5-T9，附录 L §3 第 14 行；heroes.json id=gunslinger）。
##
## 主动齐射（CD 660t/15 蓝，heroes 行经 setup 覆写）：朝当前瞄准方向扇形 6 发复制弹
## ——「复制弹」= 当前远程武器单发伤害 ×0.6 的玩家弹（伤害乘区与常规枪击完全同口径：
## 配件 dmg_pct round 整数化 → player.scaled_damage 天赋×祝福 → ×0.6 round；元素身份
## 走 rig.element_hit_profile 同一契约），扇面展开确定性（无 jitter——同 bulwark 碎片
## 确定性出射纪律，同种子复现），走 CombatSystem.spawn_projectile 通道（source_type
## "skill" 归因标记）。当前武器为近战/空槽（手刀）时无复制源 → 施放照常过门（CD/蓝
## 不退——框架无退回缝，hunter 猎印空目标先例）。
## 强化（data["upgraded"]，HeroApplier 按存档注入，附录 L 强化行「齐射 8 发且穿透
## +1」）：8 发 + 每发穿透 +1（穿透 = 行值 + 配件 pierce_flat + 1）。
## 议定值披露（附录 L 未给，Balance Bot 校准点）：扇面总角 30°（rig 武器散布同构
## _fan_offset 展开），复制弹不继承 rig 暴虐回响 crit_detonate（skill 面不进暴击引爆
## ——猎印爆裂/碎片先例均不带）。
##
## 被动精炼火药（passive_id=refined_powder）：切枪动作完成后 2s 内首发伤害 ×2。
## - 切枪计时锚点从 weapon_rig 读：_switch_until = 切枪帧 + SWITCH_LOCK_TICKS（0 =
##   未切过枪，私有约定字段跨读披露——同 rig 轮询 player._roll_left 先例）；
##   窗 = [锚点, 锚点 + 120t)（「切枪后」= 动作完成起算——切枪 0.25s 锁内本就禁发）；
## - 首发放大通道：rig.weapon_fired 前缝（try_fire 内 emit 先于 _fire_slot 结算）——
##   首发枪击拍写 player.powder_dmg_mult/until 一次性窗（until = 开火拍 +1），伤害出口
##   player.scaled_damage 同拍读取 ×2（仅非近战面——「首发」是枪击语义，melee.gd 挥击
##   不经 weapon_fired 天然不消费）；「每切枪锚点恰一次」记账在本节点（_powder_anchor）；
## - 齐射与被动的交互口径：复制弹不吃首发 ×2 也不消费首发记账（齐射不走 weapon_fired，
##   记账不动）——「首发」留给窗内下一发常规枪击。已知同拍边界：与首发同拍施放的
##   齐射会读到 1 拍窗（附录 L 未述，披露不调参）。
##
## 遥测：volley_cast / powder_first_shot（Telemetry 既有清单无撞名）。
## sfx：volley（施放拍，cast 过门后响；wav 由 gen_placeholder_sfx.py 生成）。

## 技能中文名（heroes 行 skill_name 同值；HUD/后续实现取数兜底）。
const SKILL_NAME := "齐射"
const VOLLEY_COUNT_BASE := 6         # 附录 L §3：扇形 6 发
const VOLLEY_COUNT_UPGRADED := 8     # 强化：8 发
const COPY_DMG_MULT := 0.6           # 单发 ×0.6（附录 L §3 逐字）
const VOLLEY_FAN_DEG := 30.0         # 议定值（附录 L 未给扇角；Balance Bot 校准点）
const UPGRADED_PIERCE_BONUS := 1     # 强化：穿透 +1
const COPY_SPEED_FALLBACK := 320.0   # 武器行缺 bullet_speed 时兜底（手刀虚拟行防护）
# ---- 精炼火药（附录 L §3「切枪后 2s 内首发伤害 +100%」逐字） ----
const POWDER_WINDOW_TICKS := 120     # 2s（自切枪动作完成锚点起算）
const POWDER_DMG_MULT := 2.0         # 首发 +100% = ×2

var upgraded := false
var _powder_anchor := -1             # 已消费首发的切枪锚点（-1 = 无；锚点变更自动再武装）

func _init() -> void:
	cooldown_ticks = 660               # 11s（数据行覆写）
	energy_cost = 15

func _load(data: Dictionary) -> void:
	super._load(data)                  # SkillBase 无字段装载；保留钩子链（m5-t7 先例）
	upgraded = bool(data.get("upgraded", false))

func setup(p: Player, data: Dictionary) -> void:
	super.setup(p, data)
	var rig := p.weapon_rig if p != null else null
	if rig != null and not rig.weapon_fired.is_connected(_on_weapon_fired):
		rig.weapon_fired.connect(_on_weapon_fired)   # 首发前缝：方法引用，free 时自动断连

# ================================================================ 主动：齐射

func _activate(frame: int) -> void:
	if player == null:
		return
	var rig := player.weapon_rig
	var combat = player.combat
	if rig == null or combat == null:
		return                          # 无 rig/无房 combat：过门 no-op（披露见头注）
	var w := rig.current()
	if w.is_empty() or bool(w.get("is_melee", false)):
		return                          # 近战/手刀态无复制源：过门 no-op（hunter 空目标先例）
	var eff := rig._attachment_effects(w)          # melee.gd 同款私有读先例（伤害口径对齐）
	var att_base := maxi(0, int(round(float(int(w["damage"])) * (1.0 + float(eff["dmg_pct"])))))
	var single := player.scaled_damage(att_base)
	var copy_damage := maxi(1, int(round(float(single) * COPY_DMG_MULT)))
	var profile := rig.element_hit_profile(w, frame)
	var pierce := maxi(0, int(w["pierce"]) + int(eff["pierce_flat"])) \
		+ (UPGRADED_PIERCE_BONUS if upgraded else 0)
	var n := VOLLEY_COUNT_UPGRADED if upgraded else VOLLEY_COUNT_BASE
	var speed := float(w.get("bullet_speed", COPY_SPEED_FALLBACK))
	var origin: Vector2 = player.global_position \
		+ Vector2(float(w.get("muzzle", 8.0)), 0.0).rotated(player.facing.angle())
	var base_angle := player.facing.angle()
	for i in n:
		var ang := base_angle + deg_to_rad(_fan_offset(n, i, VOLLEY_FAN_DEG))
		combat.spawn_projectile({
			"pos": origin, "vel": Vector2.RIGHT.rotated(ang) * speed,
			"damage": copy_damage,
			"faction": Projectile.Faction.PLAYER,
			"element": profile["element"], "pierce": pierce,
			"enchant_element": profile["proc_element"],
			"enchant_proc_chance": profile["proc_chance"],
			"bounce": maxi(0, int(w["bounce"]) + int(eff["bounce_flat"])),
			"life_seconds": float(w.get("bullet_life", 1.2)),
			"radius": float(w.get("bullet_radius", 3.0)),
			"source_type": "skill", "source_id": "gunslinger_volley",
			"source_name": SKILL_NAME, "attack_name": "齐射",
		})
	AudioMgr.play("volley")
	Telemetry.log_row(["volley_cast", frame, n, copy_damage], "gunslinger")

## 扇形均布偏移（weapon_rig._fan_offset 同式本地实现——偶数发不含正中向，与武器
## 散弹展开语义一致；确定性无 jitter）。
static func _fan_offset(n: int, i: int, spread_deg: float) -> float:
	if n <= 1:
		return 0.0
	var step := spread_deg / float(n - 1)
	return -spread_deg / 2.0 + step * i

# ================================================================ 被动：精炼火药

## 首发前缝（rig.weapon_fired，先于本发结算）：切枪完成窗内首个枪击 → 写一次性
## ×2 窗（scaled_damage 同拍读取；窗 1 拍自灭无残留）。记账每锚点恰一次；窗外/
## 已消费/无 rig 静默返回。当前帧基准（Engine 物理帧）与 try_fire/_fire_slot 同拍。
func _on_weapon_fired(_weapon: Dictionary, _aim: Vector2, _mirrored: bool) -> void:
	if player == null or player.weapon_rig == null:
		return
	var su := int(player.weapon_rig._switch_until)
	if su <= 0 or _powder_anchor == su:
		return                          # 未切过枪 / 本锚点首发已消费
	var f := Engine.get_physics_frames()
	if f < su or f >= su + POWDER_WINDOW_TICKS:
		return                          # 窗外（切枪完成前本就禁发；2s 外过期）
	_powder_anchor = su
	player.powder_dmg_mult = POWDER_DMG_MULT
	player.powder_dmg_mult_until = f + 1
	Telemetry.log_row(["powder_first_shot", f, su], "gunslinger")

## 切枪锚点读数（测试/HUD 用）：当前是否在精炼火药窗内（记账未消费）。
func powder_window_active(frame: int) -> bool:
	if player == null or player.weapon_rig == null:
		return false
	var su := int(player.weapon_rig._switch_until)
	return su > 0 and _powder_anchor != su and frame >= su and frame < su + POWDER_WINDOW_TICKS
