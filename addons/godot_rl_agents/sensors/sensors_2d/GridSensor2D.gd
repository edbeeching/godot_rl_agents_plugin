@tool
extends ISensor2D
class_name GridSensor2D

@export var debug_view := false:
	get: return debug_view
	set(value):
		debug_view = value
		_update()
		
@export_flags_2d_physics var detection_mask := 0:
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

@export_range(1, 200, 0.1) var cell_width := 20.0:
	get: return cell_width
	set(value):
		cell_width = value
		_update()

@export_range(1, 200, 0.1) var cell_height := 20.0:
	get: return cell_height
	set(value):
		cell_height = value
		_update()	

@export_range(1, 21, 2, "or_greater") var grid_size_x := 3:
	get: return grid_size_x
	set(value):
		grid_size_x = value
		_update()

@export_range(1, 21, 2, "or_greater") var grid_size_y := 3:
	get: return grid_size_y
	set(value):
		grid_size_y = value
		_update()

var _obs_buffer: PackedFloat64Array
var _rectangle_shape: RectangleShape2D
var _collision_mapping: Dictionary
var _n_layers_per_cell: int

var _highlighted_cell_color: Color
var _standard_cell_color: Color

func get_observation():
	return _obs_buffer
	
func _update():
	if Engine.is_editor_hint():
		if is_node_ready():
			_spawn_nodes()	

func _ready() -> void:
	_set_colors()
	
	if Engine.is_editor_hint():	
		if get_child_count() == 0:
			_spawn_nodes()
	else:
		_spawn_nodes()
		
	
func _set_colors() -> void:
	_standard_cell_color = Color(100.0/255.0, 100.0/255.0, 100.0/255.0, 100.0/255.0)
	_highlighted_cell_color = Color(255.0/255.0, 100.0/255.0, 100.0/255.0, 100.0/255.0)

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

func _spawn_nodes():
	for cell in get_children():
		cell.name = "_%s" % cell.name # Otherwise naming below will fail
		cell.queue_free()
	
	_collision_mapping = _get_collision_mapping()
	#prints("collision_mapping", _collision_mapping, len(_collision_mapping))
	# allocate memory for the observations
	_n_layers_per_cell = len(_collision_mapping)
	_obs_buffer = PackedFloat64Array()
	_obs_buffer.resize(grid_size_x*grid_size_y*_n_layers_per_cell)
	_obs_buffer.fill(0)
	#prints(len(_obs_buffer), _obs_buffer )
	
	_rectangle_shape = RectangleShape2D.new()
	_rectangle_shape.set_size(Vector2(cell_width, cell_height))
	
	var shift := Vector2(
		-(grid_size_x/2)*cell_width,
		-(grid_size_y/2)*cell_height,
	)
	
	for i in grid_size_x:
		for j in grid_size_y:
			var cell_position =  Vector2(i*cell_width, j*cell_height) + shift
			_create_cell(i, j, cell_position)
		

func _create_cell(i:int, j:int, position: Vector2):
	var cell : = Area2D.new()
	cell.position = position
	cell.name = "GridCell %s %s" %[i, j]
	cell.modulate = _standard_cell_color
	
	if collide_with_areas:
		cell.area_entered.connect(_on_cell_area_entered.bind(i, j))
		cell.area_exited.connect(_on_cell_area_exited.bind(i, j))
		
	if collide_with_bodies:
		cell.body_entered.connect(_on_cell_body_entered.bind(i, j))
		cell.body_exited.connect(_on_cell_body_exited.bind(i, j))
	
	cell.collision_layer = 0
	cell.collision_mask = detection_mask
	cell.monitorable = true
	add_child(cell)
	cell.set_owner(get_tree().edited_scene_root)

	var col_shape : = CollisionShape2D.new()
	col_shape.shape = _rectangle_shape
	col_shape.name = "CollisionShape2D"
	cell.add_child(col_shape)
	col_shape.set_owner(get_tree().edited_scene_root)
	
	if debug_view:
		var quad = MeshInstance2D.new()
		quad.name = "MeshInstance2D"
		var quad_mesh = QuadMesh.new()
		
		quad_mesh.set_size(Vector2(cell_width, cell_height))
		
		quad.mesh = quad_mesh
		cell.add_child(quad)
		quad.set_owner(get_tree().edited_scene_root)

func _update_obs(cell_i:int, cell_j:int, collision_layer:int, entered: bool):
	for key in _collision_mapping:
		var bit_mask = 2**key
		if (collision_layer & bit_mask) > 0:
			var collison_map_index = _collision_mapping[key]
			
			var obs_index = (
							(cell_i * grid_size_x * _n_layers_per_cell) + 
							(cell_j * _n_layers_per_cell) + 
							collison_map_index
							)
			#prints(obs_index, cell_i, cell_j)
			if entered:
				_obs_buffer[obs_index] += 1
			else:
				_obs_buffer[obs_index] -= 1

func _toggle_cell(cell_i:int, cell_j:int):
	var cell = get_node_or_null("GridCell %s %s" %[cell_i, cell_j])
	
	if cell == null:
		print("cell not found, returning")
		
	var n_hits = 0
	var start_index = (cell_i * grid_size_x * _n_layers_per_cell) + (cell_j * _n_layers_per_cell)
	for i in _n_layers_per_cell:
		n_hits += _obs_buffer[start_index+i]
		
	if n_hits > 0:
		cell.modulate = _highlighted_cell_color
	else:
		cell.modulate = _standard_cell_color
		
func _on_cell_area_entered(area:Area2D, cell_i:int, cell_j:int):
	#prints("_on_cell_area_entered", cell_i, cell_j)
	_update_obs(cell_i, cell_j, area.collision_layer, true)
	if debug_view:
		_toggle_cell(cell_i, cell_j)
	#print(_obs_buffer)

func _on_cell_area_exited(area:Area2D, cell_i:int, cell_j:int):
	#prints("_on_cell_area_exited", cell_i, cell_j)
	_update_obs(cell_i, cell_j, area.collision_layer, false)
	if debug_view:
		_toggle_cell(cell_i, cell_j)

func _on_cell_body_entered(body: Node2D, cell_i:int, cell_j:int):
	#prints("_on_cell_body_entered", cell_i, cell_j)
	_update_obs(cell_i, cell_j, body.collision_layer, true)
	if debug_view:
		_toggle_cell(cell_i, cell_j)

func _on_cell_body_exited(body: Node2D, cell_i:int, cell_j:int):
	#prints("_on_cell_body_exited", cell_i, cell_j)
	_update_obs(cell_i, cell_j, body.collision_layer, false)
	if debug_view:
		_toggle_cell(cell_i, cell_j)
