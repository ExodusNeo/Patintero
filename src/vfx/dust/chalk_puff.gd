extends CPUParticles3D
class_name ChalkPuffVFX

# Visual FX: White Chalk Powder Puff on Line Crossing & Defender Slides
# godot-3d-essentials

func burst() -> void:
	emitting = true
	get_tree().create_timer(lifetime + 0.1).timeout.connect(queue_free)
