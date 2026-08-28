class_name SkillBase
extends Node
## 技能框架基类（M1 t2）。player.tscn 恒挂一个本脚本 Skill 节点；
## 具体技能脚本由角色数据在局开始时注入（Task 11 hero data）。
## 帧注入风格与 M0 一致：can_cast/cast/tick/cooldown_remaining 全部显式收 frame，可无头测试。

var player: Player = null
var skill_id := ""
var cooldown_ticks := 0
var energy_cost := 0
var _cd_until := -1

## 装配：player 绑定 + 数值按技能数据行覆写（未给则用子类 _init 默认）。
func setup(p: Player, data: Dictionary) -> void:
	player = p
	skill_id = String(data.get("id", ""))
	cooldown_ticks = int(data.get("cooldown_ticks", cooldown_ticks))
	energy_cost = int(data.get("energy_cost", energy_cost))
	_load(data)

## 子类钩子：装载技能特有数据（如 VanguardRampage 的 "upgraded"）。
func _load(_data: Dictionary) -> void:
	pass

func can_cast(frame: int) -> bool:
	return frame >= _cd_until and (player == null or player.energy >= energy_cost)

## 施放：过门（CD + 耗蓝）→ 扣蓝 → 起 CD → 生效。返回是否成功。
func cast(frame: int) -> bool:
	if not can_cast(frame):
		return false
	if player != null:
		player.energy -= energy_cost
	_cd_until = frame + cooldown_ticks
	_activate(frame)
	return true

## 子类钩子：施放生效（写状态窗/发事件等）。
func _activate(_frame: int) -> void:
	pass

## 每拍推进（子类按需覆写；框架默认无操作）。
func tick(_frame: int) -> void:
	pass

## HUD 用：距可再次施放还剩多少拍。
func cooldown_remaining(frame: int) -> int:
	return maxi(0, _cd_until - frame)
