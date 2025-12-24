extends GPUParticles3D

func _ready():
	emitting = false

func start_drift():
	emitting = true

func stop_drift():
	emitting = false

