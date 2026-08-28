class_name VanguardRampage
extends SkillBase
## 骑士·凛 主动技「狂潮」（GDD §6）：CD 840t（14s）、持续 480t（8s）。
## 施放 → 武器架 dual_wield_until = frame + 480：期间 try_fire 双武器齐射且免蓝耗。
## 升级版（data["upgraded"]）：持续期内玩家受伤 -30%（经 player.rampage_active_until 查询）。

const DURATION_TICKS := 480          # 8s

var upgraded := false

func _init() -> void:
	cooldown_ticks = 840               # 14s（GDD §6；数据行可覆写）

func _load(data: Dictionary) -> void:
	upgraded = bool(data.get("upgraded", false))

func _activate(frame: int) -> void:
	if player == null:
		return
	if player.weapon_rig != null:
		player.weapon_rig.dual_wield_until = frame + DURATION_TICKS
	if upgraded:
		player.rampage_active_until = frame + DURATION_TICKS   # 仅升级版写减伤窗（非升级无减伤）
