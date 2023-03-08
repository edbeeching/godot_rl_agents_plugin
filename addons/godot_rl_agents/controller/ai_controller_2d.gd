extends AIController
class_name AIController2D

# ------------------ Godot RL Agents Logic ------------------------------------#
var _player: Node2D

func init(player: Node2D):
	_player = player
