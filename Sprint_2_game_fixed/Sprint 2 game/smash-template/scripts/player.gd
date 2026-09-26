extends CharacterBody2D
class_name SmashPlayer

##
## Four attack directions:
# tap attack for neutral,
# hold jump + attack for up, 
#hold down + attack for down, #
#or reverse direction right as you ## press attack for a "back" pivot strike behind you. A small flash shap

const GRAVITY := 1400.0
const FRICTION := 1400.0
const BLAST_TOP_Y := -650.0
const BLAST_BOTTOM_Y := 1000.0
const BLAST_SIDE_X := 1400.0
const SCREEN_SPLAT_CHANCE := 0.35
const DEFAULT_ATTACK := {
	"damage": 12.0, "kb_base": 150.0, "kb_scale": 6.0, "range": 30.0,
	"startup": 0.06, "active": 0.12, "cooldown": 0.4, "hits": 1, "angle": 35.0,
}

@export var input_prefix: String = "p1_"
@export var is_cpu: bool = false
@export var is_remote: bool = false # true only for the network opponent's puppet in online mode
@export var stats: Dictionary = {}
@export var stocks: int = 3

var damage_percent: float = 0.0
var jumps_left: int = 1
var max_jumps: int = 1
var facing: int = 1
var is_attacking: bool = false
var attack_cooldown: float = 0.0
var opponents: Array = []
var current_attack: Dictionary = DEFAULT_ATTACK
var current_strike_dir: int = 1

signal ko(player)

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var attack_fx: Polygon2D = $AttackFX
@onready var hitbox: Area2D = $Hitbox
@onready var damage_label: Label = $DamageLabel

func _ready() -> void:
	var color: Color = stats.get("color", Color.WHITE)
	sprite.sprite_frames = SpriteGen.build(color)
	sprite.play("idle")
	max_jumps = 1 + int(stats.get("extra_jumps", 1))
	jumps_left = max_jumps
	hitbox.monitoring = false
	hitbox.body_entered.connect(_on_hitbox_body_entered)
	_update_label()

func _physics_process(delta: float) -> void:
	if is_remote:
		# This is just a puppet of the other player's real character - its
		# actual state arrives via apply_remote_state() (see game.gd's
		# _on_network_message), not local simulation. Still update its
		# animation so it visually reflects whatever state just arrived.
		_update_animation()
		return

	if attack_cooldown > 0.0:
		attack_cooldown -= delta

	var gravity_scale: float = stats.get("gravity_scale", 1.0)
	if not is_on_floor():
		velocity.y += GRAVITY * gravity_scale * delta
	else:
		jumps_left = max_jumps

	var direction := 0.0
	var jump_pressed := false
	var attack_pressed := false
	var variant := "neutral"
	var old_facing := facing

	if is_cpu:
		var cpu_result := _cpu_think()
		direction = cpu_result[0]
		jump_pressed = cpu_result[1]
		attack_pressed = cpu_result[2]
		variant = cpu_result[3]
	else:
		direction = Input.get_axis(input_prefix + "left", input_prefix + "right")
		jump_pressed = Input.is_action_just_pressed(input_prefix + "jump")
		attack_pressed = Input.is_action_just_pressed(input_prefix + "attack")
		if Input.is_action_pressed(input_prefix + "down"):
			variant = "down"
		elif Input.is_action_pressed(input_prefix + "jump"):
			variant = "up"
		elif direction != 0.0 and int(sign(direction)) != old_facing:
			# This one should act as a pivot attack or backstrike 🙏🙏🙏✌️✌️
			variant = "back"

	var speed: float = stats.get("speed", 300.0)
	if direction != 0.0:
		facing = int(sign(direction))
		sprite.flip_h = facing < 0
		velocity.x = move_toward(velocity.x, direction * speed, FRICTION * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	if jump_pressed and jumps_left > 0:
		velocity.y = stats.get("jump_velocity", -600.0)
		jumps_left -= 1

	if attack_pressed and attack_cooldown <= 0.0 and not is_attacking:
		_do_attack(variant)

	move_and_slide()
	_update_animation()

	if global_position.y < BLAST_TOP_Y:
		_on_ko(true)
	elif global_position.y > BLAST_BOTTOM_Y or absf(global_position.x) > BLAST_SIDE_X:
		_on_ko(false)

func _update_animation() -> void:
	if is_attacking:
		return
	var anim := "idle"
	if not is_on_floor():
		anim = "jump"
	elif absf(velocity.x) > 20.0:
		anim = "run"
	if sprite.animation != anim:
		sprite.play(anim)

func _do_attack(variant: String = "neutral") -> void:
	is_attacking = true
	var attacks: Dictionary = stats.get("attacks", {})
	var atk: Dictionary = attacks.get(variant, attacks.get("neutral", DEFAULT_ATTACK))
	current_attack = atk
	var hits: int = int(atk.get("hits", 1))
	attack_cooldown = atk.get("cooldown", 0.4)

	if sprite.sprite_frames.has_animation("attack"):
		sprite.play("attack")

	await get_tree().create_timer(atk.get("startup", 0.06)).timeout

	var range_val: float = atk.get("range", 30.0)
	current_strike_dir = facing

	match variant:
		"up":
			hitbox.position = Vector2(range_val * 0.6 * facing, -60)
			attack_fx.position = Vector2(range_val * 0.3 * facing, -66)
			attack_fx.rotation = deg_to_rad(-90.0)
		"down":
			hitbox.position = Vector2(range_val * facing, -8)
			attack_fx.position = Vector2(range_val * 0.6 * facing, -4)
			attack_fx.rotation = deg_to_rad(90.0)
		"back":
			current_strike_dir = -facing
			hitbox.position = Vector2(range_val * current_strike_dir, -32)
			attack_fx.position = Vector2(range_val * current_strike_dir * 0.7, -32)
			attack_fx.rotation = 0.0 if current_strike_dir > 0 else PI
		_:
			hitbox.position = Vector2(range_val * facing, -32)
			attack_fx.position = Vector2(range_val * 0.7 * facing, -32)
			attack_fx.rotation = 0.0 if facing > 0 else PI

	attack_fx.color = stats.get("color", Color.WHITE).lightened(0.4)
	attack_fx.visible = true

	for h in hits:
		hitbox.monitoring = true
		await get_tree().create_timer(atk.get("active", 0.12) / hits).timeout
		hitbox.monitoring = false
		if h < hits - 1:
			await get_tree().create_timer(0.03).timeout

	attack_fx.visible = false
	is_attacking = false

func _on_hitbox_body_entered(hit_body: Node) -> void:
	if hit_body == self:
		return
	if hit_body.has_method("take_hit"):
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
				"type": "hit", "damage": per_hit_damage, "from_dir": current_strike_dir,
				"kb_base": kb_base, "kb_scale": kb_scale, "angle": angle,
			})
		else:
			hit_body.take_hit(per_hit_damage, current_strike_dir, kb_base, kb_scale, angle)

func take_hit(dmg: float, from_dir: int, kb_base: float = 150.0, kb_scale: float = 6.0, angle_deg: float = 35.0) -> void:
	damage_percent += dmg
	var weight: float = stats.get("weight", 1.0)
	var kb: float = ((kb_base + damage_percent * kb_scale) * 0.01) / maxf(weight, 0.1)
	var rad := deg_to_rad(angle_deg)
	velocity.x = from_dir * kb * 100.0 * cos(rad)
	velocity.y = -kb * 100.0 * sin(rad)
	_update_label()
	if sprite.sprite_frames.has_animation("hurt"):
		sprite.play("hurt")

func _update_label() -> void:
	if damage_label:
		damage_label.text = "%d%%" % int(damage_percent)

func _on_ko(top_blast: bool = false) -> void:
	stocks -= 1
	damage_percent = 0.0
	_update_label()
	if top_blast and randf() < SCREEN_SPLAT_CHANCE:
		ScreenFX.show_splat(stats.get("color", Color.WHITE))
	ko.emit(self)
	if stocks <= 0:
		queue_free()
	else:
		global_position = Vector2(0, -200)
		velocity = Vector2.ZERO

func _cpu_think() -> Array:
	var direction := 0.0
	var jump_pressed := false
	var attack_pressed := false
	var variant := "neutral"
	var target: SmashPlayer = _nearest_opponent()
	if target != null:
		var to_opp: Vector2 = target.global_position - global_position
		if absf(to_opp.x) > 30.0:
			direction = sign(to_opp.x)
		if to_opp.y < -80.0 and jumps_left > 0 and randf() < 0.05:
			jump_pressed = true
		if absf(to_opp.x) < 60.0 and attack_cooldown <= 0.0:
			attack_pressed = true
			if to_opp.y < -50.0:
				variant = "up"
			elif to_opp.y > 50.0 and not is_on_floor():
				variant = "down"
	if global_position.x < -320.0:
		direction = 1.0
	elif global_position.x > 320.0:
		direction = -1.0
	return [direction, jump_pressed, attack_pressed, variant]

func _nearest_opponent() -> SmashPlayer:
	var nearest: SmashPlayer = null
	var best_dist := INF
	for o in opponents:
		if o == null or not is_instance_valid(o):
			continue
		var d: float = global_position.distance_to(o.global_position)
		if d < best_dist:
			best_dist = d
			nearest = o
	return nearest

## Called by game.gd (_on_network_message) whenever a "state" packet
## arrives from the other player over the relay. Just applies it directly -
## this player is is_remote, so nothing else is driving its transform.
func apply_remote_state(data: Dictionary) -> void:
	global_position = Vector2(data.get("x", global_position.x), data.get("y", global_position.y))
	velocity = Vector2(data.get("vx", 0.0), data.get("vy", 0.0))
	damage_percent = data.get("dmg", damage_percent)
	stocks = int(data.get("stocks", stocks))
	facing = int(data.get("facing", facing))
	sprite.flip_h = facing < 0
	_update_label()
	if stocks <= 0:
		# The real fighter (on the other machine) already ran its own
		# _on_ko() and freed itself - mirror that here so our HUD shows
		# "KO" instead of a stale 0% entry that never goes away.
		queue_free()
