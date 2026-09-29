class_name MirageDecoy
extends SkillBase
## 影卫·蜃 主动技「留影」+ 被动「调虎」（附录 L §3，M5 T6；heroes.json id=mirage）。
##
## 主动留影：CD 600t（10s，数据行 skill_cd 覆写）/10 蓝，在施放位置留 4s（240t）诱饵
## （3 HP）：诱饵注册 PLAYER 阵营战斗体（SummonBase 契约）——敌方弹幕命中/拦截它，
## 我方弹/我方 AoE 天然不误伤（CombatSystem 同阵营不结算，FollowAlly 同缝）。
## 存活期结束（到期/被击毁）原地「烟爆」：60px 内敌方体固定 15 伤（坚守直结先例，
## 无暴击 RNG；半径 60px 议定值——坚守 AoE/生命潮汐法阵同款先例，T11 bot 校准点）。
## 强化（data["upgraded"]，HeroApplier 按存档注入）：再按技能键手动提前引爆
## （cast() 覆写：诱饵存活期按键=引爆，不烧 CD 不耗蓝——CD 仍自首次施放起算）。
##
## 被动调虎（passive_id=decoy_master 门控）：诱饵存活期敌 AI 优先攻诱饵——
## EnemyBase.target_override 仇恨缝（单点，本卡落）经技能侧注入：施放拍 + 每拍
## 维护（扫 "enemies" 组写入，覆盖施放后新刷的敌人）；诱饵退场（烟爆同拍）清除。
## 覆写体释放/亡故由 EnemyBase 侧 is_instance_valid/is_alive() 双保险自动回落。
## 缝口径披露：仅覆盖 _player_pos() 读点原型（shooter/orbiter/barrage/suicide/heavy/
## splitter/summoner/mushroom/turret 的瞄准与逼近）；直读 player_ref 的路径
## （接触伤/charger 冲刺/laser 瞄准/heavy 拉拽）不被调虎（单点最小增量）。
##
## 诱饵纪律（FollowAlly 同款）：不进 "enemies"/"summons" 组（不污染索敌/炮台库存），
## 由技能实例持有唯一引用（CD 600t > 存活 240t，场上恒至多 1 只，无叠窗可能）。
## 帧注入直驱（tick(frame) + decoy.tick(frame)）可无头测；生产 _physics_process 自驱
## （life_tide 习语）。
##
## 遥测：decoy_cast / decoy_burst / decoy_detonate（Telemetry 既有清单无撞名）。
## sfx：decoy_leave（施放拍）/ decoy_burst（烟爆拍，wav 由 gen_placeholder_sfx.py 生成）。

const SKILL_NAME := "留影"          # 技能中文名（heroes 行 skill_name 同值）
const DECOY_HP := 3                 # 附录 L §3 逐字
const DECOY_LIFETIME_TICKS := 240   # 4s
const BURST_DMG := 15               # 消失烟爆 15 伤
const BURST_RADIUS_PX := 60.0       # 议定值（坚守 AoE/潮汐法阵 60px 先例）
const DECOY_RADIUS_PX := 6.0        # 判定体半径（玩家同径，议定值）

var upgraded := false
var decoy: MirageDecoyBody = null   # 场上诱饵唯一引用（null = 无）

func _init() -> void:
	cooldown_ticks = 600               # 10s（数据行覆写）
	energy_cost = 10

func _load(data: Dictionary) -> void:
	upgraded = bool(data.get("upgraded", false))

## 施放入口：强化态且诱饵存活 → 按键=手动引爆（不烧 CD/不耗蓝；CD 自首施放持续）。
func cast(frame: int) -> bool:
	if upgraded and decoy_alive():
		detonate(frame, "manual")
		return true
	return super.cast(frame)

## 诱饵是否存活（无引用/已退场 = 否）。
func decoy_alive() -> bool:
	return decoy != null and is_instance_valid(decoy) and decoy.is_alive()

## 施放生效：铺诱饵（SummonBase 装配 → PLAYER 阵营注册 → 调虎注入）。
func _activate(frame: int) -> void:
	if player == null:
		return
	AudioMgr.play("decoy_leave")
	var d := MirageDecoyBody.new()
	d.setup({
		"id": "mirage_decoy", "hp": DECOY_HP, "radius": DECOY_RADIUS_PX,
		"lifetime_ticks": DECOY_LIFETIME_TICKS,
	})
	d.player = player
	if combat_host() != null:
		d.combat = combat_host()
		combat_host().add_child(d)     # CombatSystem 为纯 Node：position 即全局位
		d.global_position = player.global_position
		d.brain_pos = d.global_position
		combat_host().register_body(d, d.combat_faction())   # 定位后注册（哈希落点）
	else:
		player.add_child(d)            # 无 combat 兜底（裸测）：仍可存活计时
		d.global_position = player.global_position
		d.brain_pos = d.global_position
	d.despawned.connect(_on_decoy_despawned)
	d.begin(frame)
	decoy = d
	_apply_aggro()
	Telemetry.log_row(["decoy_cast", frame, 1 if upgraded else 0])

## 每拍推进（生产 _physics_process 自驱；无头测试直驱）：存活期维护调虎注入
## （覆盖施放后新刷敌人）；退场后零开销直返。
func tick(_frame: int) -> void:
	if not decoy_alive():
		return
	_apply_aggro()

## 调虎注入（被动门控）：扫 "enemies" 组写 target_override（已指向本诱饵则跳过写）。
func _apply_aggro() -> void:
	if player == null or player.passive_id != "decoy_master":
		return
	if not player.is_inside_tree() or not decoy_alive():
		return
	for node in player.get_tree().get_nodes_in_group("enemies"):
		var e := node as Node
		if e == null or not is_instance_valid(e):
			continue
		if e.get("target_override") != decoy:
			e.set("target_override", decoy)

## 诱饵退场统一结算（到期/击毁/手动引爆同路径）：调虎清除 → 烟爆 → 引用置空。
func _on_decoy_despawned(reason: String) -> void:
	var d := decoy
	decoy = null
	if d == null:
		return
	_clear_aggro(d)
	if player == null:
		return
	AudioMgr.play("decoy_burst")
	var pos: Vector2 = d.global_position
	var hits := 0
	if combat_host() != null:
		for body in combat_host().bodies_in_radius(pos, BURST_RADIUS_PX,
				Projectile.Faction.ENEMY):
			body.take_hit({
				"amount": BURST_DMG, "is_crit": false, "element": Elements.Id.NONE,
				"from": pos, "source_type": "skill", "source_id": "mirage_decoy",
				"source_name": SKILL_NAME, "attack_name": "烟爆", "player_damage": true,
			})
			hits += 1
	Telemetry.log_row(["decoy_burst", Engine.get_physics_frames(), hits, reason])

## 强化手动引爆（cast 覆写入口）：提前结束存活期（烟爆同统一结算）。
func detonate(frame: int, reason := "manual") -> void:
	if decoy_alive():
		decoy.despawn(reason)
	Telemetry.log_row(["decoy_detonate", frame, reason])

## 调虎清除：仅回写仍指向本诱饵的敌人（不碰其他写者）。
func _clear_aggro(d: MirageDecoyBody) -> void:
	if player == null or not player.is_inside_tree():
		return
	for node in player.get_tree().get_nodes_in_group("enemies"):
		var e := node as Node
		if e != null and is_instance_valid(e) and e.get("target_override") == d:
			e.set("target_override", null)

## 房间 CombatSystem 读缝（player.combat setter 由房间注入；无绑定 → null）。
func combat_host() -> CombatSystem:
	if player == null:
		return null
	return player.combat

## 生产自驱（life_tide 习语）：诱饵存活计时由 SummonBase._physics_process 自持，
## 本 tick 只做调虎维护。
func _physics_process(_delta: float) -> void:
	tick(Engine.get_physics_frames())


## 留影诱饵实体（SummonBase 友方实体先例）：PLAYER 阵营战斗体，敌方弹可击毁，
## 我方结算天然不误伤。brain_pos = EnemyBase 仇恨缝契约读数；is_alive() = 缝自证存活。
class MirageDecoyBody:
	extends SummonBase
	## EnemyBase.target_override 契约：权威位置（静态诱饵 = 部署点，每拍对齐）。
	var brain_pos := Vector2.ZERO

	func _tick_ai(_frame: int) -> void:
		brain_pos = global_position        # 静态诱饵：恒等于部署点

	## 仇恨缝存活自证：未退场且尚有 HP。
	func is_alive() -> bool:
		return not is_despawned() and hp > 0
