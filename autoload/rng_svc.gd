extends Node
## 种子化随机服务（m0-t3 实现完整逻辑，当前空壳可运行）。
var run_seed: int = 0
func setup_run(seed: int) -> void:
	run_seed = seed
