# Task 5 评审报告：音频管理器 + sfx 全套接线（m2-t5）

- **被审对象**：`.worktrees/m2-t5`（分支 m2-t5，commit 682010a + d43d1c3，基线 ed88ef8）
- **评审范围**：`git diff ed88ef8..HEAD`（10 文件 +279 行）
- **评审日期**：2026-08-30
- **评审人**：独立评审 agent（只读评审，未改动任何生产代码）

## 结论：Approved-with-notes

核心规格 7/8 接线点正确落地、TDD 三项全覆盖、实测 733/733 全绿（0 orphans）、热路径与 headless 安全合规，无 Blocker。存在 2 个 Major 规格缺口（死亡音未接线、set_music_volume API 缺失），修复量合计 <10 行，建议随 T23（音乐卡，同文件 audio_mgr.gd）或独立微卡闭环，**不阻塞本卡合入**，但必须在 T23 开工前补齐。

## 规格符合度逐项核对

| # | 规格项 | 判定 | 证据 |
|---|---|---|---|
| 1 | AudioStreamPlayer 池 sfx 8 语音 | **PASS** | `autoload/audio_mgr.gd:19` `POOL_SIZE := 8`，`_ready` 建池；测试断言 8 个 player 子节点 |
| 2 | music 2 通道 | 偏差（谅解） | 未建。与规格同段的"不做 music（T23）"边界条款一致，空 music 通道在 T23 前无意义；T23（波次表 G-2）已列 `audio_mgr.gd` 归属。记 Minor① |
| 3 | `play(key: String, pitch_scale := 1.0)` | **PASS** | `audio_mgr.gd:49` 签名逐字一致 |
| 4 | 音源表 = `audio/generated/sfx/*.wav` | PARTIAL | 实际目录有 **47 个** WAV（计划写"12 个既有"已过时，非实现者责任，建议编排者更新计划行文）。`KEYS` 11 项覆盖规格要求的全部 key（除 death，见 #11）+ 3 个预留 key（player_hurt/door_open/ui_click，WAV 均存在） |
| 5 | player 开火→shoot_player | **PASS** | `core/player/weapon_rig.gd:105`，成功路径末尾（CD 未好/空蓝 return false 不发声）；双持齐射仍一声，注释明示 |
| 6 | enemy 开火→shoot_enemy | **PASS** | `core/enemies/enemy_base.gd:121`，`fire_bullet` 实际出弹后 |
| 7 | melee 挥击→melee_swing | **PASS** | `core/player/melee.gd:32`，`try_attack` 成功路径（CD/挥击中 return false 不发声） |
| 8 | 命中→hit_enemy | **PASS** | `core/combat/combat_system.gd:130`，玩家弹**有效命中**才响（比 MANIFEST 建议的 enemy_damaged 消费处更精确——0 伤/overkill 不噪音），敌方弹打玩家不发声，注释明示 |
| 9 | 暴击→crit_hit（pitch 1.15） | **PASS** | `core/combat/combat_system.gd:128` `AudioMgr.play("crit_hit", 1.15)`，参数逐字符合规格 |
| 10 | 拾取→pickup_* | **PASS** | `core/rooms/pickup.gd:56`；kind 值域 coin/energy/heart → pickup_coin/pickup_energy/pickup_heart 三 key 全在 KEYS 且 WAV 存在 |
| 11 | 死亡→death | **FAIL** | 全仓 `AudioMgr` 调用点仅 6 处（grep 验证），无任何死亡接线；`KEYS` 无 death；目录无 death.wav。**注意**：存在现成 `enemy_die.wav`（0.3s），且 `audio/generated/MANIFEST.md` 需求清单明确标注其接线位置为 "EventBus.enemy_killed 消费处"。记 Major① |
| 12 | set_music_volume/get 接 SaveSystem.settings | **FAIL**（部分） | 仅实现 `set_sfx_volume/get_sfx_volume`。代码注释声称"控制器决议：总线布局留给 M3 音量 UI 卡再议"，但 `docs/superpowers/` 下无任何书面决议存档可佐证（仅有代码内注释自述）。记 Major② |
| 13 | 不做 music（T23 的活，不得越界） | **PASS** | 无 play_music/曲目/Boss 切层代码；music 目录既有 5 曲未被触碰 |
| 14 | TDD：8 语音轮转断言 | **PASS** | `test_pool_round_robin_reuses_all_eight_and_steals_oldest`：8 次播满全池 + 第 9 次 pitch 1.5 落在 players[0] 证明轮转夺最旧 |
| 15 | TDD：未知 key push_warning 不崩 | **PASS** | `test_unknown_key_warns_once_and_is_silent_noop`（警告恰 1 次、全池 stream 为 null）；额外覆盖"已知 key 但 WAV 缺失"负路径（`test_missing_wav_warns_once_and_noops`，超出规格要求） |
| 16 | TDD：音量设置持久化读取 | **PASS** | `test_sfx_volume_persisted_to_settings_and_disk`（活动设置 + 落盘 JSON 双断言）+ `test_ready_reads_persisted_volume`（_ready 读回并施加到池） |

## 质量发现

### Blocker（无）

### Major

1. **死亡音未接线**。规格接线点"死亡→death"完全缺失；`enemy_die.wav` 现成可用、MANIFEST 已给出建议接线位（`EventBus.enemy_killed` 消费处或 `enemy_base.gd:145 die()`）。敌人死亡是基础战斗反馈，缺失可感知。修复 ≈2 行（KEYS +"enemy_die"、die() 或 enemy_killed 消费处加 play）。
2. **set_music_volume/get_music_volume API 缺失**。规格原文明确列出该 API 属本卡（M3 才补 UI）。实现以代码注释形式声称"控制器决议"延后，但仓库内无决议文档可查证——独立评审只能按计划文本判缺。风险低（消费方在 M3），但要么补 API（≈6 行，镜像 sfx_volume 三件套），要么补书面决议记录进 docs。

### Minor

1. music 2 通道未建——与"不做 music"边界条款一致，留给 T23，属规格内部张力的合理裁定（见符合度 #2）。
2. `pickup.gd:56` 的 `"pickup_" + kind` 字符串拼接——位于 `_on_body_entered` 信号回调（离散事件、低频），**不在** `_process`/`_physics_process`，Global Constraint 5 字面合规。可选优化：kind→key 常量映射查表，彻底零分配。
3. `KEYS` 为 Array，`has()` 线性扫 11 项——零分配、无违规，纯微优化空间（Dictionary/PackedStringArray）。
4. 计划卡"12 个既有 WAV"与实际 47 个不符——计划信息过时，建议编排者随 T23 更新（非实现者问题）。
5. 测试 `_tmp_settings()` 用全局 `randi()`（不经 RngSvc）生成临时文件名——仅测试文件路径随机化，不触及玩法确定性契约，可接受。

### 正面亮点（质量维度）

- **热路径合规**：`combat_system._physics_process` 内两处调用均为字符串字面量 key；`play()` 缓存命中路径零分配（KEYS.has → _streams.has → 取池播放，无拼接无新建 Dictionary）；首次 miss 才 `load()` 并负缓存——正是 M1 终审 Important ① 确立的 ArtLookup 缓存模式。
- **池语义自洽**：严格 round-robin，游标序=最旧使用序，8 语音全忙时第 9 次自然夺最旧（语音窃取标准做法），注释推导清楚；stream 实例同 key 全池共享（`test_stream_cache_reuses_same_instance` 断言同实例）。
- **headless/裁剪 fail-soft 完整**：未知 key 警告一次即静默；已知 key 但 WAV 缺失（`ResourceLoader.exists` 预检）同样警告一次 + 负缓存（缺失 key 不重复探测磁盘）；实测 headless 全量跑通无崩溃。
- **音量细节**：0 线性映射 -80 dB 而非 -inf，避免 volume_db 无穷值；clamp 双向越界均有断言。
- **测试卫生（对照 M1 终审 testgun 夹具教训）**：`after_test` 逐个删除临时存档文件（含 .tmp）；`save_path` 注入全新 SaveSystem 替身，不触碰真实 `user://save.json`（与 `test_save.gd` 既定 SpySaver 模式一致）；所有实例 `auto_free`；全局 autoload 仅只读断言不写状态；`SpyWarn` 只覆写 `_warn` 不打扰真实警告通道；全量 **0 orphans** 佐证无泄漏。
- **改动最小性**：`project.godot` 仅 +1 行；AudioMgr 注册在 SaveSystem 之后（`_ready` 读设置的正确依赖序，且有测试锁该序）；5 个接线文件各 +1~6 行；`.uid` ×2 按规提交；两个 commit 均带卡号（682010a feat + d43d1c3 style 缩进修复），历史干净。

## 测试实测计数

| 步骤 | 结果 |
|---|---|
| `godot --headless --path . --import` | exit 0 |
| GdUnit4 全量（`-a res://tests --ignoreHeadlessMode`） | **733/733 PASSED**，48/48 套件，0 errors / 0 failures / 0 flaky / 0 skipped / **0 orphans**，2min 46s |
| 与实现者声称（733/733）比对 | 一致 |
| 新增测试 | `tests/unit/test_audio_mgr.gd` 9 个用例，全过 |
| 评审副作用 | import 产生 `icon.svg.import` 行尾变更，评审员已 `git checkout --` 还原，worktree 现为干净 |

## 修复建议清单（Approved-with-notes 附带，T23 前必须闭环）

1. **[Major①] 补死亡音接线**：`KEYS` 追加 `"enemy_die"`；在 `enemy_base.gd:145 die()`（`died.emit` 前后皆可）或 `EventBus.enemy_killed` 消费处加 `AudioMgr.play("enemy_die")`。附一条轮转/缓存复用断言即可（现有测试模式照搬）。若规格坚持字面 key "death"，则需在 audio_mgr 加别名映射（key→文件名），建议直接用 enemy_die 键并回报编排者修订计划行文。
2. **[Major②] 补 set_music_volume/get_music_volume**（镜像 sfx 三件套：clamp→施加→`set_setting("music_volume")`，_ready 读回），或在 docs 补书面控制器决议存档说明延后至 M3/T23 的依据。
3. **[Minor②可选] pickup key 查表化**：`const PICKUP_KEYS := {"coin":"pickup_coin", ...}` 消除事件回调内拼接。
4. **[给编排者] 计划卡更新**：T5 卡"12 个既有 WAV"改为实际 47；确认 death 键名口径（enemy_die）。
