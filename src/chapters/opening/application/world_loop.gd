extends RefCounted
## Explicit frame and fixed-step world lifecycle.
## The scene owns state and nodes. This service holds a weak scene reference.
var _owner: WeakRef

func _init(owner: Node3D) -> void:
	_owner = weakref(owner)

func foundation_physics_process(delta: float) -> void:
	var host: Node3D = _owner.get_ref()
	if not host.ready_for_review or host.paused:return
	host.freya.weighted_locomotion=not host.legacy_locomotion and (not host.automate or host.weighted_locomotion_override)
	if not host.automate and not host.dead and not host.fixed_view:
		var input: Vector2=Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
		var running: bool=Input.is_physical_key_pressed(KEY_SHIFT)
		# movement-v09: a gamepad stick gives a graded walk; a full push runs.
		if input.length()<.1 and not Input.get_connected_joypads().is_empty():
			var stick: Vector2=Vector2(Input.get_joy_axis(0,JOY_AXIS_LEFT_X),Input.get_joy_axis(0,JOY_AXIS_LEFT_Y))
			var amount: float=clampf((stick.length()-.18)/.82,0,1)
			if amount>0:
				running=running or amount>.9 or Input.is_joy_button_pressed(0,JOY_BUTTON_LEFT_STICK)
				input=stick.normalized()*(1. if running else clampf(amount/.9,.25,1))
		host.freya.direction=Basis(Vector3.UP,host.yaw)*Vector3(input.x,0,input.y).limit_length()
		host.freya.running=running
	if host.kesh_demo and host.kesh_demo.has_dialogue():
		host.freya.direction = Vector3.ZERO
	if host.camp:host.camp.tick(delta)
	host.update_camera(delta)
	if host.freya.position.y< -150 and not host.dead:
		host.dead=true;host.freya.health=0;host.freya.direction=Vector3.ZERO
		host.message.text="Outside prototype ground\nEnter or Backspace · return to camp"
	host.update_status()

func foundation_process(delta: float) -> void:
	var host: Node3D = _owner.get_ref()
	if host.ready_for_review and not host.paused and host.dressing:host.dressing.tick(delta)
	if host.ready_for_review and not host.paused and host.frame_samples.size()<1800:host.frame_samples.append(delta*1000.)

func _physics_process(delta: float) -> void:
	var host: Node3D = _owner.get_ref()
	host.scenery_floor=false
	if host.ready_for_review and not host.paused and host.scenery and host.scenery_contact:
		var query: PhysicsRayQueryParameters3D=PhysicsRayQueryParameters3D.create(host.freya.position+Vector3.UP*.8,host.freya.position-Vector3.UP*1.2,1)
		query.hit_back_faces=true
		var hit: Dictionary=host.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.normal.y>.4 and hit.collider.is_in_group("scenery_solid"):
			host.scenery_floor=true;host.scenery_origin=hit.position;host.scenery_center=Vector2(host.freya.position.x,host.freya.position.z)
			host.scenery_gradient=Vector2(hit.normal.x,hit.normal.z)/hit.normal.y
	host.world_loop.foundation_physics_process(delta)

func scenery_process(delta: float) -> void:
	var host: Node3D = _owner.get_ref()
	host.world_loop.foundation_process(delta)
	if host.scenery and host.ready_for_review and not host.paused:host.scenery.tick(delta)

func progression_process(delta: float) -> void:
	var host: Node3D = _owner.get_ref()
	host.world_loop.scenery_process(delta)
	if not host.rpg_ready:
		return
	if not host.paused:
		for i: int in range(host.world_clock.advance(delta)):
			host.world_tick()
	host.camp.objective.visible = false
	host._update_tracker()
	var near: Dictionary = {} if host.inventory_open or host.paused or host.dead else host._nearest_pickup()
	host.pickup_prompt.text = "" if near.is_empty() else "E · " + str(near.label)
	host.toast_left -= delta
	if host.toast_left <= 0:
		host.toast.text = ""
		if not host.toast_queue.is_empty():
			host.toast.text = host.toast_queue.pop_front()
			host.toast_left = 3.0
	if host.map_view.visible:
		host.map_view.queue_redraw()

func _process(delta: float) -> void:
	var host: Node3D = _owner.get_ref()
	host.world_loop.progression_process(delta)
	if host.kesh_village and not host.paused:
		host.kesh_village.tick(delta)
	if host.kesh_demo:
		host.kesh_demo.tick(delta)
	host.hud_policy.update(host)
	host.checkpoints.tick(delta)

