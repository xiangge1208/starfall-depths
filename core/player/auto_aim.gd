class_name AutoAim
extends RefCounted
## 自动瞄准纯逻辑（GDD §5.1 触屏辅助：「无右摇杆输入时，向 60° 锥内最近敌人自动开火」）。
##
## 生产接线：PlayerDriver 在无显式触屏右杆输入且 auto_aim=true 时收集存活敌人，
## 调本类选出 60° 锥内最近目标并自动开火；显式触屏右杆/手柄右杆优先。
## 返回零向量表示「锥内无目标且无既有瞄准」，调用方不开火。
##
## 选目标规则（GDD §5.1）：先滤掉 60° 锥外目标，再在锥内取最近者；
## 距离完全相同才按输入顺序稳定取前者。锥外忽略；无目标 → -1。

## 在以 player_pos 为顶点、朝向 facing（弧度）、总张角 cone_deg 的扇形内选目标索引。
## 返回 enemies_pos 中的索引；锥内无目标返回 -1。与玩家重合的敌人方向未定义，跳过。
static func pick_target(player_pos: Vector2, facing: float, enemies_pos: Array[Vector2], cone_deg := 60.0) -> int:
	var half := deg_to_rad(cone_deg) * 0.5
	var best := -1
	var best_dist := INF
	for i in enemies_pos.size():
		var to: Vector2 = enemies_pos[i] - player_pos
		if to == Vector2.ZERO:
			continue                     # 方向未定义（同位），不参与选目标
		var diff := absf(wrapf(to.angle() - facing, -PI, PI))
		if diff > half + 0.000001:      # 边界含入（1e-6 rad 容差，抗浮点噪声）
			continue                     # 锥外忽略
		var d := to.length()
		if d < best_dist:
			best = i
			best_dist = d
	return best

## 自动瞄准方向：锥内选中目标 → 指向该目标的单位向量；
## 无目标/全锥外 → 回退 current_aim 归一化（零向量回退为零，调用方据零不开火）。
static func aim_vector(player_pos: Vector2, targets: Array[Vector2], current_aim: Vector2, cone_deg := 60.0) -> Vector2:
	var fallback := current_aim.normalized() if current_aim != Vector2.ZERO else Vector2.ZERO
	var facing := current_aim.angle() if current_aim != Vector2.ZERO else 0.0
	var idx := pick_target(player_pos, facing, targets, cone_deg)
	if idx == -1:
		return fallback
	var dir: Vector2 = targets[idx] - player_pos
	return dir.normalized() if dir != Vector2.ZERO else fallback
