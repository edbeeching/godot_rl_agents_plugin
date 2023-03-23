extends AIController
class_name AIController3D

# ------------------ Godot RL Agents Logic ------------------------------------#
var _player: Node3D

func init(player: Node3D):
	_player = player
