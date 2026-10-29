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
  GameManager.gd        selected mode, YOUR character, CPU slots, the finished characters array
  NetworkManager.gd     WebSocket relay client (room codes, send/receive)
scripts/
  start_screen.gd
  mode_select.gd
  character_select.gd
  cpu_setup.gd          toggle up to 3 CPU opponents on/off, pick their color
  online_lobby.gd
  character_roster.gd   THE place to add/edit characters (stats, movesets, colors)
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

Every character is just data - there's no special-cased "Pikachu code".
All of it lives in `scripts/character_roster.gd`, in the `_definitions()`
list. `GameManager.characters` is built from that list once at startup, and
Character Select, CPU Opponents, the HUD and the match spawner all read the
finished array - so **adding a character means editing that one list and
nothing else.**

### Adding a character (the fast way)

Only write what's *different*. Anything you leave out is inherited:

```gdscript
{
    "id": "purple",                  # unique, lowercase - used by based_on and GameManager.character_index("purple")
    "name": "Guy Purple",            # shown on Character Select and the HUD
    "color": Color(0.6, 0.25, 0.85),
    "based_on": "red",               # start as a copy of Guy Red (must be defined ABOVE this one)
    "weight": 1.6,                   # heavier = knocked back less
    "speed": 230.0,
    "attacks": {
        "neutral": {"damage": 20.0, "cooldown": 0.8},   # only the fields that change
        "up":      {"angle": 90.0},
    },
},
```

- `based_on` copies every stat and all four moves from an earlier character
  first, then your overrides are applied on top. Guy Black is just
  `based_on: "yellow"` with a new color.
- Without `based_on`, a character starts from `BASE_STATS` / `BASE_MOVE`
  (middle-of-the-road numbers), so even a 4-line character is playable.
- `attacks` only needs the moves and fields you want to change.
- Typos get caught: an unknown key (`"dammage"`), an unknown move
  (`"nuetral"`), a missing `id`/`name`, a duplicate `id`, a bad `based_on`,
  or a `weight` of 0 all print a warning/error in Godot's Output panel at
  startup instead of silently falling back to a default.
- `face_color` and `ui_color` are picked automatically so very dark
  characters stay readable (Guy Black gets a white face and a gray HUD
  name). Set either one yourself in the definition to override it.
- Optional `"frames": "res://path/to/frames.tres"` gives that one character
  its own hand-made `SpriteFrames` (animations `idle`, `run`, `jump`,
  `attack`, `hurt`) instead of the generated colored guy - see "Sprites &
  animation" above.
- The order in `_definitions()` is the order on Character Select, and the
  position in that list is what gets sent over the network in online mode,
  so both players need the same version of the game.
- Character Select's grid is 10 columns by at least 3 rows (empty slots fill
  it out, Random sits in the last slot). It adds rows as the roster grows and
  shrinks the tiles to fit, up to roughly 50 characters.

### What the stats mean

```gdscript
"speed", "jump_velocity", "gravity_scale", "extra_jumps"   # movement feel
"weight"                    # how much knockback they take (lighter flies further)
"attacks": {
    "neutral": {...},       # plain attack button
    "up":      {...},       # hold jump + attack (hitbox above)
    "down":    {...},       # hold down + attack (hitbox low)
    "back":    {...},       # pivot strike - reverse direction as you hit attack
}
# each move: damage, kb_base, kb_scale, range, startup, active, cooldown, hits, angle
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
`{"enabled": bool, "character": int}` entries. Character Select
(`character_select.gd`) is laid out like Smash: a grid of character tiles on
top and four colored player panels along the bottom (P1 red = you, P2 blue,
P3 yellow, P4 green = the three CPU slots). Click a panel to make it
active, then click a tile to give it that character; the "?" tile is
Random. Clicking an empty CPU panel (or its ADD CPU button) switches that CPU
on, and REMOVE switches it off. A CPU set to Random stores
`GameManager.RANDOM_CHARACTER` (-1) and `game.gd` rolls a real character for
it each time a match starts; if P1 picks Random it's rolled when you press
CONFIRM. `game.gd` then spawns you (always P1) plus one CPU per enabled
slot, at the stage's `SpawnP2`/`SpawnP3`/`SpawnP4` markers, and wires every
fighter's `opponents` list to "everyone else" so CPUs target whichever
opponent is nearest (`_nearest_opponent()` in `player.gd`) - a real
free-for-all. (The old separate CPU Opponents screen,
`CpuSetup.tscn`/`cpu_setup.gd`, is no longer used.)

Note: this multi-CPU flow is **local only**. Online mode has its own 4-player system (see below).

## Controls

- **Player 1 (you):** A/D move, W jump (hold for up-attack), S held for
  down-attack, F attack (tap the opposite direction as you press F to
  throw a back-attack behind you)
- **Player 2 (only used in online mode, or if you wire up local 2P):**
  Left/Right move, Up jump, Down for down-attack, Enter attack

## Online mode (up to 4 players)

`NetworkManager.gd` connects every player to a small relay server over
WebSocket (see `relay_server/`) using a 5-letter room code - no port
forwarding or IP addresses needed. The relay gives each player a **slot**
0-3 (host = slot 0 = P1, then P2, P3, P4 in join order); the slot is also
the player's panel on Character Select and their spawn marker on the Stage.

Flow: the host presses HOST GAME and shares the code; up to 3 friends JOIN.
The lobby shows how many players are in, and the host's **START MATCH**
button (needs 2+ players) locks the room and sends everyone to Character
Select. Each player confirms a character; once everyone has, the match
starts. If someone leaves mid-match, only their fighter is removed.

It's a starting point, not production netcode: each player's
position/damage/stocks are sent every physics frame with no interpolation or
reconciliation. A hit is sent to the one machine that owns the victim
("to": their slot), which applies it to its own fighter. **You must
redeploy the relay** (`wrangler deploy` in `relay_server/`) for 4-player
rooms to work - the old relay only accepts 2.

## Results screen, rematch and the leaderboard

**Match end.** A match with 2+ fighters ends when only one is left (`game.gd`,
`_check_match_end`). A results screen shows the winner:
- **Local:** PLAY AGAIN (same characters; Random CPUs re-roll), CHARACTER SELECT, MAIN MENU.
- **Online:** PLAY AGAIN is a vote. When every player still in the room has
  voted, the relay sends `rematch_go` and everyone reloads the match together.
  LEAVE goes back to the title screen.

**Usernames.** Online play needs an account: the first time you open the
Online screen, type a username (3-16 letters/numbers/_, must be unique) and
press REGISTER. The relay creates the account and the game saves the ID and a
secret token in `user://profile.cfg`. Names show in the lobby, on Character
Select and on the results screen.

**Leaderboard** (main menu): wins, games played and win % for every
registered player, sortable. Only **online** matches count. Stats live on the
relay (a SQLite-backed Durable Object), never in the game, and a match is only
recorded when every connected player's game reports the **same winner** and at
least **two different accounts** played - so one person with several windows
can't farm wins. Win % ranks players with 3+ games first (`*` = not ranked yet).

**Deploying.** Everything server-side is in `relay_server/src/worker.js`. After
changing it run `npx.cmd wrangler deploy` in `relay_server/`. The leaderboard
needs the `v2` migration in `wrangler.toml` (already added); the first deploy
creates it automatically.

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

## Specials and the Almanac

- **Specials**: every character in `scripts/character_roster.gd` has four named specials (`special_neutral`, `special_side`, `special_up`, `special_down`). Press the Special key (G for P1, Slash for P2); hold a direction/jump/down for the other three. They glow while winding up and burst out as a star.
- **Roster**: 29 characters. Add more by copying the template above the `# ADD NEW CHARACTERS HERE` marker; use `based_on` to inherit and only override what's different. Give each a `"bio"` and named specials.
- **Almanac** (main menu, under START): the CHARACTERS tab shows every fighter's bio, stat bars and full move table; the CONTROLS tab shows keys and how to do each attack. Both read from the roster and InputMap, so they update automatically when you change a character or rebind a key.
