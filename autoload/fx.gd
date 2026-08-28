extends Node
## 打击感服务（m0-t12 实现完整逻辑，当前空壳保证 t7~t11 可调用）。
func hitstop(_ms: int) -> void: pass
func shake(_strength: float, _duration: float) -> void: pass
func on_roll(_player: Node2D) -> void: pass
func on_player_hurt(_player: Node2D, _amount: int) -> void: pass
func on_enemy_hit(_enemy: Node2D, _ctx: Dictionary) -> void: pass
func spawn_damage_number(_pos: Vector2, _amount: int, _is_crit: bool) -> void: pass
