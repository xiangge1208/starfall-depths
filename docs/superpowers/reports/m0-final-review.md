# M0 全分支终审报告（final whole-branch review）

- 日期：2026-08-28
- 范围：2b43812..8ffae12（tag m0）+ 终审修复波 df9f9fa
- 结论：**Ready to close M0: Yes**；修复波复评 5/5 ADDRESSED、无新破坏
- 终审时点证据：55/61 单测（修复后 61/61）+ 43 项 e2e 冒烟全过

## 终审亮点（Strengths 摘要）

1. 种子 RNG 严谨度超阈值：FNV-1a-64 + Python 参考实现 + 十进制字面量钉死，跨引擎位稳定有回归保护。
2. 60Hz 逻辑时钟纪律全通过：逻辑路径零墙钟、零全局 RNG（表现层例外均有注释）。
3. hitstop Critical 修复教科书级（权威计时器交接 + 精确回归）。
4. e2e 冒烟（43 检查）覆盖了单任务评审看不见的跨任务接缝。
5. 数据驱动契约贯彻：武器/敌人/波次/奖励全 JSON，fail-closed 校验，数值与附录逐字一致。

## 终审发现与处置（全部已修复于 df9f9fa）

| # | 级别 | 问题 | 修复 |
|---|---|---|---|
| 1 | Important | 池满驱逐绕过 _kill → 空间哈希条目泄漏（饱和下无界增长） | `on_evict` 回调接线 `_kill`；哈希计数回归测试（601≠501 判别） |
| 2 | Important | 哈希查询余量硬编码 12px，radius>12 的实体被静默漏判 | `_max_body_radius` 单调跟踪；radius-20 回归测试 |
| 3 | Important | SHATTER AoE 包含触发体 | self/DEAD 排除 + 测试 |
| 4 | Important | 附录 B.1 苦力虫"死亡即刻爆"未实现（控制器裁定：die() 统一拥有爆炸，自杀虫去重） | die() 死亡爆炸 + 玩家 i-frame 节流 + 单次爆炸测试 |

## Deferred-Backlog 分流表（终审裁定，M1 规划的直接输入）

**FIX-M1-ENTRY（已在本修复波完成）**：池驱逐泄漏 / 查询余量 / SHATTER 自包含。

**DEFER（已在 M1 任务束中定位）**：
- M1-B（房型框架）：房间配置 schema 校验；敌方实例复用需 setup() 全量重置；set_script 原型挂载改 preload 映射；木桩无碰撞化
- M1-D（角色线）：翻滚免疫/fatal/heal 钳制覆盖；武器架改 E 键交互；删除 `_last_damaged_frame` 死代码
- M1-E（数据线）：GameDB 测试夹具清理（testgun/testgun3）；加载器覆盖缺口补测；from_name/共鸣 NONE 路径补测（元素武器接入前置）；子弹 life/radius/muzzle 入表
- M1-F（Boss/敌人线）：自杀虫 14px 门控与 aoe 参数补测；透视（无 LOS）接触伤害留意；弹幕上限 400（敌）/500（池）与 GDD §7.5 对齐
- M1-G（局流程）：`RngSvc.setup_run` 必须在开局调用（当前恒 0，种子链未激活）；RNG 流按用途分盐（proj_crit/rig）；死亡结算画面
- M1-H（HUD/Juice）：遥测集中化（缓冲/轮转/hurt 行覆盖独立战斗房）；击杀遥测来源标记；enemy_damaged 死信号启用或删除；_find_sprite 约定

**DROP**：文档提交规范、icon.svg、input device id、physics_ticks 键存续、_salt_hash 重复、桶字典未类型化、未知原型 fail-soft、smoke 4/10 按键断言——均无风险或已被后续证据覆盖。

## 遗留观察（无行动，记录备查）

- 池无回调驱逐路径现在会先 on_despawn 再复用（净效果不变）
- _death_explosion 的 aoe 默认值 0 严格化（旧代码默认 40/8）——未来新行必须显式给出
- 接触伤害无 LOS 检查（裁定允许）；冒烟接触断言是不等式（证明发生不证明数值）
