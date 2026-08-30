extends "res://core/enemies/archetypes/heavy.gd"
## 石盾武僧（小 Boss，附录 B.3「正面格挡一切，需绕背或近战反弹破势」）：
## 继承重装逼近+正面减伤（行 front_block_pct=1.0 → 正面全格挡）。破势：
## 正面近战命中（source_type=="melee"）→ 武僧自晕 guard_break_stun_ticks（输出窗），
## 且 GUARD_DOWN_TICKS 内正面格挡失效（绕背之外的第二条破法：近战反弹）。
## 破势一击本身不落血（反弹换输出窗，不白给伤害）。
## 格挡失效经 _effective_block_pct 钩子落地（heavy 的 take_hit 直接消费，不重筛）。

const GUARD_DOWN_TICKS := 90     # 破势后正面失守 1.5s
const DEFAULT_BREAK_STUN := 36   # 0.6s 自晕

var _guard_down_until := -1

func _effective_block_pct(frame: int) -> float:
	if frame < _guard_down_until:
		return 0.0   # 破势窗：正面也全伤
	return float(row.get("front_block_pct", 0.0))

func take_hit(ctx: Dictionary) -> void:
	if state == State.DEAD:
		return
	var frame := int(ctx.get("frame", Engine.get_physics_frames()))
	if frame < _guard_down_until:
		super(ctx)   # 破势窗：直接走 heavy（其钩子已把减伤归零）
		return
	var from: Vector2 = ctx.get("from", brain_pos)
	var incoming := from - brain_pos
	var frontal := incoming.length_squared() > 0.0001 \
		and _facing.dot(incoming.normalized()) > 0.0
	if frontal and String(ctx.get("source_type", "")) == "melee":
		# 正面近战 → 破势：自晕输出窗 + 格挡失效窗；本击不落血。
		_guard_down_until = frame + GUARD_DOWN_TICKS
		stun_until = maxi(stun_until, frame + int(row.get("guard_break_stun_ticks", DEFAULT_BREAK_STUN)))
		Fx.on_enemy_hit(self, {"telegraph": true})
		return
	super(ctx)
