class_name FollowAlly
extends SummonBase
## m5-f 佣兵跟随（局内临时同伴，M5 借鉴卡 #6）：事件房「佣兵」招募的远程援射随从。
##
## 数值：复用敌人花名册 crossbowman 行（弩兵 bullet_dmg 3 / bullet_speed 110 /
## bullet_life 2.5s / bullet_radius 3 / speed 60 / radius 6，GameDB.get_enemy 只读拷贝，
## 不污染共享缓存），攻击节拍 = 行 cd_ticks（1.8s 含其 windup——友军不播敌侧红闪
## telegraph，直接按整周期出弹）。
## 行为：跟随玩家保持 FOLLOW_MIN~MAX_PX（60~90px）距离带 + 索敌最近 240px 内敌人
## （"enemies" 组扫描 + AutoAim.pick_target 全向，同 TurretSummon 习语），弹幕走
## Projectile.Faction.PLAYER 阵营经房间 CombatSystem 结算（与武器弹同通路、可暴击）。
##
## ★ 无敌简化（规格明示，双重披露=头注+提交体）：友军不实现 HP——take_hit 恒 no-op，
## 平衡完全靠 90s 存活时限。战斗体注册为 PLAYER 阵营的既有语义是「己方弹穿透
## （不误伤）/敌方弹命中（faction 异侧）」，故敌方直射弹会被友军身体拦截但零伤害——
## 该拦截属可接受增益，随 90s 时限自愈，非永久护墙。
##
## 存活/退场（复用 SummonBase 框架）：90s（LIFETIME_TICKS）超时 despawn("expired")、
## 玩家死亡（EventBus.player_damaged fatal=true）despawn("player_dead")、重复招募
## despawn("replaced")——场上至多 1 名采用【替换】语义（规格二选一披露）：新体照常
## 部署，旧体提前退场。换层自然消亡（挂玩家父节点随场景释放）。
##
## 组纪律：绝不进 "enemies" 组（否则被己方 AoE/索敌当敌人打）；也不进 "summons" 组
## （不污染工程师炮台 summon_cap 库存计数）——独立 "follow_ally" 组，跨房 combat
## 重接由 FloorScene 房间接线的同款扫描完成（事件房/商店房无 CombatSystem，保留
## 上一战斗房引用无判定后果：别房弹打不到本房注册体，下一战斗房重接自愈）。
## 帧注入直驱（tick(frame)，同 test_summons 风格）可无头测，不经墙钟。

const LIFETIME_TICKS := 5400    # 90s × 60fps（TimeConst.ticks(90.0)，const 不吃静态调用）
const FOLLOW_MIN_PX := 60.0     # 跟随距离带下沿（规格）
const FOLLOW_MAX_PX := 90.0     # 跟随距离带上沿（规格）
const TARGET_RANGE_PX := 240.0  # 索敌半径（规格，同炮台口径）
const GROUP := "follow_ally"
const SOURCE_ID := "follow_ally"
const SOURCE_NAME := "佣兵弩手"
const ATTACK_NAME := "援射"
const DEFAULT_CD_TICKS := 108   # crossbowman 行 cd_ticks 缺省
const DEFAULT_SPEED := 60.0     # crossbowman 行 speed 缺省
# GameDB 缺 crossbowman 行时的兜底（与 data/enemies.json 同值，防数据卡改动击穿本卡）
const FALLBACK_ROW := {
	"id": "crossbowman", "hp": 16, "speed": 60, "radius": 6.0,
	"cd_ticks": 108, "bullet_dmg": 3, "bullet_speed": 110,
	"bullet_life_seconds": 2.5, "bullet_radius": 3.0,
}

var brain_pos := Vector2.ZERO    # 权威位置（同 EnemyBase 口径；无碰撞体，直接回写 position）
var _fire_wait := 0              # 距下次开火剩余拍（deploy 后首拍整周期，不开火）

## 部署行：花名册 crossbowman 行拷贝 + 友军 id/存活时限（只读，不污染 GameDB 缓存）。
static func follower_row() -> Dictionary:
	var row: Dictionary = GameDB.get_enemy("crossbowman").duplicate(true)
	if row.is_empty():
		row = FALLBACK_ROW.duplicate(true)
	row["id"] = SOURCE_ID
	row["lifetime_ticks"] = LIFETIME_TICKS
	return row

## 统一招募入口（EventRoom.summon_follower 接缝 / 测试直呼）：至多 1 名=替换语义——
## 扫组退旧体（despawn 队列体按存活口径过滤，同 EngineerTurret.living_summons），
## 新体挂 host（生产=玩家父节点，跨房存活于本层）、注册 PLAYER 阵营战斗体后起拍。
## host/player 缺席 fail-closed 返回 null（不产生半成品节点）。
static func deploy(host: Node, player: Node2D, combat, frame: int) -> FollowAlly:
	if host == null or player == null:
		return null
	if host.is_inside_tree():
		for node in host.get_tree().get_nodes_in_group(GROUP):
			var old := node as FollowAlly
			if old != null and not old.is_despawned() and not old.is_queued_for_deletion():
				old.despawn("replaced")
	var ally := FollowAlly.new()
	host.add_child(ally)
	ally.global_position = player.global_position
	ally.setup(follower_row())
	ally.combat = combat
	ally.player = player
	ally.brain_pos = ally.global_position
	ally.add_to_group(GROUP)
	ally.begin(frame)
	if combat != null:
		combat.register_body(ally, ally.combat_faction())   # PLAYER 阵营（无敌披露见头注）
	return ally

## 占位视觉（友军蓝色块 + 弩身，同 TurretSummon 回落习语；正式贴图归美术卡）。
func _ready() -> void:
	var body := Polygon2D.new()
	body.name = "Visual"
	body.polygon = PackedVector2Array([
		Vector2(-5, -5), Vector2(5, -5), Vector2(5, 5), Vector2(-5, 5),
	])
	body.color = Color(0.35, 0.6, 0.95)          # 友军蓝（敌方红闪/中立棕对照）
	add_child(body)
	EventBus.player_damaged.connect(_on_player_damaged)

func _on_deploy(frame: int) -> void:
	_fire_wait = _fire_interval()                  # 部署拍起整周期（首拍不开火，同炮台）

## 每拍：跟随走位 + 开火节拍（生产由 SummonBase._physics_process 自驱；测试注入帧直驱）。
func _tick_ai(frame: int) -> void:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		despawn("player_gone")                     # 召唤主失效兜底（正常走 fatal 信号路径）
		return
	_follow_step()
	position = brain_pos
	_fire_wait = maxi(_fire_wait - 1, 0)
	if _fire_wait > 0:
		return
	_fire_wait = _fire_interval()
	var target := _acquire_target()
	if target != null:
		_fire_at(target)

## 距离带保持（同 shooter 走位习语的对称版）：太近后撤、太远贴近、带内停步。
func _follow_step() -> void:
	var to_player := player.global_position - brain_pos
	var dist := to_player.length()
	if dist <= FOLLOW_MAX_PX and dist >= FOLLOW_MIN_PX:
		return
	if to_player == Vector2.ZERO:
		return                                     # 同位方向未定义（生产中玩家必移动，自愈）
	var step := float(row.get("speed", DEFAULT_SPEED)) / TimeConst.FPS
	if dist < FOLLOW_MIN_PX:
		brain_pos -= to_player.normalized() * step
	else:
		brain_pos += to_player.normalized() * step

## 索敌：240px 内最近存活敌人（"enemies" 组扫描 + AutoAim 全向；友军自身不在该组）。
func _acquire_target() -> EnemyBase:
	if not is_inside_tree():
		return null
	var candidates: Array[Vector2] = []
	var enemies: Array[EnemyBase] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as EnemyBase
		if e == null or e.state == EnemyBase.State.DEAD:
			continue
		if e.brain_pos.distance_to(brain_pos) > TARGET_RANGE_PX:
			continue
		enemies.append(e)
		candidates.append(e.brain_pos)
	if candidates.is_empty():
		return null
	var idx := AutoAim.pick_target(brain_pos, 0.0, candidates, 360.0)
	return enemies[idx] if idx >= 0 else null

## 援射弹：玩家阵营经房间 CombatSystem（命中/暴击/元素与武器弹同通路，不另起 RNG）。
## 数值读花名册行（bullet_speed/bullet_dmg/bullet_life_seconds/bullet_radius）。
func _fire_at(target: EnemyBase) -> void:
	if combat == null or not is_instance_valid(combat):
		return
	var dir := (target.brain_pos - brain_pos).normalized()
	combat.spawn_projectile({
		"pos": brain_pos, "vel": dir * float(row.get("bullet_speed", 110.0)),
		"damage": int(row.get("bullet_dmg", 3)), "faction": Projectile.Faction.PLAYER,
		"element": Elements.Id.NONE, "pierce": 0, "bounce": 0,
		"life_seconds": float(row.get("bullet_life_seconds", 2.5)),
		"radius": float(row.get("bullet_radius", 3.0)),
		"source_type": "summon", "source_id": SOURCE_ID,
		"source_name": SOURCE_NAME, "attack_name": ATTACK_NAME,
	})

func _fire_interval() -> int:
	return maxi(int(row.get("cd_ticks", DEFAULT_CD_TICKS)), 1)

## ★ 无敌简化（规格明示，与头注双重披露）：不实现 HP——任何来源 take_hit 恒 no-op。
## 敌方弹命中本体的既有结算语义 = 弹被身体拦截消耗（无穿透时）+ 零伤害。
func take_hit(_ctx: Dictionary) -> void:
	pass                                          # 无敌：平衡靠 LIFETIME_TICKS 时限

## 玩家死亡即消散（EventBus 单点信号；fatal 已含复活/图腾后的最终判定）。
func _on_player_damaged(_amount: int, fatal: bool) -> void:
	if fatal:
		despawn("player_dead")

func despawn(reason: String) -> void:
	if not _despawned and EventBus.player_damaged.is_connected(_on_player_damaged):
		EventBus.player_damaged.disconnect(_on_player_damaged)
	super.despawn(reason)
