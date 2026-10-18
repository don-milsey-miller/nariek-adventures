extends CharacterBody3D
class_name BasicEnemy

enum EnemyState {
	IDLE,
	CHASE,
	ATTACK,
	DEFEATED,
}

const CLEAR_FEEDBACK_COLOR := Color(1.0, 1.0, 1.0, 0.0)
const TELEGRAPH_COLOR := Color(1.0, 0.72, 0.08, 0.55)
const DAMAGE_FLASH_COLOR := Color(1.0, 0.95, 0.92, 0.72)

@export_category("Movement")
@export_range(0.1, 10.0, 0.1) var move_speed: float = 3.2
@export_range(0.1, 40.0, 0.1) var acceleration: float = 14.0
@export_range(1.0, 30.0, 0.5) var detection_range: float = 8.0
@export_range(1.0, 40.0, 0.5) var disengage_range: float = 12.0

@export_category("Combat")
@export_range(0.5, 5.0, 0.1) var attack_range: float = 1.8
@export_range(1, 1000, 1) var attack_damage: int = 15
@export_range(0.1, 3.0, 0.05) var attack_windup: float = 0.55
@export_range(0.1, 5.0, 0.05) var attack_cooldown: float = 1.0
@export_range(0.1, 10.0, 0.1) var respawn_delay: float = 4.0

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var health: HealthComponent = $Health
@onready var visuals: Node3D = $Visuals
@onready var model_root: Node3D = $Visuals/OrcModel
@onready var health_fill: MeshInstance3D = $Visuals/HealthBar/Fill

var current_state: EnemyState = EnemyState.IDLE
var target: PlayerController
var _spawn_position: Vector3
var _feedback_material: StandardMaterial3D
var _feedback_tween: Tween


func _ready() -> void:
	_spawn_position = global_position
	_feedback_material = StandardMaterial3D.new()
	_feedback_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_feedback_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_feedback_material.albedo_color = CLEAR_FEEDBACK_COLOR
	_apply_feedback_overlay(model_root)
	target = get_tree().get_first_node_in_group("player") as PlayerController

	health.health_changed.connect(_on_health_changed)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	_on_health_changed(health.current_health, health.maximum_health)


func _physics_process(delta: float) -> void:
	if current_state == EnemyState.DEFEATED:
		return

	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as PlayerController

	if target == null or target.health.is_dead:
		current_state = EnemyState.IDLE
		_slow_to_stop(delta)
		_apply_gravity_and_move(delta)
		return

	var distance_to_target := _flat_distance_to_target()

	match current_state:
		EnemyState.IDLE:
			_slow_to_stop(delta)
			if distance_to_target <= detection_range:
				current_state = EnemyState.CHASE
		EnemyState.CHASE:
			if distance_to_target > disengage_range:
				current_state = EnemyState.IDLE
			elif distance_to_target <= attack_range:
				_begin_attack()
			else:
				_chase_target(delta)
		EnemyState.ATTACK:
			_slow_to_stop(delta)

	_apply_gravity_and_move(delta)


func _chase_target(delta: float) -> void:
	var direction := target.global_position - global_position
	direction.y = 0.0
	direction = direction.normalized()

	velocity.x = move_toward(velocity.x, direction.x * move_speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * move_speed, acceleration * delta)
	_face_direction(direction, delta)


func _slow_to_stop(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)


func _apply_gravity_and_move(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	move_and_slide()


func _face_direction(direction: Vector3, delta: float) -> void:
	if direction == Vector3.ZERO:
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	var turn_weight := clampf(10.0 * delta, 0.0, 1.0)
	visuals.rotation.y = lerp_angle(visuals.rotation.y, target_yaw, turn_weight)


func _begin_attack() -> void:
	if current_state == EnemyState.ATTACK or health.is_dead:
		return

	current_state = EnemyState.ATTACK
	velocity.x = 0.0
	velocity.z = 0.0

	var direction := target.global_position - global_position
	direction.y = 0.0
	_face_direction(direction.normalized(), 1.0)
	_set_feedback_color(TELEGRAPH_COLOR)

	await get_tree().create_timer(attack_windup).timeout
	if current_state != EnemyState.ATTACK:
		return

	_set_feedback_color(CLEAR_FEEDBACK_COLOR)
	if (
		is_instance_valid(target)
		and not target.health.is_dead
		and _flat_distance_to_target() <= attack_range + 0.15
	):
		target.health.take_damage(attack_damage)

	await get_tree().create_timer(attack_cooldown).timeout
	if current_state == EnemyState.ATTACK:
		current_state = EnemyState.CHASE


func _flat_distance_to_target() -> float:
	var offset := target.global_position - global_position
	offset.y = 0.0
	return offset.length()


func _on_health_changed(current_health: int, maximum_health: int) -> void:
	health_fill.scale.x = float(current_health) / float(maximum_health)


func _on_damaged(amount: int) -> void:
	_show_damage_number(amount)

	if current_state == EnemyState.ATTACK:
		return

	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()

	_set_feedback_color(DAMAGE_FLASH_COLOR)
	_feedback_tween = create_tween()
	_feedback_tween.tween_property(
		_feedback_material,
		"albedo_color",
		CLEAR_FEEDBACK_COLOR,
		0.2
	)


func _on_died() -> void:
	current_state = EnemyState.DEFEATED
	velocity = Vector3.ZERO
	collision_shape.set_deferred("disabled", true)
	visuals.visible = false

	await get_tree().create_timer(respawn_delay).timeout

	global_position = _spawn_position
	health.reset_health()
	_set_feedback_color(CLEAR_FEEDBACK_COLOR)
	visuals.visible = true
	collision_shape.set_deferred("disabled", false)
	current_state = EnemyState.IDLE


func _set_feedback_color(color: Color) -> void:
	_feedback_material.albedo_color = color


func _apply_feedback_overlay(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_overlay = _feedback_material

	for child: Node in node.get_children():
		_apply_feedback_overlay(child)


func _show_damage_number(amount: int) -> void:
	var damage_label := Label3D.new()
	damage_label.text = "-%d" % amount
	damage_label.position = Vector3(0.0, 2.6, 0.0)
	damage_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	damage_label.fixed_size = true
	damage_label.font_size = 64
	damage_label.modulate = Color(1.0, 0.82, 0.2, 1.0)
	damage_label.outline_modulate = Color(0.08, 0.03, 0.01, 1.0)
	damage_label.outline_size = 10
	damage_label.no_depth_test = true
	add_child(damage_label)

	var float_tween := create_tween()
	float_tween.set_parallel(true)
	float_tween.tween_property(
		damage_label,
		"position",
		damage_label.position + Vector3(0.0, 0.75, 0.0),
		0.65
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	float_tween.tween_property(damage_label, "modulate:a", 0.0, 0.65)
	float_tween.chain().tween_callback(damage_label.queue_free)

