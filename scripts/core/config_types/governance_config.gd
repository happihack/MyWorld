class_name GovernanceConfig
extends ConfigBase
## Governance v0 (bible §17.4, M12.5): who leads a settlement, and what
## comes of it.

@export_group("Who leads")
## A settlement of at least this many has a leader.
@export_range(1, 50) var least_people: int = 3
## What makes someone looked to (weights of their standing):
## the respect and liking of their neighbours (each the mean, −1 … +1) …
@export_range(0.0, 10.0, 0.05) var respect_weight: float = 2.0
@export_range(0.0, 10.0, 0.05) var affinity_weight: float = 1.0
## … years (best at `prime_years`, nothing `prime_span` years either side) …
@export_range(0.0, 10.0, 0.05) var age_weight: float = 1.0
@export_range(16, 100) var prime_years: int = 40
@export_range(1, 100) var prime_span: int = 30
## … having founded the settlement …
@export_range(0.0, 10.0, 0.05) var founder_weight: float = 1.0
## … what they have done (significance points, up to `deeds_most`) …
@export_range(0.0, 10.0, 0.05) var deeds_weight: float = 0.15
@export_range(0.0, 100.0, 0.5) var deeds_most: float = 6.0
## … and their nature (ambitious, social).
@export_range(0.0, 10.0, 0.05) var ambition_weight: float = 0.5
@export_range(0.0, 10.0, 0.05) var sociability_weight: float = 0.3
## A leader is replaced only by someone this much more looked to.
@export_range(0.0, 10.0, 0.05) var challenge_margin: float = 0.8

@export_group("What a leader brings")
## People's interpretations lean toward their leader's beliefs (this much
## for a belief held fully).
@export_range(0.0, 5.0, 0.05) var belief_weight: float = 0.6
## An ambitious leader builds sooner: the building job is this much more
## pressing (fully ambitious), and homes are planned with one place more to spare.
@export_range(0.0, 2.0, 0.05) var ambition_building: float = 0.5
@export_range(0.0, 1.0, 0.05) var ambition_homes_from: float = 0.3
## A cautious leader keeps more food back from trade (this much more, fully
## cautious); a generous one less (this much less, fully generous).
@export_range(0.0, 2.0, 0.05) var caution_keep: float = 0.4
@export_range(0.0, 1.0, 0.05) var generosity_keep: float = 0.3


func validate() -> PackedStringArray:
	return PackedStringArray()
