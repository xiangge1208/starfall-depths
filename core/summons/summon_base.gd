class_name SummonBase
extends Node2D
## 召唤物框架基类（M2-T8 B-1）：工程师炮台及后续召唤（法师/守护者系）共用骨架。
## 契约（计划卡 Task 8）：
## - setup(row)：数值行注入（id/hp/lifetime_ticks 及子类自有键），同 EnemyBase.setup 习语；
## - begin(frame)：部署锚定——记录部署帧并起存活计时（生产/测试同一入口，帧注入可无头测）；
## - combat 注入：挂所在房间 RoomCombat/FloorScene 的 CombatSystem 引用
##   （duck-typed 接缝同 ShieldSpirit；引用失效/房间被释放时静默失效，等超时清理）；
## - player 注入：召唤主玩家引用（框架接缝；索敌以召唤物自身为中心，子类按需消费）；
## - 生命/存活计时：tick(frame) 先判超时，再交子类 _tick_ai；
## - 死亡/超时统一走 despawn(reason)：注销战斗体 + despawned 信号 + Telemetry 统计行
##   + queue_free（不 free 场景节点，同敌人退场习语）。

signal despawned(reason: String)

var row: Dictionary = {}
var id := ""
var hp := 1
var hp_max := 1
var lifetime_ticks := 0            # 0 = 无存活计时（子类自管退场）
var combat = null                  # 房间 CombatSystem（duck-typed，部署方注入）
var player: Node2D = null          # 召唤主玩家引用（部署方注入）
var _deploy_frame := -1
var _expire_frame := -1
var _despawned := false

## 数值行装配：键缺省时保留子类/本类默认（row 可为空 Dictionary 仅占位）。
func setup(r: Dictionary) -> void:
	row = r
	id = String(r.get("id", "summon"))
	hp = maxi(1, int(r.get("hp", 1)))
	hp_max = hp
	lifetime_ticks = maxi(0, int(r.get("lifetime_ticks", 0)))

## 部署锚定：以部署帧起存活计时与子类节拍（须在 setup 后、入树后调用）。
func begin(frame: int) -> void:
	_deploy_frame = frame
	_expire_frame = frame + lifetime_ticks if lifetime_ticks > 0 else -1
	_on_deploy(frame)

## 子类部署钩子：起射击/导弹等节拍时钟。
func _on_deploy(_frame: int) -> void:
	pass

## 每拍推进：生产侧由 _physics_process 自驱；测试可注入任意帧直驱。
func tick(frame: int) -> void:
	if _despawned:
		return
	if _expire_frame >= 0 and frame >= _expire_frame:
		despawn("expired")
		return
	_tick_ai(frame)

## 子类行为钩子（索敌/开火等；超时判定已由基类持有）。
func _tick_ai(_frame: int) -> void:
	pass

## 战斗体接缝（CombatSystem 命中结算）：玩家阵营，可被敌方弹幕击毁。
func take_hit(ctx: Dictionary) -> void:
	if _despawned:
		return
	hp -= maxi(0, int(ctx.get("amount", 0)))
	if hp <= 0:
		despawn("destroyed")

func combat_radius() -> float:
	return float(row.get("radius", 6.0))

func combat_faction() -> int:
	return Projectile.Faction.PLAYER

func is_despawned() -> bool:
	return _despawned

## 统一退场：幂等；注销战斗体 → despawned 信号（HUD/上层可挂）→ 遥测统计行 → queue_free。
func despawn(reason: String) -> void:
	if _despawned:
		return
	_despawned = true
	if combat != null and is_instance_valid(combat) and combat.has_method("unregister_body"):
		combat.unregister_body(self)
	despawned.emit(reason)
	Telemetry.log_row(["summon_end", Engine.get_physics_frames(), id, reason])
	queue_free()

func _physics_process(_delta: float) -> void:
	tick(Engine.get_physics_frames())
