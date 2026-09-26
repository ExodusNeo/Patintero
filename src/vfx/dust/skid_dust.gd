extends CPUParticles3D
class_name SkidDustVFX

# Visual FX: Asphalt Skid & Slide Dust Puffs
# Compatible with Desktop, Web, and Mobile renderers (CPUParticles3D)
# godot-3d-essentials / physics-tuning

func burst() -> void:
	emitting = true
	get_tree().create_timer(lifetime + 0.1).timeout.connect(queue_free)

func set_continuous(active: bool) -> void:
	emitting = active
