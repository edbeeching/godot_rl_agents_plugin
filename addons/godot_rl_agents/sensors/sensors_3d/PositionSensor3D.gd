extends ISensor3D
class_name PositionSensor3D

@export var objects_to_observe: Array[Node3D]

## Whether to include relative x position in obs
@export var include_x := true
## Whether to include relative y position in obs
@export var include_y := true
## Whether to include relative z position in obs
@export var include_z := true

## Max distance, values in obs will be normalized,
## 0 will represent the closest distance possible, and 1 the farthest.
## Do not use a much larger value than needed, as it would make the obs
## very small after normalization.
@export_range(0.01, 2_500) var max_distance := 1.0

@export var use_separate_direction: bool = false

@export var debug_lines: bool = true
@export var debug_color: Color = Color.GREEN

@onready var mesh: ImmediateMesh


func _ready() -> void:
	if debug_lines:
		var debug_mesh = MeshInstance3D.new()
		add_child(debug_mesh)
		var line_material := StandardMaterial3D.new()
		line_material.albedo_color = debug_color
		debug_mesh.material_override = line_material
		debug_mesh.mesh = ImmediateMesh.new()
		mesh = debug_mesh.mesh


func get_observation():
	var observations: Array[float]

	if debug_lines:
		mesh.clear_surfaces()
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		mesh.surface_set_color(debug_color)

	for obj in objects_to_observe:
		var relative_position := Vector3.ZERO

		## If object has been removed, keep the zeroed position
		if is_instance_valid(obj): relative_position = to_local(obj.global_position)

		if debug_lines:
			mesh.surface_add_vertex(Vector3.ZERO)
			mesh.surface_add_vertex(relative_position)

		var direction := Vector3.ZERO 
		var distance := 0.0
		if use_separate_direction:
			direction = relative_position.normalized()
			distance = min(relative_position.length() / max_distance, 1.0)
			if include_x:
				observations.append(direction.x)
			if include_y:
				observations.append(direction.y)
			if include_z:
				observations.append(direction.z)
			observations.append(distance)
		else:
			relative_position = relative_position.limit_length(max_distance) / max_distance
			if include_x:
				observations.append(relative_position.x)
			if include_y:
				observations.append(relative_position.y)
			if include_z:
				observations.append(relative_position.z)

	if debug_lines:
		mesh.surface_end()
	return observations
