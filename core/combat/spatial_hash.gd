class_name SpatialHash
## 网格空间哈希（GDD §18.2），格子默认 32px。

var _cell: float
var _buckets: Dictionary = {}   # Vector2i -> Dictionary{ id: true }
var _pos: Dictionary = {}       # id -> Vector2

func _init(cell_size: float = 32.0) -> void:
	_cell = cell_size

func _key(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / _cell)), int(floor(p.y / _cell)))

func insert(id: int, pos: Vector2) -> void:
	_pos[id] = pos
	_bucket(_key(pos))[id] = true

func move(id: int, new_pos: Vector2) -> void:
	if not _pos.has(id):
		insert(id, new_pos)
		return
	var old: Vector2 = _pos[id]
	var ok := _key(old)
	var nk := _key(new_pos)
	if ok != nk:
		_buckets[ok].erase(id)
		_bucket(nk)[id] = true
	_pos[id] = new_pos

func remove(id: int) -> void:
	if not _pos.has(id):
		return
	_buckets[_key(_pos[id])].erase(id)
	_pos.erase(id)

func query(pos: Vector2, radius: float) -> Array[int]:
	var out: Array[int] = []
	var min_c := _key(pos - Vector2(radius, radius))
	var max_c := _key(pos + Vector2(radius, radius))
	var r2 := radius * radius
	for cx in range(min_c.x, max_c.x + 1):
		for cy in range(min_c.y, max_c.y + 1):
			var b: Dictionary = _buckets.get(Vector2i(cx, cy), {})
			for id: int in b:
				var p: Vector2 = _pos[id]
				if pos.distance_squared_to(p) <= r2:
					out.append(id)
	return out

func clear() -> void:
	_buckets.clear()
	_pos.clear()

func _bucket(k: Vector2i) -> Dictionary:
	if not _buckets.has(k):
		_buckets[k] = {}
	return _buckets[k]
