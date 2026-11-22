extends SkeletonModifier3D
## movement-v09: tilts Freya's whole body toward her horizontal acceleration,
## pivoting at the ground beneath the hips so the planted feet stay put, then
## counter-rotates the neck so her head stays steadier than her body.
## Runs before the foot solver, which then re-plants the legs.
## Does nothing unless the motion graph and foot solver are both active, so
## story clips, seated poses and the injury set are untouched.
var visual: Node3D
var head_counter: float = .55
var applied_deg: float = 0.

func _process_modification_with_delta(_delta: float) -> void:
	applied_deg = 0.
	if not visual or not visual.tree.active or not visual.feet or not visual.feet.active: return
	var lean: Vector3 = visual.lean_world
	var angle: float = lean.length()
	if angle < .0015: return
	var sk: Skeleton3D = get_skeleton()
	var hips: int = sk.find_bone("Hips"); var neck: int = sk.find_bone("Neck"); var root: int = sk.find_bone("Root")
	if hips < 0: return
	var to_skeleton: Basis = sk.global_basis.orthonormalized().inverse()
	var axis: Vector3 = (to_skeleton * Vector3.UP.cross(lean / angle)).normalized()
	var up: Vector3 = (to_skeleton * Vector3.UP).normalized()
	var turn: Basis = Basis(axis, angle)
	var pose: Transform3D = sk.get_bone_global_pose(hips)
	var ground: Vector3 = sk.get_bone_global_pose(root).origin if root >= 0 else Vector3.ZERO
	var pivot: Vector3 = pose.origin - up * up.dot(pose.origin - ground)
	pose.origin = pivot + turn * (pose.origin - pivot)
	pose.basis = turn * pose.basis
	sk.set_bone_global_pose(hips, pose)
	if neck >= 0 and head_counter > 0:
		var neck_pose: Transform3D = sk.get_bone_global_pose(neck)
		neck_pose.basis = Basis(axis, -angle * head_counter) * neck_pose.basis
		sk.set_bone_global_pose(neck, neck_pose)
	applied_deg = rad_to_deg(angle)

