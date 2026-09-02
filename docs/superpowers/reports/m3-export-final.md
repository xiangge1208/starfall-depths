# M3 X-C 导出包收口报告（版本号 / 图标 / 存档 v2 兼容 / 双包启动冒烟 · Task X-C）

任务卡 X-C 交付：`export_presets.cfg` 版本号与图标收口 + `tools/gen_icon.py` 程序化图标
+ 存档 v2 兼容收口验证 + 双包（Windows exe / Android apk+aab）产出与冒烟 + 本报告。

- 分支：`m3-xc`（基于 main @ 11c789a）；执行日 2026-09-02
- 冒烟结论：**PASS —— Windows exe 冒烟 PASS；Android apk+aab 双产物产出、签名核验通过、
  versionCode=100 / versionName=1.0.0 / 自适应图标四件套全部入包**（见 §5/§6 证据）
- 全量回归：`cmd //c "tools\\run_tests.cmd"` → **1622 test cases | 0 errors | 0 failures |
  0 flaky | 0 skipped | 0 orphans，(1622/1622)，exit 0**（基线 1622 持平，§7）

---

## 1. 版本策略表

| 键 | 平台 | 前 | 后 | 规则 |
|---|---|---|---|---|
| `version/name` | Android | "1.0.0"（X-A 已定） | **"1.0.0"（不变）** | semver 三段，对外可见版本 |
| `version/code` | Android | 1 | **100** | 100 = 1.0.0 交付基线；递增规则见下 |
| `application/file_version` | Windows | "" | **"1.0.0.0"** | VS_VERSIONINFO 四段格式，semver 1.0.0 ↔ 末段 `.0` 为 Windows 补位 |
| `application/product_version` | Windows | "" | **"1.0.0.0"** | 同上，与 file_version 恒一致 |

**version/code 递增规则（本卡正式口径，后续发版遵守）**：
1. **每次对外分发（含热修重包）严格 +1**，绝不复用、绝不回退（Android 升级链硬要求）；
2. 辅助映射：`100 = 1.0.0`；semver 升位时跳号预留——`1.1.x → ≥110`、`1.2.x → ≥120`、
   `2.x.x → ≥200`（百位=主版本、十位=次版本段），保证跨 semver 升位时 code 单调不冲突；
3. Windows 侧 file/product version 跟随 semver，Android `version/name` 与 Windows 双字段
   同卡同值改动，禁止只改一侧（本次收口即为「三处一致」样例：1.0.0 / 100 / 1.0.0.0）。

**游戏内版本读点**：现有 UI 无版本字符串显示点（grep `ui/*.gd` 无 version 读点）。按任务卡
「没有则不越权加 UI」，本卡不加，**移交 G-1**（建议：设置面板底部一行 `v1.0.0 (100)`，
读点取 preset 同源常量，避免第三处硬编码）。

## 2. 图标收口

### 2.1 产物（`art/generated/icon/`，全部程序化自产 + 已入库 .import 边车）

| 文件 | 尺寸 | 用途 |
|---|---|---|
| `icon_256.png` | 256×256 | Windows `application/icon`（Godot 导出器自动转多尺寸 ICO） |
| `icon_192.png` | 192×192 | Android `launcher_icons/main_192x192`（传统启动器图标） |
| `adaptive_background_432.png` | 432×432 | 自适应图标背景层（星空+星陨，不透明满幅） |
| `adaptive_foreground_432.png` | 432×432 | 自适应图标前景层（地牢门，主体 256px 居中、四周透明） |
| `adaptive_monochrome_432.png` | 432×432 | 自适应单色层（白色剪影，Android 13 主题图标） |

### 2.2 生成器 `tools/gen_icon.py`

- **确定性**：`random.Random(42)`（沿用 gen_placeholder_art.py 种子惯例）；脚本内置
  「两次构建 SHA256 一致」自检，两轮运行 QA 全过；
- **调色板封口**：13 色全部取自 `tools/spritegen_m3.py` 的 DB16 衍生调色板
  （#181420 夜空 / #8a8296+#6e6678 石材 / #544c60 星门内壁 / #b06cff 辉光 /
  #ffd94a·#e2c04c·#c8901c·#ffe86a·#ff8a2e 金橙系 / #fff3b8 星色 / #ffffff·#d8d8d8 白灰），
  QA 逐像素断言无调色板外色值——**零新增色值、零第三方素材、无版权负担**；
- **设计**：星空 + 金色流星自右上坠入 + 石砌地牢门（钥孔石/门楣/双柱/星门紫辉环/
  门心之星/三级台阶），造型语言对齐既有 `fx/trial_gate.png`（试炼之门 16x16）；
  64×64 逻辑像素画整数倍（×3/×4）最近邻放大，保持像素风；
- **QA 五项自检**（脚本内，失败退出码 1）：尺寸精确 / 背景层全不透明 / 调色板封口 /
  确定性哈希 / 自适应安全区圆（66.7%）内——**两轮全 PASS**；
- 注意：`tools/gen_placeholder_art.py` 的 main() 为全量再生（破坏性，裁定⑪），本卡**未裸跑**，
  独立小脚本不触碰既有素材库；`art/generated/MANIFEST.md`（M2 生成器所有）未动。

### 2.3 preset 接线（export_presets.cfg）

```
[preset.0.options] (Windows Desktop)
application/icon="res://art/generated/icon/icon_256.png"

[preset.1.options] (Android)
launcher_icons/main_192x192="res://art/generated/icon/icon_192.png"
launcher_icons/adaptive_foreground_432x432="res://art/generated/icon/adaptive_foreground_432.png"
launcher_icons/adaptive_background_432x432="res://art/generated/icon/adaptive_background_432.png"
launcher_icons/adaptive_monochrome_432x432="res://art/generated/icon/adaptive_monochrome_432.png"
```

### 2.4 入包实证

- **Windows exe**：`(Get-Item starfall.exe).VersionInfo` → FileVersion/ProductVersion =
  `1.0.0.0`、ProductName=StarfallDepths、FileDescription=Starfall Depths - 2D pixel roguelike；
  `ExtractAssociatedIcon` 抽出 32×32 图标即新图标（`user_export/xc_exe_icon_extracted.png`）——
  Godot 已把 256px PNG 转 ICO 多尺寸嵌入；
- **Android apk**：`aapt dump badging` → `versionCode='100' versionName='1.0.0'`；
  `application-icon-*` 全密度指向 `res/2r.xml`，解包确认为 `<adaptive-icon>`
  （background/foreground/monochrome 三元素），层 webp 解帧即本图标
  （144×144 层见 `user_export/apk_icon_probe/AF.png`）。

### 2.5 边界与移交

- `project.godot` 的 `config/icon` 仍为 Godot 默认 `icon.svg`（X-A 口径 project.godot 禁改；
  计划卡原文「LOGO 定稿需用户过目」）——**运行时窗口图标/编辑器图标仍是默认蓝人形，
  移交 G-1 连同 LOGO 定稿一并裁定**；两平台安装包图标已全部收口，不受此影响。

## 3. 存档 v2 兼容收口

**结论：未发现兼容缺陷，`autoload/save_system.gd` 零改动**（fail-SOFT + additive 默认骨架
回落设计经受住了全部样本）。

### 3.1 既有回归（M2 口径，全绿）

`tests/unit/test_save.gd` 23 用例（v1→v2 迁移/幂等/脏档回落/全字段往返）、
`test_settings_ui.gd` 旧档新键容错 + 音量 int 键持久化往返、`test_rebind.gd` 序列化/持久化
往返、`test_codex_system.gd` 解锁进度跨档往返——本卡未动 tests/unit（并行禁碰区），
以上随全量 1622 绿一并复核（用例名：`test_v1_save_migrates_to_v2_preserving_all_fields` /
`test_migration_v2_idempotent_double_load` / `test_roundtrip_persists_all_fields` /
`test_unlock_tasks_progress_roundtrip` / `test_volume_int_keys_roundtrip_through_disk` 等）。

### 3.2 X-C 专项证据（一次性脚本，gitignore 证据区）

`godot --headless --path . --script user_export/xc_save_v2_verify.gd`
→ 日志 `user_export/xc_save_v2_verify.log`：**checks=135 fails=0 → PASS（exit 0）**

| PART | 内容 | 数字 |
|---|---|---|
| PART1 | **v2 全字段往返**：新档 → 正式 API 写满 10 个顶层字段（gems=777 / 3 英雄 / 2 成就 / settings 全 12 键 / 2 天赋 / 2 武器 / 2 Boss 首杀 / unlock_tasks 五计数+floor_clears 三桶 / 2 条改键事件）→ 盘上 JSON 抽查（version==2、floor_clears 键按 JSON 契约字符串化、无 .tmp 残骸）→ **全新实例重读（等价进程重启）深比较逐叶相等**（含访问器口径抽查） | 顶层 10/10 字段、settings 12/12 键逐叶相等 |
| PART2 | **旧档样本 6 件全部不崩 + 缺省补齐**：A=M2-era v2 缺 m3 追加键（key_rebinds/hitstop/vibration/三路音量缺键→默认补齐，既有字段全保留）；B=v1 全字段迁移（v2 新键默认空）；C=无版本号（from_version=0）；D=脏类型逐键回落；E=损坏 JSON fail-SOFT 回默认档；F=脏重映射表合法项保留+脏项剔除（修饰键缺省回落 false） | 6/6 样本 PASS |
| PART3 | **迁移幂等**：v1→载入（盖 2）→add_gems+record_talent_purchase→二次载入深比较一致、Boss 名录不翻倍、gems 12+3=15 | 重载逐叶一致 |

向后兼容声明核对：save_system.gd 头注「v2 相对 v1 纯增量（additive）……全部由
_merge_saved 的默认骨架回落」与 6 件样本实测行为一致——**声明成立**。
（注：脚本内 `unlock_hero` 未调用——其内部引用 AchievementSystem autoload，-s 脚本环境
不保证在树；heroes 字段走 data 直写，与解锁路径共用同一 _merge_saved 合并口径。）

### 3.3 导出包内口径

SaveSystem autoload 启动即读档（`_ready`→`load_save`），Windows exe 30s 存活 + 游戏日志
无崩溃标记已覆盖「导出包内读档路径不崩」；「首次启动建档→重启读档」的真人闭环走查
随 G-1 试玩员执行。

## 4. 双包产出与冒烟

| 包 | 产出 | 大小（字节） | 判据 | 结果 |
|---|---|---|---|---|
| Windows exe | `user_export/starfall.exe`（embed_pck） | 121,859,256 | `tools/export_smoke.cmd`：导出成功 → 启动 30s 进程存活 → 游戏日志无 FATAL/CRASH | **PASS**（exit 0） |
| Android apk | `user_export/starfall-release.apk` | 89,069,473 | `tools/export_android.cmd`：apksigner verify 证书 SHA-256 与 X-A 一致 | **PASS**（exit 0） |
| Android aab | `user_export/starfall-release.aab` | 38,123,508 | jarsigner -verify exit 0（中文 locale「jar 已验证。」） | **PASS**（exit 0） |

### 4.1 Windows 冒烟证据（`user_export/smoke_console.log` 转录）

```
=== [export_smoke] 1/3 Windows Desktop release export ===
[export_smoke] Windows export OK: user_export\starfall.exe
=== [export_smoke] 2/3 Windows 30s launch smoke ===
[export_smoke] Process alive after 30s: OK (auto-closed)
[export_smoke] No crash markers in game log: OK
=== [export_smoke] 3/3 Android pre-flight export ===
[export_smoke] SKIP: Android export pre-flight failed on this machine (rc=1) ... honest SKIP
=== [export_smoke] RESULT: Windows smoke PASS; Android SKIP ===
```

- 判据即 M2 导出冒烟既有口径（进程存活 + 日志无崩溃标记）；SKIP 为该脚本设计的诚实
  分支（当时本 worktree 尚未自举 android/ 模板，随后已按 X-A §2 自举并走 §4.2 专线）；
- **交互截图尝试披露**：附加做了主菜单交互截图脚本（`user_export/xc_menu_smoke.ps1`），
  本机为共享多显示器桌面，游戏窗口不在可见顶层——屏幕拷贝混入其他应用窗口内容、
  PrintWindow 对 GL 窗口出黑帧，**该批截图判定证据无效并已删除**（避免第三方内容入档，
  且不再对共享桌面做置顶/光标类侵入操作）。窗口化交互截图与真人走查移交 G-1 试玩员，
  既有进程存活+日志判据不受影响。

### 4.2 Android 证据（`user_export/xc_android_console.log` 转录）

```
[export_android] keystore injected via env: D:/workspace/thomas/.keystores/m3-release/...（口令不入库机制照旧）
[export_android] temp toggle import_etc2_astc=ON
[export_android] APK OK: user_export\starfall-release.apk
[export_android] AAB OK: user_export\starfall-release.aab
Signer #1 certificate SHA-256 digest: e5fc73396a67293ce1d10881289b5bf3c5dc84905d6d20921df5623f18220998
[export_android] temp edits restored, zero-drift verified against backups
[export_android] RESULT: PASS, apk + aab produced and signature-verified
```

- 证书 SHA-256 与 X-A 报告完全一致（同一 keystore 签名链）；导出期双开关
  （import_etc2_astc / export_format）临时写入-无条件还原，交付面零漂移（git status 仅本卡文件）；
- **真机启动冒烟移交 G-1**：X-B 已证模拟器 GPU 仿真跑不动 Godot 4.7 渲染器（不重复尝试），
  真机安装 release apk（versionCode=100 可直接覆盖安装 X-A 期 code=1 的任何旧包）+
  触屏完整一局归 G-1 试玩员；
- 机器级引导注记：本 worktree 的 `android/`（gitignored）按 X-A §2 自举——解压
  `export_templates/4.7.2.stable/android_source.zip` 至 `android/build` + `android/.build_version`
  写 `4.7.2.stable` + `android/build/.gdignore`；export_android.cmd 的自愈/清扫前置兼容该状态。

## 5. 全量回归

`cmd //c "tools\\run_tests.cmd"` → **Overall Summary: 1622 test cases | 0 errors | 0 failures |
0 flaky | 0 skipped | 0 orphans，Executed (1622/1622)，88/88 suites，exit 0**
（2026-09-02，与基线 1622 持平；本卡改动未增删用例、未触发任何回归。）

## 6. 交付物清单（本卡 commit 范围）

| 文件 | 动作 |
|---|---|
| `export_presets.cfg` | 修改：Android version/code=100；Windows file/product version=1.0.0.0；图标接线 5 键 |
| `tools/gen_icon.py` | 新增：确定性图标生成器（含 QA 五项自检） |
| `art/generated/icon/*.png`（5 张）+ `*.png.import`（5 份） | 新增：图标产物与导入边车 |
| `docs/superpowers/reports/m3-export-final.md` | 新增：本报告 |

## 7. 残余风险与移交 G-1 清单

1. **Android 真机启动冒烟**：安装 release apk + 触屏完整一局（覆盖新 versionCode=100 /
   自适应图标实装效果）；模拟器路线已由 X-B 排除，不重试；
2. **Windows 真人交互走查**：本机共享桌面无法安全取窗口截图（§4.1 披露），主菜单/设置/
   完整一局交互验收归 G-1 试玩员；
3. **LOGO/icon.svg 定稿**：运行时窗口图标与 `project.godot config/icon` 仍为 Godot 默认
   （计划卡口径「定稿需用户过目」）；若裁定采纳 `art/generated/icon/icon_256.png`，
   仅需改 project.godot 一行 + icon.svg 替换，两平台安装包无需再动；
4. **游戏内版本读点**：无既有显示点，建议设置面板加 `v1.0.0 (100)` 一行（§1）；
5. **Windows 产品信息空字段**：company_name/copyright/trademarks 仍空（非本卡版本口径，
   需求裁定后一并补）；
6. **X-A 既有移交沿用**：`import_etc2_astc=true` 正式落 project.godot 的裁定；
   keystore 异地备份；
7. **B-2 终判 CONDITIONAL 三项**（A1 TTK 深度出带 2.25×、三带 bot 永久不可评、停滞 11%）
   按 `m3-balance-w2.md` §14.3 口径随门禁一并裁定。
