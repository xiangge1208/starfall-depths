# 环境验证报告（M0 Task 1）

日期：2026-08-28

## Godot

- **版本**：`4.7.2.stable.official.ed1daf0bf`（winget 包 `GodotEngine.GodotEngine` 4.7.2，即 godotengine.org 4.7.2-stable win64）
- **可执行文件路径**：
  - `C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot.exe`（winget 创建的符号链接，该目录已由 winget 加入用户 PATH，新开的 shell 可直接用 `godot`）
  - 实体：`C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe`
- **安装方式**：`winget install --id GodotEngine.GodotEngine -e`（计划中的 ID `GodotEngine.Godot` 在 winget 源中不存在，实际 ID 为 `GodotEngine.GodotEngine`）
- `project.godot` 的 `config/features` 据此设为 `PackedStringArray("4.7")`

## GdUnit4

- **来源**：master 分支 zip（计划中的原始 URL 成功）：`https://github.com/MikeSchulze/gdUnit4/archive/refs/heads/master.zip`
- **版本**：插件版本 **6.2.1**（`addons/gdUnit4/plugin.cfg`）
- 已通过 `godot --headless --path . --import` 完成首次导入，无报错

## 测试命令（最终可用版）

一键无头测试：

```
tools\run_tests.cmd
```

内容（GODOT 环境变量优先，否则回退 PATH 上的 `godot`）：

```bat
@echo off
rem Resolve Godot: %GODOT% env var wins, else fall back to `godot` on PATH.
if not defined GODOT set GODOT=godot
"%GODOT%" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode %*
```

直接调用等价于：

```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode
```

结果：2/2 测试通过（test_autoloads_exist、test_input_actions_registered），退出码 0。

## 对计划步骤的三处必要修正（均已验证）

1. **InputMap 持久化**：运行时 `InputMap.add_action()` 只改内存，不会写入 ProjectSettings，因此计划中 setup_input.gd 原样执行后动作无法持久化。已在 `tools/setup_input.gd` 中把每个动作镜像写入 `ProjectSettings.set_setting("input/<action>", {"deadzone": 0.2, "events": [...]})` 后再 `ProjectSettings.save()`（这正是编辑器自身的持久化方式）。重复执行经验证幂等（15 个事件不翻倍）。
2. **`--ignoreHeadlessMode`**：GdUnit4 6.2.1 默认拒绝 headless 运行（退出码 103），按其 CLI 选项在 run_tests.cmd 追加 `--ignoreHeadlessMode`。
3. **winget 包 ID**：见上。

## 其他说明

- `icon.svg`：Godot 官方默认图标文件不在引擎仓库可直取的路径（raw 404），用手写的简洁默认图标（Godot 蓝圆角方块+白星）替代，功能等同（仅作为项目默认图标资源）。
- `physics/common/physics_ticks_per_second=60` 与引擎默认值相同，Godot 执行 `ProjectSettings.save()` 时会将其按"与默认一致"省略；当前 project.godot 中已手工保留该键，后续若被 Godot 重写消失属正常现象，值仍为 60。
- InputMap 动作：move_left(A/←) move_right(D/→) move_up(W/↑) move_down(S/↓) fire(鼠标左键) roll(Shift/Space) switch_weapon(Q) interact(E) skill(F) pause(Esc)，deadzone 全部 0.2，键盘事件均用 physical_keycode。
- 测试报告输出目录 `reports/` 已加入 .gitignore（GdUnit4 默认输出位置；模式写作 `/reports/` 锚定仓库根，避免误伤 docs/superpowers/reports/）。
