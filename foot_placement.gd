extends SkeletonModifier3D
# C18: preserve the corrected authored ankle/toe orientation. Fit the actual
# skinned sole, and solve from joint vectors rather than guessed bone axes.
var visual: Node3D
var height_field: Callable
var flat_height_field: Callable
# Optional (RPG World): sample the ground 5 times around the ankle and test
# every sole probe against that local plane instead of one query per probe.
# Falls back to exact per-probe queries where the 5 samples are not planar
# (steps, cap edges). Unset = the accepted per-probe path, unchanged.
var plane_sampling: bool=false
var plane_radius: float=.22
var plane_tolerance: float=.012
var plane_hits: int=0
var plane_fallbacks: int=0
var enabled: bool=true
var locking: bool=true
var anchors: Dictionary={}
var contacts: Dictionary={}
var anchor_bases: Dictionary={}
var last_poses: Dictionary={}
var max_reach_error: float=0
var released_reach_contacts: int=0
var profile_usec: int=0
var profile_calls: int=0
# movement-v09: while standing (not locking), keep each foot where it landed
# and take a short procedural step when the idle pose drifts away from it
# (after a stop, or while turning on the spot). Off unless the pawn's weighted
# locomotion is active, so every other user keeps the accepted behaviour.
var idle_settle: bool=false
var settle_distance: float=.11
var settle_force: float=.24
var step_seconds: float=.26
var step_lift: float=.05
var settle_anchor: Dictionary={}
var settle_step: Dictionary={}
var settle_steps_taken: int=0
var held_target: Dictionary={}
# Per-foot blend when switching between walking plant, standing plant and free
# swing, so a change of mode never moves a foot in a single frame.
var plant_mode: Dictionary={}
var last_output: Dictionary={}
var mode_blend: Dictionary={}
var mode_from: Dictionary={}
var mode_blend_seconds: float=.15
func clear_contacts() -> void:
	anchors.clear();contacts.clear();anchor_bases.clear();settle_anchor.clear();settle_step.clear();held_target.clear();plant_mode.clear();last_output.clear();mode_blend.clear();mode_from.clear()
func settle_target(side: String,world_ankle: Vector3,clearance: float,delta: float) -> Vector3:
	if not settle_anchor.has(side):
		# Hand over from the running plant at the position actually applied last
		# frame (the plant fades out late in stance), so the foot never jumps.
		anchors.erase(side)
		if held_target.has(side) and clearance<.06:
			var held: Vector3=held_target[side];settle_anchor[side]=Vector3(held.x,world_ankle.y,held.z)
		elif clearance<.035:settle_anchor[side]=world_ankle
		else:
			held_target.erase(side);return world_ankle
		held_target.erase(side)
	if settle_step.has(side):
		var step: Dictionary=settle_step[side]
		step.t=float(step.t)+delta/step_seconds
		var u: float=minf(1.,float(step.t))
		var p: Vector3=(step.from as Vector3).lerp(world_ankle,smoothstep(0.,1.,u))
		if u>=1.:settle_step.erase(side);settle_anchor[side]=world_ankle
		return Vector3(p.x,world_ankle.y+step_lift*sin(PI*u),p.z)
	var anchor: Vector3=settle_anchor[side]
	var gap: float=Vector2(world_ankle.x-anchor.x,world_ankle.z-anchor.z).length()
	var other: String="R" if side=="L" else "L"
	if (gap>settle_distance and not settle_step.has(other)) or gap>settle_force:
		settle_step[side]={"from":anchor,"t":0.};settle_steps_taken+=1
	return Vector3(anchor.x,world_ankle.y,anchor.z)
func solve_leg(sk: Skeleton3D,upper: int,lower: int,foot: int,target: Vector3,up: Transform3D,low: Transform3D,ankle: Transform3D) -> void:
	var a: float=up.origin.distance_to(low.origin)
	var b: float=low.origin.distance_to(ankle.origin)
	var axis: Vector3=(target-up.origin).normalized()
	var distance: float=clampf(target.distance_to(up.origin),.01,a+b-.00001)
	var actual: Vector3=up.origin+axis*distance
	max_reach_error=maxf(max_reach_error,target.distance_to(actual))
	var along: float=(a*a-b*b+distance*distance)/(2*distance)
	var pole: Vector3=low.origin-up.origin
	pole-=axis*pole.dot(axis)
	if pole.length_squared()<.000001:pole=Vector3.BACK-axis*Vector3.BACK.dot(axis)
	pole=pole.normalized()
	var knee: Vector3=up.origin+axis*along+pole*sqrt(maxf(0,a*a-along*along))
	var upper_pose: Transform3D=up
	upper_pose.basis=Basis(Quaternion((low.origin-up.origin).normalized(),(knee-up.origin).normalized()))*up.basis
	sk.set_bone_global_pose(upper,upper_pose)
	var lower_pose: Transform3D=low
	lower_pose.origin=knee;lower_pose.basis=Basis(Quaternion((ankle.origin-low.origin).normalized(),(actual-knee).normalized()))*low.basis
	sk.set_bone_global_pose(lower,lower_pose)
	ankle.origin=actual;sk.set_bone_global_pose(foot,ankle)
func _process_modification_with_delta(_delta: float) -> void:
	var profile_start: int=Time.get_ticks_usec()
	var sk: Skeleton3D=get_skeleton()
	if not sk or not visual or not height_field.is_valid():return
	for side: String in ["L","R"]:
		var prefix: String="Left" if side=="L" else "Right"
		var upper: int=sk.find_bone(prefix+"UpperLeg")
		var lower: int=sk.find_bone(prefix+"LowerLeg")
		var foot: int=sk.find_bone(prefix+"Foot")
		if min(upper,min(lower,foot))<0:continue
		if enabled:
			var up: Transform3D=sk.get_bone_global_pose(upper)
			var low: Transform3D=sk.get_bone_global_pose(lower)
			var ankle: Transform3D=sk.get_bone_global_pose(foot)
			var clearance: float=sole_clearance(sk,side)
			var phase: float=fposmod(visual.phase+(.5 if side=="R" else 0),1)
			var stance: float=lerpf(.58,.34,visual.run_blend)
			var contact: bool=not locking or (phase<stance and clearance<.10)
			var world_ankle: Vector3=sk.to_global(ankle.origin)
			var target_world: Vector3=world_ankle
			# Standing or barely moving: the walk-cycle plant fades out below full
			# move blend, so the settle plant takes over there too (no snap).
			var settling: bool=idle_settle and visual.action_name=="" and (not locking or visual.move_blend<=.95)
			if settling:
				target_world=settle_target(side,world_ankle,clearance,_delta)
			elif contact and locking and visual.move_blend>.95:
				settle_anchor.erase(side);settle_step.erase(side)
				if not anchors.has(side):anchors[side]=world_ankle
				var weight: float=smoothstep(0,.045,phase)*(1-smoothstep(stance-.07,stance,phase))
				var anchor: Vector3=anchors[side]
				if Vector2(world_ankle.x-anchor.x,world_ankle.z-anchor.z).length()>.20:
					anchors.erase(side);released_reach_contacts+=1
				else:
					target_world.x=lerpf(target_world.x,anchor.x,weight);target_world.z=lerpf(target_world.z,anchor.z,weight)
				held_target[side]=target_world
			else:
				anchors.erase(side);held_target.erase(side)
				if not settling:settle_anchor.erase(side);settle_step.erase(side)
			if idle_settle:
				var now: String="settle" if settling else ("lock" if anchors.has(side) else "free")
				if plant_mode.has(side) and plant_mode[side]!=now and last_output.has(side):
					mode_from[side]=last_output[side];mode_blend[side]=0.
				plant_mode[side]=now
				if mode_blend.has(side):
					mode_blend[side]=float(mode_blend[side])+_delta/mode_blend_seconds
					if float(mode_blend[side])>=1.:mode_blend.erase(side)
					else:
						var from: Vector3=mode_from[side];var u: float=smoothstep(0.,1.,float(mode_blend[side]))
						target_world.x=lerpf(from.x,target_world.x,u);target_world.z=lerpf(from.z,target_world.z,u)
				last_output[side]=target_world
			else:plant_mode.erase(side);last_output.erase(side);mode_blend.erase(side)
			var adjustment: float=clampf(.003-clearance,-.12,.16) if contact else maxf(0,.003-clearance)
			target_world.y+=adjustment
			var target: Vector3=sk.to_local(target_world)
			for iteration: int in range(4):
				solve_leg(sk,upper,lower,foot,target,up,low,ankle)
				var lift: float=boot_clearance_lift(sk,side)
				if lift<.0002:break
				target+=sk.global_basis.inverse()*Vector3(0,lift,0)
		else:anchors.erase(side)
	for bone: int in range(sk.get_bone_count()):last_poses[sk.get_bone_name(bone)]=sk.get_bone_global_pose(bone)
	profile_usec+=Time.get_ticks_usec()-profile_start;profile_calls+=1

# Cached low training-shoe vertices in each influencing bone's bind space.
var floor_probes: Dictionary={"L":[],"R":[]}
var probes_ready: bool=false
var rigid_probes: Dictionary={"L":{},"R":{}}
var weighted_probes: Dictionary={"L":[],"R":[]}
var packed_probes: Dictionary={"L":[],"R":[]}
var used_bones: Dictionary={}
var raw_probe_count: int=0
var unique_probe_count: int=0

func prepare_floor_probes(skeleton: Skeleton3D) -> void:
	probes_ready=true
	var part: MeshInstance3D
	for part_name: String in visual.parts:
		if part_name.ends_with("Body_Feet"):part=visual.parts[part_name]
	assert(part,"Skinned training-foot surface required for floor fitting")
	var indices: Array[int]=[]
	var seen: Dictionary={}
	for bind: int in range(part.skin.get_bind_count()):
		var name_value: String=part.skin.get_bind_name(bind)
		indices.append(skeleton.find_bone(name_value) if not name_value.is_empty() else part.skin.get_bind_bone(bind))
	for surface: int in range(part.mesh.get_surface_count()):
		var arrays: Array=part.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
		for i: int in range(vertices.size()):
			if vertices[i].y>.08:continue
			raw_probe_count+=1
			# Split normals/UV seams export identical positions and skin weights.
			# Exact keys retain every distinct weighted surface point.
			var signature: Array=[vertices[i]]
			for j: int in range(4):signature.append(bones[i*4+j]);signature.append(weights[i*4+j])
			if seen.has(signature):continue
			seen[signature]=true
			unique_probe_count+=1
			var influences: Array=[]
			for j: int in range(4):
				var weight: float=weights[i*4+j]
				if weight<.000001:continue
				var bind: int=bones[i*4+j]
				influences.append({"bone":indices[bind],"point":part.skin.get_bind_pose(bind)*vertices[i],"weight":weight})
				used_bones[indices[bind]]=true
			var side: String="L" if vertices[i].x>0 else "R"
			floor_probes[side].append(influences)
			if influences.size()==1 and float(influences[0].weight)==1.0:
				var bone: int=influences[0].bone
				if not rigid_probes[side].has(bone):rigid_probes[side][bone]=PackedVector3Array()
				rigid_probes[side][bone].append(influences[0].point)
			else:
				weighted_probes[side].append(influences)
				var ids: PackedInt32Array=[];var points: PackedVector3Array=[];var skin_weights: PackedFloat32Array=[]
				for influence: Dictionary in influences:ids.append(influence.bone);points.append(influence.point);skin_weights.append(influence.weight)
				packed_probes[side].append([ids,points,skin_weights])

func sole_clearance(skeleton: Skeleton3D,side: String) -> float:
	if not probes_ready:prepare_floor_probes(skeleton)
	var poses: Array[Transform3D]=[];poses.resize(skeleton.get_bone_count())
	for bone: int in used_bones:poses[bone]=skeleton.global_transform*skeleton.get_bone_global_pose(bone)
	var minimum: float=100
	var plane_height: float=NAN
	if flat_height_field.is_valid():
		var ankle: Vector3=poses[skeleton.find_bone("LeftFoot" if side=="L" else "RightFoot")].origin
		plane_height=float(flat_height_field.call(ankle.x,ankle.z,.4))
	var flat: bool=not is_nan(plane_height)
	var sloped: bool=false
	var origin: Vector3;var gradient: Vector2
	if not flat and plane_sampling:
		var ankle: Vector3=poses[skeleton.find_bone("LeftFoot" if side=="L" else "RightFoot")].origin
		var r: float=plane_radius
		var h0: float=float(height_field.call(ankle.x,ankle.z))
		var hx0: float=float(height_field.call(ankle.x-r,ankle.z));var hx1: float=float(height_field.call(ankle.x+r,ankle.z))
		var hz0: float=float(height_field.call(ankle.x,ankle.z-r));var hz1: float=float(height_field.call(ankle.x,ankle.z+r))
		if is_finite(h0+hx0+hx1+hz0+hz1) and absf(hx0+hx1-2*h0)<plane_tolerance and absf(hz0+hz1-2*h0)<plane_tolerance:
			sloped=true;origin=Vector3(ankle.x,h0,ankle.z);gradient=Vector2((hx1-hx0)/(2*r),(hz1-hz0)/(2*r));plane_hits+=1
		else:plane_fallbacks+=1
	for bone: int in rigid_probes[side]:
		var world_pose: Transform3D=poses[bone]
		for local_point: Vector3 in rigid_probes[side][bone]:
			var point: Vector3=world_pose*local_point
			var ground: float=plane_height if flat else (origin.y+gradient.x*(point.x-origin.x)+gradient.y*(point.z-origin.z) if sloped else float(height_field.call(point.x,point.z)))
			minimum=minf(minimum,point.y-ground)
	for packed: Array in packed_probes[side]:
		var ids: PackedInt32Array=packed[0];var points: PackedVector3Array=packed[1];var weights: PackedFloat32Array=packed[2]
		var point: Vector3=Vector3.ZERO
		for i: int in range(ids.size()):point+=(poses[ids[i]]*points[i])*weights[i]
		var ground: float=plane_height if flat else (origin.y+gradient.x*(point.x-origin.x)+gradient.y*(point.z-origin.z) if sloped else float(height_field.call(point.x,point.z)))
		minimum=minf(minimum,point.y-ground)
	return minimum

func boot_clearance_lift(skeleton: Skeleton3D,side: String) -> float:
	return maxf(0,.003-sole_clearance(skeleton,side))

