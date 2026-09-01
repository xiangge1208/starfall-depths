# M3-X-A Android release 签名 + 产出冒烟报告

任务卡 X-A 交付：`export_presets.cfg` release 化 + `tools/export_android.cmd` 一键导出（apk+aab）
+ 本报告（一次性引导手册 + 证据留存）。

- 分支：`m3-xa`（基于 main @ 9a9fdbc，已并 main @ 0d7c859 —— 含 m3-sb/m3-rc/m3-sc）
- 执行入口：`tools/export_android.cmd`（仓库根运行；`GODOT` 环境变量优先，否则 PATH 上的 godot 4.7.2）
- 冒烟结论：**PASS —— apk 与 aab 双产物产出，双签名核验通过，交付文件零漂移**（见 §5 证据）

---

## 1. 交付物与预设改动（export_presets.cfg，Android preset）

| 键 | 前 | 后 | 说明 |
|---|---|---|---|
| `gradle_build/use_gradle_build` | false | **true** | gradle 构建是 aab 的前置，也是 release 签名链推荐路径 |
| `version/name` | "1.0" | **"1.0.0"** | semver 三段；`version/code=1` 不变（X-C 收口时统一版本策略） |
| `package/unique_name` | org.godotengine.starfalldepths | **com.thomas.starfalldepths** | 退役 Godot 模板默认包名 |
| `keystore/release` / `release_user` / `release_password` | 空 | **保持空串** | 口令与 keystore 路径绝不入库（§3） |
| 其余（min_sdk/target_sdk 空模板默认、arm64-v8a、etc2_astc 纹理格式等） | 不变 | 不变 | 最小改动 |

## 2. 一次性引导（机器级，全部仓库外，换机重建照此执行）

1. **Android SDK**：`D:\dev\android-sdk`，含 cmdline-tools、platform-tools、`platforms;android-34`、
   `build-tools;34.0.0`，`sdkmanager --licenses` 全部接受。脚本经 `ANDROID_HOME`（默认该路径）+ `ANDROID_SDK_ROOT` 下发。
2. **gradle 用 JDK**：`D:\dev\jdk-21.0.12.1+1`。Godot 4.7.2 模板 gradle 8.11.1 不支持 JDK 25 跑 daemon，
   故独立安装 JDK 21，仅由脚本以 `JAVA_HOME` 注入给 gradle 进程，不污染全局。
3. **release keystore**（仓库外 `D:\workspace\thomas\.keystores\m3-release\`，目录级 gitignore）：
   - `keytool -genkeypair -v -keystore starfall-release.keystore -alias starfall-release -keyalg RSA -keysize 2048 -validity 10000`
   - `keystore.properties` 三键：`keystore_path` / `keystore_user` / `keystore_password`。
   - **丢失此 keystore = 无法对既有应用发升级包**，请自行异地备份（口令与实体都不在任何仓库里）。
4. **Android gradle 构建模板**（gitignore `/android/` 整目录）：
   - 解压 `<export_templates>/4.7.2.stable/android_source.zip` 到 `res://android/build`
     （等效编辑器「项目 → 安装 Android 构建模板」，约 207MB）；
   - **版本戳必须落在 `res://android/.build_version`（build 的上一级！）**，内容为 Godot 的
     `VERSION_FULL_CONFIG`，即 `godot --version` 输出的前 4 段（`4.7.2.stable.official.ed1daf0bf` → `4.7.2.stable`）。
   - **`res://android/build/.gdignore`（空文件）必须存在**：把 Godot 资源扫描挡在模板外。
     没有它，编辑器扫描会往模板里写 `*.import` 边车（gradle 资源合并随即报
     "file name must end with .xml or .png"），并把上次导出遗留在 `src/main/assets` 的
     编译产物索引进工程（打包阶段报 "Can't open file"）。
   - 排障实录（Godot 4.7.2 源码核对）：`export_project()` 按
     `gradle_build_directory.get_base_dir()/.build_version` 读取并与 `FULL_CONFIG` 精确比对——
     戳放进 `build/` 里或写成带 hash 的完整串，分别报「版本信息不存在，请从项目菜单重新安装」
     与「Android build version mismatch: Template installed: … Requested version: …」。
     脚本前置阶段对版本戳与 .gdignore 均做自愈，并先行清探单模板内 `.import` 边车与
     遗留 assets/instrumented 目录。

## 3. 口令不入库机制

`export_presets.cfg` 是入库文件，keystore/release* 三键恒为空串。脚本运行期从仓库外
`keystore.properties` 解析三键，注入 `GODOT_ANDROID_KEYSTORE_RELEASE_PATH/USER/PASSWORD`
环境变量；Godot `EditorExportPreset::get_or_env`（4.7.2）约定 **env 非空即覆盖 preset**，
签名照常生效。仓库内任何文件不含口令/alias/路径三要素中的任一个。

## 4. 两个导出期开关：临时写入-无条件还原（交付面零漂移）

| 开关 | 为什么不能入库 | 机制 |
|---|---|---|
| `project.godot` 的 `rendering/textures/vram_compression/import_etc2_astc=true` | Godot 强制校验 Android 导出必须开它，但 project.godot 属本卡禁改文件 | 备份 → `[rendering]` 段首插一行 → 导出 → 还原 |
| `export_presets.cfg` 的 `gradle_build/export_format` 0→1 | aab 与 apk 共用一个 preset，格式键互斥 | 备份 → 翻转 → aab 导出 → 还原 |

还原后将当前文件与导出前备份做二进制比对（fc /b）自证，任何漂移打印 WARNING；失败路径同样
先还原再退出。注意漂移判定不与 git index 比——工作树对 preset 的未提交意图改动（§1）会误报。
**G-1 建议**：若门禁裁定接受，可把 `import_etc2_astc=true` 正式落进 project.godot，
删除开关 a；`export_format` 因 apk/aab 双产物仍需保留开关 b。

## 5. 产出冒烟证据（2026-09-01，run6，脚本退出码 0 = PASS）

| 项 | 值 |
|---|---|
| 退出码 | 0（PASS） |
| APK | `user_export/starfall-release.apk`，89,035,428 字节 |
| AAB | `user_export/starfall-release.aab`，38,083,099 字节 |
| APK 核签 | `apksigner verify --print-certs` 通过：CN=Starfall Depths, OU=Games, O=thomas, L=Beijing, ST=Beijing, C=CN；**证书 SHA-256 `e5fc73396a67293ce1d10881289b5bf3c5dc84905d6d20921df5623f18220998`**（日志 `user_export/android_apk_sign_verify.log`） |
| AAB 核签 | `jarsigner -verify` 退出码 0（本机中文 locale 输出「jar 已验证。」；脚本内的 `findstr "jar verified"` 仅证据展示、非门槛，locale 不同时不命中属预期） |
| jarsigner 警告 | 「证书链无效 PKIX path building failed」为自签名 keystore 的预期警告（jarsigner 按 JDK 受信 CA 校验），非缺陷；apksigner 对 apk 的校验为权威结论 |
| 漂移自检 | project.godot / export_presets.cfg 与导出前备份 fc /b 二进制一致，零漂移 |
| 导出日志 | `user_export/android_apk_export.log`、`android_aab_export.log` |

## 6. 已知边界与移交 G-1/X-C 的注记

- 本卡产物为**冒烟级**：证明签名链与双格式产出可用；真机安装/启动/触屏回归归 G-1 试玩员（X-B 性能复测同机进行）。
- 应用图标仍为 Godot 默认 icon.svg（M2 遗留），X-C 导出收口卡负责正式图标与版本号终判。
- `version/code` 恒为 1，正式渠道分发前需随版本递增（X-C 口径）。
- gradle 模板与 SDK/JDK 均为机器级引导物，换机重建按 §2（脚本会自愈版本戳并诚实报缺）。
