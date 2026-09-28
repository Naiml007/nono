# AGENTS.md

Guidance for AI coding agents and human contributors working in `nono`, a
2D top-down arcade space-survival game built with **Godot 4.7.2** (GDScript).

## What this game is

**NONO — Endless Space Survival.** A top-down arena arcade game: you pilot a
robot, dodge chaser drones, grab energy cores (coins), chain score combos,
collect power-ups, and survive wave after wave. Every cleared wave offers a
choice of 3 upgrade buffs. Wave 50 is a boss fight with its own camera,
health bar and a special achievement.

- Genre: 2D arena / wave survival
- View: top-down, single screen arena (1280×720)
- Controls: 8-direction movement (Arrows always + WASD optional), dash
  (Space / Shift / mouse click), ESC to pause
- Runner: Godot 4.7.2 stable (`.NET` mono build, but the project is pure
  GDScript — no C# code)

## Quick start

| Task | Command |
| --- | --- |
| Run the game | Open `scenes/main_menu.tscn` in the editor, press Play (F5) |
| Boot straight into gameplay | Run `scenes/game.tscn` |
| Run a test suite | Open the test `.tscn`/`.gd` in `tests/` and run it, or use Ziva's `run_tests` |
| Regenerate music | Run `tools/chiptune_generator.gd` (one-shot, see note below) |

The main scene (`project.godot`) is `res://scenes/main_menu.tscn`.
Window is 1280×720, renderer is `gl_compatibility`. Mobile: stretch aspect is
`expand` (the 1280×720 arena stays centered; the wider margins hold the touch
controls) and orientation is locked landscape (`sensor_landscape`).

## Project layout

```
res://
├── project.godot          Engine config, autoloads, input actions
├── default_bus_layout.tres  Audio buses (Master, Music, Sfx)
├── scenes/                .tscn files, one per entity/UI
│   ├── main_menu.tscn     Title screen + settings overlay
│   ├── game.tscn          The whole run: world, HUD, camera, overlays
│   ├── touch_controls.tscn  On-screen joystick + DASH/PAUSE buttons (mobile)
│   ├── player.tscn        CharacterBody2D robot pilot
│   ├── enemy.tscn         Chaser drone (Area2D hitbox)
│   ├── boss.tscn          Wave-50 boss (extends Enemy)
│   ├── boss_bolt.tscn     Boss projectile
│   ├── coin.tscn          Energy-core pickup
│   └── power_up.tscn      Magnet / Shield / Heart drop
├── scripts/               One .gd per scene (same name as the scene)
│   ├── game.gd            Game controller: waves, scoring, upgrades, UI
│   ├── touch_controls.gd  Virtual joystick (drives move_*) + touch DASH/PAUSE
│   ├── joystick_visual.gd Draws the joystick base ring + knob
│   ├── game_state.gd      Autoload: run state, best score, settings, input actions
│   ├── player.gd
│   ├── enemy.gd / boss.gd / boss_bolt.gd
│   ├── coin.gd / power_up.gd
│   ├── DebrisFieldSpawner.gd  Grid-based coin scatterer
│   ├── sfx.gd / music.gd / fx.gd   Audio + "juice" autoloads
│   ├── achievements.gd    Achievement autoload + toast UI
│   ├── main_menu.gd / pause_menu.gd / upgrade_panel.gd
├── assets/
│   ├── generated/         AI-generated sprites & icons (all art lives here)
│   ├── audio/sfx/         One-shot wav effects (coin, dash, explode, ...)
│   ├── audio/music/       4 chiptune wav loops (menu, battle, boss, gameover)
│   ├── sprites/           Hand-placed sprites (player, coin)
│   ├── fonts/             Chakra Petch (OFL) - UI font family
│   ├── ui/                THE design system: nono_theme.tres + icons + README
│   └── textures/ tilesets/   Mostly empty / unused
├── shaders/               menu_bg.gdshader (procedural starfield backdrop)
├── tests/                 Headless verification scripts + scenes
├── tools/                 chiptune_generator.gd (music synth)
└── addons/                phantom_camera, GDQuest formatter, ziva_agent
```

Convention: a scene `scenes/X.tscn` always pairs with `scripts/X.gd`. Assets
are referenced as absolute `res://assets/...` paths. Do not edit anything
under `addons/` unless fixing a bug (see "Known issues" below).

## Global architecture

### Autoloads (registered in project.godot, in load order)

| Singleton | Script | Purpose |
| --- | --- | --- |
| `GameState` | `scripts/game_state.gd` | Run score/kills/wave, best-score persistence, WASD/mouse-dash settings, **defines all input actions at runtime** |
| `Sfx` | `scripts/sfx.gd` | One-shot SFX; the five frequent sounds share a polyphonic player |
| `Fx` | `scripts/fx.gd` | "Juice": particle bursts, floating popups, camera shake. `Fx.setup(world, camera)` is called by `game.gd` |
| `Achievements` | `scripts/achievements.gd` | Unlock tracking + toast banner. Currently `let_me_solo_her` |
| `PhantomCameraManager` | `addons/.../phantom_camera_manager.gd` | Engine-level camera manager singleton |
| `Music` | `scripts/music.gd` | Crossfading BGM loop player; tracks preloaded and looped |
| `Debug` | `scripts/debug.gd` | Developer toolbar: F1 overlay, F2 boss jump, F3 skip wave, F4 kill enemies, F5 god mode, F6 reset run. **Inert unless `OS.is_debug_build()` AND F1 is toggled on** |

These singletons are referenced by bare name (`GameState.add_score(...)`,
`Sfx.play("coin")`) — no `class_name` is needed/used for autoloads.

### Debug toolbar (developer only)

`Debug` is the only autoload that is allowed to no-op: every entry point checks
`available` (`OS.is_debug_build()`, false in a release export) **and** `active`
(the F1 toggle, default off). `game.gd` calls `Debug.register(self)` in
`_ready` / `Debug.unregister(self)` in `_exit_tree`; nothing else in the game
reaches into `Debug`, so wave jumps go through `Game.debug_*` methods. The
overlay draws the camera's visible world rect next to the arena rect, which
makes "the player left the map" visible while testing. Keys are F1-F6 — see
`DEBUG_KEYS` in `game_state.gd` (registered at runtime, never in
`project.godot`). God mode is `Player.debug_god`, checked inside
`is_invulnerable()` and `_can_dash()`, so it is off in every normal run.

### Input actions — defined in code, not the editor

`GameState._setup_input_actions()` builds the InputMap at startup. There are
**no** custom actions in `project.godot`:

- `move_left/right/up/down` — arrow keys always; WASD added only when
  `GameState.wasd_controls` is on (setting persists to `user://`)
- `dash` — Space + Shift (always bound)
- `pause` — Escape

Mouse-click dash is handled directly in `player.gd` `_unhandled_input`, not
via an action, so clicks on UI never dash. If you add an InputMap action,
prefer following this runtime pattern over editing project.godot, since
settings toggles rebind at runtime.

On phones the virtual joystick feeds the SAME `move_left/right/up/down`
actions via `Input.action_press/release` (re-asserted every frame), so
`player.gd` has zero touch code.

### Game flow (scripts/game.gd)

`game.gd` (`class_name Game`) drives everything:

1. `_ready()` → `GameState.reset_run()`, `Fx.setup()`, wire signals, `Music.play("battle")`, `_start_wave(1)`.
2. Each wave: shows banner, clears any leftover hearts/coins from the previous wave (`_clear_leftover_hearts`/`_clear_leftover_coins`), scatters a fresh coin field (`_scatter_coins` → DebrisFieldSpawner), spawns `2 + wave` enemies over time, staggered from screen edges (`_edge_spawn_pos`).
3. Enemies (group `"enemies"`) home toward the player with a sine wobble; contact kills them but damages the player unless dashing/invulnerable/shielded.
4. Coins (group `"coins"`) give `(1 + value_bonus) * combo_multiplier` score; combo multiplier = `1 + floor(combo / 4)` capped at 5, resets 3s after the last pickup.
5. When all enemies die → `_start_next_wave()` → 1s pause → `_offer_upgrades()` (tree pauses, 3 random buff cards, wait for `upgrade_chosen`) → next wave.
6. Enemies/power-ups drop: 12% magnet, 10% shield, 7% heart (heart pickups are group `"heart_pickup"`; both hearts and uncollected coins are force-cleared at each wave start so the arena's node count stays flat over a long run).
7. Wave 50 → boss wave (`_start_boss_wave`): boss spawns above arena, `BossCam` priority raised to 40, boss health bar shown. On death: +500 score, power-up drops, `let_me_solo_her` achievement if a single source dealt all damage, boss cam priority reset.
8. Player death → game-over panel (score + best), `GameState.save_best()`, retry reloads scene, Menu unpauses and switches scene.

### Player (scripts/player.gd)

`class_name Player extends CharacterBody2D` (`MOTION_MODE_FLOATING`).
- Movement: `Input.get_vector(...)` × `speed` × `speed_mult`.
- Dash: 820 px/s for 0.14s, i-frames, cooldown; dash-through kills enemies; with the `shockwave` buff it also AoE-kills enemies and damages the boss.
- Health: 4 HP, `took_hit`/`died` signals, invulnerability window, red hurt-flash sprite modulate.
- Shield absorbs one hit (with 0.8s grace), magnet pulls coins for 7s.
- Buffs live on the player as multipliers: `speed_mult`, `dash_cd_mult`, `dash_speed_mult`, `magnet_radius_bonus`, `shockwave`.
- `source_id()` returns `multiplayer.get_unique_id()` — singleplayer always 1; used by boss damage tracking.
- Position is clamped to the fixed `ARENA` box (1280×720) — the arena is
  always the 1280×720 logical box, even when the mobile `aspect = expand`
  viewport is wider/taller.

### Touch controls (mobile)

- `touch_controls.tscn` (`class_name TouchControls`, a CanvasLayer at layer 5)
  sits in `game.tscn` as `%TouchControls`. It auto-shows on the first touch and
  auto-hides on any real keyboard/mouse event.
- The virtual joystick anchors where the thumb touches, but only in the left
  62% of the screen; a dead zone (0.18) is remapped to a smooth ramp. It drives
  the shared `move_*` actions via `Input.action_press/release`, re-asserted
  every frame in `_process` (a single `action_press` only lasts one frame).
- DASH emits `dash_pressed` -> `game.gd` -> `player.try_dash()` (the single
  dash implementation). PAUSE emits `pause_requested` -> `game.gd`
  `_on_touch_pause_requested()` -> the same pause overlay as ESC.
- Godot synthesizes mouse events from touches; while touch mode is ON an
  emulated click is swallowed (`set_input_as_handled`) **only** when it lands in
  the joystick zone and not on a touch button, so a stray touch never also fires
  the mouse-click dash. The zone gate matters: `_input` runs before GUI dispatch,
  so swallowing every emulated click would also kill the real HUD buttons (the
  top-right MENU button was dead on phones).
- `TouchControls` is `PROCESS_MODE_ALWAYS` and releases every `move_*` action it
  pressed in `_exit_tree()` (and scrubs them on ready). The joystick drives the
  **global** `Input` singleton via `Input.action_press`, and that state outlives
  `reload_current_scene()` — without the release a run that ended mid-drag made
  the next run drift sideways from frame one.
- `PAUSE` sits bottom-left mirroring `DASH` bottom-right. It is deliberately NOT
  top-left: this CanvasLayer draws above the HUD, and the top-left strip belongs
  to the hearts readout.
- Buttons are 97px (`BUTTON_SIZE`, ≥ the 88px touch target), laid out from
  `DisplayServer.get_display_safe_area()` so they clear notches/home bars.
  `game.gd` calls `set_controls_enabled(false)` while paused / game over so
  the controls never float over a menu (and while the upgrade panel is open, so
  a tap can't fire a phantom dash on a paused tree).
- The setting `GameState.touch_controls` (default on) persists to
  `user://nono_settings.cfg` and has a toggle in the main-menu settings panel.

### Enemies & boss

- `enemy.gd` (`class_name Enemy extends CharacterBody2D`): homes to player, sine wobble, dies on contact with a dashing player / shield. `die(scored: bool)` awards +10 when the player caused it.
- `boss.gd` (`class_name Boss extends Enemy`): 18 HP, state machine `CHASE → TELEGRAPH_CHARGE/BURST → CHARGE`. Telegraphed attacks (charge dash, 8-way radial bolt burst via `boss_bolt.gd`). **Never dies on contact**; only dash-through damages it (proximity check while `player.is_dashing`). Tracks `_damage_sources` per `source_id` for the solo achievement.
- Collision: enemies/boss bolt hit the player via `Area2D` in group `"player_hurtbox"` → calls `player.on_enemy_contact()` / `player.apply_boss_damage()`.

### Upgrades (wave-clear buffs)

`BUFFS` dictionary in `game.gd` with `"stack"` (max picks per run), `"one_off"`
(once per run) or `"repeat"` (never exhausted) keys: speed, dash, magnet, shield,
heal, maxhp, combo, value, shock, overcharge, repair, reserve. Choices are picked
from the remaining pool, shuffled, 3 shown as code-built Button cards in the
upgrade panel (1/2/3 hotkeys). `_apply_buff` mutates the player or run state
directly. The three `repeat` entries guarantee the pool can never empty over a
50-wave run, so the panel is never skipped.

### Camera (Phantom Camera addon)

- `Camera2D` (named `Camera`) has a child `PhantomCameraHost`.
- Two `PhantomCamera2D` nodes: `PlayerCam` (priority 10, glued to Player) and `BossCam` (priority 0, glued, zoom 1.2, damping 0.12).
- `game.gd` flips boss cam priority 0↔40 to switch active camera on boss spawn/death
  (and resets it on player death, so the game-over screen never renders zoomed).
- **Camera bounds** (the visible world rect is `viewport / zoom`, so on a
  viewport *larger* than the arena — stretch aspect `expand` on any non-16:9
  window or landscape phone — camera limits alone cannot contain the view):
  `Game._apply_camera_bounds()` derives a **minimum zoom** from the arena, sets
  it on both `PhantomCamera2D`s (`boss_cam` gets `BOSS_ZOOM *` it), and pins
  the host `Camera2D` limits to `Rect2(0,0,1280,720)`. It re-runs on every
  `size_changed` and whenever the addon forwards its own limits (it emits
  unlimited defaults). `Game._enforce_camera_floor()` runs every frame at
  `process_priority = 400` (after the `PhantomCameraHost` at 300) so a mid-tween
  zoom cannot dip below the floor. `tests/camera_test.gd` asserts the invariant
  for a matrix of viewport sizes on both cameras.
- Manager is an autoload (`PhantomCameraManager`) AND registers itself as an engine singleton named `PhantomCameraManager`.

### Audio

- `Sfx`: loads wavs from `assets/audio/sfx/`; `play(name, pitch=1, vol=0)`.
  The five frequent sounds (`coin` 12, `explode` 8, `powerup` 6, `dash` 4,
  `hurt` 4 voices — see `POLYPHONY`) each use a shared
  `AudioStreamPolyphonic` player, so rapid overlaps never spawn nodes. The rare
  ones (`wave`, `gameover`) still spawn a short-lived player on the `Sfx` bus
  (`finished → queue_free`).
- `Music`: crossfades between 2 `AudioStreamPlayer`s (`Music` bus). Tracks
  preloaded as `AudioStreamWAV` with `LOOP_FORWARD` set in code. `play()` is
  a no-op if the track is already active — retry/restart never cuts music —
  and it kills any in-flight crossfade tween first, so a `play()` inside
  `FADE_TIME` can never silence the track that just faded in. Keys: `menu`,
  `battle`, `boss`, `gameover`.
- **Battle intensity tiers**: battle music intensifies every 5 waves instead of
  looping one static track. `game.gd` maps wave → tier (`_battle_tier_for_wave`,
  tiers 1-10, wave 50 = boss) and calls `Music.play_battle_tier(tier)` on tier
  change. Tier 1 reuses `battle_theme.wav`; tiers 2-10 are committed as
  `battle_tier_<n>.wav` (preferred), or synthesized once into `user://` via
  `ChiptuneGenerator.ensure_battle_tier()` if a file is missing (cached per run,
  never regenerated). After the boss dies the battle tier resumes. All tier
  switching routes through `play()`/`play_battle_tier`, so crossfade + no-op
  semantics are shared with `battle`/`boss`.
- Buses: `Master`, `Music`, `Sfx` (default_bus_layout.tres).

### FX (juice)

`Fx.burst(at, color, ...)` → one-shot `CPUParticles2D`; `Fx.popup(at, text,
...)` → tweened floating Label; `Fx.shake(amount, dur)` → camera offset jitter.
Requires `Fx.setup(world, camera)` once per scene (done by `game.gd`).

Bursts and popups are **pooled** (capped at 64 particles / 32 popups): a parked
node stays a child of the world but is inert, so effects never churn the
SceneTree during play. `Fx` is `PROCESS_MODE_ALWAYS` so a hit-stop that
overlaps a pause still restores `Engine.time_scale`.

## Persistence (user://)

| File | What | Written by |
| --- | --- | --- |
| `user://nono_save.cfg` | Best score (`meta/best`) | `GameState` on death |
| `user://nono_settings.cfg` | `wasd`, `mouse_dash`, `touch`, master/music/sfx volume, fullscreen | `GameState` on change (volume writes are debounced 0.5s, flushed on exit) |
| `user://nono_achievements.cfg` | Unlocked id list | `Achievements` |

All are simple `ConfigFile`s.

## Testing

Headless test scripts live in `tests/` (each with a tiny `.tscn`):

| Test | Verifies |
| --- | --- |
| `boss_flow_test.gd` | Boss spawn/HP/dash-damage/bar/cam, solo achievement, heart + magnet/shield despawn between waves, standing inside the boss keeps damaging, pooled FX + polyphonic SFX, `health_changed` never negative |
| `audit_fix_test.gd` | i-frames award no kill/score (drone is still cleared) but a dash-through still scores; boss bolts pass through an invulnerable player yet are consumed when they land or the shield eats them; two achievement toasts claim different slots; the world freezes behind the game-over panel |
| `camera_test.gd` | Player cam active by default; boss cam priority → zoom 1.2; back to 1.0; visible world rect stays inside the arena for a matrix of viewport sizes on both cams |
| `coin_pos_test.gd` | All spawned coins land inside the 1280×720 arena |
| `debug_mode_test.gd` | Debug toolbar: no-op while disabled, overlay toggles, god mode, one-key boss jump (wave 50 + boss spawned + cam priority 40 + health bar) |
| `music_test.gd` | 4 tracks load & loop, crossfades work, main menu boots; battle tiers load/loop and revisiting a tier never re-renders; a rapid double `play()` leaves exactly one audible player |
| `mobile_ui_test.gd` | `TouchControls` is `PROCESS_MODE_ALWAYS`; the emulated-mouse swallow is limited to the steering zone so the HUD Menu button works on touch; freeing the node releases `move_*` and a new instance scrubs leaked presses; PAUSE/DASH never cover the HUD hearts |
| `retry_test.gd` | Real `reload_current_scene()` from a paused + hit-stopped state leaves the new run unpaused at `time_scale == 1.0` |
| `upgrade_panel_test.gd` | Upgrade offer: exactly 3 cards, pause/unpause, buff applied once, STACK/ONCE-PER-RUN/REPEATABLE chips, out-of-range index ignored, pool never empties over 50 waves |
| `progress_persistence_test.gd` | Settings round-trip (volume/fullscreen), corrupted/missing file fallbacks, achievement persistence, reset_progress keeps settings, volume writes are debounced |
| `smoke_test.gd` | Wave 1→50 boss kill→game over flow, score+best labels, retry reset, menu unpause |
| `touch_input_test.gd` | Virtual joystick drives move_* actions, DASH/PAUSE route to try_dash/pause, auto show/hide, emulated-mouse swallow, safe-area anchors, controls disabled while the upgrade panel is open, touch_controls round-trip |

`tests/full_run_bot.gd` is a throwaway `SceneTree` bot (not a `*_test.tscn`, so
CI skips it): it plays wave 1 → the wave-50 boss on the real game logic at
`time_scale 5` and logs every wave, used to sanity-check a full run.

Run any test by running its `.tscn` (the `_ready` runs assertions, prints
`PASS/FAIL`, and calls `get_tree().quit()`). They instantiate `game.tscn`
directly, so they need the autoloads present. Use `run_tests` in Ziva or run
the scene headlessly. CI (`.github/workflows/build.yml`) loops over
`tests/*_test.tscn` on every push/PR — a `FAIL:` line, a non-zero
`failures=N` summary, a script error, or a non-zero exit fails the build.

> Gotcha when grepping test output: a **passing** test still prints
> `==== ... failures=0 ====`, so a case-insensitive `grep FAIL` matches every
> run. Match `^FAIL:` or `failures=[1-9]` instead.

## Tools

- `tools/chiptune_generator.gd` (`class_name ChiptuneGenerator`): one-shot
  NES-style synth that renders the music wavs into `assets/audio/music/`.
  `generate_all()` also emits the battle tiers (`battle_tier_2..10.wav`) via the
  shared `_build_battle(tier)` builder (tier 1 = `battle_theme.wav`). It also
  exposes `ensure_battle_tier(tier)` used by the game as a runtime fallback.
  Already committed output; regenerate intentionally, not on every run.
- `addons/GDQuest_GDScript_formatter`: code formatter plugin (optional use).

## Conventions & code style

- GDScript, Godot 4.x idioms: `@export`, `@onready`, typed everything,
  `signal`, `await`, `class_name` on node scripts.
- Every `var` is type-hinted (`var _combo := 0`, `var player: Player = %Player`).
- Signals are the wiring mechanism — `game.gd` `_wire()` connects player
  signals to UI updates; entities emit and free themselves.
- Node references use `%UniqueName` (`unique_name_in_owner = true` set on key
  nodes in game.tscn).
- Internal state uses the leading-underscore convention (`_wave`, `_rng`).
- Group names are stringly-typed and important: `player`, `enemies`,
  `boss`, `coins`, `heart_pickup`, `player_hurtbox`. Keep them consistent.
- `GameState`/`Sfx`/`Fx`/`Music`/`Achievements` referenced by autoload name.
- Magic numbers that matter live at the top of the file as `const` (ARENA,
  COMBO_WINDOW, BOSS_WAVE, BUFFS).
- Scene↔script pairing: `scenes/player.tscn` → `scripts/player.gd`.

## UI design system (do not bypass)

All Control styling comes from ONE theme: `assets/ui/nono_theme.tres`, applied
project-wide via `gui/theme/custom` in `project.godot`. See
`assets/ui/README.md` for the full token/scale reference.

- **Never add `theme_override_font_size`, `theme_override_colors` or
  `theme_override_styles` to a node** — add or reuse a `theme_type_variation`
  instead (`Display`, `Title`, `Heading`, `Body`, `Small`, `Readout`, `Gold`,
  `ChipStack/Once/Repeat`, `Section`, `Badge`, `BossTitle`, `Ach*`, `Toast*`,
  `FloatPopup`, `PopupSmall`, `DebugInfo`, `FloatPanel`, `DebugPanel`; buttons:
  `Primary`, `Ghost`, `Danger`, `Hud`, `Touch`, `Card`).
- **Exactly 6 font sizes exist** (16/18/24/28/32/48). Never introduce a 7th;
  new text picks an existing scale step. Same for styleboxes built in code
  (`StyleBoxFlat.new`) — prefer a theme variation over a literal.
- One corner radius (6), one border width (1, 2 for emphasis). **Zero
  `shadow_offset_*`** anywhere. Text over the backdrop = outline only; text on a
  panel = no outline. Locked/dimmed UI dims with `modulate`, not per-label
  colours, so colour tokens stay in the theme.
- The `*Hud` label variants carry the single outline for text drawn over the
  starfield; use them for anything on the gameplay backdrop.

## Git & GitHub

- Remote: `https://github.com/Naiml007/nono.git` (branch `main`).
- `.gitignore` excludes `.godot/`, `builds/`, `.ziva/`, and the large
  `zivacode/` binary. Do not commit `builds/`.
- Commit in small logical units; push with `git push origin main`.
- **CI**: `.github/workflows/build.yml` runs the headless suite on every
  push/PR, and on `main` (plus `v*` tags and manual runs) also exports the
  Windows build and the Android debug APK. It uses
  `barichello/godot-ci:mono-4.7.2` (the .NET build is required even though the
  project is pure GDScript) and moves the image's `~/.config/godot` + mono
  export templates into the `HOME` container jobs actually run with. No
  secrets: the Android APK is debug-signed with the keystore inside the image.
- **CI gotcha**: `--install-android-build-template` only works when passed to
  the **same invocation** as the export (`godot --headless --path .
  --install-android-build-template --export-debug "Android" …`). Running it as
  its own step installs nothing, and the export then fails with "Android build
  template not installed in the project".

## Exporting / Android

- `export_presets.cfg` has 4 presets: Windows Desktop, macOS, Web, Android.
  Web is **not usable**: this is the **mono** (.NET) build and Godot dropped
  .NET Web export — no web templates ship in the mono template pack.
- Android presets: `gradle_build/use_gradle_build=true` (required for C#),
  `gradle_build/min_sdk="24"` (Godot lib needs ≥24), `target_sdk="34"`,
  arm64-v8a only, `builds/nono.apk`.
- Toolchain already installed on this machine (see `export_presets.cfg` +
  editor settings): full `4.7.2.stable.mono` export templates in
  `%APPDATA%\Godot\export_templates\4.7.2.stable.mono`, Android SDK at
  `%LOCALAPPDATA%\Android\Sdk` (platform-tools, platforms;android-34,
  build-tools;34.0.0), and **JDK 21 (Temurin) at
  `%LOCALAPPDATA%\Programs\temurin21\jdk-21.0.12.1+1`** — Java 25 (Zulu)
  is NOT compatible with Gradle 8.11.1 (major version 69 > 67).
- The Gradle build template lives at `res://android/build` (gitignored;
  `--install-android-build-template` installs it). It sets
  `org.gradle.java.home=C:/Users/distr/AppData/Local/Programs/temurin21/jdk-21.0.12.1+1`
  in `android/build/gradle.properties` — use forward slashes there (Java
  properties treats `\` as an escape, so `\t`/`\Users` get mangled).
- Build for phone test (headless): `Godot_v4.7.2-stable_mono_win64.exe
  --headless --path . --export-debug "Android" builds/nono.apk`
  then `adb install -r builds/nono.apk` with a phone in USB-debugging mode.
  If `res://android/build` is missing, add `--install-android-build-template`
  to that **same** command (it does nothing as a standalone run — see the CI
  bullet above).
  The `~libziva_agent...dll` copy errors during headless export are benign
  (editor holds the DLL; the extension is excluded from the build anyway).

## Known issues & gotchas

1. **Phantom Camera null-manager** (fixed): the addon scripts
   `phantom_camera_2d.gd` / `phantom_camera_host.gd` previously crashed
   (`Invalid access to property 'screen_size' on a base object of type
   'null instance'`) when the `PhantomCameraManager` singleton wasn't
   available yet (editor preview / embedded run contexts). They now guard
   with `Engine.has_singleton` / `is_instance_valid`. **Do not regress these
   guards.** In degraded contexts the host prints "Could not find Phantom
   Camera Manager singleton" instead of crashing — normal real runs are
   unaffected.
2. **Embedded runner ≠ real run**: Ziva's `run_scene` embeds the game in a
   context where engine singletons may not register; camera errors seen
   there can be artifacts. Verify camera behavior via `tests/camera_test.gd`
   or a real SceneTree run.
3. **Arena is fixed**: the player clamps to the 1280×720 `ARENA` box, not the
   viewport, so the arena stays centered under `aspect = expand`. Headless
   viewport sizes are not the design size; don't read camera positions from
   headless runs without forcing the window size. `Input.parse_input_event`
   scales event coordinates by the window/viewport stretch factor in headless
   (~20x), so tests convert coordinates or drive handlers directly.
4. `music.gd` deliberately has **no** `class_name` — the autoload name
   `Music` is the global identifier. Adding `class_name Music` would
   conflict.
5. `input actions` are added at runtime by `GameState`; if you add a new
   action, do it there so the WASD-toggle logic keeps working.
6. Don't rename the project (`application/config/name`) — that moves Godot's
   `user://` folder and loses save data.
