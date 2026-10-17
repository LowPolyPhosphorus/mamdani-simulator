class_name PolicyCard
extends Resource

@export var card_name: String = ""
@export_multiline var description: String = ""
@export var cost: int = 10
@export var citywide: bool = false
@export var budget_change: int = 0
@export var affordability_change: int = 0
@export var ridership_change: int = 0
@export var approval_change: int = 0

@export_group("Gatekeeper")
@export_enum("None", "MTA", "Council", "Albany") var gatekeeper: String = "None"
@export var gate_threshold: int = 50
@export var attitude_change: int = 0

@export_group("Ongoing")
@export var ongoing: bool = false
@export var upkeep: int = 0
@export var per_turn_affordability: int = 0
@export var per_turn_ridership: int = 0
@export var per_turn_approval: int = 0
