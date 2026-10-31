extends CharacterBody2D
class_name SmashPlayer

## One fighter - the human players, the CPUs, and the network puppet in
## online mode are ALL this same script (game.gd's _spawn_player() creates
## every one from Player.tscn). What makes them different is just the
## @export vars below: is_cpu swaps the input for _cpu_think(), is_remote
## turns the whole thing into a puppet, and stats decides how they play.
##
## Four attack directions:
# tap attack for neutral,
# hold jump + attack for up,
#hold down + attack for down, #
#or reverse direction right as you ## press attack for a "back" pivot strike behind you. A small flash shap
# Specials (hold the special button, G for P1 - registered in InputSetup.gd):
# special alone = special_neutral, + left/right = special_side,
# + jump held = special_up, + down held = special_down. Their numbers live in
# each character's "attacks" in character_roster.gd, same fields as normal moves.
# (^ that last line got cut off - it's the AttackFX Polygon2D in Player.tscn:
# a small flash shape that appears right where the hitbox is, so you can see
# which direction the swing went. Set up in _do_attack().)

# Gravity in pixels/second^2. Each character multiplies this by their own
# "gravity_scale" stat (see _physics_process) - Yellow's 0.7 is why they're floaty.
const GRAVITY := 1400.0
# Used for BOTH speeding up and slowing down horizontally (it's the
# move_toward step in _physics_process), so raising it makes everyone
# snappier at starting AND stopping, not just stopping.
const FRICTION := 1400.0
# The three blast lines, in world coordinates - go past one and you lose a
# stock (checked at the bottom of _physics_process). Remember Godot's y
# axis points DOWN, which is why the top one is a negative number. For scale:
# the Stage's platform is at y=200 and spans x=-350..350 (see Stage.tscn).
const BLAST_TOP_Y := -650.0
const BLAST_BOTTOM_Y := 1000.0
const BLAST_SIDE_X := 1400.0
# Chance (0.0 to 1.0) that dying off the TOP blast line triggers the "Screen
# KO" splat from autoload/ScreenFX.gd. Used in _on_ko().
const SCREEN_SPLAT_CHANCE := 0.35
# What a move falls back to if the character's stats are missing it (or
# missing a number inside it) - same values as CharacterRoster.BASE_MOVE.
# Every .get("something", default) in this script is the same idea.
const DEFAULT_ATTACK := {
	"damage": 12.0, "kb_base": 150.0, "kb_scale": 6.0, "range": 30.0,
	"startup": 0.06, "active": 0.12, "cooldown": 0.4, "hits": 1, "angle": 35.0,
}

# How specials look different from normal attacks (all set up in _do_attack):
#  - a "charge" tell: the fighter glows bright during the move's startup, so
#    you can SEE a special winding up
#  - the AttackFX flash becomes a big spiky star (instead of the small bar),
#    brighter than a normal flash, and it "pops" outward when it appears
# The star's outline is built once in _ready() by _make_star() near the bottom.
const SPECIAL_GLOW := Color(2.5, 2.5, 2.5) # sprite.modulate above 1.0 = brighter than normal; this is the peak of the charge glow
const SPECIAL_FX_SCALE := 1.7 # how big the star ends up compared to the normal flash

# --- Shield / dodge tuning (all in one place so it's easy to rebalance) ---
# Hold the shield button (Shift for P1) on the ground to raise a bubble. It
# blocks every hit (no damage, no knockback) but each block - and just holding
# it - wears it down; it shrinks as it weakens. At 0 it BREAKS and you're
# stunned. While shielding you can't move or attack, but you can:
#   tap left / right  -> ROLL that way (brief invincibility)
#   tap down          -> SPOT DODGE (brief invincibility, stay put)
#   tap jump          -> hop out of the shield
const SHIELD_MAX := 100.0
const SHIELD_DRAIN := 12.0          # health lost per second just from holding it up
const SHIELD_REGEN := 22.0          # health regained per second when it's down
const SHIELD_DAMAGE_MULT := 2.0     # a blocked hit costs (its damage x this) shield health
const SHIELD_MIN_TO_RAISE := 8.0    # can't raise a nearly-empty shield (stops flicker spam)
const SHIELD_BREAK_STUN := 2.0      # seconds you're helpless after a break
const SHIELD_AFTER_BREAK := 0.35    # fraction of shield you come back with
const SHIELD_R_MAX := 40.0          # bubble radius (px) when full...
const SHIELD_R_MIN := 14.0          # ...and when almost gone
const ROLL_TIME := 0.38
const ROLL_SPEED := 430.0
const SPOT_DODGE_TIME := 0.32
const DODGE_COOLDOWN := 0.25        # short lockout after a dodge so it can't be chained forever
const SPAWN_SHIELD_TIME := 3.0      # invincible bubble after (re)spawning; ends early if you attack

# Prefix for the input actions this fighter reads: "p1_" means it listens to
# p1_left / p1_right / p1_jump / p1_down / p1_attack, which are registered
# in autoload/InputSetup.gd. CPUs get "cpu_1_" etc. from game.gd but never
# actually read it - they take the is_cpu branch instead.
@export var input_prefix: String = "p1_"
@export var is_cpu: bool = false
var net_slot: int = -1 # online only: which player (relay slot 0-3) this fighter is - set by game.gd, used to address "hit" messages
@export var is_remote: bool = false # true only for the network opponent's puppet in online mode
# This fighter's entry from GameManager.characters (built in
# scripts/character_roster.gd). game.gd's _spawn_player() assigns it BEFORE
# add_child(), which is why _ready() below can already read it.
@export var stats: Dictionary = {}
@export var stocks: int = 3

# Smash-style damage: starts at 0 and only goes up, and the higher it is
# the farther each hit launches you (see take_hit).
var damage_percent: float = 0.0
var jumps_left: int = 1
var max_jumps: int = 1 # 1 ground jump + the character's "extra_jumps" stat - set in _ready()
var facing: int = 1 # 1 = facing right, -1 = facing left
var is_attacking: bool = false # true from the start of a swing until it fully ends - blocks starting another swing
var attack_cooldown: float = 0.0 # counts down in _physics_process; can't attack again until it hits 0
var opponents: Array = [] # filled in by game.gd's _link_opponents() - the CPU looks at this to pick a target
var current_attack: Dictionary = DEFAULT_ATTACK # the move being swung right now - the hitbox callback reads damage/knockback from here
var current_strike_dir: int = 1 # which way the CURRENT swing is pointing (differs from facing for "back")
# The AttackFX's normal bar shape, remembered in _ready() so a special's star
# can be swapped in for one swing and the bar restored afterwards.
var _normal_fx_polygon: PackedVector2Array
var _special_fx_polygon: PackedVector2Array

# Shield / dodge state (see the constants above).
var shield_health: float = SHIELD_MAX
var is_shielding: bool = false
var shield_stun: float = 0.0        # after blocking a hit you can't drop the shield for a moment
var stun_time: float = 0.0          # >0 = helpless (shield break)
var dodge_time: float = 0.0         # >0 = mid roll / spot dodge (invincible, can't act)
var dodge_kind: String = ""         # "roll" or "spot"
var dodge_dir: int = 1
var dodge_cooldown: float = 0.0
var spawn_shield_time: float = 0.0  # >0 = spawn bubble up (invincible)
var _bubble: Polygon2D              # the visible bubble (made in code in _ready)
var _bubble_flash: float = 0.0      # brightens the bubble briefly when it blocks a hit
var bubble_r: float = 0.0           # radius being drawn right now; 0 = hidden. Sent to other players so puppets show it too
var _ghost: bool = false            # fighter drawn see-through (dodging)
var _dizzy: bool = false            # fighter tinted (shield broken)
var _cpu_block_timer: float = 0.0   # CPU only: how much longer it keeps its shield up

# Emitted from _on_ko() every time this fighter loses a stock. Nothing is
# connected to it right now (game.gd's HUD just polls damage_percent/stocks
# every frame in _process instead) but it's there if you want a "player
# died" hook later.
signal ko(player)

# These four are child nodes made in scenes/Player.tscn - the names in the
# $Paths have to match the node names in that scene exactly.
@onready var sprite: AnimatedSprite2D = $Sprite
@onready var attack_fx: Polygon2D = $AttackFX
@onready var hitbox: Area2D = $Hitbox
@onready var damage_label: Label = $DamageLabel

func _ready() -> void:
	var color: Color = stats.get("color", Color.WHITE)
	# Sprite: if the character has a "frames" path in character_roster.gd,
	# use that hand-made SpriteFrames (needs animations named idle, run,
	# jump, attack, hurt). Otherwise generate the colored placeholder guy
	# in code (scripts/sprite_gen.gd). face_color is white for very dark
	# characters so their face doesn't vanish.
	var frames_path: String = stats.get("frames", "")
	if frames_path != "" and ResourceLoader.exists(frames_path):
		sprite.sprite_frames = load(frames_path)
	else:
		sprite.sprite_frames = SpriteGen.build(color, stats.get("face_color", Color.BLACK))
	sprite.play("idle")
	_normal_fx_polygon = attack_fx.polygon # the bar from Player.tscn
	_special_fx_polygon = _make_star(20.0, 9.0, 8) # 8-point star, 20px tips, 9px dents
	# max_jumps counts the first jump too, so extra_jumps 1 = double jump,
	# Yellow's extra_jumps 2 = triple jump.
	max_jumps = 1 + int(stats.get("extra_jumps", 1))
	jumps_left = max_jumps
	# The hitbox stays switched off except during the "active" part of a
	# swing (see _do_attack) - otherwise it would hit anyone standing in it.
	hitbox.monitoring = false
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	# The shield bubble: a unit circle that gets scaled to the radius we want.
	_bubble = Polygon2D.new()
	var circle := PackedVector2Array()
	for i in 32:
		circle.append(Vector2(cos(TAU * i / 32.0), sin(TAU * i / 32.0)))
	_bubble.polygon = circle
	_bubble.position = Vector2(0, -32) # chest height, like the hitbox
	_bubble.z_index = 3
	_bubble.visible = false
	add_child(_bubble)
	spawn_shield_time = SPAWN_SHIELD_TIME
	_update_label()

func _physics_process(delta: float) -> void:
	if is_remote:
		# This is just a puppet of the other player's real character - its
		# actual state arrives via apply_remote_state() (see game.gd's
		# _on_network_message), not local simulation. Still update its
		# animation so it visually reflects whatever state just arrived.
		_update_animation()
		_draw_bubble(delta)
		_apply_tint()
		return

	if attack_cooldown > 0.0:
		attack_cooldown -= delta
	dodge_cooldown = maxf(dodge_cooldown - delta, 0.0)
	shield_stun = maxf(shield_stun - delta, 0.0)
	spawn_shield_time = maxf(spawn_shield_time - delta, 0.0)
	if stun_time > 0.0:
		stun_time -= delta
		if stun_time <= 0.0:
			stun_time = 0.0
	if dodge_time > 0.0:
		dodge_time -= delta
		if dodge_time <= 0.0:
			dodge_time = 0.0
			dodge_cooldown = DODGE_COOLDOWN

	# Gravity only while airborne; touching the floor refills jumps. (is_on_floor()
	# reports what happened during LAST frame's move_and_slide() below.)
	var gravity_scale: float = stats.get("gravity_scale", 1.0)
	if not is_on_floor():
		velocity.y += GRAVITY * gravity_scale * delta
	else:
		jumps_left = max_jumps

	# --- Step 1: figure out what this fighter wants to do this frame ---
	# Both humans and CPUs fill in these same 5 variables, and everything
	# after this block doesn't care which one produced them.
	var direction := 0.0 # -1 = left, 0 = nothing, 1 = right
	var jump_pressed := false
	var attack_pressed := false
	var special_pressed := false # the special button (G) - picks one of the "special_*" moves instead
	var variant := "neutral" # which move in stats["attacks"] to use ("neutral", "up", "special_side"...)
	var shield_held := false # the shield button is down
	var left_tap := false # just-pressed this frame (used for rolls out of shield)
	var right_tap := false
	var down_tap := false # (spot dodge)
	var old_facing := facing # remembered BEFORE we update facing below - that's how "back" can tell you just turned around

	if is_cpu:
		# _cpu_think() returns [direction, jump_pressed, attack_pressed, variant]
		var cpu_result := _cpu_think()
		direction = cpu_result[0]
		jump_pressed = cpu_result[1]
		attack_pressed = cpu_result[2]
		variant = cpu_result[3]
		shield_held = cpu_result[4]
		# The CPU rolls out of its shield sometimes, so it isn't just a statue.
		if shield_held and is_shielding and randf() < 0.01:
			left_tap = randf() < 0.5
			right_tap = not left_tap
	else:
		direction = Input.get_axis(input_prefix + "left", input_prefix + "right")
		# "just_pressed" = only the frame the key goes down (one jump per tap)...
		jump_pressed = Input.is_action_just_pressed(input_prefix + "jump")
		attack_pressed = Input.is_action_just_pressed(input_prefix + "attack")
		# ...but is_action_pressed below is "is it held right now", which is
		# how hold-jump + attack = up attack works. The order of this
		# if/elif is a priority list: down beats up, and both beat back.
		if Input.is_action_pressed(input_prefix + "down"):
			variant = "down"
		elif Input.is_action_pressed(input_prefix + "jump"):
			variant = "up"
		elif direction != 0.0 and int(sign(direction)) != old_facing:
			# This one should act as a pivot attack or backstrike 🙏🙏🙏✌️✌️
			# (holding the opposite way of where you're currently facing)
			variant = "back"
		if InputMap.has_action(input_prefix + "shield"):
			shield_held = Input.is_action_pressed(input_prefix + "shield")
		left_tap = Input.is_action_just_pressed(input_prefix + "left")
		right_tap = Input.is_action_just_pressed(input_prefix + "right")
		down_tap = Input.is_action_just_pressed(input_prefix + "down")

		# Specials. The guard is there so the game doesn't spam errors if the
		# "special" action hasn't been registered in InputSetup.gd yet (an
		# unknown action name makes Input complain every frame).
		if InputMap.has_action(input_prefix + "special"):
			special_pressed = Input.is_action_just_pressed(input_prefix + "special")
		# Same priority-list idea as above, but for specials: the direction held
		# when you hit G picks WHICH special. This runs after the normal chain,
		# so if G is pressed it overrides whatever variant that chose.
		# (The CPU never uses specials - special_pressed just stays false for it.)
		if special_pressed:
			if Input.is_action_pressed(input_prefix + "down"):
				variant = "special_down"
			elif Input.is_action_pressed(input_prefix + "jump"):
				variant = "special_up"
			elif direction != 0.0:
				variant = "special_side" # facing is updated to this direction in step 2 just below, so the hit goes where you're pushing
			else:
				variant = "special_neutral"

	# --- Step 1.5: shield / dodge / stun ---
	# These override what the fighter wanted to do above.
	var locked := stun_time > 0.0 or dodge_time > 0.0 # helpless: no moving, jumping or attacking
	if locked:
		is_shielding = false
		direction = 0.0
		jump_pressed = false
		attack_pressed = false
		special_pressed = false
	else:
		if shield_held and not is_attacking and is_on_floor() \
				and (is_shielding or (shield_health >= SHIELD_MIN_TO_RAISE and dodge_cooldown <= 0.0)):
			is_shielding = true
		elif is_shielding and shield_stun > 0.0 and is_on_floor():
			pass # just blocked a hit: can't drop it instantly (shield stun)
		else:
			is_shielding = false
	if is_shielding:
		shield_health -= SHIELD_DRAIN * delta
		if jump_pressed:
			is_shielding = false # hop out of the shield (the jump below still happens)
		elif (left_tap or right_tap) and shield_stun <= 0.0:
			is_shielding = false
			dodge_kind = "roll"
			dodge_dir = 1 if right_tap else -1
			dodge_time = ROLL_TIME
			_ghost = true
			direction = 0.0
		elif down_tap and shield_stun <= 0.0:
			is_shielding = false
			dodge_kind = "spot"
			dodge_time = SPOT_DODGE_TIME
			_ghost = true
			direction = 0.0
		else:
			# Shielding = rooted and can't attack.
			direction = 0.0
			attack_pressed = false
			special_pressed = false
			if shield_health <= 0.0:
				_shield_break(0)
	elif not locked:
		shield_health = minf(shield_health + SHIELD_REGEN * delta, SHIELD_MAX)

	# --- Step 2: apply it ---
	var speed: float = stats.get("speed", 300.0)
	if direction != 0.0:
		facing = int(sign(direction))
		sprite.flip_h = facing < 0 # the placeholder sprite faces right by default
		# Ramp toward full speed instead of snapping to it (FRICTION is the ramp rate)
		velocity.x = move_toward(velocity.x, direction * speed, FRICTION * delta)
	else:
		# No input: ramp back down to a stop
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	if dodge_time > 0.0:
		# Rolls slide you along the ground; spot dodges stay put.
		velocity.x = dodge_dir * ROLL_SPEED if dodge_kind == "roll" else 0.0
	elif is_shielding:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * 2.0 * delta) # sliding to a stop after a block's pushback

	# Negative jump_velocity because up is negative y. Works mid-air too as
	# long as jumps_left > 0 - that's the double/triple jump.
	if jump_pressed and jumps_left > 0:
		velocity.y = stats.get("jump_velocity", -600.0)
		jumps_left -= 1

	# Can't start a swing while the cooldown is running OR while the previous
	# swing is still playing out. _do_attack() is async (it awaits timers),
	# so this call returns right away and the swing finishes in the background.
	# Either button starts a swing - `variant` (set in step 1) says which move.
	if (attack_pressed or special_pressed) and attack_cooldown <= 0.0 and not is_attacking:
		_do_attack(variant)

	# move_and_slide() actually moves the body using `velocity` and handles
	# bumping into the stage. Fighters are on collision layer 2 and only
	# mask layer 1 (the stage - see Player.tscn), so they walk through each other.
	move_and_slide()
	_update_animation()
	_draw_bubble(delta)
	_apply_tint()

	# Blast line checks. Top blast is separate so it can trigger the Screen KO splat.
	if global_position.y < BLAST_TOP_Y:
		_on_ko(true)
	elif global_position.y > BLAST_BOTTOM_Y or absf(global_position.x) > BLAST_SIDE_X:
		_on_ko(false)

# Picks idle / jump / run from what the body is doing right now. Skipped
# entirely mid-swing so the "attack" animation that _do_attack() started
# isn't overwritten the next frame. (Also runs for online puppets, since
# their velocity/floor state comes from apply_remote_state().)
func _update_animation() -> void:
	if is_attacking:
		return
	var anim := "idle"
	if not is_on_floor():
		anim = "jump"
	elif absf(velocity.x) > 20.0: # small threshold so tiny leftover drift still reads as standing
		anim = "run"
	if sprite.animation != anim: # only call play() on a change, otherwise it restarts the animation every frame
		sprite.play(anim)

# Runs one whole swing: startup delay -> position the hitbox -> hitbox is
# live for "active" seconds -> done. The three awaits are what pause it
# between those stages without freezing the rest of the game.
# `variant` is "neutral" / "up" / "down" / "back" / "special_neutral" /
# "special_side" / "special_up" / "special_down" - a key in stats["attacks"].
func _do_attack(variant: String = "neutral") -> void:
	is_attacking = true
	spawn_shield_time = 0.0 # swinging pops the spawn bubble
	# Online: tell the other players we just swung, so THEIR copy of us
	# (the puppet) plays the same swing - animation, flash, special glow.
	# (Puppets run this same function from show_remote_attack, which is why
	# the is_remote check is here: they must not send it back.) The damage
	# itself is NOT sent this way - see _on_hitbox_body_entered.
	if net_slot >= 0 and not is_remote:
		NetworkManager.send({"type": "attack", "variant": variant, "facing": facing})
	var attacks: Dictionary = stats.get("attacks", {})
	# Fallback chain: the requested move -> the neutral move -> DEFAULT_ATTACK
	var atk: Dictionary = attacks.get(variant, attacks.get("neutral", DEFAULT_ATTACK))
	current_attack = atk # so _on_hitbox_body_entered knows what damage/knockback to use
	var hits: int = int(atk.get("hits", 1))
	attack_cooldown = atk.get("cooldown", 0.4)

	if sprite.sprite_frames.has_animation("attack"):
		sprite.play("attack")

	# Specials are told apart from normal moves by their name starting with "special_".
	var is_special := variant.begins_with("special_")

	# "startup" = the wind-up before the hit can land. Longer startup = easier to dodge.
	var charge: Tween = null
	if is_special:
		# Charge tell: fade the sprite up to a bright glow over the whole startup,
		# so the wind-up is visible. It snaps back to normal the moment the hit
		# starts (just below). Normal moves skip this and just play the attack animation.
		charge = create_tween()
		charge.tween_property(sprite, "modulate", SPECIAL_GLOW, atk.get("startup", 0.06))
	await get_tree().create_timer(atk.get("startup", 0.06)).timeout
	if charge != null:
		charge.kill() # stop it explicitly - otherwise it could finish a frame late and re-apply the glow after the reset below
	sprite.modulate = Color.WHITE # end of the glow (normal moves are already white, so this changes nothing for them)

	var range_val: float = atk.get("range", 30.0)
	current_strike_dir = facing

	# Place the invisible Hitbox and the visible AttackFX flash. The player's
	# origin is at their FEET and the body is about 64px tall, so y = -32 is
	# roughly chest height, and -60 is above the head. x is multiplied by
	# `facing` so the hit appears on the side you're looking at.
	match variant:
		# (the specials share the normal moves' hitbox spots for now: special_up
		# is placed like "up", special_down like "down", and special_neutral /
		# special_side fall into the default case at the bottom - give one its
		# own case here when you want it to hit somewhere different)
		"up", "special_up":
			hitbox.position = Vector2(range_val * 0.6 * facing, -60)
			attack_fx.position = Vector2(range_val * 0.3 * facing, -66)
			attack_fx.rotation = deg_to_rad(-90.0) # point the flash straight up
		"down", "special_down":
			hitbox.position = Vector2(range_val * facing, -8) # low, near the feet
			attack_fx.position = Vector2(range_val * 0.6 * facing, -4)
			attack_fx.rotation = deg_to_rad(90.0)
		"back":
			# Strikes the OPPOSITE way from `facing`. Since you just turned
			# to face the new direction, this is what hits whoever is behind you.
			current_strike_dir = -facing
			hitbox.position = Vector2(range_val * current_strike_dir, -32)
			attack_fx.position = Vector2(range_val * current_strike_dir * 0.7, -32)
			attack_fx.rotation = 0.0 if current_strike_dir > 0 else PI
		_: # "neutral", "special_neutral", "special_side" (and anything unrecognized)
			hitbox.position = Vector2(range_val * facing, -32)
			attack_fx.position = Vector2(range_val * 0.7 * facing, -32)
			attack_fx.rotation = 0.0 if facing > 0 else PI

	if is_special:
		# Special look: star shape, much lighter than a normal flash, and it
		# starts small and pops out to SPECIAL_FX_SCALE (TRANS_BACK overshoots a
		# little first, which is what makes it feel like a burst).
		attack_fx.polygon = _special_fx_polygon
		attack_fx.color = stats.get("color", Color.WHITE).lightened(0.75)
		attack_fx.scale = Vector2(0.5, 0.5)
		var pop := create_tween()
		pop.tween_property(attack_fx, "scale", Vector2(SPECIAL_FX_SCALE, SPECIAL_FX_SCALE), 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		attack_fx.polygon = _normal_fx_polygon
		attack_fx.color = stats.get("color", Color.WHITE).lightened(0.4)
		attack_fx.scale = Vector2.ONE
	attack_fx.visible = true

	# For multi-hit moves (Yellow's neutral has hits = 3), the "active" time
	# is split evenly between the hits, and the hitbox is switched off and
	# back on between each one - that re-trigger is what lets the same
	# opponent get hit again, because body_entered only fires when something
	# ENTERS the area. The extra 0.03s gap between hits is on top of "active".
	for h in hits:
		hitbox.monitoring = true
		await get_tree().create_timer(atk.get("active", 0.12) / hits).timeout
		hitbox.monitoring = false
		if h < hits - 1:
			await get_tree().create_timer(0.03).timeout

	attack_fx.visible = false
	attack_fx.polygon = _normal_fx_polygon # put the bar back so the next normal move looks normal
	attack_fx.scale = Vector2.ONE
	is_attacking = false

# Fires whenever a body overlaps the Hitbox while hitbox.monitoring is on.
# The hitbox's collision mask is 2 (fighters only, see Player.tscn), so this
# only ever sees other fighters - but the checks below are still needed
# because the hitbox also overlaps its own owner.
func _on_hitbox_body_entered(hit_body: Node) -> void:
	if hit_body == self or is_remote:
		return # (a puppet's swing is just for show - the real fighter on its own machine decides who it hits)
	# Anything with a take_hit() function counts as hittable - this is how
	# the same code would work on a training dummy or something later.
	if hit_body.has_method("take_hit"):
		# A multi-hit move's total damage is split across its hits, so a 3-hit
		# move with damage 3.0 does 1.0 per hit.
		var hits: int = maxi(int(current_attack.get("hits", 1)), 1)
		var per_hit_damage: float = current_attack.get("damage", 12.0) / hits
		var kb_base: float = current_attack.get("kb_base", 150.0)
		var kb_scale: float = current_attack.get("kb_scale", 6.0)
		var angle: float = current_attack.get("angle", 35.0)
		if "is_remote" in hit_body and hit_body.is_remote:
			# hit_body is just our local puppet of the opponent - the real,
			# authoritative copy of them lives on their machine. Tell them
			# about the hit over the relay instead of applying it here;
			# their own take_hit() call will show up in their next "state"
			# broadcast back to us.
			NetworkManager.send({
				"type": "hit", "to": hit_body.net_slot, "damage": per_hit_damage, "from_dir": current_strike_dir,
				"kb_base": kb_base, "kb_scale": kb_scale, "angle": angle,
			})
			# (the other machine receives this in game.gd's _on_network_message "hit" case)
		else:
			hit_body.take_hit(per_hit_damage, current_strike_dir, kb_base, kb_scale, angle)

# Called on the fighter that GOT hit (directly from the attacker's
# _on_hitbox_body_entered in local games, or from game.gd's
# _on_network_message in online games).
# dmg - percent to add; from_dir - 1 sends them right, -1 sends them left;
# the rest are the attacker's kb_base / kb_scale / angle numbers.
func take_hit(dmg: float, from_dir: int, kb_base: float = 150.0, kb_scale: float = 6.0, angle_deg: float = 35.0) -> void:
	# Dodging (roll / spot dodge) or standing in the spawn bubble: the hit simply misses.
	if dodge_time > 0.0 or spawn_shield_time > 0.0:
		return
	# Blocking: no damage, no knockback - the hit chews up the shield instead.
	if is_shielding:
		shield_health -= dmg * SHIELD_DAMAGE_MULT
		shield_stun = 0.05 + dmg * 0.008 # a short moment where you can't let go
		velocity.x = from_dir * clampf(dmg * 18.0, 60.0, 260.0) # small pushback
		_bubble_flash = 0.12
		if shield_health <= 0.0:
			_shield_break(from_dir)
		return
	damage_percent += dmg # damage goes up FIRST so this very hit already counts toward its own knockback
	var weight: float = stats.get("weight", 1.0)
	# The knockback formula (also written out in the README): base push plus
	# extra per damage%, shrunk by 100x to get a multiplier, then divided by
	# weight - so heavier characters (weight > 1) fly less far, lighter ones
	# (like Yellow's 0.8) fly further. maxf() stops a weight of 0 dividing by zero.
	var kb: float = ((kb_base + damage_percent * kb_scale) * 0.01) / maxf(weight, 0.1)
	var rad := deg_to_rad(angle_deg)
	# Split the knockback into sideways/up using the angle: cos = how
	# horizontal, sin = how vertical (minus because up is negative y).
	# This REPLACES velocity instead of adding to it, and there's no hitstun -
	# you can steer and attack again right away (the README's "extending it
	# further" list mentions hitstun as a future idea).
	velocity.x = from_dir * kb * 100.0 * cos(rad)
	velocity.y = -kb * 100.0 * sin(rad)
	_update_label()
	if sprite.sprite_frames.has_animation("hurt"):
		sprite.play("hurt")

# The shield ran out: the bubble pops, you hop up helpless for a couple of
# seconds, then come back with a partly-filled shield.
func _shield_break(from_dir: int) -> void:
	is_shielding = false
	shield_health = SHIELD_MAX * SHIELD_AFTER_BREAK
	stun_time = SHIELD_BREAK_STUN
	shield_stun = 0.0
	velocity = Vector2(from_dir * 120.0, -520.0)
	_dizzy = true
	_bubble_flash = 0.0

# Shows / sizes the bubble. Local fighters work out the radius from their own
# state; puppets just use the radius that came in the last "state" message
# (see apply_remote_state), so everyone sees everyone's shields.
func _draw_bubble(delta: float) -> void:
	if not is_remote:
		bubble_r = 0.0
		if is_shielding:
			bubble_r = lerpf(SHIELD_R_MIN, SHIELD_R_MAX, clampf(shield_health / SHIELD_MAX, 0.0, 1.0))
		elif spawn_shield_time > 0.0:
			bubble_r = SHIELD_R_MAX
			# blink during the last moments so you can tell it's about to end
			if spawn_shield_time < 0.7 and int(spawn_shield_time * 10.0) % 2 == 0:
				bubble_r = 0.0
	_bubble_flash = maxf(_bubble_flash - delta, 0.0)
	_bubble.visible = bubble_r > 0.5
	if not _bubble.visible:
		return
	_bubble.scale = Vector2(bubble_r, bubble_r)
	var col: Color = stats.get("color", Color.WHITE)
	# Weak shields redden, like Smash's.
	var weak := 0.0
	if is_shielding or is_remote:
		weak = 1.0 - clampf((bubble_r - SHIELD_R_MIN) / (SHIELD_R_MAX - SHIELD_R_MIN), 0.0, 1.0)
	col = col.lightened(0.1).lerp(Color(1.0, 0.25, 0.2), weak * 0.7)
	var alpha := 0.6 if _bubble_flash > 0.0 else 0.42
	_bubble.color = Color(col, alpha)

# See-through while dodging; yellowish while stunned. Local fighters derive it
# from their own timers; puppets get the two flags in each state message.
func _apply_tint() -> void:
	if not is_remote:
		_ghost = dodge_time > 0.0
		_dizzy = stun_time > 0.0
	if is_attacking:
		return # a swing controls the sprite's colour (special glow) - leave it alone
	if _dizzy:
		sprite.modulate = Color(1.0, 1.0, 0.45)
	elif _ghost:
		sprite.modulate = Color(1.0, 1.0, 1.0, 0.45)
	elif sprite.modulate != Color.WHITE:
		sprite.modulate = Color.WHITE

# Refreshes the little "12%" text floating above the fighter's head (the
# DamageLabel node in Player.tscn). The `if damage_label:` guard is there
# because take_hit() could in theory run before the node tree is ready.
func _update_label() -> void:
	if damage_label:
		damage_label.text = "%d%%" % int(damage_percent)

# Called from _physics_process when you cross a blast line.
# top_blast is true only for the top line - that's the only one that can
# do the Screen KO splat.
func _on_ko(top_blast: bool = false) -> void:
	stocks -= 1
	damage_percent = 0.0
	_update_label()
	if top_blast and randf() < SCREEN_SPLAT_CHANCE:
		ScreenFX.show_splat(stats.get("color", Color.WHITE))
	ko.emit(self)
	if stocks <= 0:
		# Out of stocks: remove this fighter. game.gd's HUD notices the node
		# is gone (is_instance_valid fails) and switches their entry to "KO".
		queue_free()
	else:
		# Respawn above the middle of the stage (the platform is at y=200,
		# so -200 drops them onto it) with no leftover momentum.
		global_position = Vector2(0, -200)
		velocity = Vector2.ZERO
		# Fresh start: full shield, nothing carried over, and the spawn bubble.
		shield_health = SHIELD_MAX
		is_shielding = false
		stun_time = 0.0
		dodge_time = 0.0
		shield_stun = 0.0
		spawn_shield_time = SPAWN_SHIELD_TIME

# The CPU's whole brain. Deliberately dumb: it fakes the same inputs a human
# would give and returns them as [direction, jump_pressed, attack_pressed, variant]
# - the exact 4 values _physics_process asks for in step 1.
func _cpu_think() -> Array:
	var direction := 0.0
	var jump_pressed := false
	var attack_pressed := false
	var variant := "neutral"
	var shield_up := false
	var target: SmashPlayer = _nearest_opponent()
	if target != null:
		var to_opp: Vector2 = target.global_position - global_position
		# Walk toward them, but stop once within 30px horizontally so it
		# doesn't jitter back and forth over their head.
		if absf(to_opp.x) > 30.0:
			direction = sign(to_opp.x)
		# If they're well above us (negative y), jump with a 5%-per-frame
		# chance - the randomness stops it from jumping at the exact same
		# instant every time and keeps it from wasting all its jumps at once.
		if to_opp.y < -80.0 and jumps_left > 0 and randf() < 0.05:
			jump_pressed = true
		# Swing as soon as they're within 60px sideways and our cooldown is
		# ready. Up attack if they're above, down attack if they're below
		# AND we're airborne (a down attack on the ground would just whiff
		# at their feet). The CPU never picks "back" - see the README.
		# Defence: when an opponent swings at us from close range, sometimes put
		# the shield up for a moment (it has to react, so it isn't unbeatable).
		_cpu_block_timer = maxf(_cpu_block_timer - get_physics_process_delta_time(), 0.0)
		if target.is_attacking and absf(to_opp.x) < 90.0 and is_on_floor() and not is_attacking \
				and _cpu_block_timer <= 0.0 and shield_health > 30.0 and randf() < 0.2:
			_cpu_block_timer = randf_range(0.3, 0.7)
		if _cpu_block_timer > 0.0:
			shield_up = true
		elif absf(to_opp.x) < 60.0 and attack_cooldown <= 0.0:
			attack_pressed = true
			if to_opp.y < -50.0:
				variant = "up"
			elif to_opp.y > 50.0 and not is_on_floor():
				variant = "down"
	# Edge safety: this overrides the chase above so the CPU turns around
	# before running off the platform (which spans x = -350..350 in Stage.tscn).
	if global_position.x < -320.0:
		direction = 1.0
	elif global_position.x > 320.0:
		direction = -1.0
	return [direction, jump_pressed, attack_pressed, variant, shield_up]

# Builds a star outline for the special-move flash: `points` tips, alternating
# between the outer radius (the tips) and the inner radius (the dents) as it
# goes around the circle. Returns the list of corner points Polygon2D wants.
static func _make_star(outer: float, inner: float, points: int) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for i in points * 2:
		var radius := outer if i % 2 == 0 else inner
		var angle := PI * float(i) / points # half a step per vertex
		poly.append(Vector2(cos(angle), sin(angle)) * radius)
	return poly

# Finds the closest living fighter in `opponents` by straight-line distance.
# Returns null if there are none left (everyone else already got freed).
func _nearest_opponent() -> SmashPlayer:
	var nearest: SmashPlayer = null
	var best_dist := INF
	for o in opponents:
		# A knocked-out opponent was queue_free()'d, so the array can hold
		# dead references - is_instance_valid() filters those out.
		if o == null or not is_instance_valid(o):
			continue
		var d: float = global_position.distance_to(o.global_position)
		if d < best_dist:
			best_dist = d
			nearest = o
	return nearest

## Smash-style name tag above the head: a coloured plate with the player's
## name and a little arrow pointing down at the fighter, so you can tell
## players apart even when everyone picked the same character. Called by
## game.gd right after the fighter is spawned (text = username online,
## "P1" / "CPU 2" locally; color = that player's slot colour). The two Labels
## are made here in code, so Player.tscn didn't need editing. They sit above
## the damage % label (which spans y = -92 to -66).
var name_tag: Label
var name_arrow: Label

func set_tag(text: String, color: Color) -> void:
	if name_tag == null:
		name_tag = Label.new()
		name_tag.add_theme_font_size_override("font_size", 13)
		name_tag.add_theme_color_override("font_color", Color.WHITE)
		name_tag.add_theme_color_override("font_outline_color", Color.BLACK)
		name_tag.add_theme_constant_override("outline_size", 4)
		name_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(name_tag)
		name_arrow = Label.new()
		name_arrow.text = "▼"
		name_arrow.add_theme_font_size_override("font_size", 12)
		name_arrow.add_theme_color_override("font_outline_color", Color.BLACK)
		name_arrow.add_theme_constant_override("outline_size", 3)
		name_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(name_arrow)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(color, 0.9)
	plate.set_corner_radius_all(4)
	plate.content_margin_left = 6
	plate.content_margin_right = 6
	plate.content_margin_top = 1
	plate.content_margin_bottom = 1
	name_tag.add_theme_stylebox_override("normal", plate)
	name_tag.text = text
	var size := name_tag.get_minimum_size() # plate hugs the text...
	name_tag.size = size
	name_tag.position = Vector2(-size.x / 2.0, -124.0) # ...and is centred over the head
	name_arrow.add_theme_color_override("font_color", color)
	name_arrow.size = Vector2(20, 16)
	name_arrow.position = Vector2(-10.0, -106.0)

## Called by game.gd when an "attack" message arrives for this puppet: plays
## the same swing the real fighter just started (wind-up glow, flash, star...)
## so attacks are visible on every player's screen. Purely visual - the
## puppet's hitbox is ignored (see the is_remote check in
## _on_hitbox_body_entered), so it can't double-hit anyone.
func show_remote_attack(variant: String, new_facing: int) -> void:
	if not is_remote or is_attacking:
		return
	facing = new_facing
	sprite.flip_h = facing < 0
	_do_attack(variant)

## Called by game.gd (_on_network_message) whenever a "state" packet
## arrives from the other player over the relay. Just applies it directly -
## this player is is_remote, so nothing else is driving its transform.
func apply_remote_state(data: Dictionary) -> void:
	global_position = Vector2(data.get("x", global_position.x), data.get("y", global_position.y))
	velocity = Vector2(data.get("vx", 0.0), data.get("vy", 0.0))
	damage_percent = data.get("dmg", damage_percent)
	bubble_r = float(data.get("br", 0.0)) # shield / spawn bubble size
	_ghost = bool(data.get("gh", false))  # dodging
	_dizzy = bool(data.get("st", false))  # stunned
	stocks = int(data.get("stocks", stocks))
	facing = int(data.get("facing", facing))
	sprite.flip_h = facing < 0
	_update_label()
	if stocks <= 0:
		# The real fighter (on the other machine) already ran its own
		# _on_ko() and freed itself - mirror that here so our HUD shows
		# "KO" instead of a stale 0% entry that never goes away.
		queue_free()
