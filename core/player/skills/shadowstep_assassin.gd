class_name ShadowstepAssassin
extends RangerShadowstep
## 刺客·蝉 主动技「残影斩」（M2-T13 计划卡 + GDD §6 刺客列）——影袭变体：
## 沿用 ranger 瞬步脚本（本类 = 最小参数化子类），差异 = 突进距离 220px（游侠 140px）。
## 距离经 heroes 行 dash_dist_px 附加键注入（基类 _load 读 HeroApplier meta "hero"
## 接缝，同 turret summon_cap 先例）；CD 480t（8s）经 skill_cd 既有 setup 通路覆写。
## 其余行为全部继承：无敌窗 15t/36t（升级）、4s 必暴 + 弹速 +20% 窗、单帧位移披露取舍。
## 口径披露：GDD §6 残影斩的「路径 2×30 伤害 / 击杀刷新冷却」不在本卡变体范围
## （计划卡决议：影袭变体参数差异化，非新技能）。
## 被动「掠影」（近战击杀返还 5 蓝 + 1s 内翻滚无冷却，passive_id=shadow_reap，
## m4-c2 接线）：消费点 = melee.gd 击杀上报 → player.on_melee_kill（返蓝 + 60t 翻滚
## 免冷却窗，roll_ready_at 门控）。

const ASSASSIN_DASH_DIST_PX := 220.0   # GDD §6 刺客列（基类 const 不可遮蔽，独立命名）

# ---- m5-d 强化分支（GDD §6 刺客列「强化」：突进终点留下残影，0.5s 后爆炸 20 伤害）----
const AFTERIMAGE_FUSE_TICKS := 30      # 0.5s
const AFTERIMAGE_DMG := 20
const AFTERIMAGE_RADIUS_PX := 80.0     # 奥术新星 120 的刺客变体缩档（计划卡 m5-d 披露）

# upgraded 字段继承自 RangerShadowstep（_load 装载，基类无敌 36t 分支同源生效）
var _afterimage_pos := Vector2.ZERO
var _afterimage_boom_frame := -1

func _init() -> void:
	super._init()
	dash_dist_px = ASSASSIN_DASH_DIST_PX
	cooldown_ticks = 480            # 8s（GDD §6；生产数值以 heroes 行 skill_cd 覆写为准）

## 强化版：突进终点落残影，AFTERIMAGE_FUSE_TICKS 后爆炸（AoE 20 / 80px）。
## 驱动 = 技能节点自身 _physics_process（life_tide 习语；tick() 空钩子无调用方）。
## 测试可绕墙钟直驱 _detonate_afterimage(frame)。
func _activate(frame: int) -> void:
	super._activate(frame)
	if upgraded and player != null:
		_afterimage_pos = player.global_position
		_afterimage_boom_frame = frame + AFTERIMAGE_FUSE_TICKS

func _physics_process(_delta: float) -> void:
	if _afterimage_boom_frame >= 0 and Engine.get_physics_frames() >= _afterimage_boom_frame:
		_detonate_afterimage(Engine.get_physics_frames())

## 残影爆炸本体：enemies 组遍历 + take_hit（奥术新星同通路；技能伤不掷暴击）。
## 爆炸一次即清窗（_afterimage_boom_frame 复位 -1）。返回命中数（测试观察口）。
func _detonate_afterimage(frame: int) -> int:
	_afterimage_boom_frame = -1
	if player == null or not player.is_inside_tree():
		return 0
	var hit := 0
	for node in player.get_tree().get_nodes_in_group("enemies"):
		var e := node as EnemyBase
		if e == null or e.state == EnemyBase.State.DEAD:
			continue
		if e.brain_pos.distance_to(_afterimage_pos) > AFTERIMAGE_RADIUS_PX:
			continue
		e.take_hit({
			"amount": AFTERIMAGE_DMG, "is_crit": false, "element": Elements.Id.NONE,
			"from": _afterimage_pos, "frame": frame, "source_type": "skill",
			"source_id": "shadowstep_assassin", "source_name": "残影",
			"attack_name": "残影爆炸", "player_damage": true,
		})
		hit += 1
	if hit > 0:
		AudioMgr.play_once("nova")     # 复用新星爆发拍（完备性 tripwire 键已存在）
	return hit
