class_name PerfConfig
extends ConfigBase
## Performance targets and budgets (bible §31.14, §33).

@export_range(15, 120) var target_fps_high: int = 60
@export_range(15, 120) var target_fps_low: int = 30
## Simulation time allowed per rendered frame.
@export_range(0.5, 16.0, 0.1) var sim_budget_ms_per_frame: float = 4.0
## Time allowed per frame for answering queued path requests.
@export_range(0.1, 8.0, 0.1) var path_budget_ms_per_frame: float = 1.0
@export_range(64, 4096) var memory_budget_low_end_mb: int = 350
@export_range(50, 5000) var draw_calls_budget_low_end: int = 250


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, target_fps_low <= target_fps_high, "target_fps_low must be <= target_fps_high")
	return p
