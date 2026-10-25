extends Node3D
## OFFLINE training game. All geometry and gameplay are created locally.
const WheelControl = preload("res://scripts/wheel.gd")
const LIMIT_KMH: float = 35.0
const MAX_SPEED: float = 16.0
const MAX_REVERSE: float = 4.5
const MAX_WHEEL_TURN_RAD: float = PI * 2.5  # 450 degrees left/right, 900 lock-to-lock
const WHEEL_BASE: float = 2.65
const START_POS := Vector3(-3.0, 0.0, 18.0)
const SAVE_PATH := "user://driving_academy_save.json"

var car: Node3D
var camera: Camera3D
var light_red: MeshInstance3D
var light_green: MeshInstance3D
var wheel3d: Node3D
var wheels_front: Array[Node3D] = []
var wheel_mount: Node3D
var gauge_needle_speed: Node3D
var gauge_needle_rpm: Node3D
var indicator_left_lamps: Array[MeshInstance3D] = []
var indicator_right_lamps: Array[MeshInstance3D] = []
var brake_lamps: Array[MeshInstance3D] = []
var steer_visual: float = 0.0
var engine_rpm: int = 850
var fuel_level: float = 100.0
var handbrake_on: bool = false
var indicator_mode: int = 0  # -1 left, 0 off, 1 right, 2 hazards
var indicator_elapsed: float = 0.0
var signal_lit: bool = false
var indicator_left_button: Button
var indicator_right_button: Button
var hazard_button: Button
var handbrake_button: Button
var brake_status_label: Label
var rpm_label: Label
var fuel_label: Label
var indicator_label: Label
var parking_label: Label
var mirror_left_viewport: SubViewport
var mirror_right_viewport: SubViewport
var mirror_left_camera: Camera3D
var mirror_right_camera: Camera3D
var mirror_left_panel: Control
var mirror_right_panel: Control
var traffic_vehicles: Array[Dictionary] = []
var static_obstacles: Array[Dictionary] = []
var collision_cooldown: float = 0.0
var sensor_distance: float = 99.0
var beep_cooldown: float = 0.0
var beep_player: AudioStreamPlayer
var speed: float = 0.0  # m/s; negative = reverse
var heading: float = 0.0  # positive toward the right of northbound traffic
var steer_input: float = 0.0
var gas_held: bool = false
var brake_held: bool = false
var gear: String = "D"
var cockpit: bool = false
var stage: int = 0
var score: int = 100
var best_score: int = 0
var traffic_time: float = 0.0
var green: bool = false
var warning_cooldown: float = 0.0
var speed_penalty_cooldown: float = 0.0
var info_timer: float = 0.0
var parked: bool = false
var steer_control: Control
var speed_label: Label
var lesson_label: Label
var hint_label: Label
var feedback_label: Label
var gear_button: Button
var camera_button: Button
var traffic_label: Label

func _ready() -> void:
	_read_save()
	_build_world()
	_build_car()
	_build_traffic()
	_build_mirrors()
	_build_beeper()
	_build_ui()
	_update_stage_ui()

func _process(delta: float) -> void:
	if warning_cooldown > 0.0:
		warning_cooldown -= delta
	if speed_penalty_cooldown > 0.0:
		speed_penalty_cooldown -= delta
	if info_timer > 0.0:
		info_timer -= delta
		if info_timer <= 0.0:
			feedback_label.text = ""
	if collision_cooldown > 0.0:
		collision_cooldown -= delta
	indicator_elapsed += delta
	signal_lit = fmod(indicator_elapsed, 0.84) < 0.42
	traffic_time += delta
	green = fmod(traffic_time, 20.0) >= 10.0
	_set_light_color(light_red, Color(0.94, 0.13, 0.10) if not green else Color(0.22, 0.045, 0.045))
	_set_light_color(light_green, Color(0.13, 0.89, 0.31) if green else Color(0.035, 0.18, 0.06))
	traffic_label.text = "SIGNAL: GREEN" if green else "SIGNAL: RED"
	traffic_label.add_theme_color_override("font_color", Color(0.28, 1.0, 0.57) if green else Color(1.0, 0.43, 0.39))
	var keyboard_steer: float = Input.get_axis("ui_left", "ui_right")
	if Input.is_key_pressed(KEY_A):
		keyboard_steer = -1.0
	elif Input.is_key_pressed(KEY_D):
		keyboard_steer = 1.0
	var effective_steer: float = keyboard_steer if abs(keyboard_steer) > 0.05 else steer_input
	steer_visual = lerpf(steer_visual, effective_steer, minf(1.0, delta * 5.5))
	var accelerating: bool = gas_held or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
	var braking: bool = brake_held or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
	if not parked:
		_update_car(delta, steer_visual, accelerating, braking)
	_update_traffic(delta)
	_update_dashboard(delta, accelerating, braking)
	_update_parking_sensors(delta)
	_update_lamps(braking)
	_update_camera(delta)
	_update_mirror_cameras()
	speed_label.text = "%02d km/h   |   %s   |   %d pts   |   BEST %d" % [int(abs(speed) * 3.6), gear, score, best_score]

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_V:
				_toggle_camera()
			KEY_H:
				_toggle_handbrake()
			KEY_Z:
				_toggle_indicator(-1)
			KEY_X:
				_toggle_indicator(1)
			KEY_C:
				_toggle_indicator(2)
			KEY_R:
				_reset_drive()
			KEY_Q:
				_set_gear("R")
			KEY_E:
				_set_gear("D")

func _update_car(delta: float, steer: float, gas: bool, braking: bool) -> void:
	var requested_direction: float = -1.0 if gear == "R" else 1.0
	if handbrake_on:
		speed = move_toward(speed, 0.0, 18.0 * delta)
		gas = false
	if gas:
		if speed * requested_direction < 0.0:
			speed = move_toward(speed, 0.0, 10.0 * delta)
		else:
			speed += requested_direction * 4.2 * delta
	if braking:
		speed = move_toward(speed, 0.0, 13.0 * delta)
	if not gas and not braking:
		speed = move_toward(speed, 0.0, 2.0 * delta)
	speed = clampf(speed, -MAX_REVERSE, MAX_SPEED)
	if abs(speed) < 0.02:
		speed = 0.0
	var prev_z: float = car.position.z
	heading += speed / WHEEL_BASE * tan(steer * 0.5) * delta
	var direction := Vector3(sin(heading), 0.0, -cos(heading))
	car.position += direction * speed * delta
	car.rotation.y = -heading
	for fw in wheels_front:
		fw.rotation.y = -steer * 0.42
	if wheel3d:
		# Spin around its own tilted steering column, rather than rotating the whole dashboard.
		wheel3d.rotation.y = -steer * MAX_WHEEL_TURN_RAD
	# Keep car on accessible training grounds.
	car.position.x = clampf(car.position.x, -50.0, 50.0)
	car.position.z = clampf(car.position.z, -150.0, 60.0)
	if abs(speed) * 3.6 > LIMIT_KMH and speed_penalty_cooldown <= 0.0:
		_penalize("Slow down: 35 km/h school-zone limit", 5)
		speed_penalty_cooldown = 4.0
	if stage <= 1 and car.position.x > 0.25 and warning_cooldown <= 0.0:
		_penalize("Keep LEFT (right-hand-drive road rule)", 4)
		warning_cooldown = 5.0
	if stage == 0 and car.position.z < -32.0 and car.position.z > -44.0 and abs(speed) < 0.35:
		stage = 1
		_score_bonus("Nice stop! Wait for GREEN before crossing.", 10)
		_update_stage_ui()
	elif stage == 0 and prev_z >= -45.0 and car.position.z < -45.0:
		_penalize("You missed the stop line. Try again.", 12)
		_reset_car_only()
	elif stage == 1 and prev_z >= -56.0 and car.position.z < -56.0:
		if green:
			stage = 2
			_score_bonus("Great! Now park in the blue bay ahead.", 15)
			_update_stage_ui()
		else:
			_penalize("Red light violation. Return to stop line.", 15)
			car.position = Vector3(-3.0, 0.0, -36.0)
			speed = 0.0
			heading = 0.0
	if stage == 2 and car.position.z < -95.0 and car.position.z > -115.0 and car.position.x > -10.0 and car.position.x < -5.6:
		if abs(speed) < 0.24 and abs(wrapf(heading, -PI, PI)) < 0.40 and handbrake_on:
			stage = 3
			parked = true
			_score_bonus("LESSON COMPLETE! Parked straight with handbrake ON.", 25)
			best_score = maxi(best_score, score)
			_save_result()
			_update_stage_ui()

func _update_camera(delta: float) -> void:
	if car == null:
		return
	var forward := Vector3(sin(heading), 0.0, -cos(heading))
	var right := Vector3(cos(heading), 0.0, sin(heading))
	var target_pos: Vector3
	var look_target: Vector3
	if cockpit:
		# Driver's head on the RIGHT of the vehicle.
		target_pos = car.position + Vector3.UP * 1.43 + right * 0.59 - forward * 0.24
		look_target = target_pos + forward * 16.0 - Vector3.UP * 0.12
	else:
		target_pos = car.position + Vector3.UP * 6.2 - forward * 10.8
		look_target = car.position + Vector3.UP * 0.9 + forward * 5.2
	var t: float = minf(1.0, delta * 6.0)
	camera.global_position = camera.global_position.lerp(target_pos, t)
	camera.look_at(look_target, Vector3.UP)

func _build_world() -> void:
	var sky_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.54, 0.74, 0.91)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.80, 0.88)
	env.ambient_light_energy = 0.75
	sky_env.environment = env
	add_child(sky_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 25.0, -10.0)
	sun.light_energy = 0.95
	add_child(sun)
	_box(self, Vector3(0, -0.16, -42), Vector3(230, 0.3, 350), Color(0.29, 0.48, 0.29))
	# Main two-lane road and crossroad, both with shoulders.
	_box(self, Vector3(0, 0.012, -41), Vector3(12.5, 0.08, 230), Color(0.20, 0.24, 0.27))
	_box(self, Vector3(0, 0.02, -48), Vector3(145, 0.08, 12.5), Color(0.20, 0.24, 0.27))
	for z in range(-145, 58, 9):
		if z < -55 or z > -41:
			_box(self, Vector3(0, 0.073, float(z)), Vector3(0.18, 0.016, 4.6), Color(0.96, 0.86, 0.35))
	for x in range(-70, 72, 9):
		if x < -7 or x > 7:
			_box(self, Vector3(float(x), 0.073, -48), Vector3(4.6, 0.016, 0.18), Color(0.96, 0.86, 0.35))
	for edge in [-6.28, 6.28]:
		_box(self, Vector3(edge, 0.08, -41), Vector3(0.16, 0.015, 230), Color(0.88, 0.88, 0.82))
	# Zebra crossing and STOP bar just before crossroad.
	_box(self, Vector3(-3.0, 0.082, -38.7), Vector3(5.4, 0.018, 0.42), Color.WHITE)
	for n in range(7):
		_box(self, Vector3(-5.1 + n * 0.75, 0.082, -42.0), Vector3(0.35, 0.018, 3.0), Color(0.92, 0.92, 0.90))
	# Parking bay off the LEFT side of road.
	_box(self, Vector3(-8.2, 0.086, -105), Vector3(5.0, 0.05, 16.0), Color(0.15, 0.36, 0.57))
	_box(self, Vector3(-10.6, 0.12, -105), Vector3(0.14, 0.02, 14.0), Color.WHITE)
	_box(self, Vector3(-8.2, 0.12, -113.0), Vector3(4.6, 0.02, 0.14), Color.WHITE)
	_box(self, Vector3(-8.2, 0.12, -97.0), Vector3(4.6, 0.02, 0.14), Color.WHITE)
	# Cones and visual landmarks.
	for i in range(5):
		var cone := MeshInstance3D.new()
		var cone_mesh := CylinderMesh.new()
		cone_mesh.top_radius = 0.05
		cone_mesh.bottom_radius = 0.32
		cone_mesh.height = 0.74
		cone.mesh = cone_mesh
		cone.material_override = _material(Color(0.96, 0.32, 0.09))
		cone.position = Vector3(5.0, 0.42, -69.0 - float(i) * 5.0)
		add_child(cone)
	# Pavement city blocks, all lightweight primitive geometry.
	for z in range(-126, 50, 30):
		for x in [-28.0, -18.0, 19.0, 29.0]:
			var h: float = 7.0 + float(abs(int(x + z)) % 4) * 2.4
			var color: Color = Color(0.61, 0.66, 0.66) if x < 0 else Color(0.70, 0.59, 0.50)
			_box(self, Vector3(x, h * 0.5, float(z)), Vector3(7.4, h, 11.0), color)
			for level in range(1, int(h / 2.7)):
				_box(self, Vector3(x, level * 2.4 + 0.7, float(z) + 5.53), Vector3(4.0, 1.0, 0.06), Color(0.20, 0.39, 0.50))
	# Signal pole and separate emissive red/green bulbs.
	_box(self, Vector3(-6.8, 2.5, -39.0), Vector3(0.17, 5.0, 0.17), Color(0.16, 0.18, 0.20))
	_box(self, Vector3(-6.8, 4.5, -39.0), Vector3(0.8, 1.62, 0.45), Color(0.09, 0.11, 0.12))
	light_red = _sphere(self, Vector3(-6.8, 4.89, -38.7), 0.25, Color.RED)
	light_green = _sphere(self, Vector3(-6.8, 4.14, -38.7), 0.25, Color.GREEN)
	# Yellow traffic-marker pillars make the school zone readable.
	for x in [-6.7, 6.7]:
		for z in [-25.0, -88.0]:
			_box(self, Vector3(x, 1.05, z), Vector3(0.12, 2.1, 0.12), Color(0.93, 0.83, 0.32))
	camera = Camera3D.new()
	camera.fov = 74.0
	camera.near = 0.05
	camera.far = 250.0
	camera.position = Vector3(-3.0, 7.0, 32.0)
	add_child(camera)
	camera.current = true

func _build_car() -> void:
	car = Node3D.new()
	car.name = "RHD_Car"
	car.position = START_POS
	add_child(car)
	# Visible vehicle: bonnet, cabin, windshield, head/tail lamps.
	_box(car, Vector3(0, 0.57, 0.0), Vector3(1.84, 0.58, 4.0), Color(0.06, 0.43, 0.67))
	_box(car, Vector3(0, 1.18, 0.23), Vector3(1.67, 0.70, 2.15), Color(0.11, 0.22, 0.29))
	_box(car, Vector3(0, 1.56, 0.19), Vector3(1.52, 0.08, 2.02), Color(0.08, 0.37, 0.57))
	_box(car, Vector3(0, 1.21, -0.98), Vector3(1.48, 0.53, 0.08), Color(0.34, 0.59, 0.69, 0.65), true)
	_box(car, Vector3(0, 0.91, -1.94), Vector3(1.83, 0.18, 0.12), Color(0.09, 0.19, 0.24))
	for x in [-0.70, 0.70]:
		_box(car, Vector3(x, 0.75, -2.035), Vector3(0.34, 0.18, 0.045), Color(1.0, 0.96, 0.70))
		brake_lamps.append(_box(car, Vector3(x, 0.70, 2.041), Vector3(0.29, 0.18, 0.05), Color(0.42, 0.05, 0.045)))
		for z_pos in [-2.045, 2.045]:
			var lamp := _box(car, Vector3(x, 0.69, z_pos), Vector3(0.22, 0.12, 0.06), Color(0.3, 0.17, 0.025))
			if x < 0:
				indicator_left_lamps.append(lamp)
			else:
				indicator_right_lamps.append(lamp)
	for x in [-0.92, 0.92]:
		for z in [-1.32, 1.35]:
			var wheel := Node3D.new()
			wheel.position = Vector3(x, 0.39, z)
			car.add_child(wheel)
			var tire_mesh := CylinderMesh.new()
			tire_mesh.top_radius = 0.36
			tire_mesh.bottom_radius = 0.36
			tire_mesh.height = 0.26
			var tire := MeshInstance3D.new()
			tire.mesh = tire_mesh
			tire.rotation.z = PI * 0.5
			tire.material_override = _material(Color(0.045, 0.045, 0.05))
			wheel.add_child(tire)
			if z < 0:
				wheels_front.append(wheel)
	# Interior, dashboard, and realistic cockpit position to the RIGHT.
	_box(car, Vector3(0, 1.17, -0.80), Vector3(1.55, 0.20, 0.58), Color(0.075, 0.09, 0.10))
	_box(car, Vector3(0.57, 1.02, 0.46), Vector3(0.44, 0.50, 0.48), Color(0.12, 0.13, 0.15))
	_box(car, Vector3(-0.55, 1.02, 0.46), Vector3(0.44, 0.50, 0.48), Color(0.12, 0.13, 0.15))
	# Two real car-side mirror shells, mounted on left and right door pillars.
	for side in [-1.0, 1.0]:
		_box(car, Vector3(side * 0.99, 1.25, -0.78), Vector3(0.29, 0.13, 0.17), Color(0.045, 0.055, 0.064))
		_box(car, Vector3(side * 1.08, 1.32, -0.84), Vector3(0.30, 0.24, 0.14), Color(0.055, 0.075, 0.087))
		_box(car, Vector3(side * 1.08, 1.33, -0.753), Vector3(0.255, 0.175, 0.012), Color(0.43, 0.58, 0.68))
	# Dashboard hood, instrument binnacle and two driver-facing moving needle gauges.
	_box(car, Vector3(0.57, 1.30, -0.86), Vector3(0.69, 0.29, 0.21), Color(0.045, 0.055, 0.064))
	gauge_needle_speed = _build_instrument(Vector3(0.40, 1.34, -0.735), Color(0.19, 0.81, 0.98))
	gauge_needle_rpm = _build_instrument(Vector3(0.72, 1.34, -0.735), Color(0.99, 0.68, 0.22))
	# Steering column is tilted. The inner wheel node rotates around its local Y axle.
	wheel_mount = Node3D.new()
	wheel_mount.position = Vector3(0.59, 1.27, -0.52)
	wheel_mount.rotation.x = 1.13
	car.add_child(wheel_mount)
	wheel3d = Node3D.new()
	wheel_mount.add_child(wheel3d)
	var rim := TorusMesh.new()
	rim.inner_radius = 0.205
	rim.outer_radius = 0.259
	var rim_instance := MeshInstance3D.new()
	rim_instance.mesh = rim
	rim_instance.material_override = _material(Color(0.055, 0.07, 0.082))
	wheel3d.add_child(rim_instance)
	_box(wheel3d, Vector3.ZERO, Vector3(0.042, 0.034, 0.47), Color(0.13, 0.16, 0.18))
	_box(wheel3d, Vector3.ZERO, Vector3(0.46, 0.034, 0.042), Color(0.13, 0.16, 0.18))
	_sphere(wheel3d, Vector3(0, 0.012, 0), 0.072, Color(0.15, 0.2, 0.24))
	# Dashboard central multimedia screen and air vents.
	_box(car, Vector3(-0.18, 1.26, -0.76), Vector3(0.42, 0.27, 0.04), Color(0.025, 0.12, 0.15))
	for x in [-0.48, -0.42]:
		_box(car, Vector3(x, 1.25, -0.74), Vector3(0.025, 0.20, 0.03), Color(0.40, 0.46, 0.51))

func _build_instrument(local_pos: Vector3, accent: Color) -> Node3D:
	var root := Node3D.new()
	root.position = local_pos
	car.add_child(root)
	var housing := CylinderMesh.new()
	housing.top_radius = 0.151
	housing.bottom_radius = 0.151
	housing.height = 0.025
	var face := MeshInstance3D.new()
	face.mesh = housing
	face.rotation.x = PI * 0.5
	face.material_override = _material(Color(0.016, 0.022, 0.031))
	root.add_child(face)
	var center_disc := _sphere(root, Vector3(0, 0, 0.035), 0.027, accent)
	var needle := Node3D.new()
	needle.position.z = 0.041
	root.add_child(needle)
	_box(needle, Vector3(0.0, 0.047, 0.0), Vector3(0.011, 0.103, 0.011), accent)
	return needle

func _build_traffic() -> void:
	# Oncoming cars stay in the opposite (right) lane. Cross traffic goes on its green phase.
	for i in range(3):
		var npc := _make_traffic_car(Color(0.77, 0.18, 0.17) if i == 0 else Color(0.87, 0.82, 0.66) if i == 1 else Color(0.23, 0.64, 0.51))
		npc.position = Vector3(3.1, 0.0, -122.0 + i * 74.0)
		npc.rotation.y = PI
		traffic_vehicles.append({"node": npc, "route": "oncoming", "speed": 5.0 + i * 0.7, "radius": 1.4})
	var cross := _make_traffic_car(Color(0.94, 0.72, 0.19))
	cross.position = Vector3(-63.0, 0.0, -51.0)
	cross.rotation.y = -PI * 0.5
	traffic_vehicles.append({"node": cross, "route": "crossing", "speed": 7.0, "radius": 1.4})
	# A stationary car by the rear of the parking bay is a reversing-sensor target.
	var parked_npc := _make_traffic_car(Color(0.55, 0.63, 0.71))
	parked_npc.position = Vector3(-8.0, 0.0, -120.1)
	traffic_vehicles.append({"node": parked_npc, "route": "parked", "speed": 0.0, "radius": 1.35})
	for sx in [-10.05, -6.25]:
		var z_pos := -114.8
		_box(self, Vector3(sx, 0.55, z_pos), Vector3(0.27, 1.10, 0.27), Color(0.96, 0.69, 0.11))
		static_obstacles.append({"position": Vector3(sx, 0.0, z_pos), "radius": 0.32})
	for i in range(5):
		static_obstacles.append({"position": Vector3(5.0, 0.0, -69.0 - i * 5.0), "radius": 0.33})

func _make_traffic_car(paint: Color) -> Node3D:
	var npc := Node3D.new()
	add_child(npc)
	_box(npc, Vector3(0, 0.61, 0), Vector3(1.75, 0.58, 3.52), paint)
	_box(npc, Vector3(0, 1.14, 0.15), Vector3(1.54, 0.59, 1.92), Color(0.17, 0.29, 0.39))
	_box(npc, Vector3(0, 1.45, 0.1), Vector3(1.49, 0.065, 1.78), paint.darkened(0.18))
	for side in [-0.88, 0.88]:
		for z in [-1.05, 1.08]:
			var tire := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.31
			mesh.bottom_radius = 0.31
			mesh.height = 0.22
			tire.mesh = mesh
			tire.rotation.z = PI * 0.5
			tire.position = Vector3(side, 0.34, z)
			tire.material_override = _material(Color(0.035, 0.04, 0.045))
			npc.add_child(tire)
	for side in [-0.65, 0.65]:
		_box(npc, Vector3(side, 0.71, -1.79), Vector3(0.29, 0.15, 0.06), Color(1.0, 0.94, 0.66))
		_box(npc, Vector3(side, 0.71, 1.79), Vector3(0.28, 0.15, 0.06), Color(0.84, 0.06, 0.05))
	return npc

func _update_traffic(delta: float) -> void:
	for vehicle in traffic_vehicles:
		var npc: Node3D = vehicle["node"]
		var route: String = vehicle["route"]
		if route == "oncoming":
			npc.position.z += float(vehicle["speed"]) * delta
			if npc.position.z > 61.0:
				npc.position.z = -137.0
		elif route == "crossing":
			# Finish clearing the junction if the traffic light switches mid-crossing.
			if not green or (npc.position.x > -12.0 and npc.position.x < 12.0):
				npc.position.x += float(vehicle["speed"]) * delta
			if npc.position.x > 65.0:
				npc.position.x = -65.0
		var horizontal_distance := Vector2(npc.position.x - car.position.x, npc.position.z - car.position.z).length()
		if horizontal_distance < 2.15 and collision_cooldown <= 0.0:
			_collision("Vehicle contact! Maintain a safe distance.")
	for entry in static_obstacles:
		var p: Vector3 = entry["position"]
		if Vector2(car.position.x - p.x, car.position.z - p.z).length() < 1.05 and collision_cooldown <= 0.0:
			_collision("Obstacle contact. Check your mirrors and clearance.")

func _collision(explanation: String) -> void:
	speed = 0.0
	collision_cooldown = 2.5
	_penalize(explanation, 10)

func _build_mirrors() -> void:
	# Separate low-resolution live renders show traffic behind both door mirrors.
	mirror_left_viewport = SubViewport.new()
	mirror_left_viewport.size = Vector2i(232, 104)
	mirror_left_viewport.world_3d = get_viewport().world_3d
	mirror_left_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(mirror_left_viewport)
	mirror_left_camera = Camera3D.new()
	mirror_left_camera.fov = 72.0
	mirror_left_camera.far = 105.0
	mirror_left_viewport.add_child(mirror_left_camera)
	mirror_left_camera.current = true
	mirror_right_viewport = SubViewport.new()
	mirror_right_viewport.size = Vector2i(232, 104)
	mirror_right_viewport.world_3d = get_viewport().world_3d
	mirror_right_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(mirror_right_viewport)
	mirror_right_camera = Camera3D.new()
	mirror_right_camera.fov = 72.0
	mirror_right_camera.far = 105.0
	mirror_right_viewport.add_child(mirror_right_camera)
	mirror_right_camera.current = true
	_update_mirror_cameras()

func _update_mirror_cameras() -> void:
	if car == null or mirror_left_camera == null:
		return
	mirror_left_camera.global_transform = Transform3D(car.global_basis * Basis(Vector3.UP, PI - 0.22), car.to_global(Vector3(-1.03, 1.37, -0.73)))
	mirror_right_camera.global_transform = Transform3D(car.global_basis * Basis(Vector3.UP, PI + 0.22), car.to_global(Vector3(1.03, 1.37, -0.73)))

func _build_beeper() -> void:
	beep_player = AudioStreamPlayer.new()
	add_child(beep_player)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var samples := PackedByteArray()
	var count: int = 2205
	samples.resize(count * 2)
	for i in range(count):
		var fade: float = minf(1.0, float(i) / 140.0) * minf(1.0, float(count - i) / 220.0)
		var wave: int = int(sin(TAU * 790.0 * float(i) / 22050.0) * 7000.0 * fade)
		if wave < 0:
			wave += 65536
		samples[i * 2] = wave & 255
		samples[i * 2 + 1] = (wave >> 8) & 255
	wav.data = samples
	beep_player.stream = wav
	beep_player.volume_db = -8.0

func _update_parking_sensors(delta: float) -> void:
	beep_cooldown = maxf(0.0, beep_cooldown - delta)
	if gear != "R":
		sensor_distance = 99.0
		parking_label.text = "PARKING SENSOR  •  Shift to R to activate"
		parking_label.add_theme_color_override("font_color", Color(0.65, 0.87, 0.92))
		return
	var nearest: float = 7.0
	for vehicle in traffic_vehicles:
		var npc: Node3D = vehicle["node"]
		nearest = minf(nearest, _rear_distance_to(npc.global_position, float(vehicle["radius"])))
	for entry in static_obstacles:
		nearest = minf(nearest, _rear_distance_to(entry["position"], float(entry["radius"])))
	sensor_distance = nearest
	if nearest >= 6.5:
		parking_label.text = "REAR SENSOR  ● CLEAR (>6.5 m)"
		parking_label.add_theme_color_override("font_color", Color(0.42, 0.98, 0.58))
	else:
		var danger := nearest <= 0.75
		parking_label.text = "REAR SENSOR  %0.1f m   %s" % [maxf(0.0, nearest), "STOP!" if danger else "CAUTION" if nearest < 2.2 else "OBJECT"]
		parking_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.31) if danger else Color(1.0, 0.80, 0.35))
		if nearest < 3.5 and beep_cooldown <= 0.0:
			beep_player.play()
			beep_cooldown = clampf(0.12 + nearest * 0.18, 0.12, 0.8)

func _rear_distance_to(point: Vector3, radius: float) -> float:
	var local: Vector3 = car.to_local(point)
	if local.z < 1.0 or local.z > 9.0 or abs(local.x) > 1.04 + radius:
		return 99.0
	return maxf(0.0, local.z - 2.0 - radius)

func _update_dashboard(delta: float, accelerating: bool, braking: bool) -> void:
	engine_rpm = clampi(int(850.0 + abs(speed) * 175.0 + (550.0 if accelerating and not handbrake_on else 0.0)), 850, 5600)
	if accelerating and not handbrake_on:
		fuel_level = maxf(0.0, fuel_level - delta * 0.012)
	rpm_label.text = "ENGINE  %d RPM  |  Speedometer  %02d km/h" % [engine_rpm, int(abs(speed) * 3.6)]
	fuel_label.text = "FUEL %d%%   •   GEAR %s   •   LIMIT 35" % [int(fuel_level), gear]
	brake_status_label.text = "HANDBRAKE: ON  ●" if handbrake_on else "HANDBRAKE: OFF"
	brake_status_label.add_theme_color_override("font_color", Color(1.0, 0.39, 0.36) if handbrake_on else Color(0.45, 0.96, 0.58))
	var status: String = "◀ LEFT" if indicator_mode == -1 else "RIGHT ▶" if indicator_mode == 1 else "▲ HAZARDS ▲" if indicator_mode == 2 else "TURN SIGNALS OFF"
	indicator_label.text = status if indicator_mode == 0 or signal_lit else "··············"
	indicator_label.add_theme_color_override("font_color", Color(1.0, 0.77, 0.28) if indicator_mode != 0 else Color(0.72, 0.82, 0.83))
	if gauge_needle_speed != null:
		gauge_needle_speed.rotation.z = deg_to_rad(140.0 - clampf(abs(speed) * 3.6 / 70.0, 0.0, 1.0) * 280.0)
		gauge_needle_rpm.rotation.z = deg_to_rad(140.0 - clampf(float(engine_rpm) / 6000.0, 0.0, 1.0) * 280.0)

func _update_lamps(braking: bool) -> void:
	var amber_on := Color(1.0, 0.68, 0.05)
	var amber_off := Color(0.29, 0.15, 0.025)
	for lamp in indicator_left_lamps:
		_set_light_color(lamp, amber_on if signal_lit and (indicator_mode == -1 or indicator_mode == 2) else amber_off)
	for lamp in indicator_right_lamps:
		_set_light_color(lamp, amber_on if signal_lit and (indicator_mode == 1 or indicator_mode == 2) else amber_off)
	for lamp in brake_lamps:
		_set_light_color(lamp, Color(1.0, 0.055, 0.04) if braking or handbrake_on else Color(0.43, 0.05, 0.045))

func _toggle_indicator(mode: int) -> void:
	indicator_mode = 0 if indicator_mode == mode else mode
	indicator_elapsed = 0.0
	_message("Hazard warning lights ON" if indicator_mode == 2 else "LEFT turn signal" if indicator_mode == -1 else "RIGHT turn signal" if indicator_mode == 1 else "Turn signals OFF")

func _toggle_handbrake() -> void:
	if not handbrake_on and abs(speed) > 0.55:
		_message("Stop the car before applying the parking brake")
		return
	handbrake_on = not handbrake_on
	handbrake_button.text = "P BRAKE ON" if handbrake_on else "P BRAKE OFF"
	_message("Handbrake engaged" if handbrake_on else "Handbrake released")

func _add_mirror_panel(overlay: Control, viewport: SubViewport, title: String, on_right: bool) -> Control:
	var group := VBoxContainer.new()
	if on_right:
		group.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		group.offset_left = -260.0
		group.offset_right = -16.0
	else:
		group.set_anchors_preset(Control.PRESET_TOP_LEFT)
		group.offset_left = 16.0
		group.offset_right = 260.0
	group.offset_top = 225.0
	group.offset_bottom = 367.0
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(group)
	var caption := _label(group, title + " • LIVE", 14)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_child(frame)
	var view := TextureRect.new()
	view.texture = viewport.get_texture()
	view.custom_minimum_size = Vector2(232, 104)
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(view)
	group.visible = cockpit
	return group

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay)
	var top_panel := PanelContainer.new()
	top_panel.anchor_right = 1.0
	top_panel.offset_left = 12.0
	top_panel.offset_top = 10.0
	top_panel.offset_right = -12.0
	top_panel.offset_bottom = 84.0
	top_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(top_panel)
	var column := VBoxContainer.new()
	top_panel.add_child(column)
	speed_label = _label(column, "00 km/h  |  D  | 100 pts", 20)
	lesson_label = _label(column, "LESSON 1 — Come to a complete stop at the STOP line", 17)
	var info_panel := HBoxContainer.new()
	info_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info_panel.offset_left = -385.0
	info_panel.offset_top = 94.0
	info_panel.offset_right = -16.0
	info_panel.offset_bottom = 146.0
	overlay.add_child(info_panel)
	traffic_label = _label(info_panel, "SIGNAL: RED", 17)
	gear_button = _button(info_panel, "GEAR D", Vector2(100, 48))
	gear_button.pressed.connect(_gear_pressed)
	camera_button = _button(info_panel, "COCKPIT", Vector2(110, 48))
	camera_button.pressed.connect(_toggle_camera)
	var reset_button := _button(overlay, "RESET", Vector2(95, 48))
	reset_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	reset_button.position = Vector2(18, 96)
	reset_button.pressed.connect(_reset_drive)
	handbrake_button = _button(overlay, "P BRAKE OFF", Vector2(157, 50))
	handbrake_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	handbrake_button.position = Vector2(18, 158)
	handbrake_button.pressed.connect(_toggle_handbrake)
	# Touch-operated LEFT / RIGHT indicators and hazard lights.
	var indicator_row := HBoxContainer.new()
	indicator_row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	indicator_row.offset_left = 18.0
	indicator_row.offset_top = -178.0
	indicator_row.offset_right = 340.0
	indicator_row.offset_bottom = -127.0
	indicator_row.add_theme_constant_override("separation", 7)
	overlay.add_child(indicator_row)
	indicator_left_button = _button(indicator_row, "◀ LEFT", Vector2(97, 49))
	indicator_left_button.pressed.connect(func(): _toggle_indicator(-1))
	hazard_button = _button(indicator_row, "HAZARD", Vector2(106, 49))
	hazard_button.pressed.connect(func(): _toggle_indicator(2))
	indicator_right_button = _button(indicator_row, "RIGHT ▶", Vector2(97, 49))
	indicator_right_button.pressed.connect(func(): _toggle_indicator(1))
	# Left foot controls: accelerating and braking. Multi-touch enabled.
	var foot_controls := HBoxContainer.new()
	foot_controls.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot_controls.offset_left = 18.0
	foot_controls.offset_top = -106.0
	foot_controls.offset_right = 291.0
	foot_controls.offset_bottom = -20.0
	foot_controls.add_theme_constant_override("separation", 14)
	overlay.add_child(foot_controls)
	var brake_btn := _button(foot_controls, "BRAKE", Vector2(124, 83))
	brake_btn.add_theme_color_override("font_color", Color(1.0, 0.47, 0.40))
	brake_btn.button_down.connect(func(): brake_held = true)
	brake_btn.button_up.connect(func(): brake_held = false)
	var gas_btn := _button(foot_controls, "GAS", Vector2(124, 83))
	gas_btn.add_theme_color_override("font_color", Color(0.45, 1.0, 0.57))
	gas_btn.button_down.connect(func(): gas_held = true)
	gas_btn.button_up.connect(func(): gas_held = false)
	# The touch steering wheel is on the right, in line with the RIGHT-hand driver's seat.
	steer_control = WheelControl.new()
	steer_control.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	steer_control.offset_left = -214.0
	steer_control.offset_top = -213.0
	steer_control.offset_right = -20.0
	steer_control.offset_bottom = -19.0
	steer_control.steering_changed.connect(func(v: float): steer_input = v)
	overlay.add_child(steer_control)
	var steer_lbl := _label(overlay, "DRAG TO STEER  ◀ ▶", 14)
	steer_lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	steer_lbl.offset_left = -211.0
	steer_lbl.offset_top = -247.0
	steer_lbl.offset_right = -12.0
	steer_lbl.offset_bottom = -216.0
	steer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	steer_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feedback_label = _label(overlay, "", 19)
	feedback_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	feedback_label.offset_left = -360.0
	feedback_label.offset_top = 159.0
	feedback_label.offset_right = 360.0
	feedback_label.offset_bottom = 203.0
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.add_theme_color_override("font_color", Color(1.0, 0.91, 0.45))
	feedback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The cockpit dashboard mirrors the physical dials and includes live proximity readout.
	var dashboard_panel := PanelContainer.new()
	dashboard_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dashboard_panel.offset_left = 334.0
	dashboard_panel.offset_right = -241.0
	dashboard_panel.offset_top = -138.0
	dashboard_panel.offset_bottom = -16.0
	dashboard_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dashboard_panel)
	var dashboard_rows := VBoxContainer.new()
	dashboard_rows.add_theme_constant_override("separation", 2)
	dashboard_panel.add_child(dashboard_rows)
	rpm_label = _label(dashboard_rows, "ENGINE 850 RPM  |  Speedometer 00 km/h", 17)
	fuel_label = _label(dashboard_rows, "FUEL 100%   •   GEAR D   •   LIMIT 35", 15)
	brake_status_label = _label(dashboard_rows, "HANDBRAKE: OFF", 15)
	indicator_label = _label(dashboard_rows, "TURN SIGNALS OFF", 15)
	parking_label = _label(dashboard_rows, "PARKING SENSOR • Shift to R to activate", 15)
	mirror_left_panel = _add_mirror_panel(overlay, mirror_left_viewport, "LEFT MIRROR", false)
	mirror_right_panel = _add_mirror_panel(overlay, mirror_right_viewport, "RIGHT MIRROR", true)
	hint_label = _label(overlay, "Offline • RHD • H: handbrake  Z/X: signals  C: hazards", 14)
	hint_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hint_label.offset_left = -305.0
	hint_label.offset_top = 125.0
	hint_label.offset_right = 305.0
	hint_label.offset_bottom = 150.0
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _label(parent: Node, text_value: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text_value
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.97, 0.99, 1.0))
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	parent.add_child(l)
	return l

func _button(parent: Node, label: String, minimum: Vector2) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = minimum
	b.add_theme_font_size_override("font_size", 18)
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b

func _gear_pressed() -> void:
	_set_gear("R" if gear == "D" else "D")

func _set_gear(new_gear: String) -> void:
	if abs(speed) > 0.28:
		_message("Brake to a stop before changing gears")
		return
	gear = new_gear
	gear_button.text = "GEAR " + gear
	_message("Reverse selected" if gear == "R" else "Drive selected")

func _toggle_camera() -> void:
	cockpit = not cockpit
	camera_button.text = "CHASE" if cockpit else "COCKPIT"
	mirror_left_panel.visible = cockpit
	mirror_right_panel.visible = cockpit
	# Two extra cameras are only rendered when the driver uses the cockpit view.
	mirror_left_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if cockpit else SubViewport.UPDATE_DISABLED
	mirror_right_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if cockpit else SubViewport.UPDATE_DISABLED
	_message("RIGHT-HAND driver's view" if cockpit else "Third-person view")

func _update_stage_ui() -> void:
	match stage:
		0:
			lesson_label.text = "LESSON 1 / 3  — Stop fully near the white line (zebra crossing)."
		1:
			lesson_label.text = "LESSON 2 / 3  — Watch light. Cross intersection only on GREEN."
		2:
			lesson_label.text = "LESSON 3 / 3  — Park in BLUE bay. Stop straight and apply P BRAKE."
		3:
			lesson_label.text = "PASSED! TRAINING COMPLETE  — Press RESET for another run."

func _penalize(text_value: String, points: int) -> void:
	score = maxi(0, score - points)
	_message(text_value + "  -" + str(points) + " pts")

func _score_bonus(text_value: String, points: int) -> void:
	score += points
	_message(text_value + "  +" + str(points) + " pts")

func _message(value: String) -> void:
	feedback_label.text = value
	info_timer = 4.3

func _reset_car_only() -> void:
	car.position = START_POS
	car.rotation = Vector3.ZERO
	heading = 0.0
	speed = 0.0
	gas_held = false
	brake_held = false
	steer_visual = 0.0
	if wheel3d:
		wheel3d.rotation.y = 0.0

func _reset_drive() -> void:
	_reset_car_only()
	stage = 0
	score = 100
	parked = false
	traffic_time = 0.0
	gear = "D"
	handbrake_on = false
	handbrake_button.text = "P BRAKE OFF"
	indicator_mode = 0
	indicator_elapsed = 0.0
	fuel_level = 100.0
	gear_button.text = "GEAR D"
	_update_stage_ui()
	_message("New lesson: keep LEFT and stop at the first white line")

func _read_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data is Dictionary:
		best_score = maxi(0, int(data.get("best_score", 0)))

func _save_result() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"best_score": best_score}))

func _box(parent: Node3D, pos: Vector3, sz: Vector3, tint: Color, transparent: bool = false) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = sz
	inst.mesh = mesh
	inst.position = pos
	inst.material_override = _material(tint, transparent)
	parent.add_child(inst)
	return inst

func _sphere(parent: Node3D, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	inst.mesh = mesh
	inst.position = pos
	inst.material_override = _material(color)
	parent.add_child(inst)
	return inst

func _material(tint: Color, transparent: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.85
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func _set_light_color(inst: MeshInstance3D, color: Color) -> void:
	if inst == null:
		return
	var mat: StandardMaterial3D = inst.material_override
	mat.albedo_color = color
