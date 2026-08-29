# M1 Gate — Integration Guard Report

## RE-RUN after m1-t27 integration (2026-08-28)

- Repo: D:\workspace\thomas, branch `main`, HEAD `9ef819d` (`merge: m1-t27 main loop integration into main`) — matches expected post-merge HEAD.
- Godot: `4.7.2.stable.official.ed1daf0bf` (WinGet PATH shim; `GODOT` env unset).
- Tooling note: from Git Bash, plain `cmd /c` is path-mangled into an interactive cmd (first attempt ran zero tests, discarded); must use `MSYS_NO_PATHCONV=1 cmd /c "tools\run_tests.cmd"`.
- Prior-run residue confirmed fixed: the 180 untracked `m0-evidence/*.png.import` sidecars (F1) and the m1 evidence sidecars are now committed/tracked.

### Check 1 — Full test suite: PASS

Command: `MSYS_NO_PATHCONV=1 cmd /c "tools\run_tests.cmd"`.

- Exit code: **0**
- `Overall Summary: 570 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans`
- `Executed test suites: (42/42)` / `Executed test cases : (570/570)` — 24s 140ms (vs 558/558, 41/41 at `8b0a5b7`; +12 tests, +1 suite from the m1-t27 integration work)
- `SCRIPT ERROR` count: **0**
- Console ERROR/WARNING lines (26 total): all within the accepted-noise list — GameDB negative-test ERRORs (missing/bad-json/id-mismatch/type-mismatch/not-a-dictionary/unknown-start-weapon/bad-effect), room-template spawn-door rejection (`test_bad_room_t4.json ... within 64px of door`), buffs `unknown buff no_such_buff` / `unique buff extra_projectiles already picked`, SceneRouter `unknown route key '__nope__'` / `'no_such_route'`, RoomCombat spawn-fallback WARNING x2 — plus the previously documented informational negative-path set (Shrine/DrinkMachine negative kinds/effects, test_save corrupt/nondict fallback + JSON parse errors, EnemyBase archetype / EliteAffix warnings, 2x engine `Can't use get_node() with absolute paths` in the router negative test). Nothing new or unexpected.

### Check 2 — Boot smoke: PASS

Command: `godot --headless --path . --quit-after 300`.

- Exit code: **0**; log is the version banner only; `SCRIPT ERROR` count: **0**.

### Check 3 — 1000-seed dungeon validation: PASS

Command: `godot --headless --path . --script res://tools/validate_dungeon.gd`.

- Exit code: **0**; output: `1000/1000 PASS`.

### Check 4 — Determinism: PASS

Second identical suite run.

- Exit code: **0**; same summary `570 | 0 | 0 | 0 | 0 | 0`, 42/42 suites, 570/570 cases.
- Normalized full-log diff (per-test durations, `report_N` dirs, random fixture names masked): sole remaining delta is one suite's total-duration string (`PASSED 1s` vs `PASSED`) — pure timing jitter, no behavioral difference.
- ERROR/WARNING line streams byte-identical between runs (26 = 26) after masking randomized `user://test_save_{corrupt,nondict}_<rand>.json` fixture names.

### Check 5 — Repo hygiene: FAIL (regressed with new untracked evidence)

- HEAD `9ef819d` ✓; branch `main` ✓; `git tag` → `m0` only, **no `m1` tag** ✓ (none created by this battery).
- `git status --porcelain` → **NOT empty**: 57 entries, byte-identical pre- vs post-battery (battery itself added nothing; gdUnit4 artifacts land in gitignored `/reports/`, verified via `git check-ignore`):
  - 46 `??` untracked: 22 new evidence PNGs under `docs/superpowers/reports/m1-evidence/` (01-main-menu … playtest-session screenshots) + 11 new `.png.import` sidecars for them + `docs/superpowers/reports/m1-gate-playtest.md` + this report file.
  - 11 `M` on already-committed `m1-evidence/*.png.import`: **line-ending-only** (working-copy CRLF vs index LF; `git diff --ignore-cr-at-eol` empty, zero content change).
- R1 (blocking): post-merge playtest session left 22 PNGs + 11 sidecars + `m1-gate-playtest.md` uncommitted. Fix: commit them (same remedy as the prior sidecar fix).
- R2 (cosmetic, non-blocking): EOL-normalization false-modification on 11 tracked sidecars; resolves with R1's commit (or a `.gitattributes` text rule).

### RE-RUN verdict

Functional battery fully green on the integrated tree (570/570 twice, clean boot, 1000/1000 seeds, deterministic ERROR/WARNING streams). Sole blocker is repo hygiene again: new uncommitted m1 evidence artifacts (R1). Formal verdict: end of file (supersedes the prior run's verdict line below).

---

# Prior run — initial gate battery (HEAD 8b0a5b7)

- Date: 2026-08-29 (battery window ~09:05–09:20 +0800)
- Repo: D:\workspace\thomas, branch `main`, HEAD `8b0a5b7` (`merge: m1-hygiene hud wiring + smoke flush into main`)
- Godot: `4.7.2.stable.official.ed1daf0bf` (WinGet shim `C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot.exe`, `GODOT` env unset)
- Baseline captured before any run: `git status --porcelain` already showed untracked `docs/superpowers/reports/m0-evidence/*.png.import` files.

## Check 1 — Full test suite: PASS

Command: `cmd /c "tools\run_tests.cmd"` (i.e. `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode`), from repo root.

- Exit code: **0**
- `Overall Summary: 558 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans`
- `Executed test suites: (41/41)` / `Executed test cases : (558/558)` — total 24s 57ms
- 0 `SCRIPT ERROR` lines.

Console ERROR/WARNING lines vs accepted-noise list:

Accepted per gate definition (all present, all matched): GameDB negative-test ERROR lines (missing/bad-json/id-mismatch/type-mismatch/not-a-dictionary/unknown-start-weapon/bad-effect), test_room_templates spawn-door rejection (`GameDB user://test_bad_room_t4.json row bad: spawn_points[0] [11, 2] within 64px of door`), test_buffs `BuffManager: unknown buff no_such_buff` + `unique buff extra_projectiles already picked`, test_scene_router `SceneRouter: unknown route key 'no_such_route'` + `'__nope__'`, test_room_flow spawn-fallback WARNING (`RoomCombat.filter_spawn_points: all points filtered — falling back to raw points, spawn invariants dropped`).

Beyond the accepted list (see Finding F2 — noise-level, all from deliberate negative tests, all associated test cases PASSED):
- test_facilities.gd: `ERROR: Shrine: unknown kind bogus`, `ERROR: Shrine: xingsui requires weapon_rig`, `ERROR: DrinkMachine: unknown drink effect fly`
- test_save.gd: `ERROR: Parse JSON failed. Error at line 0: Expected '}'` / `Expected key`, 2x `ERROR: SaveSystem: corrupted save user://test_save_{corrupt,nondict}_<rand>.json — falling back to defaults (fail-soft)`
- test_elites.gd: `WARNING: EnemyBase: unknown archetype 'nope'` (test_unknown_archetype_stays_on_base_and_warns), `WARNING: EliteAffix: unknown affix 'bogus'` (test_unknown_affix_is_ignored)
- test_scene_router.gd `test_hero_select_choose_router_absent_no_crash`: 2x engine `ERROR: Can't use get_node() with absolute paths from outside the active scene tree.`

## Check 2 — Boot smoke: PASS

Command: `godot --headless --path . --quit-after 300`

- Exit code: **0**
- `SCRIPT ERROR` count: **0**. Entire log: `Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org` (banner only, no errors/warnings).

## Check 3 — 1000-seed dungeon validation (M1-T7): PASS

Tool header (`tools/validate_dungeon.gd`) prescribes: `godot --headless --path . --script res://tools/validate_dungeon.gd`.

- Exit code: **0**
- Output: `1000/1000 PASS` (seeds via `DungeonBuilder.seed_at(i)`, build + validate_build per seed; no failing seeds, no fallback usage).

## Check 4 — Determinism: PASS

Command: second identical `cmd /c "tools\run_tests.cmd"`.

- Exit code: **0**; `Overall Summary: 558 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans`; 41/41 suites; 558/558 — identical counts to run 1.
- Full-line diff of all ERROR/WARNING lines between runs: identical except the random numeric suffix in test_save fixture filenames (`test_save_corrupt_2790937810` vs `2460524514`, `test_save_nondict_1060550269` vs `2955372232`) — the suites generate randomized temp filenames; no behavioral difference.

## Check 5 — Save roundtrip in isolation: PASS

Command: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/test_save.gd --ignoreHeadlessMode`

- Exit code: **0**; `Statistics: 14 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans | PASSED`; `Executed test cases : (14/14)`.
- Includes `test_roundtrip_persists_all_fields`, `test_settings_roundtrip`, corruption/nondict fallback, migration tests — all PASSED.
- Leakage: none. `user://` resolves to `%APPDATA%\Godot\app_userdata\<project>\` (outside the repo); test save files use randomized `user://test_save_*.json` names and are cleaned up by the suite. gdUnit4 XML/HTML artifacts land in `/reports/` which is gitignored. Post-battery `git status --porcelain` contains no save-related entries.

## Check 6 — Repo hygiene: FAIL

- `git log --oneline -1` → `8b0a5b7 merge: m1-hygiene hud wiring + smoke flush into main` — matches expected HEAD.
- `git tag` → `m0` only. No `m1` tag exists; none was created by this battery (correct — tag only after gate pass).
- Branch: `main`.
- `git status --porcelain` → **NOT empty**: 180 lines, all `??` untracked `docs/superpowers/reports/m0-evidence/*.png.import` (Godot-generated import sidecars for the m0 evidence PNGs). Zero modified/staged tracked files. The untracked set is byte-identical to the pre-battery baseline — file mtimes are all 2026-08-28 22:37:50 (+0800), i.e. created by a prior godot run before this gate battery; this battery added nothing. These sidecars are not covered by `.gitignore` (which lists `.godot/`, `*.tmp`, `user_export/`, `/reports/`, `.worktrees/`).

## Findings

- **F1 (blocking, Check 6):** 180 untracked `docs/superpowers/reports/m0-evidence/*.png.import` Godot import sidecars; `git status --porcelain` is not clean. Pre-existing (created 2026-08-28 22:37, before this battery); not caused by any gate run. Fix: either commit the sidecars alongside the tracked PNGs or add a gitignore rule (e.g. `docs/**/*.png.import`).
- **F2 (informational, non-blocking):** negative-test console ERROR/WARNING output beyond the gate's documented accepted-noise list (test_facilities Shrine/DrinkMachine, test_save corrupt-save fallback + JSON parse, test_elites archetype/affix warnings, test_scene_router `get_node()` absolute-path engine errors). Every associated test case PASSED; these are deliberate negative-path prints. Recommend extending the accepted-noise list in the gate definition.

Functional checks are all green (558/558 twice, clean boot, 1000/1000 seeds, save 14/14, no leakage, no stray tag); the sole gate-blocking item is the repo-hygiene finding F1.

INTEGRATION GUARD VERDICT: RED (findings: F1 git status not clean — 180 pre-existing untracked docs/superpowers/reports/m0-evidence/*.png.import sidecars, not gitignored; F2 informational — negative-test console noise beyond accepted list, all tests PASSED)

INTEGRATION GUARD VERDICT: RED (findings: R1 git status not clean — 22 untracked docs/superpowers/reports/m1-evidence/*.png + 11 new .png.import sidecars + m1-gate-playtest.md left uncommitted by the post-merge playtest session; R2 cosmetic — 11 tracked sidecars flagged M by EOL normalization only, no content change)
