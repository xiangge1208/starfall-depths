class_name BossBase
extends EnemyBase
## Boss 三阶段框架（GDD §15）：行数据 "phases":[1.0,0.6,0.3]（血量分数，降序）解析为绝对血线；
## 血量下跨线 → 阶段只进不退 + 72t 转换无敌窗 + EventBus.boss_phase 广播 + _on_phase_enter 钩子。
## 子类照常写 _engage(frame)，按 phase() 分支；_on_engage_start 钩子原样继承。

const PHASE_INVULN_TICKS := 72   # 1.2s 阶段转换无敌窗

var _phase := 0
var _phase_thresholds: Array[int] = []   # 绝对血量线（floor(row.hp × 分数)），下标即阶段
var _phase_invuln_until := -1

func _test_init(r: Dictionary) -> void:
	super(r)          # 基类初始化（BossBase/子类脚本不触发原型换装，无实例重绑问题）
	_parse_phases(r)

## 行内血量分数 → 绝对血线（向下取整）。无 "phases" 行退化为单阶段 [hp]（框架对普通行安全）。
func _parse_phases(r: Dictionary) -> void:
	_phase = 0
	_phase_invuln_until = -1
	_phase_thresholds.clear()
	var total := float(r.get("hp", 10))
	for frac in r.get("phases", [1.0]):
		_phase_thresholds.append(int(floor(float(frac) * total)))

func phase() -> int:
	return _phase

## hp 所在阶段：从最深血线往回找第一条 hp<=线 的下标；均不满足（满血以上）为 0。
func _phase_for_hp(hp_value: int) -> int:
	for i in range(_phase_thresholds.size() - 1, -1, -1):
		if hp_value <= _phase_thresholds[i]:
			return i
	return 0

func take_hit(ctx: Dictionary) -> void:
	_take_hit_at(ctx, Engine.get_physics_frames())

## 可注入帧接缝（同 player.take_hit_ctx 模式）：阶段无敌窗按物理帧判定，headless 测试可注入帧。
## 基类 take_hit 的伤害体在此复写并在扣血后、死亡判定前插入血线检查——
## super(ctx) 无法在「死亡判定」前落钩，故不经 super（EnemyBase.take_hit 体小且稳定）。
func _take_hit_at(ctx: Dictionary, frame: int) -> void:
	if state == State.DEAD:
		return
	if frame < _phase_invuln_until:
		return   # 阶段转换无敌窗：不掉血、不闪白（死亡亦不可经此窗达成——门在扣血前返回）
	hp -= int(ctx["amount"])
	_advance_phase_if_crossed(frame)
	Fx.on_enemy_hit(self, ctx)
	if status != null:
		status.apply_hit(int(ctx.get("element", 0)), int(ctx["amount"]), frame)
	if hp <= 0:
		die()

## 血线下跨线 → 推进阶段（只进不退，hp 回升/零伤天然不触发）、开无敌窗、广播、进钩子。
func _advance_phase_if_crossed(frame: int) -> void:
	var p := _phase_for_hp(hp)
	if p <= _phase:
		return
	_phase = p
	_phase_invuln_until = frame + PHASE_INVULN_TICKS
	EventBus.boss_phase.emit(self, _phase)
	_on_phase_enter(_phase)

## 阶段进入钩子：子类覆写（换弹幕/位移模式等）；基类无操作。
func _on_phase_enter(_phase_idx: int) -> void:
	pass
