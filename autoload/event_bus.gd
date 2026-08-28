extends Node
## 全局事件总线。信号随任务追加，先声明 M0 已知的。
signal enemy_damaged(amount: int, is_crit: bool)
signal enemy_killed(enemy_id: String)
signal player_damaged(amount: int, fatal: bool)
signal status_applied(target: Node, element: int)
signal resonance_triggered(reaction: int, at: Vector2, payload: Dictionary)
signal room_cleared(room_id: String)
signal shield_broken                                  # m1-t2：护盾由 >0 归 0 的破碎拍（坚守触发源）
signal player_crit_landed(amount: int, at: Vector2)   # m1-t2：玩家阵营弹暴击落地（特效/被动挂钩）
signal boss_phase(boss, phase_idx)                    # m1-t8：Boss 阶段推进（HUD/演出挂钩）
