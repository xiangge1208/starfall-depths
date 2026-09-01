class_name TrialSystem
extends RefCounted
## 每日试炼引擎（M3-R-A）：业务日 / 每日种子 / 因子抽取 / mods 注入素材。
## 纯逻辑类（同 TalentSystem 习语：RefCounted + 实例方法直引 autoload）。
## 数据源唯一 = GameDB.trials（data/trials.json 经 GameDB fail-closed 装载）；
## 本卡只建通道：抽取结果经 RunState.start_trial_run 单点注入 RunState.mods，
## 全系统消费侧只读 RunState.mods，禁止散读 trials.json（消费接线随 R-B/J 后续卡）。
##
## 墙钟豁免口径（60Hz 逻辑帧禁墙钟的唯一例外 = 试炼入口读系统日期，元游戏调度）：
## today_date() 是本卡唯一直读 Time.get_datetime_dict_from_system() 的薄包装；
## 其余纯逻辑（business_date / daily_seed / pick_factors）全部时间参数注入、
## 随机只走 RngSvc 派生链复刻——全局 randi()/randf() 禁令全卡零违反。
##
## 规格 §2 一次定稿（换式即换当日布局，实现定稿后不得更换）：
## - trial_seed = stable_hash(盐"trial" 的 FNV, trial_date 串的 FNV)——纯整数运算，
##   跨会话/跨平台确定；种子不含角色 id（同日所有人同布局，角色自由选择）；
## - 抽取流种子精确复刻 RngSvc.stream 派生链（run_seed=trial_seed、floor_idx=0、
##   salt=RunState.SALT_TRIAL），等价性由 test_trial_system 钉死（防实现漂移）。

## 业务日回退步长：05:00 刷新点前的时刻归前一业务日（规格 §2）
const DATE_SHIFT_SECONDS := 86400


## 每日种子（规格 §2 一次定稿式）：stable_hash(盐"trial"，日期串)。同日多次调用恒等；
## 日期串 = business_date 产出的 "YYYY-MM-DD"（跨月/跨年由日历运算保证唯一拼写）。
func daily_seed(date_str: String) -> int:
	return RngSvc.stable_hash(RngSvc._salt_hash(RunState.SALT_TRIAL),
		RngSvc._salt_hash(date_str))


## 业务日（规格 §2）：本地时区 05:00 为刷新点，t < 05:00 归前一业务日。
## 纯函数：dt 为 Time.get_datetime_dict_from_system() 同形字典（墙钟只经 today_date
## 注入，本函数不读墙钟）；日运算走 Unix 时间 ±86400（纯日历换算，跨月/跨年/闰年
## 由 Time 单例的日历数学保证，输入按统一口径换算不影响 ±1 天的日期结果）。
func business_date(dt: Dictionary) -> String:
	var unix := Time.get_unix_time_from_datetime_dict({
		"year": int(dt.get("year", 0)), "month": int(dt.get("month", 1)),
		"day": int(dt.get("day", 1)), "hour": int(dt.get("hour", 0)),
		"minute": int(dt.get("minute", 0)), "second": int(dt.get("second", 0)),
	})
	if int(dt.get("hour", 0)) < GameDB.TRIAL_REFRESH_HOUR:
		unix -= DATE_SHIFT_SECONDS
	var shifted := Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [int(shifted["year"]), int(shifted["month"]), int(shifted["day"])]


## 试炼入口唯一墙钟直读点（硬约束豁免口径）：读系统日期 → 业务日。
## 元游戏调度用（主菜单试炼入口 / 每日布局展示），战斗逻辑禁调本方法。
func today_date() -> String:
	return business_date(Time.get_datetime_dict_from_system())


## 每日因子抽取（规格 §2）：候选 = GameDB.trials 的 id 升序表 → 局部 rng（种子复刻
## RngSvc.stream 派生链，见 _pick_rng_seed）Fisher-Yates 全洗牌取前 pick_per_day 条
## → 按 id 升序输出（抽取结果排序后使用，保证同日跨会话/跨角色因子组合一致）。
## 无副作用：不改写 RngSvc.run_seed、不动 RunState（主菜单预览安全，裁定③）。
func pick_factors(date_str: String) -> Array[String]:
	var candidates: Array[String] = []
	for id: String in GameDB.trials:
		candidates.append(id)
	candidates.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = _pick_rng_seed(date_str)
	for i: int in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: String = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp
	var picked: Array[String] = []
	for id: String in candidates.slice(0, mini(GameDB.TRIAL_PICK_PER_DAY, candidates.size())):
		picked.append(id)
	picked.sort()
	return picked


## 抽取流种子（规格 §2 一次定稿）：精确复刻 RngSvc.stream(floor_idx, salt) 的派生链于
## run_seed=daily_seed(date_str)、floor_idx=0、salt=RunState.SALT_TRIAL——
## 与 RngSvc.setup_run(daily_seed) 后 RunState.stream(SALT_TRIAL)（floor_idx=0）的
## 首抽序列严格一致（test_pick_rng_seed_equals_runstate_stream_derivation 钉死）。
func _pick_rng_seed(date_str: String) -> int:
	return RngSvc.stable_hash(RngSvc.stable_hash(daily_seed(date_str), 0),
		RngSvc._salt_hash(RunState.SALT_TRIAL))


## 当日因子 mods 合并（RunState.mods 单点注入素材）：按因子 id 升序遍历
## （pick_factors 已排序）；键冲突理论不存在（8 因子 mods 键互不相交），
## 若发生 later-wins + push_warning 防御（数据契约被破坏时的可观测信号）。
func pick_mods(date_str: String) -> Dictionary:
	var mods: Dictionary = {}
	for id: String in pick_factors(date_str):
		var row: Dictionary = GameDB.trials.get(id, {})
		var factor_mods: Dictionary = row.get("mods", {})
		for k: String in factor_mods:
			if mods.has(k):
				push_warning("TrialSystem: mod key collision '%s' (later wins)" % k)
			mods[k] = factor_mods[k]
	return mods
