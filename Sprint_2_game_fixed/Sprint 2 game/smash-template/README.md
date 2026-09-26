# Smash Godot Template (Godot 4.6)

**Start Screen -> Mode Select (Local vs CPU / Online) -> Character Select
(your color) -> CPU Opponents (local only, toggle up to 3 CPUs) -> Match**
on one floating stage, up to 4 fighters at once in local mode, with a
Smash-style bottom HUD showing everyone's damage % and remaining stocks.

Everyone plays as a color-swapped "Godot guy" (a simple original
placeholder mascot, not the real Godot logo).

## Project layout

```
project.godot
icon.svg
autoload/
  InputSetup.gd        registers p1_/p2_ input actions in code
  GameManager.gd        selected mode, YOUR character, CPU slots, all character stats/movesets
  NetworkManager.gd     ENet host/join wrapper
scripts/
  start_screen.gd
  mode_select.gd
  character_select.gd
  cpu_setup.gd          toggle up to 3 CPU opponents on/off, pick their color
  online_lobby.gd
  sprite_gen.gd          builds placeholder sprite animations in code
  player.gd              fighter controller: movement/attacks/CPU/sync
  game.gd                spawns fighters onto the stage, builds/updates the HUD
scenes/
  StartScreen.tscn, ModeSelect.tscn, CharacterSelect.tscn, CpuSetup.tscn,
  OnlineLobby.tscn, Stage.tscn (4 spawn points), Player.tscn,
  Game.tscn (stage + players + HUD)
```

## Sprites & animation

`sprite_gen.gd` builds a small `SpriteFrames` resource **in code** for each
character's color - `idle`, `run`, `jump`, `attack`, `hurt` - so every
fighter has working animations with zero art assets. `player.gd` plays the
right one each frame (`_update_animation()`), flips the sprite with
`sprite.flip_h` based on facing, and switches to `attack`/`hurt` on cue.

**To use real art:** make (or import) a `SpriteFrames` resource in the
Godot editor's SpriteFrames panel with animations named `idle`, `run`,
`jump`, `attack`, `hurt`, then in `player.gd`'s `_ready()` replace
`sprite.sprite_frames = SpriteGen.build(color)` with
`sprite.sprite_frames = preload("res://path/to/your_frames.tres")`.
Everything else (flipping, animation switching, hit reactions) keeps
working unchanged.

## Attacks & how to make a different character

There's no special-cased "Pikachu code" - every character is just a
dictionary in `GameManager.characters`, with **four** moves:

```gdscript
{
    "name": "Guy Yellow",
    "color": Color(0.95, 0.8, 0.15),
    "speed": 380.0,            # fast
    "jump_velocity": -640.0,
    "gravity_scale": 0.7,      # floaty - falls slower than gravity
    "extra_jumps": 2,          # triple jump total
    "weight": 0.8,             # light - flies further when hit
    "attacks": {
        "neutral": {"damage": 3.0, "kb_base": 50.0, "kb_scale": 4.0, "range": 26.0, "startup": 0.04, "active": 0.3, "cooldown": 0.35, "hits": 3, "angle": 35.0},
        "up":      {"damage": 9.0, "kb_base": 130.0, "kb_scale": 6.0, "range": 24.0, "startup": 0.05, "active": 0.08, "cooldown": 0.3, "hits": 1, "angle": 85.0},
        "down":    {"damage": 6.0, "kb_base": 90.0, "kb_scale": 4.5, "range": 22.0, "startup": 0.04, "active": 0.1, "cooldown": 0.3, "hits": 1, "angle": 15.0},
        "back":    {"damage": 4.0, "kb_base": 70.0, "kb_scale": 4.0, "range": 24.0, "startup": 0.03, "active": 0.12, "cooldown": 0.3, "hits": 1, "angle": 30.0},
    },
},
```

`player.gd` reads every field at runtime - `gravity_scale`, `speed`,
`jump_velocity`, `extra_jumps` and `weight` plug directly into
movement/knockback math. Each entry in `attacks` is a full move: startup
delay, how long the hitbox is live, damage per hit, knockback strength,
`angle` (launch direction in degrees - 0deg is a flat horizontal hit, 90deg
sends straight up), range in front of the character, and how many hits
it does (>1 = a quick flurry like Yellow's neutral attack).

**Which attack plays:**
- Tap attack alone -> `neutral`
- Hold jump + tap attack -> `up` (a launcher; hitbox appears above the character)
- Hold down + tap attack -> `down` (a low hit; hitbox appears near the feet)
- Reverse direction and tap attack in the same instant -> `back` (a
  "pivot" strike that hits whatever's behind your *new* facing - a real
  fighting-game tech for catching someone who just ran past or behind you)
- CPUs pick automatically among neutral/up/down based on where their
  target is (they don't use the back-pivot tech - that one's a player
  skill-expression move).

**Seeing which way you're swinging:** every attack now flashes a small
white-ish `AttackFX` shape (a `Polygon2D`, tinted your character's color)
right where the hitbox actually is - out front for neutral, overhead for
up, low for down, or behind you for a pivot strike - so the direction is
visually obvious, not just implied by the little face dot flipping.

**To add a new character:** copy one of the four dictionaries in
`GameManager.characters`, tweak the numbers - it automatically shows up
in Character Select and the CPU Opponents color-cycle button. Give it all
four attack variants, or it'll fall back to `neutral`'s stats (or the
built-in `DEFAULT_ATTACK`) for anything missing.

Damage/knockback math: each hit adds `damage / hits` to `damage_percent`;
knockback speed is `(kb_base + damage_percent * kb_scale) * 0.01 /
weight`, split into x/y by `angle` and sent toward whoever got hit.

## Blast lines & the Screen KO easter egg

Three blast lines end a stock, all checked in `player.gd`:

- `BLAST_BOTTOM_Y = 1000.0` - fall off the bottom
- `BLAST_SIDE_X = 1400.0` - fly off either side
- `BLAST_TOP_Y = -650.0` - get launched too high (the new one)

Going out the **top** specifically has a `SCREEN_SPLAT_CHANCE` (35%)
chance to trigger a comedic "Screen KO": `ScreenFX` (another persistent
autoloaded `CanvasLayer`) flashes the screen white and squishes a big
color-matched blob face against it for a moment, with a random
onomatopoeia ("SPLAT!", "BONK!", etc.) - a nod to Smash's own screen-KO
gag, built from a `Panel` with a heavily-rounded `StyleBoxFlat`, two
`ColorRect` eyes, and a `Tween` for the squash-and-fade - no addons or
image assets needed. Tune the odds via `SCREEN_SPLAT_CHANCE`, or call
`ScreenFX.show_splat(color)` yourself to trigger it from anywhere (e.g.
if you want it on big side-blast KOs too, not just the top).

## Why fighters don't collide with each other

Stage terrain is on physics layer 1; every fighter's `CharacterBody2D` is
on layer 2 with a collision mask of just layer 1 - so they land on the
platform normally but pass straight through each other instead of
pushing each other around or getting stuck standing on one another's
heads, matching how actual Smash fighters behave. Attack hitboxes
(`Area2D`) use `collision_mask = 2` so they still detect other fighters;
they just don't detect the stage itself.

## The HUD

`game.gd` builds the bottom bar after spawning fighters: one column per
fighter with their name (tinted their color), a big damage % readout, and
a row of small colored squares - one per remaining stock. It polls each
fighter's `damage_percent`/`stocks` every frame in `_process()`, and
switches a fighter's readout to "KO" once they're out of stocks and freed.
Want stock icons that look like the actual character instead of a plain
square, or a flashing/color-shifting percent as damage climbs? Swap the
dot-drawing in `_set_stock_count()` and the label styling in `_build_hud()`.

## Toggling multiple CPUs

`GameManager.cpu_slots` is an array of up to 3
`{"enabled": bool, "character": int}` entries. The **CPU Opponents**
screen (`CpuSetup.tscn`/`cpu_setup.gd`) renders one row per slot with an
ON/OFF toggle and a color swatch you click to cycle characters. `game.gd`
then spawns you (always P1) plus one CPU per enabled slot, at the stage's
`SpawnP2`/`SpawnP3`/`SpawnP4` markers, and wires every fighter's
`opponents` list to "everyone else" so CPUs target whichever opponent is
nearest (`_nearest_opponent()` in `player.gd`) - a real free-for-all.

Note: this multi-CPU flow is **local only**. Online mode is still capped
at 2 players (see below) - extending it to more peers means tracking a
real list of connected peer IDs instead of the "host = P1, one client =
P2" shortcut currently in `game.gd`.

## Controls

- **Player 1 (you):** A/D move, W jump (hold for up-attack), S held for
  down-attack, F attack (tap the opposite direction as you press F to
  throw a back-attack behind you)
- **Player 2 (only used in online mode, or if you wire up local 2P):**
  Left/Right move, Up jump, Down for down-attack, Enter attack

## Online mode

`NetworkManager.gd` wraps a basic `ENetMultiplayerPeer` host/join - a
starting point, not production netcode: 2 players only, state synced via
an unreliable RPC every physics frame (no interpolation/reconciliation),
direct IP connect only, and character select is skipped (host = color 0,
joining player = color 1).

## Old-cartoon filter

`PostFX` is an autoloaded scene (`autoload/PostFX.tscn`), so it's a
persistent `CanvasLayer` sitting on top of every screen from the Start
Screen through the match - not something you have to add per-scene. It
holds one full-screen `ColorRect` running `shaders/cuphead_filter.gdshader`,
a canvas_item shader that reads the screen behind it (`hint_screen_texture`)
and adds:

- animated **film grain**
- a **vignette** (darkened corners)
- a gentle **sepia** tint
- light **posterization** (flattens colors slightly for a hand-inked feel)
- **low-frame-rate judder** - grain and a subtle jitter update at ~12fps
  (`film_fps` uniform) instead of animating smoothly at 60, since old
  film/animation didn't
- an occasional flickering vertical **scratch line**

It's pure built-in Godot: a `CanvasLayer`, a `ColorRect`, and a
`.gdshader` file - no addons.

**Tuning it:** select `PostFX/FilterRect` in the scene tree (or open
`autoload/PostFX.tscn`) and its Shader Parameters show up right in the
Inspector - `grain_amount`, `vignette_strength`, `sepia_amount`,
`posterize_levels`, `jitter_amount`, `scratch_amount`, `film_fps`. You can
also change them at runtime from any script with
`PostFX.set_param("grain_amount", 0.3)`, or toggle the whole effect with
`PostFX.set_enabled(false)`. Press **F9** anytime in-game to flip it on/off
for a quick before/after look.

## Extending it further

- More stages: duplicate `Stage.tscn`, add spawn markers, point
  `Game.gd` at it.
- Local 2-human-player support: give the CPU Opponents screen (or a new
  screen) a way to mark slot 2 as "Human" instead of CPU, and have
  `game.gd` spawn it with `is_cpu = false, input_prefix = "p2_"`.
- Real character-specific animations per attack variant, hitstun that
  prevents acting immediately after being hit, shielding/dodging.

Open `project.godot` in Godot 4.6 and run - it boots into the Start
Screen.
