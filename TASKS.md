# NONO — Code Audit Task List

Generated from a full read-only audit of `scripts/`, `scenes/`, `tools/`, `tests/`
(Godot 4.7.2, GDScript, `gl_compatibility`).

Items marked **[VERIFIED]** were confirmed empirically by running throwaway headless
Godot probes (`Godot_v4.7.2-stable_mono_win64_console.exe --headless --path .
--scene res://tests/audit_main.tscn`). The probe files were deleted after the run;
no project files were modified by the audit.

**Scope of this file:** fix the bugs and performance issues below. Do not refactor
unrelated code, do not rename the project, and do not edit anything under `addons/`
unless a fix explicitly requires it.

---

## Priority summary

| # | Severity | Area | Title | Status |
|---|----------|------|-------|--------|
| 1 | CRITICAL | Audio | Music dies permanently on overlapping crossfades | ☑ |
| 2 | MAJOR | Gameplay | Upgrade pool exhausts at wave 7 | ☑ |
| 3 | MAJOR | Flow | Retry does not unpause → frozen run | ☑ |
| 4 | MAJOR | Gameplay | Standing inside the boss deals no damage | ☑ |
| 5 | MAJOR | Mobile UI | Touch controls live above the upgrade panel | ☑ |
| 6 | MAJOR | Memory | MAGNET/SHIELD power-ups are never freed | ☑ |
| 7 | MODERATE | Perf/I-O | `save_settings()` writes to disk per slider frame | ☑ |
| 8 | MODERATE | Robustness | `Fx.hitstop` can leave `time_scale = 0` forever | ☑ |
| 9 | MODERATE | Polish | Boss camera not reset on death during boss fight | ☑ |
| 10 | MINOR | Polish | Banner tween race | ☑ |
| 11 | MINOR | Audio | `health_changed` emitted with a negative value | ☑ |
| 12 | MINOR | FX | Popup centering is a no-op | ☑ |
| 13 | PERF | FX | `Fx.burst` / `Fx.popup` node churn | ☑ |
| 14 | PERF | Audio | `Sfx.play` node churn for non-coin sounds | ☑ |
| 15 | PERF | Gameplay | Per-frame `get_nodes_in_group("coins")` in `_tick_magnet` | ☑ |
| 16 | NIT | Maintainability | Duplicated joystick radius constants | ☑ |

---

## CRITICAL

### [x] 1. Music dies permanently if `play()` is called twice within 1.2s **[VERIFIED]**

- **Severity:** CRITICAL
- **File:** `scripts/music.gd:59-76` (`play()`)
- **Triggers:** `main_menu.gd:67`, `game.gd:90`, `game.gd:212`, `game.gd:250`, `game.gd:549`, `music.gd:83`

**Symptom**
Two `Music.play()` calls less than `FADE_TIME` (1.2s) apart leave **both**
`AudioStreamPlayer`s stopped, and the music never comes back for the rest of the run.
No audio at all for the entire session.

**Root cause**
`play()` never kills the previous crossfade tween. It picks the incoming/outgoing
players by swapping indices:

```gdscript
var incoming_idx := 0 if _current_idx != 0 else 1
var outgoing_idx := 1 - incoming_idx
...
var tw := create_tween().set_parallel(true)
tw.tween_property(incoming, "volume_db", 0.0, fade)
tw.tween_property(outgoing, "volume_db", -80.0, fade)
tw.chain().tween_callback(func() -> void:
	outgoing.stop())
```

On the second call the two players swap roles, so the **old** tween's
`tween_callback(outgoing.stop())` now targets the player that just became the
**new incoming** track — killing it mid-fade. Measured trace (`menu` at t=0,
`battle` at t=0.5):

```
p0.stream=menu_theme.wav    playing=false  vol=-80.0
p1.stream=battle_theme.wav  playing=false  vol=0.0
any_player_audible=false
```

Compounding it: `_active` is left as `"battle"`, and the `key == _active` guard
makes every later `play("battle")` a no-op — so it never self-heals.

**Reachable path**
`main_menu.gd:67` plays `"menu"`. If the user clicks Play within 1.2s,
`game.gd:90` plays `"battle"` and the race triggers. Also: `_to_menu()` from the
pause menu shortly after a run starts, and Retry from game over.

**Fix**
- Store the tween: `var _fade_tween: Tween` and `_fade_tween.kill()` at the top of
  `play()` (and in `stop()`).
- Capture the outgoing player in a local before building the lambda so the callback
  can never observe a mutated index.
- Consider a short "was stopped by a rival tween" guard: only `stop()` the outgoing
  player if it is no longer the active track.

**Verify**
Headless: call `Music.play("menu")`, wait 0.5s, call `Music.play("battle")`, wait
1.6s, assert exactly one of `Music._players[0|1].playing == true` and that its
`stream` is `battle_theme.wav`. Add as a permanent case in `tests/music_test.gd`.

---

## MAJOR

### [x] 2. Upgrade pool is exhausted at wave 7 — no upgrades for waves 10-50 **[VERIFIED]**

- **Severity:** MAJOR (progression dead-ends for 43 of 50 waves)
- **File:** `scripts/game.gd:22-32` (`BUFFS`), `scripts/game.gd:420-433` (`_pick_upgrade_choices`), `scripts/game.gd:405-418` (`_offer_upgrades`)

**Symptom**
The wave-clear upgrade panel stops appearing entirely from wave 10 onward. Waves 7-9
show a single card under a hint that still reads *"Press 1 / 2 / 3 or click to choose"*.
The player gets no visible signal that upgrades are gone.

**Root cause**
Total available picks = 17 stacked (`speed` 3, `dash` 3, `magnet` 3, `combo` 3,
`value` 5) + 4 one-off (`shield`, `heal`, `maxhp`, `shock`) = **21**, consumed at
3 per wave.

```
wave 6 would offer 3 card(s)
wave 7 would offer 1 card(s): ["value"]
wave 9 would offer 1 card(s): ["value"]
wave 10 would offer 0 card(s): []
```

`_pick_upgrade_choices` returns an empty array, `_offer_upgrades` returns early before
pausing, and the wave simply proceeds.

**Fix (needs a design decision — pick one or a mix)**
- Raise `stack` caps so the pool covers at least 50 waves.
- Add repeatable / infinite-stack entries (e.g. a small permanent score or speed bump).
- Convert the one-offs to stacks.
- Add a documented fallback: when the pool is nearly empty, offer heal/max-HP style
  cards so the panel is never skipped entirely.
- Make the hint text reflect the real card count instead of hardcoding `1 / 2 / 3`.

**Verify**
Extend `tests/upgrade_panel_test.gd` to walk `_pick_upgrade_choices` for 50 waves and
assert it is never empty (or that the documented fallback fires).

### [x] 3. Retry does not unpause — the new run is permanently frozen **[VERIFIED]**

- **Severity:** MAJOR
- **File:** `scripts/game.gd:616-617` (`_retry`)

**Symptom**
`get_tree().reload_current_scene()` does **not** reset `SceneTree.paused`. If the tree
is paused at reload time, the freshly instantiated run never processes input or
physics again — an unplayable, unfrozen-looking but dead screen.

**Root cause**

```gdscript
func _retry() -> void:
	get_tree().reload_current_scene()
```

`_to_menu()` handles this correctly (`_set_paused(false)` first); `_retry()` does not.
Verified:

```
paused_set_before_reload=true
paused_after_reload=true
```

**Fix**
```gdscript
func _retry() -> void:
	Engine.time_scale = 1.0   # see task 8
	get_tree().paused = false
	get_tree().reload_current_scene()
```

**Verify**
Add a case to `tests/smoke_test.gd` asserting `not get_tree().paused` after a real
`reload_current_scene()` (the current smoke test only calls `_set_paused(false)`
manually, which is why it misses this).

### [x] 4. Standing inside the boss deals no damage for the entire overlap **[VERIFIED]**

- **Severity:** MAJOR
- **File:** `scripts/player.gd:118-126` (`on_enemy_contact`), `scripts/enemy.gd:44-50` (`_on_hitbox_area_entered`)

**Symptom**
The player can park inside the boss indefinitely and take zero damage. Dashing
through a boss is safe to do, and there is no reason to disengage.

**Root cause**
Contact is delivered by `Area2D.area_entered`, which fires **only on enter**. For the
boss the handler deliberately does nothing to the attacker:

```gdscript
if enemy is Boss:
    if not is_dashing and _invuln_left <= 0.0:
        apply_boss_damage()
    return
```

If the player is dashing or in i-frames at the instant of entry, nothing is applied
and nothing retries. Verified: `hp_after_holding_overlap=4` across 10 physics frames of
continuous overlap.

**Fix**
Mirror the existing `_tick_dash_damage` approach — add a per-frame proximity check in
`Boss._physics_process`:

```gdscript
# contact damage: proximity every frame, not just area_entered
if _player != null and is_instance_valid(_player) \
        and global_position.distance_to(_player.global_position) < 48.0 \
        and not _player.is_invulnerable():
    _player.apply_boss_damage()
```

(`apply_boss_damage` already re-checks `is_invulnerable()` internally, so the extra
guard is belt-and-braces.)

**Verify**
Add a boss-flow case: set `player._invuln_left = 0.14`, trigger contact, hold the
overlap for several physics frames, assert `hp` drops once the i-frames expire.

### [x] 5. Touch controls stay live and render above the upgrade panel **[VERIFIED]**

- **Severity:** MAJOR (mobile-only)
- **File:** `scripts/game.gd:405-418` (`_offer_upgrades`) — compare `game.gd:108-113` (`_set_paused`) and `game.gd:544` (`_on_player_died`)
- **File:** `scripts/touch_controls.gd:52` (`layer = 5`)

**Symptom**
On mobile, the 97px DASH and PAUSE buttons draw on top of the upgrade cards and stay
tappable while the panel is open. Tapping DASH fires a dash on a paused tree: it sets
`is_dashing = true` with `_dash_left` frozen (physics is paused) and burns the dash
cooldown, so the first input after unpause is a phantom dash.

**Root cause**
`_offer_upgrades()` sets `get_tree().paused = true` but never calls
`touch_controls.set_controls_enabled(false)`. Verified: `enabled_during_upgrade=true`,
`dash_reachable_while_upgrade_open=true`. Layering confirmed: `TouchControls.layer = 5`
vs `UpgradeLayer` at the default layer 1, so it renders above.

**Fix**
```gdscript
# in _offer_upgrades(), alongside get_tree().paused = true:
touch_controls.set_controls_enabled(false)
# and in _hide_upgrade_panel() / on the resume path:
touch_controls.set_controls_enabled(true)
```
Consider also dropping the touch layer below the `UpgradeLayer`/`GameOver`/`PauseLayer`
layers so an enabled control can never sit over a menu.

**Verify**
Add a case to `tests/touch_input_test.gd`: open the upgrade offer, assert
`touch_controls.enabled == false` and `dash_button.visible == false`, and that
emitting `dash_pressed` does not set `player.is_dashing`.

### [x] 6. MAGNET/SHIELD power-ups are never freed — node + draw-call leak **[VERIFIED]**

- **Severity:** MAJOR
- **File:** `scripts/game.gd:264-267` (`_clear_leftover_hearts`), `scripts/power_up.gd:30`, `scenes/power_up.tscn:15`

**Symptom**
Uncollected magnet and shield pickups survive every wave boundary and accumulate for
the whole run, directly contradicting the "flat node count over a long run" intent
documented in `AGENTS.md` and in the code comments.

**Root cause**
`_clear_leftover_hearts()` frees only group `"heart_pickup"`, and
`power_up.gd::_ready()` only joins that group for `Type.HEART`. Magnet and shield join
only `"powerups"` (declared in `scenes/power_up.tscn:15`), which nothing ever clears.
Verified across 6 wave starts: `heart_pickup` → 0, `powerups` → 2 (magnet + shield,
persistent).

Extrapolation: waves 1-49 spawn 945 enemies (`mini(2 + n, 24)`); at the 12%/10% drop
rates that is ~113 magnet + ~94 shield drops. Uncollected ones pile up as `Area2D`
nodes, each running `_process` (`sin()` + `sprite.scale`) and each drawing through the
`actor_outline.gdshader` material — roughly 100 extra draw calls by the boss wave.

**Fix**
Clear the whole `"powerups"` group at the wave boundary — either widen
`_clear_leftover_hearts()` to iterate `"powerups"`, or add a dedicated
`_clear_leftover_powerups()` and call it from `_start_wave()` next to the other two.
Keeping `heart_pickup` is fine (it is used elsewhere); just stop relying on it as the
only cleanup path.

**Verify**
`tests/perf_profiler.gd` already samples `POWERUPS`-style node counts per wave. Add an
assertion that the `"powerups"` group size does not grow monotonically across the
11-wave sim.

---

## MODERATE

### [x] 7. Synchronous disk write on every volume-slider frame

- **Severity:** MODERATE
- **File:** `scripts/game_state.gd:128-137` (`save_settings`), `scripts/main_menu.gd:56-58`, `scripts/main_menu.gd:106-116`

**Symptom**
Dragging a volume slider performs ~60 synchronous `ConfigFile.save()` calls per second
(`fopen`/`fwrite`/`fclose` against `user://nono_settings.cfg`). Causes hitching on slow
storage and pointless flash wear.

**Fix**
Debounce. Cheapest option: in `main_menu.gd`, drive the live value from
`value_changed` but persist on `Range.drag_ended` (or `scrollbar` release). More
robust: add a `_save_pending` flag + a 0.5s debounce timer inside `GameState` so every
caller benefits. Keep `set_fullscreen` / toggle setters saving immediately — they fire
once per click.

**Verify**
`tests/progress_persistence_test.gd`: count writes by instrumenting the save path while
simulating 60 `set_master_volume` calls in one second, and assert it is debounced.

### [x] 8. `Fx.hitstop` can leave `Engine.time_scale = 0` forever

- **Severity:** MODERATE (latent, one code change away)
- **File:** `scripts/fx.gd:19-24` (`_process`), `scripts/fx.gd:42-45` (`hitstop`)

**Symptom**
If a hitstop is active at the moment `get_tree().paused = true` lands, `Engine.time_scale`
is never restored and the game is frozen permanently.

**Root cause**
`hitstop()` sets `Engine.time_scale = 0.0` and only `Fx._process()` restores it. `Fx`
is a plain autoload with the default `PROCESS_MODE_INHERIT`, and a paused tree stops
autoload `_process`. Not currently reachable (the 1s `_start_next_wave` delay outlasts
every hitstop), but `_offer_upgrades()` is a single `get_tree().paused = true` away.
Related: `SceneTree.create_timer()` **is** scaled by `time_scale`, so every timer in
`game.gd` stalls during hitstop by design.

**Fix**
- Set `process_mode = Node.PROCESS_MODE_ALWAYS` on the `Fx` autoload so the restore
  always runs.
- Reset `Engine.time_scale = 1.0` on scene exit / before any scene change (defensive).
- Optionally use `create_timer(..., true, false, true)` (ignore time scale) for the
  wave-transition timers if they should advance during hitstop.

**Verify**
`tests/smoke_test.gd:68-70` already asserts the happy path; add a case that calls
`Fx.hitstop(0.3)`, immediately sets `get_tree().paused = true`, then unpauses and
asserts `Engine.time_scale == 1.0`.

### [x] 9. Boss camera not reset on death during the boss fight

- **Severity:** MODERATE (cosmetic)
- **File:** `scripts/game.gd:542-556` (`_on_player_died`) — compare `game.gd:243-247`

**Symptom**
Dying during the wave-50 fight leaves `BossCam` at priority 40, so the game-over screen
renders at zoom 1.2.

**Fix**
Call the same reset used in `_on_boss_died` (`boss_cam.set("priority", 0)`) from
`_on_player_died`. Better: extract a `_reset_boss_cam()` helper and call it from both.

### [x] 10. Banner tween race

- **Severity:** MINOR
- **File:** `scripts/game.gd:603-614` (`_show_banner`)

**Symptom**
`_show_banner` does not kill the previous tween. A stale
`tween_callback(func(): banner.visible = false)` can hide a banner that was just
shown. Same class of bug as task 1.

**Fix**
`if _banner_tween != null and _banner_tween.is_valid(): _banner_tween.kill()` before
creating the new one.

### [x] 11. `health_changed` emitted with a negative value

- **Severity:** MINOR (cosmetic)
- **File:** `scripts/boss.gd:146-154` (`take_damage`)

The signal is emitted before the `if hp <= 0` death check, so listeners briefly see a
negative HP. `Range` clamps it so nothing breaks visually, but reorder the emit after
the death branch (or clamp with `maxi(hp, 0)`).

### [x] 12. Popup centering is a no-op

- **Severity:** MINOR (cosmetic)
- **File:** `scripts/fx.gd:85`

```gdscript
label.position = at - label.size * 0.5
```

Runs before the Label has ever been laid out, so `size` is `(0, 0)` and popups are
never actually centered. Either `await get_tree().process_frame` before positioning
(costs a frame of latency on every popup) or set a fixed width and centre via
`horizontal_alignment`.

---

## PERFORMANCE

### [x] 13. `Fx.burst` / `Fx.popup` node churn

- **File:** `scripts/fx.gd:48-71` (`burst`), `scripts/fx.gd:74-90` (`popup`)
- **Measured:** **31.6 µs per burst+popup pair**, 3 new nodes per pair
  (`CPUParticles2D` + `Label` + `Tween`).

Coin pickup fires one of each (`game.gd:321-322`), so a 20-coin magnet sweep is ~60
nodes and ~0.6ms, plus the dash trail (`player.gd:60`, one `CPUParticles2D` every
0.02s) and 18-particle bursts on every enemy death.

**Fix**
Pool the particle systems and the popups: keep a free list of pre-configured
`CPUParticles2D` and `Label` nodes, reposition/re-`emitting` them instead of
`new()`, and return them to the pool on `finished` / tween end rather than
`queue_free()`.

### [x] 14. `Sfx.play` node churn for non-coin sounds

- **File:** `scripts/sfx.gd:32-38`
- **Note:** 6 of 7 sounds create a new `AudioStreamPlayer` node per call. Only `"coin"`
  uses the shared `AudioStreamPolyphonic` player (12 voices). A 24-enemy wave churns
  24+ player nodes.

**Fix**
Extend the existing polyphonic pattern to the frequent sounds (`explode`, `powerup`,
`hurt`, `dash`) — one `AudioStreamPlayer` per sound with an `AudioStreamPolyphonic`
stream of 4-8 voices. Keep the one-shot node path for rare sounds (`wave`, `gameover`).

### [x] 15. Per-frame `get_nodes_in_group("coins")` in `_tick_magnet`

- **File:** `scripts/game.gd:356-365`
- **Measured:** **9.4 µs/call = 0.56 ms/s** with 22 live coins — ~0.06% of frame
  budget. **Low priority**, contrary to how it looks in a grep.

`get_tree().get_nodes_in_group()` allocates a fresh `Array` on every call, and this
runs every frame while the magnet is active.

**Fix**
Have `DebrisFieldSpawner` (or `Game`) keep a cached `Array[Coin]` refreshed on
spawn/collect/wave-clear, and iterate that. Worth doing for hygiene; not a frame
rate problem.

### [x] 16. Duplicated joystick radius constants

- **Severity:** NIT
- **File:** `scripts/touch_controls.gd:22-23` vs `scripts/joystick_visual.gd:7-8`

`JOYSTICK_RADIUS = 70.0` / `KNOB_RADIUS = 30.0` are hardcoded again as
`radius` / `knob_radius` on `JoystickVisual` and never wired together. If one changes
the drawn joystick silently desyncs from the input math. Set them in
`TouchControls._ready()` from the same constants.

---

## Also shipped alongside the audit fixes

Not part of the 16 audit items; added in the same pass because the audit work
made them necessary or they were needed to verify the fixes.

| Area | What | Where |
|------|------|-------|
| Camera | Minimum-zoom floor derived from the arena, so the visible world rect stays inside `Rect2(0,0,1280,720)` on **any** viewport size (stretch aspect `expand` makes the viewport wider than the arena on non-16:9 windows and landscape phones). Host camera limits re-pinned to the arena, `_enforce_camera_floor()` runs at `process_priority 400` (after the PhantomCameraHost at 300) so a mid-tween zoom can't dip below the floor. | `scripts/game.gd` (`arena_rect`, `_apply_camera_bounds`, `_enforce_camera_floor`) |
| Camera | Visible arena border so the boundary is obvious in play. | `scenes/game.tscn` (`ArenaBorder` Line2D) |
| Dev tooling | `Debug` autoload: F1 overlay (FPS / wave / nodes / draws / camera rect vs arena rect), F2 jump to the wave-50 boss, F3 skip wave, F4 kill all enemies, F5 god mode, F6 reset run. Every entry point no-ops unless `OS.is_debug_build()` **and** the F1 toggle is on, so release exports are unaffected. F-key actions are registered at runtime in `GameState` (AGENTS.md gotcha #5). | `scripts/debug.gd`, `scripts/game_state.gd` (`DEBUG_KEYS`) |
| Dev tooling | Full-run bot (wave 1 → wave-50 boss on the real game logic) and a retry regression test that reloads the scene for real. | `tests/full_run_bot.gd`, `tests/retry_test.gd`, `tests/debug_mode_test.gd` |
| CI | GitHub Actions pipeline: headless suite on every push/PR, Windows export on `main`, Android debug APK on tags/manual. Uses the `godot-ci:mono-4.7.2` image (this project needs the .NET build). | `.github/workflows/build.yml` |

Every one of the 16 audit items has a matching regression assertion in `tests/`
(re-run the suite with the `*_test.tscn` scenes to confirm).

---

## Refuted — do NOT "fix" these

Checked during the audit and found **not** to be bugs. Listed so they do not get
re-raised.

- **Deferred `queue_free` in `_start_wave` → `_scatter_coins`.** `_clear_leftover_coins()`
  uses `queue_free()`, so `_scatter_coins()` does connect `_on_coin_collected` to ~25
  already-doomed coins. Measured `before=25, during=44 (25 queued), after 2 frames=19`
  — **no accumulation, no miscount.** Wasted work at most, not a defect.
- **`Engine.time_scale` freezing today.** The permanent-freeze scenario is latent
  (task 8), not currently reachable. `tests/smoke_test.gd:68-70` confirms hitstop
  recovers to `time_scale == 1.0`.
- **Unfired `_spawn_enemy_later` timers leaking into the next wave.** Not possible:
  `_alive_enemies` is seeded with the wave's full count, so it can only reach 0 after
  every timer for that wave has already fired.
- **Boss missing from group `"enemies"`.** Intentional and handled everywhere —
  `boss.tscn:16` uses `groups=["boss"]`, `_on_boss_died` does its own accounting, and
  `player.gd:106-113` queries both groups for the shockwave.

---

## Suggested execution order

1. **Task 1** (music) — small diff, kills a permanent-silence bug.
2. **Task 3** + **Task 8** (unpause / time-scale) — same area, together they close the
   whole permanent-freeze class.
3. **Task 6** + **Task 5** (power-up leak, touch controls) — both are wave-lifecycle
   cleanups in `game.gd`.
4. **Task 4** (boss contact damage) — small, isolated to `boss.gd`.
5. **Task 2** (upgrade pool) — needs a design decision first; do it on its own.
6. **Task 7** (debounce saves), then **13 / 14** (pooling) as a perf pass.
7. **Tasks 9-12, 15-16** as a cleanup pass.

Per `AGENTS.md`: commit in small logical units, one issue per commit, and add a
regression test alongside each fix. Do not commit `builds/`.
