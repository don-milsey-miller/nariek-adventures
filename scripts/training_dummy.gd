extends Node3D
class_name TrainingDummy

const DAMAGE_FLASH_COLOR := Color(1.0, 0.18, 0.12, 1.0)

@export_range(0.1, 10.0, 0.1) var respawn_delay: float = 3.0

@onready var dummy_body: StaticBody3D = $DummyBody
@onready var collision_shape: CollisionShape3D = $DummyBody/CollisionShape3D
@onready var health: HealthComponent = $DummyBody/Health
@onready var visuals: Node3D = $Visuals
@onready var body_mesh: MeshInstance3D = $Visuals/Body
@onready var head_mesh: MeshInstance3D = $Visuals/Head
@onready var health_fill: MeshInstance3D = $Visuals/HealthBar/Fill

var _body_material: StandardMaterial3D
var _base_body_color: Color
var _flash_tween: Tween
var _is_respawning: bool = false


func _ready() -> void:
	_body_material = body_mesh.material_override.duplicate() as StandardMaterial3D
	body_mesh.material_override = _body_material
	head_mesh.material_override = _body_material
	_base_body_color = _body_material.albedo_color

	health.health_changed.connect(_on_health_changed)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	_on_health_changed(health.current_health, health.maximum_health)


func _on_health_changed(current_health: int, maximum_health: int) -> void:
	var health_ratio := float(current_health) / float(maximum_health)
	health_fill.scale.x = health_ratio


func _on_damaged(amount: int) -> void:
	_show_damage_number(amount)

	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()

	_body_material.albedo_color = DAMAGE_FLASH_COLOR
	_flash_tween = create_tween()
	_flash_tween.tween_property(_body_material, "albedo_color", _base_body_color, 0.2)


func _on_died() -> void:
	if _is_respawning:
		return

	_is_respawning = true
	collision_shape.set_deferred("disabled", true)
	visuals.visible = false

	await get_tree().create_timer(respawn_delay).timeout

	health.reset_health()
	visuals.visible = true
	collision_shape.set_deferred("disabled", false)
	_is_respawning = false


func _show_damage_number(amount: int) -> void:
	var damage_label := Label3D.new()
	damage_label.text = "-%d" % amount
	damage_label.position = Vector3(0.0, 2.45, 0.0)
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

