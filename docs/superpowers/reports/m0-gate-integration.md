# M0 Gate — Integration Guard Report

- Date: 2026-08-28
- Repo: D:\workspace\thomas (main @ `3814a85` — "fix(m0-t12): hitstop extension early-unpause, loud spawn fallback, contact damage, riders")
- Godot: v4.7.2.stable.official.ed1daf0bf (winget shim on PATH: `C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot.exe`)
- Guard scope: read-only verification; only write is this report.

## Check 1 — Full test suite

- Command: `cmd //c "tools\run_tests.cmd"` (script resolves `godot` from PATH; runs `--headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode`)
- Exit code: **0**
- Expected: 55/55 cases, 0 errors/failures/orphans, exit 0
- Actual: `Overall Summary: 55 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans |` (all 18 suite blocks PASSED)
- WARNING/ERROR scan (ANSI-stripped full log, 302 lines) — exactly 2 lines, both known-accepted:
  - `ERROR: GameDB user://test_bad_row.json row laohuoji: not a dictionary` (known-accepted fixture line, test_game_db)
  - `WARNING: RoomCombat.filter_spawn_points: all points filtered — falling back to raw points, spawn invariants dropped` (known-accepted spawn-fallback, test_room_flow)
- No other WARNING / SCRIPT ERROR / FAILED lines.
- Result: **PASS**

## Check 2 — Boot smoke

- Command: `godot --headless --path . --quit-after 300`
- Exit code: **0**
- Expected: exit 0, no script errors
- Actual: full output is 2 lines — `Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org` + blank line. Zero ERROR / SCRIPT ERROR / WARNING lines.
- Result: **PASS**

## Check 3 — Determinism probe

- Command: `cmd //c "tools\run_tests.cmd"` (second run)
- Exit code: **0**
- Actual: identical to run 1 — `Overall Summary: 55 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans |`; the same 2 known-accepted lines at identical log positions (lines 84 / 197), no flaky markers (gdUnit reports `0 flaky`).
- Result: **PASS**

## Check 4 — Telemetry artifact sanity

- Path checked: `%APPDATA%\Godot\app_userdata\StarfallDepths\telemetry.csv`
- File exists: yes (234 bytes, mtime 19:52 — immediately after boot smoke)
- First 3 lines:
  ```
  event,ts_frame,v1,v2,v3
  m0,1,2
  hit,24351,2,0
  ```
- Result: **PASS** (write path functional on this machine)

## Check 5 — Repo hygiene

- Commands: `git status --porcelain` (before and after all runs), `git log --oneline -1`
- `git status --porcelain`: empty (exit 0) — tree clean; gdUnit artifacts land in `/reports/` and `.godot/`, both gitignored.
- `git log --oneline -1`: `3814a85 fix(m0-t12): hitstop extension early-unpause, loud spawn fallback, contact damage, riders` (branch: main)
- Result: **PASS**

## Findings

None. The only WARNING/ERROR lines observed are the two documented known-accepted lines (GameDB bad-row fixture ERROR; test_room_flow spawn-fallback WARNING). Boot is silent, suite is deterministic across two runs, telemetry writes, and the tree is clean at the gate commit.

INTEGRATION GUARD VERDICT: GREEN
