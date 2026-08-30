extends EnemyBase
## 分裂（附录 B 原型「分裂」）：缓慢逼近玩家；死亡经 spawn_callback 出 split_count
## 个子体——子体 hp 取行 split_child_hp（缺省=当前 hp 一半），子体行 split_generations
## 减 1（0 = 子体不再分裂，防无限链）。magma_slime（B.2 A3）split_generations=2：
## 大→中→小两代；mud_slime/moss_slime/ice_spider 为 1 代。
## 子体 counts_for_wave=false（镜像 EnemyBase._split_spawn_children 语义）。

const DEFAULT_SPLIT_COUNT := 2

func _engage(_frame: int) -> void:
	var to_player := _player_pos() - brain_pos
	if to_player.length_squared() > 0.0001:
		brain_pos += to_player.normalized() * (float(row.get("speed", 40)) / TimeConst.FPS)

## 分裂在 die() 持有（先落子体再退场）；回调未注入（脑层测试/未接线）则跳过。
func die() -> void:
	if state != State.DEAD:
		_spawn_split_children()
	super()

func _spawn_split_children() -> void:
	if int(row.get("split_generations", 0)) <= 0 or not spawn_callback.is_valid():
		return
	var count := int(row.get("split_count", DEFAULT_SPLIT_COUNT))
	var child_row: Dictionary = (row as Dictionary).duplicate(true)
	child_row.erase("elite_affixes")
	var child_hp := int(row.get("split_child_hp", 0))
	if child_hp <= 0:
		child_hp = maxi(int(float(row.get("hp", 10)) * 0.5), 1)
	child_row["hp"] = child_hp
	child_row["split_generations"] = int(row.get("split_generations", 1)) - 1
	var r := combat_radius()
	for i in count:
		var child: Node = spawn_callback.call(String(row.get("id", "")),
			brain_pos + Vector2(r if i == 0 else -r, 0.0), child_row)
		if child != null:
			child.set("hp", child_hp)
			if "hp_max" in child:
				child.set("hp_max", child_hp)
			if "counts_for_wave" in child:
				child.set("counts_for_wave", false)
