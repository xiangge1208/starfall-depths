# M1 全分支终审报告（含 codex 37k 行联合审计）

- 日期：2026-08-30
- 范围：ddf05b6 → m1（tag）→ 82ab73c（收尾提交）；含外部 codex 交付（a7fd947，37k 行）联合审计
- 结论：**Ready to close M1? Yes**（无 Critical；3 项 Important 全部裁定为 M2-S0 首波任务）
- 复核：终审员亲自跑 720/720（47/47 套件，0 孤儿）；1000/1000 种子；全循环烟测 3 种子

## 终审亮点

1. 纯逻辑类纪律贯穿全线（floor_flow/inter_floor_flow/shop_logic/element_proc/hud_snapshot/death_recorder 全部可无头测试）
2. RNG 架构无状态化、floor-safe；全库仅 2 处豁免墙钟（run seed 熵源、fx hitstop 真实毫秒）
3. M0 系统在 M1 接线后回归面干净（弹幕反弹/共鸣/400 上限/hitstop×shake 互斥均有回归测试钉住）
4. codex 37k 行交付在敌意抽样下干净：无测试放水（全分支 2409 增断言 vs 仅 1 删且为强化替换）、enemy_factory fail-closed、element_proc 盐纪律正确
5. 主循环 30 分钟链路端到端真实接线，追踪无死端/软锁

## Important（3 项，全部裁定为 M2-S0 首波）

1. ArtLookup 弹幕视觉路径逐帧字符串拼接（~30k allocs/s @500弹）→ 静态 (faction,element)→Texture2D 备忘
2. 真人鼠标完整一局（含 Boss 三阶段 + 商店实买/回收 + 三选一生效确认）→ M2 W0/S0 第 1 项
3. SALT_LOOT 五处同种子重派生（黑商=雕像首抽=饮料机首抽的关联性）→ M2 S0 改为每设施独立盐或常驻流

## 遗留分流表（M2 计划头部直接引用）

**MUST-FIX-NOW（M2-S0 首波）**：上表 3 项 + testgun_cost5 夹具清理 + scratch 产物清理/.gitattributes（已部分完成）。

**DEFER → M2 对应束**：
- A 地牢：单种子确定性采样/重复 next 校验/叶子共享；T10 门链与 13 房性能
- B 角色：双持×射速门交互/DR 窗口边界/can_cast 空玩家/影袭墙体夹取/鹰眼暴击协同签认
- C 数据：BuffManager 顺序依赖/稀有度计数（energy_max uncommon→common 已按附录对齐）/乞丐哨兵不变量
- E 局外：spend_coins 负数守卫/run_time 门控/≤32 位种子熵/unlocked_heroes 未强制/存档 migration v2
- F 流程：死亡回顾最高 DPS 采样/乞丐哨兵/幸存者回放
- G 音频：52 WAV 接线（AudioStreamPlayer + bus）+ audio_mgr autoload + 5 曲 musicgen
- H 性能/门禁：hud_snapshot 每帧分配/门 16×36 拉伸/元素弹阵营中立/A2 里程碑围墙
- I 美术：敌人 2 帧动画/英雄 4 向行走帧/元素弹阵营分化贴图

**DROP（无玩家或测试可见影响）**：DoT 绕过阶段门（已验证修复）、近战暴击缝（已修复）、起始房 nil-combat 报错（已修复+回归测试）、testgun_cost5（T25 重写夹具机制后孤儿消失）、RING_READY 死分支、种子熵 ≤32 位（控制器裁定公式）、shield_broken 无源身份、单例场景测试恒真断言。

## 建议（M2 计划头部纳入）

1. M2 以 3 项微卡开局（S0）：真人试玩 + SALT_LOOT 每设施独立盐 + ArtLookup 纹理备忘
2. rng_svc.gd 头部写入流派生契约："每消费者每层缓存一个流实例，禁中途二次派生"
3. Balance Bot W1 先跑 A1 无头周报（弹环翻倍后的巨像压力数据先行），真人试玩验证手感而非调参
4. C 数据束（+75 武器/+21 增益/15 配方）加"转录双检"步骤（M1 两次转录滑消耗了修复轮）
5. 每束末卡显式集成收口（M1-T27 教训，roadmap §2.1 已编码）
