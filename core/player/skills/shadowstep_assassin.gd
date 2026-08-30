class_name ShadowstepAssassin
extends RangerShadowstep
## 刺客·蝉 主动技「残影斩」（M2-T13 计划卡 + GDD §6 刺客列）——影袭变体：
## 沿用 ranger 瞬步脚本（本类 = 最小参数化子类），差异 = 突进距离 220px（游侠 140px）。
## 距离经 heroes 行 dash_dist_px 附加键注入（基类 _load 读 HeroApplier meta "hero"
## 接缝，同 turret summon_cap 先例）；CD 480t（8s）经 skill_cd 既有 setup 通路覆写。
## 其余行为全部继承：无敌窗 15t/36t（升级）、4s 必暴 + 弹速 +20% 窗、单帧位移披露取舍。
## 口径披露：GDD §6 残影斩的「路径 2×30 伤害 / 击杀刷新冷却」不在本卡变体范围
## （计划卡决议：影袭变体参数差异化，非新技能）。
## 被动「掠影」（近战击杀返还 5 蓝 + 1s 内翻滚无冷却，passive_id=shadow_reap）
## 为后续卡接线，本卡不实现（同 spare_parts/blessing 先例）。

const ASSASSIN_DASH_DIST_PX := 220.0   # GDD §6 刺客列（基类 const 不可遮蔽，独立命名）

func _init() -> void:
	super._init()
	dash_dist_px = ASSASSIN_DASH_DIST_PX
	cooldown_ticks = 480            # 8s（GDD §6；生产数值以 heroes 行 skill_cd 覆写为准）
