class_name CallbackInteractable
extends Interactable
## 通用回调交互物（m1-t6）：供房间代码内联构造（训练房武器架等），
## 免为每种交互物单开脚本文件。挂 on_interact(player) 回调即用。

var on_interact := Callable()              # 签名 func(player: Node2D) -> void

func interact(player: Node2D) -> void:
	if on_interact.is_valid():
		on_interact.call(player)
