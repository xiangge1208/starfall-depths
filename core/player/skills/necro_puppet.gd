class_name NecroPuppet
extends SkillBase
## 死灵·骸 主动技「起傀」+ 被动「拾骨」（M5-T5，附录 L §3 第 11 行 + 强化行；
## heroes.json id=necro：780 拍/20 蓝，passive_id=bone_harvest）。
##
## 被动拾骨：击杀积骸能（EventBus.enemy_killed 订阅于 setup，ranger 鹰眼/烈击杀
## 返血先例；方法引用，free 时自动断连），+1/击杀、上限 10 具（BONE_CAP）。
## 骸能为技能实例状态（非玩家蓝量，独立资源条；bone_count() 供 HUD/测试读数），
## 满额后击杀不再积累；每次积累落遥测 bone_harvest。
##
## 主动起傀（CD 780t/20 蓝，数据行经 setup 覆写）：耗 4 骸能召 1 只骸骨傀儡
## （「每 4 具 1 只」= 单只转换价 4 骸能，单次施放召 1 只——头注钉死的字面读法），
## 在场傀儡 ≤2 只（MAX_PUPPETS，附录 L §3「≤2 只」）。傀儡实体 = PuppetSummon
## （core/summons/puppet.gd，turret.gd 友方部署先例：12 伤/8s 攻击节奏、12s 存活
## 后消散、不进波次计数、敌方可攻击可击杀；强化版死亡自爆 24 AoE）。
##
## 施放门（HUD 同步灰，同破釜守卫先例）：框架 CD/耗蓝门之上叠加骸能门
## （bone < 4 拒）与在场数门（≥2 拒）；任一门不过不烧 CD、不扣蓝、不耗骸能。
## player==null（占位冒烟无绑定装配）保持框架直通语义零漂移——test_heroes
## 占位冒烟契约（cast(0)==true）在替换占位后依旧成立。
##
## 满编语义议定（与炮台 FIFO 顶替分叉，头注披露）：骸能是稀缺资源，在场 ≥2 时
## 拒召不顶替（炮台顶替语义源于 GDD §6 库存口径，骸无该出处）；CD 780t > 存活
## 720t，自然施放节奏下满编实际不可达，门为规格字面守卫。
##
## 遥测：bone_harvest（击杀积累）/ puppet_summon（召出）/ puppet_burst（强化
## 自爆，落点在 PuppetSummon._self_destruct）——Telemetry 既有清单零撞名。
## sfx：puppet_summon（施放拍）/ puppet_burst（自爆拍，gen_placeholder_sfx 生成，
## test_audio_wiring 完备性 tripwire 自动覆盖新键）。

const SKILL_NAME := "起傀"          # 技能中文名（heroes 行 skill_name 同值）
const BONE_CAP := 10                # 拾骨：10 具满（附录 L §3）
const BONE_PER_PUPPET := 4          # 每 4 具 1 只（附录 L §3）
const MAX_PUPPETS := 2              # 在场 ≤2 只（附录 L §3）

var upgraded := false
var bone_energy := 0                # 骸能（0..BONE_CAP，技能实例状态）

func _init() -> void:
	cooldown_ticks = 780               # 13s（附录 L §3；数据行覆写）
	energy_cost = 20                   # 20 蓝（附录 L §3；数据行覆写）

func _load(data: Dictionary) -> void:
	super._load(data)                  # SkillBase 无字段装载；保留钩子链（同烈先例）
	upgraded = bool(data.get("upgraded", false))

func setup(p: Player, data: Dictionary) -> void:
	super.setup(p, data)
	if not EventBus.enemy_killed.is_connected(_on_enemy_killed):
		EventBus.enemy_killed.connect(_on_enemy_killed)   # 拾骨积累：free 时自动断连

## 骸能读数（HUD/测试用；0..BONE_CAP）。
func bone_count() -> int:
	return bone_energy

## 施放门：骸能门 + 在场数门叠加在框架 CD/耗蓝门之上（守卫先过，同破釜先例）；
## player==null 直通（占位冒烟契约）。在场数只数本技能傀儡（组内按类型过滤，
## 剔除已失效与已排定退场——turret.living_summons 同口径）。
func can_cast(frame: int) -> bool:
	if player != null:
		if bone_energy < BONE_PER_PUPPET or living_puppets().size() >= MAX_PUPPETS:
			return false
	return super.can_cast(frame)

## 施放生效：耗 4 骸能 → 部署傀儡（玩家脚下，挂房间 combat 作玩家阵营战斗体）。
func _activate(frame: int) -> void:
	if player == null or not player.is_inside_tree():
		return
	bone_energy -= BONE_PER_PUPPET
	_deploy(frame)
	AudioMgr.play("puppet_summon")     # m5-t5：起傀施放拍（过门后到此才响）
	Telemetry.log_row(["puppet_summon", frame, bone_energy, living_puppets().size()])

## 部署（turret._deploy 同构）：挂玩家父节点（房间/楼层根，坐标同层）；
## 无父兜底随玩家（纯逻辑环境）。强化位随行注入（自爆 24 AoE）。
func _deploy(frame: int) -> void:
	var puppet := PuppetSummon.new()
	var host := player.get_parent()
	if host != null:
		host.add_child(puppet)
		puppet.global_position = player.global_position
	else:
		player.add_child(puppet)
		puppet.position = Vector2.ZERO
	puppet.setup(PuppetSummon.default_row(upgraded))
	puppet.combat = player.combat
	puppet.player = player
	puppet.add_to_group("summons")
	puppet.begin(frame)
	if player.combat != null:
		player.combat.register_body(puppet, puppet.combat_faction())

## 存活傀儡（"summons" 组内 PuppetSummon 类型；剔除已失效与已排定退场）。
func living_puppets() -> Array[PuppetSummon]:
	var out: Array[PuppetSummon] = []
	if player == null or not player.is_inside_tree():
		return out
	for node in player.get_tree().get_nodes_in_group("summons"):
		var s := node as PuppetSummon
		if s != null and not s.is_despawned() and not s.is_queued_for_deletion():
			out.append(s)
	return out

## 拾骨：击杀 +1 骸能，上限 10（满额静默不再积累）；每次实际积累落遥测。
func _on_enemy_killed(_enemy_id: String) -> void:
	if player == null or bone_energy >= BONE_CAP:
		return
	bone_energy += 1
	Telemetry.log_row(["bone_harvest", Engine.get_physics_frames(), bone_energy, BONE_CAP])
