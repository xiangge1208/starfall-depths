extends Node2D
## 局根节点（m1-t27 最终整合卡）：一局的跨层宿主，M1 主循环的装配点。
##
## 职责链（本卡四处死缝的第 1/4 缝）：
##   选角承接：RunState.select_hero（T11 选角卡守卫调用）已开局（种子激活）；
##   本节点 _ready 读 RunState.hero_id（空则 HeroSelect.last_chosen，再空则首英雄）
##   → HeroApplier.apply 装配玩家（面板/初始武器/技能换装）→ 按 RunState.run_seed
##   构建 FloorScene（DungeonBuilder.build(seed, RunState.floor_idx)）。
##   跨层常驻：监听 FloorScene.boss_defeated（本卡新增）→ 嵌入 inter_floor.tscn
##   （三选一→喷泉→门）；inter_floor 的 next_floor_requested(new_floor) → 释放旧层
##   → 按新层号重建（RunState.next_floor() 已由 InterFloorFlow.enter_next_floor()
##   调用并结算蓝晶——本节点只消费 RunState.floor_idx / new_floor，不重复推层）。
##   层数数据门：M1 仅交付 A1 完整模板。A1 门推进到 floor_idx=2 时进入一个真实的
##   A2 入口/里程碑场景（玩家实例、HUD 与第 2 层种子语义均已切换），但不扩做 A2
##   战斗内容；第 3 层 Boss 后 InterFloorFlow 发 victory_achieved → 本节点经
##   SceneRouter 切胜利结算场景（m2-t18 接入，VictorySummary 全屏面板）。
##   死亡：DeathRecorder autoload 全局接管——本节点经 SceneRouter 路由为前台场景
##   （res://core/rooms/ 非工具区），致命伤直接 goto("death")，整棵（含本节点/
##   FloorScene/层间）随换场景干净释放，DeathSummary 确认后回主菜单。
##
## 种子口径（披露）：DungeonBuilder.build(seed, floor_idx) 内部走
## RngSvc.setup_run(seed)+stream(floor_idx,"dungeon")——直接传 RunState.run_seed
## （start_run 已写 RngSvc.run_seed 同值，幂等）；各盐流派生链含 floor_idx，
## 跨层构建不污染其它盐。RunState.run_seed 为任意 int64（可为负），
## RngSvc.stable_hash 按二补码位型运算，负种子安全。

const INTER_FLOOR_SCENE := preload("res://core/rooms/inter_floor.tscn")
const PLAYER_SCENE := preload("res://core/player/player.tscn")
const VICTORY_SCENE := "res://ui/victory_summary.tscn"   # m2-t18：胜利结算场景（SceneRouter 路由键同步注册）

const A2_ENTRY_FLOOR := 2
const OVERLAY_TEXT := "已进入第 2 层 · 晶核洞穴入口"
## m4p-w2c W2-c4c 文案勘误：M2 起 A2 战斗内容已接入（层间门真建第 2 层），
## 里程碑浮层提示不再是「M1 垂直切片完成（A2 战斗内容将在 M2 接入）」过时语。
## 该浮层现仅为表外楼层的兜底里程碑（_floor_data_available 不放行时）。
const OVERLAY_HINT := "A2 晶核洞穴生态已接入"
## m2-t22：层数 → 生态 BGM 键（GDD §17 生态三曲；越界 clamp 到 A3）。
const FLOOR_MUSIC := ["garden", "crystal", "magma"]

var player: Player = null
var floor_scene: FloorScene = null
var inter_floor: Node2D = null
var buffs := BuffManager.new()             # 局内共享（跨层保留已取增益，T20 契约）
## m2-t35：局内天赋系统（T15 永久 meta）。默认 _begin 时经 /root/SaveSystem 构造
## （测试可在 _begin 前注入替身密封真实档——裁定㉔ df9691a 同源先例）。
## 固定落地顺序 Hero→Buffs→Talents：开局首拍 talents.apply_to_player 恰一次；此后
## 每拍 buff 重 apply（层重建 floor setup / 层间三选一）后走 player.
## repair_talent_absolute_keys 成对修补——T15 披露的六键绝对写覆盖缝
## （crit/暴伤/异常/盾延时/roll_cd/附魔概率）由此收口。
## 披露：本字段不随 _reset_runtime_for_new_run 重建——生产路径每局都是全新 RunRoot
## （SceneRouter 换场景）自然重读已购；同实例跨局复用（仅测试）保留已购快照。
var talents: TalentSystem = null
## 胜利路由接缝（m2-t18 测试注入口）：有效时替代真实场景切换（同 DeathRecorder
## open_summary_override 模式——gdUnit 前台非游戏场景，真跳会把面板漏成孤儿节点）。
var victory_route_override: Callable = Callable()
var _overlay: CanvasLayer = null
var _a2_entry: Node2D = null
var _facility_run_seed := 0
var _floor_entry_max := 0                  # m4-c2：层入口被动去重（已触发过的最大层号；0=尚未进层）
var _drink_states: Dictionary = {}         # floor_idx -> {uses_left}; 同层重建不补次数
var _used_shrine_kinds: Dictionary = {}    # 四类雕像整局一次
var _talents_applied := false              # m2-t35：开局 talents.apply 恰一次；此后 wipe→repair

## 测试/嵌入缝：_ready 仅在「当前活动场景」时自举（同 FloorScene/InterFloor 约定）；
## 测试挂为子节点后直调 _begin()。
func _ready() -> void:
	if get_tree() != null and get_tree().current_scene == self:
		_begin()


## 生产入口：开局种子守卫 → 英雄装配 → 首层构建。
func _begin() -> void:
	if RunState.run_seed == 0 or RunState.hero_id.is_empty():
		var hero := HeroSelect.last_chosen
		if hero.is_empty() and not GameDB.heroes.is_empty():
			hero = String(GameDB.heroes.keys()[0])
		if hero.is_empty():
			hero = "vanguard"              # 兜底（GameDB 空表的极端防御）
		RunState.start_run(hero)
	# 同一个 RunRoot 被测试/重开流程复用时，新 run_seed 必须代表一套全新的
	# 运行时对象；只清设施字典会让旧玩家身上的 Buff、饮料、雕像临时效果、
	# 武器附魔与旧 BuffManager 基线跨局泄漏。正常换场景会创建新根节点，
	# 此守卫在生产路径仍保持幂等。
	if _facility_run_seed != RunState.run_seed:
		_facility_run_seed = RunState.run_seed
		_reset_runtime_for_new_run()
	_ensure_talents()                      # m2-t35：天赋系统就绪（注入优先，缺省读档）
	DeathRecorder.reset()                  # T22 建议的开局复位（清致死窗/遥测会话）
	AchievementSystem.reset_session()      # m2-t33 补线：成就单局口径同点清零（K.1/K.4）
	if player == null:
		# m4p-w2c W2-c4a：武器镜像快照须先于 _spawn_hero_player——HeroApplier 的初始
		# 武器 equip 会经 WeaponRig→RunState 同步覆写 weapons 镜像（镜像与 rig 实态
		# 双向耦合，record_weapon 聚合）；增益账面无此耦合，直接在恢复缝内读。
		var weapon_mirror: Array[String] = []
		for wid: String in RunState.weapons:
			weapon_mirror.append(wid)
		var weapon_slot := RunState.selected_slot
		_spawn_hero_player()
		_restore_run_build(weapon_mirror, weapon_slot)   # 重开（同 run 重载）→ 记账构筑重放进新玩家实态
	_start_floor(RunState.floor_idx)   # m4-c2：层入口被动在 _start_floor 尾部（玩家落位后）触发


## m2-t35：天赋系统惰性构造（后端读真实档）；注入缝在 _begin 前仍然生效。
func _ensure_talents() -> void:
	if talents == null:
		talents = TalentSystem.new()


## 新局硬隔离：丢弃所有持有上一局运行时状态的对象，再由 _begin 重新装配英雄/楼层。
## 使用 immediate free 是因为 _begin 随后同拍就要创建同名玩家与新 FloorScene；若仅
## queue_free，旧节点会在本帧继续连着 EventBus，并与新节点短暂并存。
func _reset_runtime_for_new_run() -> void:
	for node: Node in [inter_floor, floor_scene, _overlay, _a2_entry, player]:
		if node != null and is_instance_valid(node):
			node.free()
	inter_floor = null
	floor_scene = null
	_overlay = null
	_a2_entry = null
	player = null
	buffs = BuffManager.new()
	_floor_entry_max = 0                     # m4-c2：新局层入口去重基线复位（开局首层可再触发）
	_drink_states.clear()
	_used_shrine_kinds.clear()
	_talents_applied = false


## 英雄装配（T11 HeroApplier 契约）：面板字段 + 初始武器 + 技能换装 + meta。
func _spawn_hero_player() -> void:
	var hero := GameDB.get_hero(RunState.hero_id)
	if hero.is_empty():
		push_error("RunRoot: unknown hero '%s'" % RunState.hero_id)
		return
	player = PLAYER_SCENE.instantiate() as Player
	add_child(player)                      # 先入树（@onready WeaponRig/Skill 就位再装配）
	var rig := player.get_node_or_null("WeaponRig") as WeaponRig
	if rig != null:
		player.weapon_rig = rig
		rig.bind_run_state(RunState)
	HeroApplier.apply(hero, player)


## m4p-w2c（W2-c4a）重开构筑恢复：暂停菜单「重开」= SceneRouter "game" 键重载
## run_root（RunState 层号/种子不变，金币/蓝晶/增益/武器/试炼因子层账保留，见
## ui/pause_menu.gd 路由口径）——玩家换新实例后 `_reset_runtime_for_new_run` 已把
## buffs 归零、HeroApplier 只装初始武器，账面 RunState 与玩家实态脱节。本缝在英雄
## 装配后、首层构建前把账面构筑重放进实态：
## - 增益：RunState.buffs 逐 id buffs_manager.pick（唯一项防重由 pick 内拒绝）+
##   apply_to_player/apply_to_rig（沿 floor_scene._apply_altar_buff 落地序）。不调
##   repair_talent_absolute_keys：重开路径 _talents_applied=false，_start_floor 的
##   talents.apply_to_player 首拍 own-delta 全量落地在本重放之后（可加键对外部写入
##   可逆），此处 repair 会与该首拍叠加成双份天赋六键。
## - 武器：weapon_mirror 为 _begin 在英雄装配前定格的 RunState.weapons 快照——它是
##   WeaponRig 双槽的槽位镜像（record_weapon 聚合，weapons[i] = rig.slots[i]，
##   [0]/[1] 为槽位而非「初始/拾取」语义）。恢复按「逐槽对账」落地：快照槽 id 与
##   当前 rig 槽不同才写（非空 → GameDB 行落槽，表外 id fail-soft 同清槽；空 → 清槽，
##   局内被丢弃的武器保持丢弃态），快照与实态一致的槽零改动。全新开局快照全空 →
##   恒等 no-op（HeroApplier 初始武器装配不被重放破坏）；重开 → 双槽/当前槽精确
##   还原。WeaponRig「设施禁直写 slots」的约定针对获取路径（防聚合滞后）——本恢复
##   路径直写后立即 bind_run_state 重同步，不变量当场重建。
func _restore_run_build(weapon_mirror: Array[String], weapon_slot: int) -> void:
	if player == null:
		return
	for id: String in RunState.buffs:
		buffs.pick(id)
	if not buffs.picked.is_empty():
		buffs.apply_to_player(player)
		if player.weapon_rig != null:
			buffs.apply_to_rig(player.weapon_rig)
	var rig := player.get_node_or_null("WeaponRig") as WeaponRig
	if rig != null:
		if rig.slots.size() < 2:
			rig.slots.resize(2)
		# 快照全空 = 全新开局（局内槽 0 恒非空：无卸下主手的路径，拾取只替换不清空）
		# → 恒等 no-op，HeroApplier 初始武器装配不被重放破坏。
		var has_build := false
		for wid: String in weapon_mirror:
			if not wid.is_empty():
				has_build = true
				break
		if has_build:
			for i in 2:
				var want := weapon_mirror[i] if i < weapon_mirror.size() else ""
				if want.is_empty():
					if not rig.slots[i].is_empty():
						rig.slots[i] = {}
				elif String(rig.slots[i].get("id", "")) != want:
					rig.slots[i] = GameDB.get_weapon(want)
			if weapon_slot >= 0 and weapon_slot < rig.slots.size() \
					and not rig.slots[weapon_slot].is_empty():
				rig.slot = weapon_slot         # 状态恢复直写（非游戏切换路径，无锁定窗语义）
			rig.bind_run_state(RunState)       # selected_slot/武器镜像幂等回写（不变量重建）


## 构建一层：旧层释放 → DungeonBuilder（RunState.run_seed, floor_idx）→ FloorScene 接线。
func _start_floor(idx: int) -> void:
	if floor_scene != null and is_instance_valid(floor_scene):
		floor_scene.queue_free()
	AudioMgr.play_music(FLOOR_MUSIC[clampi(idx - 1, 0, FLOOR_MUSIC.size() - 1)])   # m2-t22：生态曲 1→garden 2→crystal 3→magma
	var build := DungeonBuilder.build(RunState.run_seed, idx)
	floor_scene = FloorScene.new()
	floor_scene.floor_idx = idx
	if not _drink_states.has(idx):
		_drink_states[idx] = {"uses_left": DrinkMachine.USES_PER_FLOOR}
	floor_scene.bind_facility_state(_drink_states[idx], _used_shrine_kinds)
	add_child(floor_scene)
	floor_scene.boss_defeated.connect(_on_boss_defeated)
	floor_scene.setup(build, player, buffs) # 玩家有父（RunRoot）→ 不被收养，落位 start
	# m2-t35 ③：固定顺序 Hero→Buffs→Talents。开场首拍 talents.apply_to_player（own-delta
	# 落地全量天赋）；此后每拍层重建 floor setup 内 buff 重 apply 会绝对写覆盖六键
	# （crit/暴伤/异常/盾延时/roll_cd/附魔概率）→ 走 player.repair_talent_absolute_keys
	# 成对修补（wipe→repair 不叠加）。
	if talents != null and player != null:
		if not _talents_applied:
			talents.apply_to_player(player)
			_talents_applied = true
		else:
			player.repair_talent_absolute_keys()
	# m4-c2：层入口被动（blessing 回盾叠层 / spare_parts 补台）。置于玩家落位
	# （floor_scene.setup → _place_player_at_start）之后：备件台落在开局/新层玩家
	# 实际站位，而非旧层坐标（跨层重建会整体搬运房间几何，落位前部署会搁浅在
	# 旧坐标、240px 索敌够不到新层怪——实测语义等价于没有这台台子）。
	_apply_floor_entry_passives(idx)


## m4-c2 英雄被动层入口钩子（GDD §6）：blessing（守护者）= 回满护盾 + 5% 全伤害叠层；
## spare_parts（工程师）= 开局/每进入新一层补 1 台便携炮台（与主动技共用库存上限 2，
## 语义经 EngineerTurret.deploy_spare_parts 统一通路）。frame 参数为测试注入缝，
## <0 时取当前物理帧（生产路径）。非三被动英雄为恒等 no-op。
## 「每进入新层」按层号去重（_floor_entry_max 单调记录已触发层）：同层重复触发
## （层间重入/测试复用根节点）不重复叠层、不重复补台；护盾回满幂等、每次入口都执行。
func _apply_floor_entry_passives(new_floor: int, frame: int = -1) -> void:
	if player == null or not is_instance_valid(player):
		return
	if frame < 0:
		frame = Engine.get_physics_frames()
	var is_new_entry := new_floor > _floor_entry_max
	if is_new_entry:
		_floor_entry_max = new_floor
	if player.passive_id == "blessing":
		_apply_blessing_floor_entry(new_floor, is_new_entry)
	elif player.passive_id == "spare_parts" and is_new_entry:
		_apply_spare_parts_floor_entry(frame)


## 祝福（守护者被动，GDD §6「每进入新层回满护盾并 +5% 全伤害（单局至多叠 4 层）」）。
## 保守读法（任务卡钉死）：首层开局不叠层；「每进入新层」= 进入第 2 层起每层 +1，
## 至多 4 层（+20%，第 5 层起封顶）。叠层持久整个单局（跨层不清；新局随玩家实例重建归零）。
## 护盾回满对首层开局幂等（HeroApplier 装配即满值）。
func _apply_blessing_floor_entry(new_floor: int, is_new_entry: bool) -> void:
	if is_new_entry and new_floor >= 2:
		player.blessing_stacks = mini(player.blessing_stacks + 1, Player.BLESSING_STACK_CAP)
	player.shield = player.shield_max


## 备件（工程师被动，GDD §6「开局带 1 台便携炮台……每进入新一层补 1 台」）：
## 部署走玩家 Skill 节点（EngineerTurret）统一通路——库存上限/满编顶替与主动技同源；
## Skill 缺席（裸玩家测试）静默跳过。披露：开战接线（turret.combat）在进首房时由
## floor_scene._wire_room_combat 的 summons 组重接缝（m2-t26）补齐——层入口时刻
## player.combat 尚为 null（房间未进），炮台先待机、进房即恢复开火，与跨房残留
## 炮台的既有语义一致（体注册随部署房，跨房不重注）。
func _apply_spare_parts_floor_entry(frame: int) -> void:
	var skill := player.get_node_or_null("Skill") as EngineerTurret
	if skill != null:
		skill.deploy_spare_parts(frame)


## boss 死亡（FloorScene.boss_defeated，boss 房清时发出）：嵌层间中转于楼层之上。
## 第 3 层胜利链（m2-t18）：open() 内 flow 走胜利分支发 victory_achieved →
## _on_victory_achieved 切胜利结算场景——连接必须先于 open()（同步发射）。
func _on_boss_defeated(_room_id: int) -> void:
	if inter_floor != null:
		return
	_quiesce_floor_combat_for_inter_floor()
	inter_floor = INTER_FLOOR_SCENE.instantiate() as Node2D
	add_child(inter_floor)
	inter_floor.setup(player, buffs, RunState.floor_idx, talents)   # m2-t35：注入天赋系统
	inter_floor.flow.victory_achieved.connect(_on_victory_achieved)
	inter_floor.next_floor_requested.connect(_on_next_floor_requested)
	inter_floor.open()


## 第 3 层 Boss 死亡链路终点：切胜利结算场景（VictorySummary 读 RunState/Telemetry
## 填充，确认时蓝晶全额入账）。延迟到帧末路由：boss_defeated 在物理回调链内发出，
## 同帧立即换场景会先于其他监听者把节点摘树（同 DeathRecorder._open_summary 手法）。
func _on_victory_achieved() -> void:
	AchievementSystem.notify_victory()   # m2-t33 补线：守夜人/速通者/拒绝治疗判定点
	Telemetry.log_row(["victory", Engine.get_physics_frames(),
		RunState.floor_idx, RunState.kills])
	if victory_route_override.is_valid():
		victory_route_override.call()
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("goto"):
		router.call_deferred("goto", "victory")
		return
	get_tree().change_scene_to_file.call_deferred(VICTORY_SCENE)   # 路由器缺席兜底


## 层间是安全中转房，不是旧 Boss 房上的 UI 覆盖层。Boss 清房后旧 FloorScene
## 仍保留到下一层门确认，以便门回调负责释放/换层；这段等待期必须同时满足：
## - 旧楼层整棵不再推进敌人、弹幕、环境效果或进房检测；
## - 玩家从旧 CombatSystem 的空间哈希注销；
## - 玩家、武器、近战与护盾精灵不再持有旧房战斗引用。
func _quiesce_floor_combat_for_inter_floor() -> void:
	if floor_scene != null and is_instance_valid(floor_scene):
		var old_combat: CombatSystem = floor_scene._registered_combat
		if old_combat != null and is_instance_valid(old_combat) and player != null:
			old_combat.unregister_body(player)
		floor_scene._registered_combat = null
		floor_scene.process_mode = Node.PROCESS_MODE_DISABLED
	if player == null or not is_instance_valid(player):
		return
	player.combat = null
	var rig := player.weapon_rig
	if rig == null:
		rig = player.get_node_or_null("WeaponRig") as WeaponRig
	if rig != null:
		rig.combat = null
		rig.combat_rng = null
	var melee := player.get_node_or_null("Melee") as Melee
	if melee != null:
		melee.combat = null
		melee.combat_rng = null
	for child in player.get_children():
		if child is ShieldSpirit:
			(child as ShieldSpirit).combat = null


## 层间门（InterFloorFlow.enter_next_floor 已推层 + §14.1 蓝晶结算）：
## 释放层间 → 有当层数据则重建楼层；无（M1 仅 A1）→ M1 完结浮层。
func _on_next_floor_requested(new_floor: int) -> void:
	CodexSystem.on_floor_entered(new_floor)   # m2-t20：过层计数 + 蓝晶入账 + 解锁结算
	# m2-t33 成就补线（裁定㉗，K.2 过层点发射）：floor_cleared(通过层号) 先求值——
	# slum_king/moneybags/bare_hands 用「本层」的受击/开火窗口与 RunState 快照；
	# 随后 floor_reached(抵达层号) 吸收新层窗口重置（深入者判定 + 赤手空拳本层口径）。
	AchievementSystem.notify_floor_cleared(new_floor - 1)
	AchievementSystem.notify_floor_reached(new_floor)
	# m4-c2：层入口被动改由 _start_floor 尾部统一触发（有当层数据才真正"进入新层"；
	# A2 里程碑/M1 浮层路径无楼层构建，不触发）。
	if inter_floor != null and is_instance_valid(inter_floor):
		inter_floor.queue_free()
	inter_floor = null
	if _floor_data_available(new_floor):
		_start_floor(new_floor)
	elif new_floor == A2_ENTRY_FLOOR:
		_enter_a2_milestone()
	else:
		_show_m1_end_overlay()


## 层数数据门：start_a<idx> 固定模板在库 且 combat_a<idx>_* 池非空（缺一即无法装配）。
func _floor_data_available(idx: int) -> bool:
	return GameDB.rooms.has("start_a%d" % idx) \
		and not DungeonBuilder.combat_pool(idx).is_empty()


## A2 入口里程碑：真正离开 A1 楼层并把玩家实例安置到标记为 floor_idx=2 的入口。
## 这里不伪造完整 A2 地牢；它是 Task 20/26 要求“进入第 2 层”的最小可玩端点。
func _enter_a2_milestone() -> void:
	if floor_scene != null and is_instance_valid(floor_scene):
		floor_scene.queue_free()
		floor_scene = null
	_a2_entry = Node2D.new()
	_a2_entry.name = "A2Entry"
	_a2_entry.set_meta("floor_idx", RunState.floor_idx)
	add_child(_a2_entry)
	if player != null:
		player.position = Vector2(240, 135)
	var marker := Polygon2D.new()
	marker.name = "CrystalCaveThreshold"
	marker.polygon = PackedVector2Array([
		Vector2(150, 70), Vector2(330, 70), Vector2(360, 135),
		Vector2(330, 200), Vector2(150, 200), Vector2(120, 135),
	])
	marker.color = Color(0.08, 0.16, 0.24)
	marker.z_index = -5
	_a2_entry.add_child(marker)
	var crystal := Polygon2D.new()
	crystal.polygon = PackedVector2Array([
		Vector2(240, 78), Vector2(268, 126), Vector2(240, 192), Vector2(212, 126),
	])
	crystal.color = Color(0.35, 0.75, 1.0, 0.75)
	_a2_entry.add_child(crystal)
	var hud := HUD.new()
	hud.player = player
	_a2_entry.add_child(hud)
	_show_m1_end_overlay()


## 里程碑提示：全屏 UI 明示已经位于第 2 层，而非停留在 A1 预告“将进入”。
func _show_m1_end_overlay() -> void:
	if _overlay != null:
		return
	_overlay = CanvasLayer.new()
	_overlay.layer = 40
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = OVERLAY_TEXT
	label.add_theme_font_size_override("font_size", 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var hint := Label.new()
	hint.text = OVERLAY_HINT
	hint.add_theme_font_size_override("font_size", 10)
	hint.modulate = Color(0.7, 0.7, 0.7)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	center.add_child(box)
	add_child(_overlay)


# ================================================================ 查询面（测试）

func m1_overlay_visible() -> bool:
	return _overlay != null


func overlay_text() -> String:
	if _overlay == null:
		return ""
	var center := _overlay.get_child(1) as CenterContainer
	return (((center.get_child(0) as VBoxContainer).get_child(0)) as Label).text


func a2_entry_active() -> bool:
	return _a2_entry != null and is_instance_valid(_a2_entry) \
		and int(_a2_entry.get_meta("floor_idx", 0)) == A2_ENTRY_FLOOR
