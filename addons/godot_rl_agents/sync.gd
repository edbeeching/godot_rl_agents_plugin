extends Node

# --fixed-fps 2000 --disable-render-loop

enum ControlModes { HUMAN, TRAINING, ONNX_INFERENCE }
@export var control_mode: ControlModes = ControlModes.TRAINING
@export_range(1, 10, 1, "or_greater") var action_repeat := 8
@export_range(0, 10, 0.1, "or_greater") var speed_up := 1.0
@export var onnx_model_path := ""

# Onnx model stored for each requested path
var onnx_models: Dictionary

@onready var start_time = Time.get_ticks_msec()

const MAJOR_VERSION := "0"
const MINOR_VERSION := "7"
const DEFAULT_PORT := "11008"
const DEFAULT_SEED := "1"
var stream: StreamPeerTCP = null
var connected = false
var message_center
var should_connect = true

var all_agents: Array
var agents_training: Array
## Policy name of each agent, for use with multi-policy multi-agent RL cases
var agents_training_policy_names: Array[String] = ["shared_policy"]
var agents_inference: Array
var agents_heuristic: Array

## For recording expert demos
var agent_demo_record: Node
## File path for writing recorded trajectories
var expert_demo_save_path: String
## Stores recorded trajectories
var demo_trajectories: Array
## A trajectory includes obs: Array, acts: Array, terminal (set in Python env instead)
var current_demo_trajectory: Array

var need_to_send_obs = false
var args = null
var initialized = false
var just_reset = false
var onnx_model = null
var n_action_steps = 0

var _action_space_training: Array[Dictionary] = []
var _action_space_inference: Array[Dictionary] = []
var _obs_space_training: Array[Dictionary] = []

# Called when the node enters the scene tree for the first time.
func _ready():
	await get_tree().root.ready
	get_tree().set_pause(true)
	_initialize()
	await get_tree().create_timer(1.0).timeout
	get_tree().set_pause(false)


func _initialize():
	_get_agents()
	args = _get_args()
	Engine.physics_ticks_per_second = _get_speedup() * 60  # Replace with function body.
	Engine.time_scale = _get_speedup() * 1.0
	prints(
		"physics ticks",
		Engine.physics_ticks_per_second,
		Engine.time_scale,
		_get_speedup(),
		speed_up
	)

	_set_heuristic("human", all_agents)

	_initialize_training_agents()
	_initialize_inference_agents()
	_initialize_demo_recording()

	_set_seed()
	_set_action_repeat()
	initialized = true


func _initialize_training_agents():
	if agents_training.size() > 0:
		_obs_space_training.resize(agents_training.size())
		_action_space_training.resize(agents_training.size())
		for agent_idx in range(0, agents_training.size()):
			_obs_space_training[agent_idx] = agents_training[agent_idx].get_obs_space()
			_action_space_training[agent_idx] = agents_training[agent_idx].get_action_space()
		connected = connect_to_server()
		if connected:
			_set_heuristic("model", agents_training)
			_handshake()
			_send_env_info()
		else:
			push_warning(
				"Couldn't connect to Python server, using human controls instead. ",
				"Did you start the training server using e.g. `gdrl` from the console?"
			)


func _initialize_inference_agents():
	if agents_inference.size() > 0:
		if control_mode == ControlModes.ONNX_INFERENCE:
			assert(
				FileAccess.file_exists(onnx_model_path),
				"Onnx Model Path set on Sync node does not exist: %s" % onnx_model_path
			)
			onnx_models[onnx_model_path] = ONNXModel.new(onnx_model_path, 1)

		for agent in agents_inference:
			var action_space = agent.get_action_space()
			_action_space_inference.append(action_space)

			var agent_onnx_model: ONNXModel
			if agent.onnx_model_path.is_empty():
				assert(
					onnx_models.has(onnx_model_path),
					(
						"Node %s has no onnx model path set " % agent.get_path()
						+ "and sync node's control mode is not set to OnnxInference. "
						+ "Either add the path to the AIController, "
						+ "or if you want to use the path set on sync node instead, "
						+ "set control mode to OnnxInference."
					)
				)
				prints(
					"Info: AIController %s" % agent.get_path(),
					"has no onnx model path set.",
					"Using path set on the sync node instead."
				)
				agent_onnx_model = onnx_models[onnx_model_path]
			else:
				if not onnx_models.has(agent.onnx_model_path):
					assert(
						FileAccess.file_exists(agent.onnx_model_path),
						(
							"Onnx Model Path set on %s node does not exist: %s"
							% [agent.get_path(), agent.onnx_model_path]
						)
					)
					onnx_models[agent.onnx_model_path] = ONNXModel.new(agent.onnx_model_path, 1)
				agent_onnx_model = onnx_models[agent.onnx_model_path]

			agent.onnx_model = agent_onnx_model
			if not agent_onnx_model.action_means_only_set:
				agent_onnx_model.set_action_means_only(action_space)
				
		_set_heuristic("model", agents_inference)


func _initialize_demo_recording():
	if agent_demo_record:
		expert_demo_save_path = agent_demo_record.expert_demo_save_path
		assert(
			not expert_demo_save_path.is_empty(),
			"Expert demo save path set in %s is empty." % agent_demo_record.get_path()
		)

		InputMap.add_action("RemoveLastDemoEpisode")
		InputMap.action_add_event(
			"RemoveLastDemoEpisode", agent_demo_record.remove_last_episode_key
		)
		current_demo_trajectory.resize(2)
		current_demo_trajectory[0] = []
		current_demo_trajectory[1] = []
		agent_demo_record.heuristic = "demo_record"


func _physics_process(_delta):
	# two modes, human control, agent control
	# pause tree, send obs, get actions, set actions, unpause tree

	_demo_record_process()

	if n_action_steps % action_repeat != 0:
		n_action_steps += 1
		return

	n_action_steps += 1

	_training_process()
	_inference_process()
	_heuristic_process()


func _training_process():
	if connected:
		get_tree().set_pause(true)

		if just_reset:
			just_reset = false
			var obs = _get_obs_from_agents(agents_training)

			var reply = {"type": "reset", "obs": obs}
			_send_dict_as_json_message(reply)
			# this should go straight to getting the action and setting it checked the agent, no need to perform one phyics tick
			get_tree().set_pause(false)
			return

		if need_to_send_obs:
			need_to_send_obs = false
			var reward = _get_reward_from_agents()
			var done = _get_done_from_agents()
			#_reset_agents_if_done() # this ensures the new observation is from the next env instance : NEEDS REFACTOR

			var obs = _get_obs_from_agents(agents_training)

			var reply = {"type": "step", "obs": obs, "reward": reward, "done": done}
			_send_dict_as_json_message(reply)

		var handled = handle_message()


func _inference_process():
	if agents_inference.size() > 0:
		var obs: Array = _get_obs_from_agents(agents_inference)
		var actions = []

		for agent_id in range(0, agents_inference.size()):
			var model: ONNXModel = agents_inference[agent_id].onnx_model
			var action = model.run_inference(
				obs[agent_id]["obs"], 1.0
			)
			var action_dict = _extract_action_dict(
				action["output"], _action_space_inference[agent_id], model.action_means_only
			)
			actions.append(action_dict)

		_set_agent_actions(actions, agents_inference)
		_reset_agents_if_done(agents_inference)
		get_tree().set_pause(false)


func _demo_record_process():
	if not agent_demo_record:
		return

	if Input.is_action_just_pressed("RemoveLastDemoEpisode"):
		print("[Sync script][Demo recorder] Removing last recorded episode.")
		demo_trajectories.remove_at(demo_trajectories.size() - 1)
		print("Remaining episode count: %d" % demo_trajectories.size())

	if n_action_steps % agent_demo_record.action_repeat != 0:
		return

	var obs_dict: Dictionary = agent_demo_record.get_obs()

	# Get the current obs from the agent
	assert(
		obs_dict.has("obs"),
		"Demo recorder needs an 'obs' key in get_obs() returned dictionary to record obs from."
	)
	current_demo_trajectory[0].append(obs_dict.obs)

	# Get the action applied for the current obs from the agent
	agent_demo_record.set_action()
	var acts = agent_demo_record.get_action()

	var terminal = agent_demo_record.get_done()
	# Record actions only for non-terminal states
	if terminal:
		agent_demo_record.set_done_false()
	else:
		current_demo_trajectory[1].append(acts)

	if terminal:
		#current_demo_trajectory[2].append(true)
		demo_trajectories.append(current_demo_trajectory.duplicate(true))
		print("[Sync script][Demo recorder] Recorded episode count: %d" % demo_trajectories.size())
		current_demo_trajectory[0].clear()
		current_demo_trajectory[1].clear()


func _heuristic_process():
	for agent in agents_heuristic:
		_reset_agents_if_done(agents_heuristic)


func _extract_action_dict(action_array: Array, action_space: Dictionary, action_means_only: bool):
	var index = 0
	var result = {}
	for key in action_space.keys():	
		var size = action_space[key]["size"]	
		var action_type = action_space[key]["action_type"]
		if action_type == "discrete":
			var largest_logit: float # Value of the largest logit for this action in the actions array
			var largest_logit_idx: int # Index of the largest logit for this action in the actions array
			for logit_idx in range(0, size):
				var logit_value = action_array[index + logit_idx]
				if logit_value > largest_logit:
					largest_logit = logit_value
					largest_logit_idx = logit_idx 
			result[key] = largest_logit_idx # Index of the largest logit is the discrete action value
			index += size
		elif action_type == "continuous":
			# For continous actions, we only take the action mean values
			result[key] = clamp_array(action_array.slice(index, index + size), -1.0, 1.0)
			if action_means_only:
				index += size # model only outputs action means, so we move index by size
			else:
				index += size * 2 # model outputs logstd after action mean, we skip the logstd part

		else:
			assert(false, 'Only "discrete" and "continuous" action types supported. Found: %s action type set.' % action_type)
		

	return result


## For AIControllers that inherit mode from sync, sets the correct mode.
func _set_agent_mode(agent: Node):
	var agent_inherits_mode: bool = agent.control_mode == agent.ControlModes.INHERIT_FROM_SYNC

	if agent_inherits_mode:
		match control_mode:
			ControlModes.HUMAN:
				agent.control_mode = agent.ControlModes.HUMAN
			ControlModes.TRAINING:
				agent.control_mode = agent.ControlModes.TRAINING
			ControlModes.ONNX_INFERENCE:
				agent.control_mode = agent.ControlModes.ONNX_INFERENCE


func _get_agents():
	all_agents = get_tree().get_nodes_in_group("AGENT")
	for agent in all_agents:
		_set_agent_mode(agent)

		if agent.control_mode == agent.ControlModes.TRAINING:
			agents_training.append(agent)
		elif agent.control_mode == agent.ControlModes.ONNX_INFERENCE:
			agents_inference.append(agent)
		elif agent.control_mode == agent.ControlModes.HUMAN:
			agents_heuristic.append(agent)
		elif agent.control_mode == agent.ControlModes.RECORD_EXPERT_DEMOS:
			assert(
				not agent_demo_record,
				"Currently only a single AIController can be used for recording expert demos."
			)
			agent_demo_record = agent
	
	var training_agent_count = agents_training.size()
	agents_training_policy_names.resize(training_agent_count)
	for i in range(0, training_agent_count):
		agents_training_policy_names[i] = agents_training[i].policy_name


func _set_heuristic(heuristic, agents: Array):
	for agent in agents:
		agent.set_heuristic(heuristic)


func _handshake():
	print("performing handshake")

	var json_dict = _get_dict_json_message()
	assert(json_dict["type"] == "handshake")
	var major_version = json_dict["major_version"]
	var minor_version = json_dict["minor_version"]
	if major_version != MAJOR_VERSION:
		print("WARNING: major verison mismatch ", major_version, " ", MAJOR_VERSION)
	if minor_version != MINOR_VERSION:
		print("WARNING: minor verison mismatch ", minor_version, " ", MINOR_VERSION)

	print("handshake complete")


func _get_dict_json_message():
	# returns a dictionary from of the most recent message
	# this is not waiting
	while stream.get_available_bytes() == 0:
		stream.poll()
		if stream.get_status() != 2:
			print("server disconnected status, closing")
			get_tree().quit()
			return null

		OS.delay_usec(10)

	var message = stream.get_string()
	var json_data = JSON.parse_string(message)

	return json_data


func _send_dict_as_json_message(dict):
	stream.put_string(JSON.stringify(dict, "", false))


func _send_env_info():
	var json_dict = _get_dict_json_message()
	assert(json_dict["type"] == "env_info")

	var message = {
		"type": "env_info",
		"observation_space": _obs_space_training,
		"action_space": _action_space_training,
		"n_agents": len(agents_training),
		"agent_policy_names": agents_training_policy_names
	}
	_send_dict_as_json_message(message)


func connect_to_server():
	print("Waiting for one second to allow server to start")
	OS.delay_msec(1000)
	print("trying to connect to server")
	stream = StreamPeerTCP.new()

	# "localhost" was not working on windows VM, had to use the IP
	var ip = "127.0.0.1"
	var port = _get_port()
	var connect = stream.connect_to_host(ip, port)
	stream.set_no_delay(true)  # TODO check if this improves performance or not
	stream.poll()
	# Fetch the status until it is either connected (2) or failed to connect (3)
	while stream.get_status() < 2:
		stream.poll()
	return stream.get_status() == 2


func _get_args():
	print("getting command line arguments")
	var arguments = {}
	for argument in OS.get_cmdline_args():
		print(argument)
		if argument.find("=") > -1:
			var key_value = argument.split("=")
			arguments[key_value[0].lstrip("--")] = key_value[1]
		else:
			# Options without an argument will be present in the dictionary,
			# with the value set to an empty string.
			arguments[argument.lstrip("--")] = ""

	return arguments


func _get_speedup():
	print(args)
	return args.get("speedup", str(speed_up)).to_float()


func _get_port():
	return args.get("port", DEFAULT_PORT).to_int()


func _set_seed():
	var _seed = args.get("env_seed", DEFAULT_SEED).to_int()
	seed(_seed)


func _set_action_repeat():
	action_repeat = args.get("action_repeat", str(action_repeat)).to_int()


func disconnect_from_server():
	stream.disconnect_from_host()


func handle_message() -> bool:
	# get json message: reset, step, close
	var message = _get_dict_json_message()
	if message["type"] == "close":
		print("received close message, closing game")
		get_tree().quit()
		get_tree().set_pause(false)
		return true

	if message["type"] == "reset":
		print("resetting all agents")
		_reset_agents()
		just_reset = true
		get_tree().set_pause(false)
		#print("resetting forcing draw")
#        RenderingServer.force_draw()
#        var obs = _get_obs_from_agents()
#        print("obs ", obs)
#        var reply = {
#            "type": "reset",
#            "obs": obs
#        }
#        _send_dict_as_json_message(reply)
		return true

	if message["type"] == "call":
		var method = message["method"]
		var returns = _call_method_on_agents(method)
		var reply = {"type": "call", "returns": returns}
		print("calling method from Python")
		_send_dict_as_json_message(reply)
		return handle_message()

	if message["type"] == "action":
		var action = message["action"]
		_set_agent_actions(action, agents_training)
		need_to_send_obs = true
		get_tree().set_pause(false)
		return true

	print("message was not handled")
	return false


func _call_method_on_agents(method):
	var returns = []
	for agent in all_agents:
		returns.append(agent.call(method))

	return returns


func _reset_agents_if_done(agents = all_agents):
	for agent in agents:
		if agent.get_done():
			agent.set_done_false()


func _reset_agents(agents = all_agents):
	for agent in agents:
		agent.needs_reset = true
		#agent.reset()


func _get_obs_from_agents(agents: Array = all_agents):
	var obs = []
	for agent in agents:
		obs.append(agent.get_obs())
	return obs


func _get_reward_from_agents(agents: Array = agents_training):
	var rewards = []
	for agent in agents:
		rewards.append(agent.get_reward())
		agent.zero_reward()
	return rewards


func _get_done_from_agents(agents: Array = agents_training):
	var dones = []
	for agent in agents:
		var done = agent.get_done()
		if done:
			agent.set_done_false()
		dones.append(done)
	return dones


func _set_agent_actions(actions, agents: Array = all_agents):
	for i in range(len(actions)):
		agents[i].set_action(actions[i])


func clamp_array(arr: Array, min: float, max: float):
	var output: Array = []
	for a in arr:
		output.append(clamp(a, min, max))
	return output


## Save recorded export demos on window exit (Close game window instead of "Stop" button in Godot Editor)
func _notification(what):
	if demo_trajectories.size() == 0 or expert_demo_save_path.is_empty():
		return

	if what == NOTIFICATION_PREDELETE:
		var json_string = JSON.stringify(demo_trajectories, "", false)
		var file = FileAccess.open(expert_demo_save_path, FileAccess.WRITE)

		if not file:
			var error: Error = FileAccess.get_open_error()
			assert(not error, "There was an error opening the file: %d" % error)

		file.store_line(json_string)
		var error = file.get_error()
		assert(not error, "There was an error after trying to write to the file: %d" % error)
