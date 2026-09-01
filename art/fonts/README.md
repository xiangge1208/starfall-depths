# art/fonts — 像素中文字体（M3-P0-5 资产捆绑）

## 文件

| 文件 | 说明 |
|---|---|
| `fusion-pixel-12px-monospaced-zh_hans.ttf` | 融合像素字体 12px 等宽 简体中文（主字体） |
| `OFL.txt` | SIL Open Font License 1.1（上游总许可，随包分发要求保留） |
| `LICENSES/` | 上游组件许可（ark-pixel / cubic-11 / galmuri） |

## 来源与校验

- 上游：https://github.com/TakWolf/fusion-pixel-font （OFL 1.1，允许捆绑与再分发，须附带许可）
- 版本：release `2026.08.11`，资产 `fusion-pixel-font-12px-monospaced-ttf-v2026.08.11.zip`
- SHA-256（zh_hans.ttf）：`5468f424d7c20956318243dac129448849e498ef32b43a219def935d888eba2c`
- 覆盖验证（2026-08-30，PIL 12 渲染探测）：ASCII（`A 5 :`）、CJK（`中 击 蓝`）、标点（`· — × → 【 ！ ？ 、`）全部有字形——**无需 latin 回退文件**。

## 使用约定（M3 执行期接线，本卡只捆绑不接线）

- 接线卡 = M3 计划 **S-C**（`ui/m3_theme.tres` 全局主题 + `project.godot` gui/theme/custom + 字号对齐 12px 整数倍 + nearest 渲染核对）；**本目录入库时不改 `project.godot`**（该文件 M2 执行期有卡片认领，M3 接线等 M2 门禁后）。
- 12px 等宽设计基准：渲染字号取 12 的整数倍（12/24），Godot `FontFile` 关闭 oversampling、`subpixel` 关，保持像素锐利（480×270 viewport）。
- 升级上游版本时：替换 TTF → 更新本表版本与 SHA-256 → 通知 S-C 回归字号走查。
