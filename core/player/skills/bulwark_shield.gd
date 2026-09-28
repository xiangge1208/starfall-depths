class_name BulwarkShield
extends SkillBase
## M5 T1 占位：铁卫·锚 主动技「架设」（附录 L §3）——数据行已落（data/heroes.json id=bulwark），
## 真实机制由 M5 技能卡（T3~T9）原地替换本文件内容（路径即最终路径，heroes.json 不改址）。
## 规格锚点：「架设」CD 12s/0蓝：架可破坏钢盾（HP 30，挡双方弹幕）
## 占位语义：框架 cast() 过门（CD + 耗蓝）后 _activate 为 no-op，仅 push_warning 留痕，
## 供 bot 冒烟/选角进局链路跑通（M5 计划 T1 卡「路径即最终路径」）。

## 技能中文名（heroes 行 skill_name 同值；HUD/后续实现取数兜底）。
const SKILL_NAME := "架设"

func _activate(_frame: int) -> void:
	push_warning("M5 placeholder: bulwark")
