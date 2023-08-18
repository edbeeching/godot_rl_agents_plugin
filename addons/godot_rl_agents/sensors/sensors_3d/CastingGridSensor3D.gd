## An alternative without creating Area3D nodes for comparative performance testing, 
## casts a single shape set to grid positions and checks for intersections.
## Currently does not feature any debug view or show the grid in editor.
## Compatible with grid sensor for now (inference on same scene should work by 
## changing the script to CastingGridSensor and optionally removing the Area/Mesh nodes).

extends Node3D

@export var debug_view := false:
	get: return debug_view
	set(value):
		debug_view = value
		_update()
		
@export_flags_3d_physics var detection_mask := 0:
	get: return detection_mask
	set(value):
		detection_mask = value
		_update()

@export var collide_with_areas := false:
	get: return collide_with_areas
	set(value):
		collide_with_areas = value
		_update()

@export var collide_with_bodies := true:
	get: return collide_with_bodies
	set(value):
		collide_with_bodies = value
		_update()

@export_range(0.1, 2, 0.1) var cell_width := 1.0:
	get: return cell_width
	set(value):
		cell_width = value
		_update()

@export_range(0.1, 2, 0.1) var cell_height := 1.0:
	get: return cell_height
	set(value):
		cell_height = value
		_update()	

@export_range(1, 21, 2, "or_greater") var grid_size_x := 3:
	get: return grid_size_x
	set(value):
		grid_size_x = value
		_update()

@export_range(1, 21, 2, "or_greater") var grid_size_z := 3:
	get: return grid_size_z
	set(value):
		grid_size_z = value
		_update()
		
var _shape: BoxShape3D
#var _obs_buffer: PackedFloat64Array
var _collision_mapping: Dictionary
var _n_layers_per_cell: int
var _space: PhysicsDirectSpaceState3D 
	
func _ready() -> void:
	_collision_mapping = _get_collision_mapping()
	_n_layers_per_cell = len(_collision_mapping)
	
	_space = get_world_3d().direct_space_state
#	_obs_buffer.resize(grid_size_x*grid_size_z*_n_layers_per_cell)
#	_obs_buffer.fill(0)
		
func get_observation():
	var _obs_buffer: PackedFloat64Array			
	_obs_buffer.resize(grid_size_x*grid_size_z*_n_layers_per_cell)
	_obs_buffer.fill(0)
	
	
	if is_node_ready() == false:
		return _obs_buffer
			
	if _shape == null:
		_shape = BoxShape3D.new()
		_shape.set_size(Vector3(cell_width, cell_height, cell_width))

	
	var shift := Vector3(
		-(grid_size_x/2)*cell_width,
		0,
		-(grid_size_z/2)*cell_width,
	) + global_position
		
	for i in grid_size_x:
		for j in grid_size_z:
			var cell_position = Vector3(i*cell_width, 0.0, j*cell_width) + shift
			var parameters := PhysicsShapeQueryParameters3D.new()
			var transform: Transform3D = Transform3D.IDENTITY
			transform.origin = cell_position
			parameters.transform = transform
			parameters.shape = _shape
			parameters.collide_with_areas = collide_with_areas
			parameters.collide_with_bodies = collide_with_bodies
			parameters.collision_mask = detection_mask
			
			for result in _space.intersect_shape(parameters, 32):
					for key in _collision_mapping:
						var bit_mask = 2**key
						if (result.collider.collision_layer & bit_mask) > 0:
							var collison_map_index = _collision_mapping[key]
							
							var obs_index = (
											(i * grid_size_x * _n_layers_per_cell) + 
											(j * _n_layers_per_cell) + 
											collison_map_index
											)
							#prints(obs_index, cell_i, cell_j)
							_obs_buffer[obs_index] += 1
		
	return _obs_buffer

func _get_collision_mapping() -> Dictionary:
	# defines which layer is mapped to which cell obs index
	var total_bits = 0
	var collision_mapping = {} 
	for i in 32:
		var bit_mask = 2**i
		if (detection_mask & bit_mask) > 0:
			collision_mapping[i] = total_bits
			total_bits += 1
		
	return collision_mapping

func _update():
	pass
