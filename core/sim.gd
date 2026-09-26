class_name Sim
extends RefCounted
## Фиксированный шаг симуляции (10 Гц) поверх переменного кадра.

const STEP := 0.1
var world: World
var _acc := 0.0
var paused := false

func _init(w: World) -> void:
	world = w

func advance(frame_dt: float) -> void:
	if paused:
		return
	_acc += frame_dt
	var n := 0
	while _acc >= STEP and n < 5:
		world.tick(STEP)
		_acc -= STEP
		n += 1
	if n == 5:
		_acc = 0.0

## Доля до следующего тика — для интерполяции отрисовки.
func alpha() -> float:
	return _acc / STEP
