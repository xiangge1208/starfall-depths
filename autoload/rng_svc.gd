extends Node
## 种子化随机服务。所有逻辑随机必须经 stream() 派生，禁止全局 randi()/randf()。

var run_seed: int = 0

static func stable_hash(a: int, b: int) -> int:
	# FNV-1a-64 偏移基 0xcbf29ce484222325 超出 int64 正域，Godot 4.7.2 会把它钳到
	# INT64_MAX（实测误译），故按二补码取其位型等值 -3750763034362895579（64 位一致）。
	var h: int = -3750763034362895579
	for v: int in [a, b]:
		var x := v
		for _i in 8:
			h ^= x & 0xFF
			# 掩码 0xFFFFFFFFFFFFFFFF 同样越界；-1 即全 64 位为 1，& -1 语义相同。
			h = (h * 0x100000001b3) & -1
			x >>= 8
	return h

func setup_run(seed: int) -> void:
	run_seed = seed

func stream(floor_idx: int, salt: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = stable_hash(stable_hash(run_seed, floor_idx), _salt_hash(salt))
	return rng

func _salt_hash(salt: String) -> int:
	# 同 stable_hash：0xcbf29ce484222325 → -3750763034362895579，掩码用 -1。
	var h: int = -3750763034362895579
	for c in salt.to_utf8_buffer():
		h ^= c
		h = (h * 0x100000001b3) & -1
	return h
