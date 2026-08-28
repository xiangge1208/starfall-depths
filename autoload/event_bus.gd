extends Node
## 全局事件总线。信号随任务追加，先声明 M0 已知的。
signal enemy_damaged(amount: int, is_crit: bool)
signal enemy_killed(enemy_id: String)
signal player_damaged(amount: int, fatal: bool)
signal status_applied(target: Node, element: int)
signal resonance_triggered(reaction: int, at: Vector2, payload: Dictionary)
signal room_cleared(room_id: String)
