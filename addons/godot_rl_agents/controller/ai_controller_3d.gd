extends Node3D
class_name AIController3D

enum ControlModes {
    INHERIT_FROM_SYNC, ## Inherit setting from sync node
    HUMAN, ## Test the environment manually
    TRAINING, ## Train a model
    ONNX_INFERENCE, ## Load a pretrained model using an .onnx file
    RECORD_EXPERT_DEMOS ## Record observations and actions for expert demonstrations
}
@export var control_mode: ControlModes = ControlModes.INHERIT_FROM_SYNC
## The path to a trained .onnx model file to use for inference (overrides the path set in sync node).
@export var onnx_model_path := ""
## Once the number of steps has passed, the flag 'needs_reset' will be set to 'true' for this instance.
@export var reset_after := 1000

@export_group("Record expert demos mode options")
## Path where the demos will be saved. The file can later be used for imitation learning.
@export var expert_demo_save_path: String
## The action that erases the last recorded episode from the currently recorded data.
@export var remove_last_episode_key: InputEvent
## Action will be repeated for n frames. Will introduce control lag if larger than 1.
## Can be used to ensure that action_repeat on inference and training matches
## the recorded demonstrations.
@export var action_repeat: int = 1

@export_group("Multi-policy mode options")
## Allows you to set certain agents to use different policies.
## Changing has no effect with default SB3 training. Works with Rllib example.
## Tutorial: https://github.com/edbeeching/godot_rl_agents/blob/main/docs/TRAINING_MULTIPLE_POLICIES.md
@export var policy_name: String = "shared_policy"

var onnx_model: ONNXModel

var heuristic := "human"
var done := false
var reward := 0.0
var n_steps := 0
var needs_reset := false

var _player: Node3D


func _ready():
	add_to_group("AGENT")


func init(player: Node3D):
	_player = player


#-- Methods that need implementing using the "extend script" option in Godot --#
func get_obs() -> Dictionary:
	assert(false, "the get_obs method is not implemented when extending from ai_controller")
	return {"obs": []}


func get_reward() -> float:
	assert(false, "the get_reward method is not implemented when extending from ai_controller")
	return 0.0


func get_action_space() -> Dictionary:
	assert(
		false,
		"the get_action_space method is not implemented when extending from ai_controller"
	)
	return {
		"example_actions_continous": {"size": 2, "action_type": "continuous"},
		"example_actions_discrete": {"size": 2, "action_type": "discrete"},
	}


func set_action(action) -> void:
	assert(false, "the set_action method is not implemented when extending from ai_controller")


#-----------------------------------------------------------------------------#


#-- Methods that sometimes need implementing using the "extend script" option in Godot --#
# Only needed if you are recording expert demos with this AIController
func get_action() -> Array:
	assert(false, "the get_action method is not implemented in extended AIController but demo_recorder is used")
	return []

# -----------------------------------------------------------------------------#


func _physics_process(delta):
	n_steps += 1
	if n_steps > reset_after:
		needs_reset = true


func get_obs_space():
	# may need overriding if the obs space is complex
	var obs = get_obs()
	return {
		"obs": {"size": [len(obs["obs"])], "space": "box"},
	}


func reset():
	n_steps = 0
	needs_reset = false


func reset_if_done():
	if done:
		reset()


func set_heuristic(h):
	# sets the heuristic from "human" or "model" nothing to change here
	heuristic = h


func get_done():
	return done


func set_done_false():
	done = false


func zero_reward():
	reward = 0.0
