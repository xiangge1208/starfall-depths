class_name TestInteraction
extends GdUnitTestSuite
## m1-t6 交互系统可测核心（brief ⑤）：
## 1) pick_best 最近可交互物选择（重叠范围取近者、半径外/空集 → null、并列取先、半径含边界）
## 2) can_interact=false 门控（候选被跳过）
## 3) Interactable 自注册 "interactables" 组 + InteractionSystem.best() 组查询
## 4) InteractPrompt 浮标 bind/clear
## 替身构造：Area2D 重叠需在树，pick_best 静态实现只读 global_position——
## 位置替身不进树即可测（auto_free，position 即 global_position）。

class LockedInteractable extends Interactable:
	func can_interact(_player: Node2D) -> bool:
		return false

func _stub(pos: Vector2) -> Interactable:
	# 不进树：global_position 退化为本地 position（headless 无物理树依赖）
	var it: Interactable = auto_free(Interactable.new())
	it.position = pos
	return it

func _locked(pos: Vector2) -> Interactable:
	var it: LockedInteractable = auto_free(LockedInteractable.new())
	it.position = pos
	return it

# ---- 1) 最近可交互物选择 ----

func test_pick_best_nearest_wins() -> void:
	var near := _stub(Vector2(10, 0))
	var far := _stub(Vector2(20, 0))
	# far 在前：证明选择按距离而非数组序
	var candidates: Array[Interactable] = [far, near]
	assert_that(InteractionSystem.pick_best(Vector2.ZERO, 24.0, candidates)).is_same(near)

func test_pick_best_out_of_radius_returns_null() -> void:
	var candidates: Array[Interactable] = [_stub(Vector2(30, 0))]
	assert_that(InteractionSystem.pick_best(Vector2.ZERO, 24.0, candidates)).is_null()

func test_pick_best_empty_candidates_returns_null() -> void:
	var candidates: Array[Interactable] = []
	assert_that(InteractionSystem.pick_best(Vector2.ZERO, 24.0, candidates)).is_null()

func test_pick_best_tie_returns_first() -> void:
	var first := _stub(Vector2(24, 0))
	var second := _stub(Vector2(-24, 0))
	var candidates: Array[Interactable] = [first, second]
	assert_that(InteractionSystem.pick_best(Vector2.ZERO, 24.0, candidates)).is_same(first)

func test_pick_best_radius_is_inclusive() -> void:
	# 恰在半径上（d == radius）视为可达（<= 契约）
	var at_edge := _stub(Vector2(24, 0))
	var candidates: Array[Interactable] = [at_edge]
	assert_that(InteractionSystem.pick_best(Vector2.ZERO, 24.0, candidates)).is_same(at_edge)

# ---- 2) can_interact 门控 ----

func test_pick_best_skips_locked_candidate() -> void:
	var locked_near := _locked(Vector2(10, 0))
	var open_far := _stub(Vector2(20, 0))
	var candidates: Array[Interactable] = [locked_near, open_far]
	assert_that(InteractionSystem.pick_best(Vector2.ZERO, 24.0, candidates)).is_same(open_far)

func test_pick_best_all_locked_returns_null() -> void:
	var candidates: Array[Interactable] = [_locked(Vector2(10, 0)), _locked(Vector2(20, 0))]
	assert_that(InteractionSystem.pick_best(Vector2.ZERO, 24.0, candidates)).is_null()

func test_default_can_interact_is_true() -> void:
	var player: Node2D = auto_free(Node2D.new())
	assert_bool(_stub(Vector2.ZERO).can_interact(player)).is_true()

# ---- 3) 组注册 + best() 组查询 ----

func test_interactable_joins_group_on_ready() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var it: Interactable = auto_free(Interactable.new())
	root.add_child(it)                          # _ready 触发自注册
	assert_bool(it.is_in_group(InteractionSystem.GROUP)).is_true()

func test_best_via_group_picks_nearest_in_range() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var sys := InteractionSystem.new()
	root.add_child(sys)
	var player: Node2D = auto_free(Node2D.new())
	root.add_child(player)
	sys.player = player
	var far: Interactable = auto_free(Interactable.new())
	far.position = Vector2(30, 0)
	var near: Interactable = auto_free(Interactable.new())
	near.position = Vector2(10, 0)
	root.add_child(far)
	root.add_child(near)
	assert_that(sys.best()).is_same(near)

func test_best_via_group_out_of_range_returns_null() -> void:
	var root: Node2D = auto_free(Node2D.new())
	add_child(root)
	var sys := InteractionSystem.new()
	root.add_child(sys)
	var player: Node2D = auto_free(Node2D.new())
	player.position = Vector2(500, 500)
	root.add_child(player)
	sys.player = player
	var it: Interactable = auto_free(Interactable.new())
	it.position = Vector2(30, 0)
	root.add_child(it)
	assert_that(sys.best()).is_null()

# ---- 4) 浮标 ----

func test_prompt_bind_shows_label_above_target() -> void:
	var prompt: InteractPrompt = auto_free(InteractPrompt.new())
	var target := _stub(Vector2(100, 50))
	target.action_label = "拾取 老伙计"
	prompt.bind(target)
	assert_bool(prompt.visible).is_true()
	assert_str(prompt.text).is_equal("拾取 老伙计")
	assert_float(prompt.global_position.y).is_equal(50.0 - 16.0)   # 上方 +16px

func test_prompt_clear_hides() -> void:
	var prompt: InteractPrompt = auto_free(InteractPrompt.new())
	var target := _stub(Vector2(100, 50))
	target.action_label = "拾取 老伙计"
	prompt.bind(target)
	prompt.clear()
	assert_bool(prompt.visible).is_false()

func test_prompt_bind_null_is_clear() -> void:
	var prompt: InteractPrompt = auto_free(InteractPrompt.new())
	prompt.bind(null)
	assert_bool(prompt.visible).is_false()
