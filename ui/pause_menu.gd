class_name PauseMenu
extends CanvasLayer
## 局内暂停菜单（GDD §19 第 10 项收口）：继续/设置/重开/回主菜单 四项；「设置」内嵌
## 既有 settings_panel（S-A 十键：屏震/伤害数字/色弱形状/自动瞄准/触屏控件/打击停顿/
## 振动/三路音量），面板打开时其底部出现运行时构建的「按 键」钮打开既有 rebind_panel
## （S-B 九动作重映射）——设置含按键重映射的 §19 口径由此闭合（主菜单入口不变）。
##
## 呼出：InputMap 既有 `pause` 动作（project.godot 本卡前仅 Esc 一个事件、全库无消费
## 者——rebind_panel.gd 头注 S-B 记录在案；本卡补手柄 Start 绑定并落消费者）。Esc 在
## 商店/熔铸/事件卡弹层打开时不误触发：三者 _unhandled_input 自行消费 Esc（楼层实体
## 在 HUD 之后入树，后入树者先收 unhandled input）；三选一/灾厄弹层不消费 Esc，由本
## 类门控拦下（见 _run_overlay_open）。死亡/胜利结算 overlay 是独立路由场景，本类不在
## 场，天然无误触发面。
##
## 暂停机制：get_tree().paused = true（世界整树停机，试炼角标/危险地块倒计时等一切
## 60Hz 逻辑随之冻结）；本层与挂其下的设置/改键面板 PROCESS_MODE_ALWAYS（同 hud/
## debug_hud 惯例），暂停中照常收输入。HUD 置灰由本层 Dim（layer 45 > HUD 10 >
## TouchControls 40）遮罩实现，mouse_filter STOP 同时挡住底层点击。
##
## 演出链口径（hitstop/慢速演出激活时表现合理）：
## - BOSS_DEATH / PLAYER_DEATH 演出链活跃 → 呼出被忽略（链尾自有死亡/胜利路由；
##   中途叠加暂停会把 SceneRouter 的 0.2s 淡入淡出 tween 一并冻死在过场里）。
## - 平凡 hitstop 冻结拍（暴击/击杀 40~60ms）中呼出 → 先 Fx.cancel_hitstop() 掐掉
##   导演的 ignore_time_scale 权威恢复定时器再上自己的暂停——否则菜单打开期间世界
##   会被解冻复活。cancel 为 fx.gd 明示的幂等场景/测试边界入口，只动表现层时计，
##   不触碰任何判定数值。
## - 恢复只翻 paused 位：不注入 trauma、不调 hitstop、不动 time_scale（恢复零演出误发）。
##
## 路由（重开口径，写明选择）：重开 = SceneRouter "game" 键重载 run_root——RunState
## 层号/种子不变 → 同种子同层重建 = 「重开当前层」语义（局内金币/蓝晶/增益/试炼因子
## 保留，玩家换新实例满状态；RunRoot._begin 自带 DeathRecorder.reset 开局复位）。
## 回主菜单 = 委托宿主 HUD 的既有放弃退出路径（settle_victory_gems 全额/试炼 ×1.5 →
## SaveSystem.add_gems → settlement_record → goto("menu")，与 HUD「放弃试炼」按钮同路
## 同 _abandon_fired 防重入守卫，不重复触发；试炼规格 §4 行为不回退）。
##
## 触屏：四钮 140×18 / 12px 字体（m3_theme 基准，同 main_menu 按钮惯例）+ HUD 侧
## PauseBtn 呼出钮。像素风红线：纯代码构建（同 debug_hud 惯例），无缩放、无重采样、
## 无非整数尺寸。测试注入口：route_override / presentation_blocked_override（同
## hud.abandon_route_override 模式）；quit_action 由 HUD 注入（无宿主时兜底直走路由）。

signal opened
signal closed

const SETTINGS_PANEL_SCENE := preload("res://ui/settings_panel.tscn")
const REBIND_PANEL_SCENE := preload("res://ui/rebind_panel.tscn")

const LAYER := 45                # HUD(10) 与 TouchControls(40) 之上、SceneRouter 黑场/
                                 # 死亡去饱和(100) 之下
const BTN_MIN := Vector2(140, 18)
const BTN_FONT := 12             # m3_theme 基准字号（同 main_menu/trial_panel 按钮）
const TITLE_FONT := 16
const OVERLAY_SCAN_LIMIT := 512  # 弹层扫描上限（防御性；实际局场景远小于此）

var hud: CanvasLayer = null      # 宿主 HUD（信息性；回主菜单委托经 quit_action）
## 回主菜单结算退出委托（HUD 注入 _on_abandon_pressed：结算+落盘+records+回菜单，
## 防重入守卫在 HUD 侧）；无效时兜底直走 route("menu")。
var quit_action := Callable()
## 路由接缝（测试注入口，同 hud.abandon_route_override 模式）：有效时替代真实
## SceneRouter.goto(key)。
var route_override := Callable()
## 演出链激活判定接缝（测试注入口，同 fx.gameplay_scene_gate 模式）：有效时替代
## 默认探测（Fx.boss_death_chain_active / death_desat_active）。
var presentation_blocked_override := Callable()

var _dim: ColorRect
var _resume_btn: Button
var _settings_btn: Button
var _settings: SettingsPanelUI = null
var _rebind: RebindPanelUI = null
var _rebind_btn: Button = null
var _is_open := false


func _ready() -> void:
	name = "PauseMenu"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS   # 树暂停中本层照常（同 debug_hud 惯例）
	visible = false
	_build_shell()
	_attach_panels()


# ---- 构建（纯代码，无 tscn——同 debug_hud 惯例） ----

func _build_shell() -> void:
	var root := Control.new()
	root.name = "Shell"
	root.mouse_filter = Control.MOUSE_FILTER_STOP   # 暂停中挡住底层一切点击（HUD 弃钮等）
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0.0, 0.0, 0.0, 0.6)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_dim)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.name = "Rows"
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var title := Label.new()
	title.name = "Title"
	title.text = "已暂停"
	title.add_theme_font_size_override("font_size", TITLE_FONT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_resume_btn = _menu_button(box, "ResumeBtn", "继 续", _on_resume_pressed)
	_settings_btn = _menu_button(box, "SettingsBtn", "设 置", _on_settings_pressed)
	_menu_button(box, "RestartBtn", "重 开", _on_restart_pressed)
	_menu_button(box, "QuitBtn", "回主菜单", _on_quit_pressed)


func _menu_button(parent: Control, btn_name: String, text: String, handler: Callable) -> Button:
	var btn := Button.new()
	btn.name = btn_name
	btn.text = text
	btn.custom_minimum_size = BTN_MIN
	btn.add_theme_font_size_override("font_size", BTN_FONT)
	btn.pressed.connect(handler)
	parent.add_child(btn)
	return btn


## 内嵌既有面板（S-A/S-B，任意场景可实例化的独立覆盖层）：挂本层下继承 ALWAYS，
## 树暂停中可正常交互。设置面板 Rows 末尾追加运行时构建的「按 键」钮（同 main_menu
## 运行时建钮手法）打开改键面板——设置含按键重映射的 §19 口径由此闭合；只增行不改
## 既有行，面板总高仍在 270 视口内（tests/unit/test_pause_menu.gd 钉死不溢出）。
func _attach_panels() -> void:
	_settings = SETTINGS_PANEL_SCENE.instantiate() as SettingsPanelUI
	if _settings != null:
		add_child(_settings)
		_settings.visibility_changed.connect(_on_settings_visibility_changed)
		var rows: Control = _settings.get_node("Center/Panel/Margin/Rows")
		_rebind_btn = Button.new()
		_rebind_btn.name = "RebindShortcut"
		_rebind_btn.text = "按 键"
		_rebind_btn.custom_minimum_size = BTN_MIN
		_rebind_btn.add_theme_font_size_override("font_size", BTN_FONT)
		_rebind_btn.visible = false
		_rebind_btn.pressed.connect(_on_rebind_pressed)
		rows.add_child(_rebind_btn)   # 末行（「返 回」之下）：只追加，不改既有布局
	_rebind = REBIND_PANEL_SCENE.instantiate() as RebindPanelUI
	if _rebind != null:
		add_child(_rebind)


# ---- 状态机：呼出 / 恢复（纯逻辑可测；Esc 与按钮/触屏同入口） ----

func is_open() -> bool:
	return _is_open


## 呼出（幂等守卫 + 门控）。返回是否实际呼出。
func try_open() -> bool:
	if _is_open or _open_blocked():
		return false
	var tree := get_tree()
	if tree != null and tree.paused:
		# 平凡 hitstop 冻结拍中呼出：先掐权威恢复定时器/恢复时计（Fx.cancel_hitstop
		# 幂等），再上自己的暂停——否则菜单打开期间世界会被导演的恢复定时器解冻。
		var fx := get_node_or_null("/root/Fx")
		if fx != null and fx.has_method("cancel_hitstop"):
			fx.call("cancel_hitstop")
		tree.paused = false
	_is_open = true
	visible = true
	if tree != null:
		tree.paused = true
	if _resume_btn != null:
		_resume_btn.grab_focus()   # 键盘可达安全出口（↑↓/Tab 导航四钮，Enter 确认）
	opened.emit()
	return true


## 继续：恢复世界（只翻 paused 位——零演出误发），复位设置/改键子层（下次呼出回主层）。
func resume() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	if _settings != null:
		_settings.visible = false
	if _rebind != null:
		_rebind.visible = false
	if _rebind_btn != null:
		_rebind_btn.visible = false
	var tree := get_tree()
	if tree != null:
		tree.paused = false
	closed.emit()


## `pause` 动作（Esc/手柄 Start）唯一消费者。子层优先：改键层 Esc → 回设置层；
## 设置层 Esc → 回暂停主层（皆不退出暂停）；主层 Esc → 恢复；未开 → 呼出。
## 返回是否消费（消费才 set_input_as_handled，被门控拦下时不吞事件）。
func handle_pause_key() -> bool:
	if _rebind != null and _rebind.visible:
		_rebind.visible = false         # 同 rebind 返回钮语义：只隐藏（监听态 Esc 由
		_settings_btn.grab_focus()      # 其 _input 前置消费，不会走到这里）
		return true
	if _settings != null and _settings.visible:
		_settings.visible = false       # 同设置面板返回钮语义：只隐藏，实例保留
		_settings_btn.grab_focus()
		return true
	if _is_open:
		resume()
		return true
	return try_open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if handle_pause_key() and get_viewport() != null:
			get_viewport().set_input_as_handled()


# ---- 门控（呼出被忽略的场面：演出链 / 过场中 / 局内弹层） ----

func _open_blocked() -> bool:
	if presentation_blocked_override.is_valid():
		return bool(presentation_blocked_override.call())
	var fx := get_node_or_null("/root/Fx")
	if fx != null:
		if fx.has_method("boss_death_chain_active") and bool(fx.boss_death_chain_active()):
			return true                 # Boss 死亡演出链（链尾自有胜利路由）
		if fx.has_method("death_desat_active") and bool(fx.death_desat_active()):
			return true                 # 玩家死亡演出链（去饱和层在链尾换场景前常驻）
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and bool(router.get("_busy")):
		return true                     # 0.2s 过场中：淡入淡出 tween 挂路由器上，
	                                    # 叠加暂停会把换场冻死在半途
	return _run_overlay_open()


## 局内弹层扫描（仅 Esc 呼出瞬间走，非热路径）：三选一/灾厄面板（不消费 Esc，必须
## 由本类拦下）+ 商店/熔铸/事件卡的 `_ui` 弹层惯例（兜底：其 _unhandled_input 在
## HUD 之后入树本应先收 Esc，此处双保险）。结算 overlay（死亡/胜利）是独立场景，
## 不在扫描面内。
func _run_overlay_open() -> bool:
	var tree := get_tree()
	var cs: Node = tree.current_scene if tree != null else null
	if tree == null:
		return false
	if cs == null:
		cs = tree.root   # 无 current_scene 环境（gdUnit 套件）：从树根起扫（生产恒走 current_scene）
	if cs == null:
		return false
	var stack: Array[Node] = [cs]
	var visits := 0
	while not stack.is_empty() and visits < OVERLAY_SCAN_LIMIT:
		visits += 1
		var n: Node = stack.pop_back()
		if n is Control and (n is BuffPick or n is CalamityPanel) \
				and (n as Control).is_visible_in_tree():
			return true
		var ui: Variant = n.get("_ui")   # 商店/熔铸/事件卡弹层持有惯例（duck 读，缺省 null）
		if ui is Control and (ui as Control).is_visible_in_tree():
			return true
		for c in n.get_children():
			stack.append(c)
	return false


# ---- 四项入口 ----

## 设置层显隐同步：隐藏时「按 键」钮一并收起，改键层不留悬空开启态。
func _on_settings_visibility_changed() -> void:
	if _settings == null:
		return
	if _rebind_btn != null:
		_rebind_btn.visible = _settings.visible
	if not _settings.visible and _rebind != null:
		_rebind.visible = false


func _on_resume_pressed() -> void:
	resume()


## 设置（内嵌既有 S-A 面板；open() 焦点落面板「返 回」，改完返回暂停层）。
func _on_settings_pressed() -> void:
	if _settings != null:
		_settings.open()


## 按键重映射（既有 S-B 面板；设置层底部「按 键」钮入口）。
func _on_rebind_pressed() -> void:
	if _rebind != null:
		_rebind.open()


## 重开当前层：先解冻（SceneRouter 的过场 tween 挂 autoload 上，树暂停时会停摆）
## 再走既有路由键 "game" 重载 run_root——RunState 层号/种子不变 = 同层重建（层重开）。
func _on_restart_pressed() -> void:
	resume()
	_route("game")


## 回主菜单：委托宿主 HUD 既有放弃退出路径（结算时机与死亡/胜利/放弃三路一致，
## 防重入守卫共享）；无宿主（独立使用）兜底直走路由。
func _on_quit_pressed() -> void:
	resume()
	if quit_action.is_valid():
		quit_action.call()
		return
	_route("menu")


func _route(key: String) -> void:
	if route_override.is_valid():
		route_override.call(key)
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("goto"):
		router.call("goto", key)
