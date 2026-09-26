extends Node3D
class_name TagHitEffect

# Visual FX: Crunchy Contact Slap Hit Spark on Tag Turnover
# Displays expanding impact star and radiating sparks
# godot-3d-essentials / godot-animation

@onready var spark_particles: CPUParticles3D = $SparkParticles
@onready var star_flash: MeshInstance3D = $StarFlash

func _ready() -> void:
	spark_particles.emitting = true
	
	# Comic Star Flash Pop
	star_flash.scale = Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(star_flash, "scale", Vector3(1.2, 1.2, 1.2), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(star_flash, "scale", Vector3.ZERO, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	get_tree().create_timer(0.45).timeout.connect(queue_free)
