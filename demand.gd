class_name Demand
extends Resource

@export var group_name: String = ""
@export_enum("budget", "affordability", "ridership") var meter: String = "ridership"
@export var threshold: int = 60
@export var turns_to_meet: int = 4
@export var reward: int = 6
@export var penalty: int = 8
