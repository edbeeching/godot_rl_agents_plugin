extends Resource
class_name ONNXModel
var inferencer_script = load("res://addons/godot_rl_agents/onnx/csharp/ONNXInference.cs")

var inferencer = null

## How many action values the model outputs
var action_output_size: int

## Used to differentiate models
## that only output continuous action mean (e.g. sb3, cleanrl export)
## versus models that output mean and logstd (e.g. rllib export)
var action_means_only: bool

## Whether action_means_value has been set already for this model
var action_means_only_set: bool

# Must provide the path to the model and the batch size
func _init(model_path, batch_size):
	inferencer = inferencer_script.new()
	action_output_size = inferencer.Initialize(model_path, batch_size)

# This function is the one that will be called from the game,
# requires the observation as an array and the state_ins as an int
# returns an Array containing the action the model takes.
func run_inference(obs: Array, state_ins: int) -> Dictionary:
	if inferencer == null:
		printerr("Inferencer not initialized")
		return {}
	return inferencer.RunInference(obs, state_ins)


func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		inferencer.FreeDisposables()
		inferencer.free()

# Check whether agent uses a continuous actions model with only action means or not
func set_action_means_only(agent_action_space):
	action_means_only_set = true
	var continuous_only: bool = true
	var continuous_actions: int
	for action in agent_action_space:
		if not agent_action_space[action]["action_type"] == "continuous":
			continuous_only = false
			break
		else:
			continuous_actions += agent_action_space[action]["size"]
	if continuous_only:
		if continuous_actions == action_output_size:
			action_means_only = true
