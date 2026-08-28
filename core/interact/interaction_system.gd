class_name InteractionSystem
extends Node
## 交互系统（m1-t6，房间挂载）：每物理拍在 "interactables" 组内查玩家 radius 内最近
## 可交互物（Interactable._ready 自注册分组，组模式），驱动浮标 bind/clear；
## E 按下（M0 输入表 interact）→ interact(player)。纯轮询，不发信号。

const GROUP := "interactables"
const INTERACT_ACTION := "interact"

var player: Node2D = null
var radius := 24.0
var prompt: InteractPrompt = null          # 注入或 _ready 自建

func _ready() -> void:
	if prompt == null:
		prompt = InteractPrompt.new()
		add_child(prompt)
	prompt.clear()

func _physics_process(_delta: float) -> void:
	var target := best()
	if target == null:
		if prompt.visible:
			prompt.clear()
		return
	prompt.bind(target)                       # 逐拍重绑：跟随目标实时位置
	if Input.is_action_just_pressed(INTERACT_ACTION):
		target.interact(player)

## 当前最佳交互目标（组内取半径内最近者；无玩家/无候选 → null）。
func best() -> Interactable:
	if player == null:
		return null
	return pick_best(player.global_position, radius, candidates(), player)

## 组内候选快照（每拍现取：动态增删交互物免登记）。
func candidates() -> Array[Interactable]:
	var out: Array[Interactable] = []
	if not is_inside_tree():
		return out
	for node in get_tree().get_nodes_in_group(GROUP):
		var it := node as Interactable
		if it != null:
			out.append(it)
	return out

## 纯函数选_best：radius 内最近者（并列取先，含边界 <=），can_interact=false 跳过；
## 无则 null。static 便于 headless 单测——只读 global_position，不需要物理树
##（Area2D 重叠监测须在树，此实现刻意绕开）。
static func pick_best(player_pos: Vector2, radius: float, cands: Array[Interactable],
		player: Node2D = null) -> Interactable:
	var best_it: Interactable = null
	var best_d := INF
	for it in cands:
		if it == null or not it.can_interact(player):
			continue
		var d := player_pos.distance_to(it.global_position)
		if d <= radius and d < best_d:
			best_d = d
			best_it = it
	return best_it
