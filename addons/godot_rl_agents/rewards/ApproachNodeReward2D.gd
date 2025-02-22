extends RewardFunction2D
class_name ApproachNodeReward2D

## Calculates the reward for approaching node
## a reward is only added when the agent reaches a new
## best distance to the target object.

## Best distance reward will be calculated for this object
@export var target_node: Node2D

## Scales the reward, 1.0 means the reward is equal to 
## how much closer the agent is than the previous best.
@export var reward_scale: float = 1.0

var _best_distance


func get_reward() -> float:
	var reward := 0.0
	var current_distance := global_position.distance_to(target_node.global_position)
	if not _best_distance:
		_best_distance = current_distance
	if current_distance < _best_distance:
		reward = (_best_distance - current_distance) * reward_scale
		_best_distance = current_distance
	return reward


func reset():
	_best_distance = null
