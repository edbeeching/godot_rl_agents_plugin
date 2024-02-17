@tool
extends ISensor3D
class_name GridSensor3D

@export var debug_view := false:
	get:
		return debug_view
	set(value):
		debug_view = value
		_update()

@export_flags_3d_physics var detection_mask := 0:
	get:
		return detection_mask
	set(value):
		detection_mask = value
		_update()

@export var collide_with_areas := false:
	get:
		return collide_with_areas
	set(value):
		collide_with_areas = value
		_update()

@export var collide_with_bodies := false:
	# NOTE! The sensor will not detect StaticBody3D, add an area to static bodies to detect them
	get:
		return collide_with_bodies
	set(value):
		collide_with_bodies = value
		_update()

@export_range(0.1, 2, 0.1) var cell_width := 1.0:
	get:
		return cell_width
	set(value):
		cell_width = value
		_update()

@export_range(0.1, 2, 0.1) var cell_height := 1.0:
	get:
		return cell_height
	set(value):
		cell_height = value
		_update()

@export_range(1, 21, 2, "or_greater") var grid_size_x := 3:
	get:
		return grid_size_x
	set(value):
		grid_size_x = value
		_update()

@export_range(1, 21, 2, "or_greater") var grid_size_z := 3:
	get:
		return grid_size_z
	set(value):
		grid_size_z = value
		_update()

var _obs_buffer: PackedFloat64Array
var _box_shape: BoxShape3D
var _collision_mapping: Dictionary
var _n_layers_per_cell: int

var _highlighted_box_material: StandardMaterial3D
var _standard_box_material: StandardMaterial3D


func get_observation():
	return _obs_buffer


func reset():
	_obs_buffer.fill(0)


func _update():
	if Engine.is_editor_hint():
		if is_node_ready():
			_spawn_nodes()


func _ready() -> void:
	_make_materials()

	if Engine.is_editor_hint():
		if get_child_count() == 0:
			_spawn_nodes()
	else:
		_spawn_nodes()


func _make_materials() -> void:
	if _highlighted_box_material != null and _standard_box_material != null:
		return

	_standard_box_material = StandardMaterial3D.new()
	_standard_box_material.set_transparency(1)  # ALPHA
	_standard_box_material.albedo_color = Color(
		100.0 / 255.0, 100.0 / 255.0, 100.0 / 255.0, 100.0 / 255.0
	)

	_highlighted_box_material = StandardMaterial3D.new()
	_highlighted_box_material.set_transparency(1)  # ALPHA
	_highlighted_box_material.albedo_color = Color(
		255.0 / 255.0, 100.0 / 255.0, 100.0 / 255.0, 100.0 / 255.0
	)


func _get_collision_mapping() -> Dictionary:
	# defines which layer is mapped to which cell obs index
	var total_bits = 0
	var collision_mapping = {}
	for i in 32:
		var bit_mask = 2 ** i
		if (detection_mask & bit_mask) > 0:
			collision_mapping[i] = total_bits
			total_bits += 1

	return collision_mapping


func _spawn_nodes():
	for cell in get_children():
		cell.name = "_%s" % cell.name  # Otherwise naming below will fail
		cell.queue_free()

	_collision_mapping = _get_collision_mapping()
	#prints("collision_mapping", _collision_mapping, len(_collision_mapping))
	# allocate memory for the observations
	_n_layers_per_cell = len(_collision_mapping)
	_obs_buffer = PackedFloat64Array()
	_obs_buffer.resize(grid_size_x * grid_size_z * _n_layers_per_cell)
	_obs_buffer.fill(0)
	#prints(len(_obs_buffer), _obs_buffer )

	_box_shape = BoxShape3D.new()
	_box_shape.set_size(Vector3(cell_width, cell_height, cell_width))

	var shift := Vector3(
		-(grid_size_x / 2) * cell_width,
		0,
		-(grid_size_z / 2) * cell_width,
	)

	for i in grid_size_x:
		for j in grid_size_z:
			var cell_position = Vector3(i * cell_width, 0.0, j * cell_width) + shift
			_create_cell(i, j, cell_position)


func _create_cell(i: int, j: int, position: Vector3):
	var cell := Area3D.new()
	cell.position = position
	cell.name = "GridCell %s %s" % [i, j]

	if collide_with_areas:
		cell.area_entered.connect(_on_cell_area_entered.bind(i, j))
		cell.area_exited.connect(_on_cell_area_exited.bind(i, j))

	if collide_with_bodies:
		cell.body_entered.connect(_on_cell_body_entered.bind(i, j))
		cell.body_exited.connect(_on_cell_body_exited.bind(i, j))

#		cell.body_shape_entered.connect(_on_cell_body_shape_entered.bind(i, j))
#		cell.body_shape_exited.connect(_on_cell_body_shape_exited.bind(i, j))

	cell.collision_layer = 0
	cell.collision_mask = detection_mask
	cell.monitorable = true
	cell.input_ray_pickable = false
	add_child(cell)
	cell.set_owner(get_tree().edited_scene_root)

	var col_shape := CollisionShape3D.new()
	col_shape.shape = _box_shape
	col_shape.name = "CollisionShape3D"
	cell.add_child(col_shape)
	col_shape.set_owner(get_tree().edited_scene_root)

	if debug_view:
		var box = MeshInstance3D.new()
		box.name = "MeshInstance3D"
		var box_mesh = BoxMesh.new()

		box_mesh.set_size(Vector3(cell_width, cell_height, cell_width))
		box_mesh.material = _standard_box_material

		box.mesh = box_mesh
		cell.add_child(box)
		box.set_owner(get_tree().edited_scene_root)


func _update_obs(cell_i: int, cell_j: int, collision_layer: int, entered: bool):
	for key in _collision_mapping:
		var bit_mask = 2 ** key
		if (collision_layer & bit_mask) > 0:
			var collison_map_index = _collision_mapping[key]

			var obs_index = (
				(cell_i * grid_size_x * _n_layers_per_cell)
				+ (cell_j * _n_layers_per_cell)
				+ collison_map_index
			)
			#prints(obs_index, cell_i, cell_j)
			if entered:
				_obs_buffer[obs_index] += 1
			else:
				_obs_buffer[obs_index] -= 1


func _toggle_cell(cell_i: int, cell_j: int):
	var cell = get_node_or_null("GridCell %s %s" % [cell_i, cell_j])

	if cell == null:
		print("cell not found, returning")

	var n_hits = 0
	var start_index = (cell_i * grid_size_x * _n_layers_per_cell) + (cell_j * _n_layers_per_cell)
	for i in _n_layers_per_cell:
		n_hits += _obs_buffer[start_index + i]

	var cell_mesh = cell.get_node_or_null("MeshInstance3D")
	if n_hits > 0:
		cell_mesh.mesh.material = _highlighted_box_material
	else:
		cell_mesh.mesh.material = _standard_box_material


func _on_cell_area_entered(area: Area3D, cell_i: int, cell_j: int):
	#prints("_on_cell_area_entered", cell_i, cell_j)
	_update_obs(cell_i, cell_j, area.collision_layer, true)
	if debug_view:
		_toggle_cell(cell_i, cell_j)
	#print(_obs_buffer)


func _on_cell_area_exited(area: Area3D, cell_i: int, cell_j: int):
	#prints("_on_cell_area_exited", cell_i, cell_j)
	_update_obs(cell_i, cell_j, area.collision_layer, false)
	if debug_view:
		_toggle_cell(cell_i, cell_j)


func _on_cell_body_entered(body: Node3D, cell_i: int, cell_j: int):
	#prints("_on_cell_body_entered", cell_i, cell_j)
	_update_obs(cell_i, cell_j, body.collision_layer, true)
	if debug_view:
		_toggle_cell(cell_i, cell_j)


func _on_cell_body_exited(body: Node3D, cell_i: int, cell_j: int):
	#prints("_on_cell_body_exited", cell_i, cell_j)
	_update_obs(cell_i, cell_j, body.collision_layer, false)
	if debug_view:
		_toggle_cell(cell_i, cell_j)
