extends Control
## 900-degree visual steering-wheel controller acting like a horizontal analogue joystick.
## The 3D car is right-hand drive; this controller stays on the right of the screen.
signal steering_changed(value: float)

var value: float = 0.0
var touch_id: int = -1
var mouse_held: bool = false
var active: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(164.0, 164.0)
	queue_redraw()

func _process(delta: float) -> void:
	if not active and abs(value) > 0.001:
		value = move_toward(value, 0.0, 2.6 * delta)
		steering_changed.emit(value)
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and touch_id == -1:
			touch_id = event.index
			active = true
			_set_from_position(event.position)
			accept_event()
		elif not event.pressed and event.index == touch_id:
			touch_id = -1
			active = false
			accept_event()
	elif event is InputEventScreenDrag and event.index == touch_id:
		_set_from_position(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		mouse_held = event.pressed
		active = mouse_held
		if mouse_held:
			_set_from_position(event.position)
		accept_event()
	elif event is InputEventMouseMotion and mouse_held:
		_set_from_position(event.position)
		accept_event()

func _set_from_position(p: Vector2) -> void:
	var radius: float = min(size.x, size.y) * 0.5
	value = clampf((p.x - size.x * 0.5) / maxf(radius * 0.85, 1.0), -1.0, 1.0)
	if abs(value) < 0.07:
		value = 0.0
	steering_changed.emit(value)
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var radius: float = min(size.x, size.y) * 0.43
	draw_circle(c, radius + 12.0, Color(0.035, 0.055, 0.068, 0.69))
	draw_arc(c, radius, 0.0, TAU, 70, Color(0.79, 0.86, 0.88, 0.95), 10.0, true)
	draw_arc(c, radius - 10.0, 0.0, TAU, 70, Color(0.18, 0.24, 0.28, 1.0), 4.0, true)
	# 450 degrees to either lock; the spokes rotate like a real steering wheel.
	var angle := value * PI * 2.5
	for tick in range(12):
		var a_tick: float = TAU * float(tick) / 12.0 + angle
		var start: Vector2 = c + Vector2(cos(a_tick), sin(a_tick)) * (radius + 3.0)
		var end: Vector2 = c + Vector2(cos(a_tick), sin(a_tick)) * (radius + 8.0)
		draw_line(start, end, Color(0.50, 0.57, 0.61), 2.5, true)
	for a in [0.0, 2.094395, 4.18879]:
		var spoke_a: float = angle + a
		var spoke_end: Vector2 = c + Vector2(cos(spoke_a), sin(spoke_a)) * (radius - 6.0)
		draw_line(c, spoke_end, Color(0.83, 0.89, 0.90), 10.0, true)
	draw_circle(c, 27.0, Color(0.11, 0.18, 0.21))
	draw_circle(c, 20.0, Color(0.23, 0.72, 0.69))
	var dot_offset := Vector2(value * radius * 0.45, 0.0)
	draw_circle(c + dot_offset, 6.0, Color(0.95, 0.99, 0.98))
	# A subtle steering center index helps learners straighten the road wheels.
	draw_line(c + Vector2(0, -radius - 17.0), c + Vector2(0, -radius - 8.0), Color(0.29, 0.99, 0.73), 5.0, true)
