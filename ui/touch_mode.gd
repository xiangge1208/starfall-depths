class_name TouchMode
extends RefCounted
## M1-T21 触屏模式的纯逻辑裁决。
##
## 仅移动端导出或持久设置显式启用。系统报告“有触屏”只是硬件事实：
## 触屏 Windows 仍是桌面端，设置关闭时必须保留鼠标瞄准和隐藏虚拟控件。
## override_value 仅是测试/诊断缝，显式值优先于生产裁决。


static func enabled(_system_touchscreen: bool, mobile_feature: bool,
		setting_enabled: bool = false, override_value: Variant = null) -> bool:
	if override_value != null:
		return bool(override_value)
	# 保留 _system_touchscreen 参数是为了让所有生产调用点显式传入并可测试
	# “触屏硬件存在但未授权触屏模式”的桌面契约；它本身不启用模式。
	return mobile_feature or setting_enabled
