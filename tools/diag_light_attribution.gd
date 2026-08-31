extends Node
## m2-t37 光照/图集 draw-call 归因诊断（评审 Minor-7 可复现性：诊断脚本随库走）。
##
## 复刻 perf_probe 的 F2 压测构图（start_a1 → 最密战斗房 + 40 注入敌 + 500 满池弹），
## 按环境变量做单变量手术，采样节流窗 RENDER_TOTAL_DRAW_CALLS_IN_FRAME，验证
## A2 光圈参与集（lit set）对批处理碎裂的贡献。task-37 报告的归因矩阵即本工具输出。
##
## 环境变量（缺省 = head，即当前提交的行为）：
##   VAR=head|t37_head|bullets_lit|polys_lit|bullets_polys_lit|cull1|nolight
##     head             当前提交口径（地形面/陈设/敌人/玩家/弹幕/预警纹 = LIT_ITEM_MASK）
##     t37_head         回放 T37 首轮（a70305d）：弹幕/预警纹退回默认位 1（不参与光照）
##     bullets_lit      追加：弹幕视觉精灵 opt-in 专属位（真实光照回弹幕，测其参与成本）
##     polys_lit        追加：全楼 Polygon2D（地刺/间歇泉/火雨预警纹等 telegraphs）opt-in
##     bullets_polys_lit 两者叠加
##     cull1            光圈 cull_mask=1（T37 前全量参与参照，应复现 ~150）
##     nolight          光圈隐藏（无光圈基线参照，应复现 ~115）
##   SHOT_OUT=user://xx.png  截图模式：不打分，构图后冻结存图（BULLETS=1 时先满池弹
##     并飞行 WAIT_FRAMES 帧再冻结——修复轮 combat 视觉证据的复现入口）
##   BULLETS=1   构图含满池弹（截图模式默认 0，评分模式默认 1 与探针同构）
##   WAIT_FRAMES=30  截图模式下弹幕飞行帧数（决定弹群与光圈的相对位置，确定性）
##
## 运行：godot --path . res://tools/diag_light_attribution.tscn
const PP := preload("res://tests/scenes/perf_probe.gd")
const PLAYER_SCENE := preload("res://core/player/player.tscn")

const WARMUP_FRAMES := 120
const SAMPLE_FRAMES := 240

var fs: FloorScene = null
var room: FloorScene.FloorRoom = null
var rng := RandomNumberGenerator.new()
var topup := false


func _ready() -> void:
	var variant := OS.get_environment("VAR")
	if variant.is_empty():
		variant = "head"
	var want_bullets := OS.get_environment("BULLETS") == "1" or \
		(OS.get_environment("BULLETS").is_empty() and OS.get_environment("SHOT_OUT").is_empty())
	var shot_out := OS.get_environment("SHOT_OUT")
	var wait_frames := 30
	if not OS.get_environment("WAIT_FRAMES").is_empty():
		wait_frames = int(OS.get_environment("WAIT_FRAMES"))
	rng.seed = 20260831
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RunState.start_run("vanguard")
	RunState.run_seed = 20260831
	RngSvc.setup_run(20260831)   # start_run 已用随机种子初始化盐流——截图确定性需重钉

	var floor_idx := 1 if variant == "f1" else 2
	fs = _make_floor(floor_idx)
	room = fs.room_node(1)
	fs.set_biome_a2(true)
	fs.enter_room(1)
	fs.player.position = fs.room_rect(1).get_center()
	for _i in 5:
		await get_tree().physics_frame
	var pp := PP.new()
	pp._inject_enemies(fs, room, PP.stress_enemy_ids(40))

	if want_bullets:
		pp._top_up_bullets(fs, room, rng)
		topup = true          # 弹亡即补（评分模式保满压；截图模式冻结后自然停摆）

	_apply_variant(variant)

	if not shot_out.is_empty():
		for _i in wait_frames:
			await get_tree().physics_frame
		topup = false
		get_tree().paused = true          # 冻结 AI/弹幕：确定性构图
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot_out)
		print("DIAG SHOT saved: ", shot_out, " ", img.get_size())
		get_tree().quit(0)
		return

	Engine.set("max_fps", 60)
	for _i in WARMUP_FRAMES:
		await get_tree().process_frame
	var draws: Array[float] = []
	for _i in SAMPLE_FRAMES:
		await get_tree().process_frame
		draws.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	var s := 0.0
	var mx := 0.0
	for d in draws:
		s += d
		mx = maxf(mx, d)
	print("DIAG variant=%s bullets=%d injected=40 alive=%d pool=%d draws avg=%.1f max=%.0f" % [
		variant, 1 if want_bullets else 0, pp._alive_enemies(room),
		room.combat.pool.active_count(), s / draws.size(), mx])
	get_tree().quit(0)


## 单变量手术（评审批处理契约的运行时对照面）。
func _apply_variant(variant: String) -> void:
	match variant:
		"t37_head":
			# 回放 T37 首轮（a70305d）：弹幕/预警纹退回默认位（不参与光照重渲）
			for vis: Sprite2D in fs._bullet_sprites:
				vis.light_mask = 1
			_polys_light_mask(fs, 1)
			return
	match variant:
		"bullets_lit", "bullets_polys_lit":
			for vis: Sprite2D in fs._bullet_sprites:
				vis.light_mask = BiomeFx.LIT_ITEM_MASK
		_:
			pass
	match variant:
		"polys_lit", "bullets_polys_lit":
			_polys_light_mask(fs, BiomeFx.LIT_ITEM_MASK)
		_:
			pass
	match variant:
		"cull1":
			fs.biome_fx.light.range_item_cull_mask = 1
		"nolight":
			fs.biome_fx.light.visible = false
		_:
			pass


func _polys_light_mask(root: Node, mask: int) -> void:
	# 预警纹/红圈等 Polygon2D telegraphs（地刺/间歇泉/火雨；Label 伤害数字不受影响）
	for child in root.get_children():
		if child is Polygon2D:
			(child as Polygon2D).light_mask = mask
		_polys_light_mask(child, mask)


func _physics_process(_delta: float) -> void:
	if topup and room != null and is_instance_valid(fs) and not get_tree().paused:
		var pp := PP.new()
		pp._top_up_bullets(fs, room, rng)
		pp.free()


func _make_floor(floor_idx: int) -> FloorScene:
	var player: Player = (PLAYER_SCENE as PackedScene).instantiate() as Player
	var f := FloorScene.new()
	f.floor_idx = floor_idx
	add_child(f)
	f.setup(PP.probe_build(floor_idx), player)
	player.hp_max = 9999
	player.hp = 9999
	return f
