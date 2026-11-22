extends CharacterBody3D
const Motion=preload("res://motion_visual.gd")
signal damaged(amount: float)
signal stone_released(origin: Vector3,aim: Vector3)
var lock_target: Node3D
var throw_aim: Vector3=Vector3.ZERO
var throw_released: bool=false
var throw_release_phase: float=.565
var throw_count: int=0
var hand_stone: MeshInstance3D
var action_heading: float=0
var action_motion_heading: float=0
var visual: Node3D
var direction: Vector3=Vector3.ZERO
var running: bool=false
var health: float=100
var stamina: float=100
var guarding: bool=false
var guard_time: float=0
var mode: String=""
var action_time: float=0
var duration: float=0
var queued_attack: bool=false
var combo: int=0
var weapon: String="staff"
var enemy: bool=false
var attack_id: int=0
var hit_targets: Dictionary={}
var hit_events: int=0
var invulnerable_hits: int=0
var previous_achieved: Vector3
var air_time: float=0
var jump_buffer: float=0
var jump_crouch: float=0
var coyote: float=0
var last_grounded: bool=true
var previous_tip: Vector3
var facing: float=0
var frozen: bool=false
var gear: MeshInstance3D
var hand_mount: BoneAttachment3D
var weapon_root: Node3D
var root_distance: float=0
var held_bind: Transform3D=Transform3D.IDENTITY
var stowed_bind: Transform3D=Transform3D.IDENTITY
var weapon_held: bool=false
# movement-v09 weighted locomotion. Off by default so historical reviews and
# automated story tests keep their accepted response; the opening world turns
# it on whenever a person is steering Freya (see world_loop.gd).
static var LOCO: Dictionary={}
var weighted_locomotion: bool=false
var weighted_active: bool=false
var yaw_rate: float=0
var travel_heading: float=0
var pivoting: bool=false
var slope_factor: float=1
var last_planar_velocity: Vector3=Vector3.ZERO
var smoothed_accel: Vector3=Vector3.ZERO

func setup(is_enemy: bool=false) -> void:
	process_mode=Node.PROCESS_MODE_PAUSABLE
	enemy=is_enemy;collision_layer=2 if enemy else 4;collision_mask=1|4 if enemy else 1|2
	if LOCO.is_empty() and FileAccess.file_exists("res://data/framework/locomotion.json"):
		LOCO=JSON.parse_string(FileAccess.get_file_as_string("res://data/framework/locomotion.json"))
	floor_snap_length=.25;floor_max_angle=deg_to_rad(46)
	var collider: CollisionShape3D=CollisionShape3D.new();var capsule: CapsuleShape3D=CapsuleShape3D.new();capsule.radius=.22;capsule.height=1.65;collider.shape=capsule;collider.position.y=.825;add_child(collider)
	visual=Motion.new();add_child(visual);visual.setup(enemy)
	hand_mount=BoneAttachment3D.new();hand_mount.bone_name="RightHand";visual.skeleton.add_child(hand_mount)
	weapon_root=Node3D.new();weapon_root.name="WeaponMount";add_child(weapon_root)
	gear=MeshInstance3D.new();weapon_root.add_child(gear);set_weapon("knife" if enemy else "staff")
	hand_stone=MeshInstance3D.new();hand_stone.name="HeldStone";var stone: SphereMesh=SphereMesh.new();stone.radius=.055;stone.height=.11;stone.radial_segments=12;stone.rings=6;hand_stone.mesh=stone
	var stone_material: StandardMaterial3D=StandardMaterial3D.new();stone_material.albedo_color=Color("827f73");stone_material.roughness=.95;hand_stone.material_override=stone_material;add_child(hand_stone);hand_stone.visible=false
	previous_tip=global_position

func set_weapon(value: String) -> void:
	weapon=value
	if not is_instance_valid(gear):return
	if weapon=="staff":
		var staff: CylinderMesh=CylinderMesh.new();staff.top_radius=.024;staff.bottom_radius=.031;staff.height=1.5;gear.mesh=staff;gear.position.y=.62
	else:
		var knife: PrismMesh=PrismMesh.new();knife.size=Vector3(.065,.36,.028);gear.mesh=knife;gear.position.y=.15
	var mat: StandardMaterial3D=StandardMaterial3D.new();mat.albedo_color=Color("795136") if weapon=="staff" else Color("8f999c");mat.roughness=.8;gear.material_override=mat
	# Build the grip from this mesh's actual knuckles. The shaft exits the
	# index/thumb side of the fist; imported bone rolls cannot turn it inward.
	var sk: Skeleton3D=visual.skeleton
	var hand: Transform3D=sk.get_bone_global_rest(sk.find_bone("RightHand"))
	var index: Vector3=sk.get_bone_global_rest(sk.find_bone("RightIndexProximal")).origin
	var little: Vector3=sk.get_bone_global_rest(sk.find_bone("RightLittleProximal")).origin
	var shaft: Vector3=(index-little).normalized()
	var palm: Vector3=(index.lerp(little,.5)-hand.origin).normalized()
	var across: Vector3=shaft.cross(palm).normalized()
	held_bind.basis=hand.basis.inverse()*Basis(across,shaft,across.cross(shaft).normalized())
	held_bind.origin=hand.affine_inverse()*sk.get_bone_global_rest(sk.find_bone("R_grip")).origin if not enemy else Vector3(0,.085,.025)
	var chest: Transform3D=sk.get_bone_global_rest(sk.find_bone("Chest"))
	var rest_mount: Transform3D=Transform3D(Basis(Vector3.FORWARD,deg_to_rad(35)),Vector3(-.406,.642,-.30))
	if weapon=="knife":rest_mount=Transform3D(Basis(Vector3.FORWARD,PI),Vector3(-.20,.85,-.12))
	stowed_bind=chest.affine_inverse()*rest_mount
	update_weapon()

func update_weapon(held_override: int=-1,staff_reach: float=1.37) -> void:
	if not is_instance_valid(weapon_root):return
	if weapon=="staff":gear.position.y=staff_reach-.75
	weapon_held=(mode=="attack" or guarding) if held_override<0 else held_override==1
	var sk: Skeleton3D=visual.skeleton
	var bone: int=sk.find_bone("RightHand" if weapon_held else "Chest")
	weapon_root.global_transform=sk.global_transform*sk.get_bone_global_pose(bone)*(held_bind if weapon_held else stowed_bind)
	# Stowed equipment sits outside outerwear; hand/grip and hit geometry stay unchanged.
	if not weapon_held and visual.outerwear and visual.outerwear.equipped:
		weapon_root.global_position+=sk.global_basis*(sk.get_bone_global_pose(bone).basis*sk.get_bone_global_rest(bone).basis.inverse())*Vector3(0,0,-.12)
	# CHAR-01: when Freya v02 is shown, carry the weapon on her bone instead.
	if visual.has_method("present"):weapon_root.global_transform=visual.present(weapon_root.global_transform,sk.get_bone_name(bone))
	if hand_stone:
		# stone_socket() stays on the logic body (contacts and hand-offs measure it);
		# the visible stone follows the shown body (v02 when on).
		hand_stone.global_position=stone_socket()
		if visual.has_method("present"):hand_stone.global_transform=visual.present(hand_stone.global_transform,"RightHand")
		hand_stone.visible=mode=="throw" and not throw_released

func stone_socket() -> Vector3:
	var sk: Skeleton3D=visual.skeleton
	return sk.to_global((sk.get_bone_global_pose(sk.find_bone("RightHand"))*held_bind).origin)

func has_lock() -> bool:
	return is_instance_valid(lock_target) and lock_target.is_inside_tree()

func target_facing() -> float:
	var gap: Vector3=lock_target.global_position-global_position
	return atan2(gap.x,gap.z) if Vector2(gap.x,gap.z).length()>.15 else facing

func request_throw(aim: Vector3) -> bool:
	if mode!="" or not is_on_floor() or stamina<12 or health<=0:return false
	stamina-=12;throw_aim=aim;throw_released=false;root_distance=0
	begin("throw","ThrowR",1.41666662693024);return true

func request_jump() -> void:jump_buffer=.13

func request_attack(heavy: bool=false) -> bool:
	if mode=="attack":
		if action_time/duration>.35:queued_attack=true
		return false
	if mode!="" or not is_on_floor() or health<=0:return false
	var cost: float=27 if heavy else 17
	if stamina<cost:return false
	if has_lock():facing=target_facing()
	stamina-=cost;combo=1-combo;attack_id+=1;hit_targets.clear();queued_attack=false;root_distance=0
	var clip: String
	if weapon=="staff":clip="root-HeavyUppercut" if heavy else ("root-Heavy1" if combo==1 else "root-Heavy2")
	else:clip="root-Stab1" if heavy else ("root-Slash1" if combo==1 else "root-Slash2")
	begin("attack",clip,1.05 if heavy else (.88 if weapon=="staff" else .68));return true

func request_dodge() -> bool:
	if mode!="" or not is_on_floor() or stamina<22 or health<=0:return false
	stamina-=22;root_distance=0
	if has_lock():facing=target_facing()
	var desired: Vector3=direction.normalized() if direction.length()>.1 else -(Basis(Vector3.UP,facing)*Vector3.BACK)
	var local: Vector3=Basis(Vector3.UP,-facing)*desired
	var clip: String="root-Retreat"
	# Match actual source displacement; source left/right is not Godot +X/-X.
	var best: float=-INF
	for candidate: String in ["root-Retreat","root-Roll","root-Roll45L","root-Roll45R","root-RollBarrelL","root-RollBarrelR"]:
		var raw: Array=visual.manifest.clips[candidate].root_delta
		var motion: Vector3=Vector3(raw[0],0,raw[2]).normalized()
		var score: float=motion.dot(local)
		if score>best:best=score;clip=candidate
	begin("dodge",clip,.68)
	var source_delta: Array=visual.manifest.clips[clip].root_delta
	action_motion_heading=atan2(desired.x,desired.z)-atan2(float(source_delta[0]),float(source_delta[2]))
	return true

func begin(state: String,clip: String,seconds: float) -> void:
	mode=state;action_time=0;duration=seconds;guarding=false
	action_heading=facing;action_motion_heading=facing
	visual.start_action(clip,seconds)

func receive_hit(amount: float,attacker: Node3D) -> void:
	if health<=0:return
	if mode=="dodge" and action_time>=.075 and action_time<=.40:invulnerable_hits+=1;return
	var to_attacker: Vector3=global_position.direction_to(attacker.global_position)
	if guarding and (Basis(Vector3.UP,facing)*Vector3.BACK).dot(to_attacker)>.25 and stamina>=16:
		stamina-=16
		if guard_time<.18:attacker.begin("hurt","Hurt1",.65)
		begin("block","GuardParry" if guard_time<.18 else "GuardBlocked",.32);return
	health=maxf(0,health-amount);damaged.emit(amount)
	begin("dead" if health<=0 else "hurt","Die1" if health<=0 else "Hurt1",1.5 if health<=0 else .38)

func _physics_process(delta: float) -> void:
	if not visual or frozen:return
	if not is_on_floor() and velocity.y<=0:apply_floor_snap()
	var grounded: bool=is_on_floor()
	coyote=.10 if grounded else maxf(0,coyote-delta)
	jump_buffer=maxf(0,jump_buffer-delta)
	# CHAR-01: with Freya v02 shown she crouches first (pushes the ground down),
	# then leaves it; jump_crouch_seconds() is 0 for the old body (instant launch).
	if jump_crouch>0:
		jump_crouch-=delta
		if mode!="" or health<=0 or not grounded:jump_crouch=0
		elif jump_crouch<=0:
			jump_crouch=0;velocity.y=5.6;coyote=0;grounded=false;air_time=0
	elif jump_buffer>0 and coyote>0 and mode=="" and health>0:
		var crouch: float=visual.jump_crouch_seconds() if visual.has_method("jump_crouch_seconds") else 0.
		if crouch>0 and grounded:
			jump_crouch=crouch;jump_buffer=0;visual.v02.begin_crouch(crouch)
		else:
			velocity.y=5.6;jump_buffer=0;coyote=0;grounded=false;air_time=0
	if not grounded:velocity.y-=19.6*delta;air_time+=delta
	elif velocity.y<0:velocity.y=-1
	if grounded and not last_grounded and mode=="" and air_time>.16:
		begin("land","UAL_Jump_Land",.30);air_time=0
	if grounded:air_time=0
	last_grounded=grounded
	if guarding:guard_time+=delta
	else:guard_time=0
	if health<=0:direction=Vector3.ZERO
	var locked: bool=has_lock()
	var local_direction: Vector3=Basis(Vector3.UP,-facing)*direction
	var maximum_speed: float=4.5 if running else 1.8
	if locked:maximum_speed=(2.2 if local_direction.z< -absf(local_direction.x) else 2.8) if running else 1.8
	var wanted: Vector3=direction.limit_length()*maximum_speed
	if mode!="" or guarding:wanted=Vector3.ZERO
	var was_weighted: bool=weighted_active
	weighted_active=weighted_locomotion and not enemy and not locked and mode=="" and not guarding and health>0 and not LOCO.is_empty()
	if weighted_active and not was_weighted:
		var planar: Vector3=Vector3(velocity.x,0,velocity.z)
		travel_heading=atan2(planar.x,planar.z) if planar.length()>.05 else facing;yaw_rate=0;pivoting=false
	if locked and mode=="":
		facing=rotate_toward(facing,target_facing(),delta*deg_to_rad(540))
	elif weighted_active:
		weighted_turn(delta)
	elif direction.length()>.1 and mode=="" and not guarding:
		facing=lerp_angle(facing,atan2(direction.x,direction.z),1-exp(-delta*14))
	if mode=="throw" and action_time<duration*.25:
		var gap: Vector3=throw_aim-global_position;gap.y=0
		if gap.length()>.15:facing=rotate_toward(facing,atan2(gap.x,gap.z),delta*deg_to_rad(360))
	visual.rotation.y=facing
	visual.locked=locked;visual.local_motion=Basis(Vector3.UP,-facing)*previous_achieved/maxf(delta,.00001)
	var speed: float=Vector2(previous_achieved.x,previous_achieved.z).length()/maxf(delta,.00001)
	var had_action: bool=mode!=""
	var root_step: Vector3=visual.tick(delta,Vector2(previous_achieved.x,previous_achieved.z).length(),speed,grounded,velocity.y,air_time,guarding)
	update_weapon()
	if had_action and mode in ["dodge","attack"]:
		var displacement: Vector3=Basis(Vector3.UP,action_motion_heading)*root_step
		if mode=="attack" and locked:
			var gap: Vector3=lock_target.global_position-global_position;gap.y=0
			var toward: Vector3=gap.normalized()
			var approach: float=displacement.dot(toward)
			if approach>0:displacement-=toward*maxf(0,approach-maxf(0,gap.length()-.9))
		velocity.x=displacement.x/delta;velocity.z=displacement.z/delta
	elif weighted_active:
		weighted_velocity(delta)
	else:
		var acceleration: float=20 if wanted.length()<.1 else 14
		velocity.x=move_toward(velocity.x,wanted.x,delta*acceleration);velocity.z=move_toward(velocity.z,wanted.z,delta*acceleration)
	var before: Vector3=global_position;move_and_slide();previous_achieved=global_position-before
	update_lean(delta)
	update_weapon()
	if had_action:root_distance+=Vector2(previous_achieved.x,previous_achieved.z).length()
	if mode!="":
		action_time+=delta
		if mode=="throw" and not throw_released and action_time>=duration*throw_release_phase:
			throw_released=true;throw_count+=1;hand_stone.visible=false
			stone_released.emit(stone_socket(),throw_aim)
		if mode=="attack" and action_time/duration>=.38 and action_time/duration<=.72:check_contacts()
		if action_time>=duration and mode!="dead":
			var follow: bool=queued_attack and mode=="attack";mode="";queued_attack=false
			if follow:request_attack()
	else:stamina=minf(100,stamina+delta*(9 if guarding else 23))
	previous_tip=weapon_tip()
	if visual.outerwear and visual.outerwear.has_method("follow_pose"):
		visual.outerwear.follow_pose(visual.skeleton)

## movement-v09: facing turns with a limited, accelerating yaw rate. A hard
## reversal at running speed becomes a braked pivot instead of a spin.
func weighted_turn(delta: float) -> void:
	var input: Vector3=Vector3(direction.x,0,direction.z)
	var speed: float=Vector2(velocity.x,velocity.z).length()
	var yaw_accel: float=deg_to_rad(float(LOCO.yaw_accel_dps2))
	if input.length()<.1:
		yaw_rate=move_toward(yaw_rate,0,delta*yaw_accel);facing=wrapf(facing+yaw_rate*delta,-PI,PI);pivoting=false;return
	var want: float=atan2(input.x,input.z)
	var gap: float=angle_difference(facing,want)
	var run_t: float=_run_t(speed)
	var max_rate: float=deg_to_rad(float(LOCO.turn_rate_idle_dps) if speed<float(LOCO.turn_in_place_speed) else lerpf(float(LOCO.turn_rate_walk_dps),float(LOCO.turn_rate_run_dps),run_t))
	if not pivoting and speed>float(LOCO.pivot_min_speed) and absf(gap)>deg_to_rad(float(LOCO.pivot_angle_deg)):pivoting=true
	if pivoting:
		if speed>float(LOCO.pivot_release_speed):max_rate=deg_to_rad(float(LOCO.pivot_hold_rate_dps))
		else:
			max_rate=deg_to_rad(float(LOCO.pivot_turn_rate_dps))
			if absf(gap)<deg_to_rad(35):pivoting=false
	var target: float=clampf(gap*float(LOCO.turn_response),-max_rate,max_rate)
	yaw_rate=move_toward(yaw_rate,target,delta*yaw_accel)
	var step: float=yaw_rate*delta
	if signf(step)==signf(gap) and absf(step)>absf(gap):step=gap;yaw_rate=gap/maxf(delta,.0001)
	facing=wrapf(facing+step,-PI,PI)

## movement-v09: speed builds and bleeds off with separate walk/run curves;
## travel follows facing more as speed rises, so turns arc instead of strafing.
func weighted_velocity(delta: float) -> void:
	var input: Vector3=Vector3(direction.x,0,direction.z)
	var magnitude: float=minf(1.,input.length())
	var planar: Vector3=Vector3(velocity.x,0,velocity.z)
	var speed: float=planar.length()
	var walk: float=float(LOCO.walk_speed);var run: float=float(LOCO.run_speed)
	var run_t: float=_run_t(speed)
	var target_heading: float=travel_heading
	var desired: float=0.
	if magnitude>=.1:
		var want: float=atan2(input.x,input.z)
		var facing_gap: float=absf(angle_difference(facing,want))
		target_heading=lerp_angle(want,facing,lerpf(float(LOCO.carve_walk),float(LOCO.carve_run),run_t))
		update_slope(delta,target_heading)
		desired=(run if running else walk)*magnitude*slope_factor
		if pivoting:desired=0.
		elif speed<float(LOCO.turn_in_place_speed) and facing_gap>deg_to_rad(float(LOCO.turn_in_place_angle_deg)):desired=0.
		else:desired*=lerpf(1.,float(LOCO.turn_speed_floor),clampf((facing_gap-deg_to_rad(20))/PI,0,1))
	if speed<.05:travel_heading=target_heading if magnitude>=.1 else facing
	elif not pivoting:
		var travel_rate: float=deg_to_rad(lerpf(float(LOCO.travel_turn_walk_dps),float(LOCO.travel_turn_run_dps),run_t))
		travel_heading=rotate_toward(travel_heading,target_heading,travel_rate*delta)
	var accel: float
	if desired>speed:accel=float(LOCO.walk_accel) if speed<walk else lerpf(float(LOCO.run_accel),float(LOCO.run_accel_top),run_t)
	elif pivoting:accel=float(LOCO.pivot_brake)
	else:accel=float(LOCO.walk_decel) if speed<=walk+.05 else float(LOCO.run_decel)
	var next_speed: float=move_toward(speed,desired,accel*delta)
	velocity.x=sin(travel_heading)*next_speed;velocity.z=cos(travel_heading)*next_speed

func _run_t(speed: float) -> float:
	return clampf((speed-float(LOCO.walk_speed))/maxf(.1,float(LOCO.run_speed)-float(LOCO.walk_speed)),0,1)

## Uphill slows her; gentle downhill helps; steep downhill makes her brake.
func update_slope(delta: float,heading: float) -> void:
	var factor: float=1.
	if is_on_floor():
		var n: Vector3=get_floor_normal()
		var grade: float=-(n.x*sin(heading)+n.z*cos(heading))/maxf(n.y,.3)
		if grade>0:factor=1.-float(LOCO.uphill_penalty)*clampf(grade,0,1)
		else:
			var g: float=-grade
			factor=1.+float(LOCO.downhill_bonus)*clampf(g/.2,0,1)-maxf(0,g-float(LOCO.downhill_brake_grade))*float(LOCO.downhill_brake)
	slope_factor=lerpf(slope_factor,clampf(factor,.55,1.12),1-exp(-delta*float(LOCO.slope_response)))

## Body tilts toward its horizontal acceleration: forward when setting off,
## back when braking, into the curve when turning. Applied by locomotion_lean.gd.
func update_lean(delta: float) -> void:
	if not ("lean_target" in visual):return
	var planar: Vector3=Vector3(previous_achieved.x,0,previous_achieved.z)/maxf(delta,.00001)
	var accel: Vector3=(planar-last_planar_velocity)/maxf(delta,.00001);last_planar_velocity=planar
	if not weighted_active or LOCO.is_empty() or not is_on_floor():
		smoothed_accel=Vector3.ZERO;visual.lean_target=Vector3.ZERO;return
	smoothed_accel=smoothed_accel.lerp(accel.limit_length(40.),1-exp(-delta*float(LOCO.lean_accel_smoothing)))
	var forward: Vector3=Vector3(sin(facing),0,cos(facing));var side: Vector3=Vector3.UP.cross(forward)
	var a_forward: float=smoothed_accel.dot(forward);var a_side: float=smoothed_accel.dot(side)
	var tilt: Vector3=forward*atan(a_forward/9.8)*float(LOCO.lean_forward_gain)+side*atan(a_side/9.8)*float(LOCO.lean_side_gain)
	visual.lean_target=tilt.limit_length(deg_to_rad(float(LOCO.lean_max_deg)))

func weapon_tip() -> Vector3:
	return gear.to_global(Vector3(0,.75 if weapon=="staff" else .18,0))

func check_contacts(tip_only: bool=false, upper_length: float=0., previous_axis: Vector3=Vector3.ZERO) -> void:
	# Sweep samples cover both the blade/shaft and its travel since the last frame.
	var hand: Vector3=weapon_root.global_position if tip_only else hand_mount.global_position
	var tip: Vector3=weapon_tip()
	var sphere: SphereShape3D=SphereShape3D.new();sphere.radius=.17 if weapon=="staff" else .15
	var query: PhysicsShapeQueryParameters3D=PhysicsShapeQueryParameters3D.new();query.shape=sphere;query.collision_mask=4 if enemy else 2;query.exclude=[get_rid()]
	for i: int in range(7):
		var fraction: float=float(i)/6.
		var points: Array[Vector3]=[previous_tip.lerp(tip,fraction)]
		if not tip_only:points.push_front(hand.lerp(tip,fraction))
		if upper_length>0.:
			var axis: Vector3=previous_axis.slerp(weapon_root.global_basis.y.normalized(),fraction)
			points.append(points[0]-axis*upper_length*.5)
			points.append(points[0]-axis*upper_length)
		for point: Vector3 in points:
			query.transform=Transform3D(Basis.IDENTITY,point)
			for result: Dictionary in get_world_3d().direct_space_state.intersect_shape(query,8):
				var body: Node=result.collider
				if body.has_method("receive_hit") and not hit_targets.has(body.get_instance_id()):
					var sight: PhysicsRayQueryParameters3D=PhysicsRayQueryParameters3D.create(hand,point,1)
					if not get_world_3d().direct_space_state.intersect_ray(sight).is_empty():continue
					hit_targets[body.get_instance_id()]=true;hit_events+=1;body.receive_hit(18 if weapon=="staff" else 12,self)

