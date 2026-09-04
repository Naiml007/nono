class_name DebrisFieldSpawner
extends Node2D
## Debris Field pattern for a top-down space game.
##
## Divides a sector into a virtual grid, then drops an item in each cell with
## a probability of [member spawn_density], offset by a clamped random jitter.
## The jitter is bounded to half a cell so items feel organic but can never
## escape their cell or overlap an adjacent one.
##
## Usage: place this as a Node2D child of your level, assign [member coin_prefab],
## then call generate_debris_field(sector_width, sector_height) once at load.
## Call randomize() once at startup (e.g. in your main/autoload _ready) so each
## playthrough gets a different field.

@export var coin_prefab: PackedScene ## Item to spawn in each filled grid cell.
@export var cell_size: int = 128      ## Grid cell edge length, in pixels.
@export var max_jitter: float = 48.0  ## Max per-axis offset from cell center, in pixels.
@export var spawn_density: float = 0.6 ## 0.0..1.0 chance that a given cell holds an item.

## Generates the debris field. Purely deterministic math + instantiation:
## no physics, collisions, or area queries run inside the loops.
func generate_debris_field(sector_width: int, sector_height: int) -> void:
	# Guard clauses: nothing to do with a missing prefab, empty sector, or bad cell size.
	if coin_prefab == null or sector_width <= 0 or sector_height <= 0 or cell_size <= 0:
		return

	# Clamp density to [0,1] so an out-of-range Inspector value can't break the loop.
	var density: float = clampf(spawn_density, 0.0, 1.0)

	# Clamp jitter to just under half a cell. The jitter is symmetric around the
	# cell center, so if max_jitter stays below cell_size/2 the final offset can
	# never push an item past its own cell boundary into a neighbor's space.
	var jitter: float = minf(max_jitter, float(cell_size) * 0.5 - 1.0)
	if jitter < 0.0:
		jitter = 0.0

	var columns: int = int(float(sector_width) / cell_size)
	var rows: int = int(float(sector_height) / cell_size)

	# The sector is centered on this node. Precompute its top-left corner once so
	# the grid maps onto the same world area regardless of where the spawner sits.
	var sector_half := Vector2(sector_width, sector_height) * 0.5
	var origin: Vector2 = global_position - sector_half

	var half_cell: float = float(cell_size) * 0.5

	for gy in rows:
		for gx in columns:
			# Per-cell probability gate -> leaves gaps, producing an uneven field.
			if randf() > density:
				continue

			# Cell center in world space: origin + (cell index * cell size) + half cell.
			var cell_center: Vector2 = origin + Vector2(gx, gy) * cell_size + Vector2(half_cell, half_cell)

			# Jitter math: pick a random offset in [-jitter, +jitter] per axis. Since
			# jitter < cell_size/2, the result stays strictly inside this cell's bounds,
			# so two neighbors can never have items closer than the gap between cells.
			var jitter_offset: Vector2 = Vector2(
				randf_range(-jitter, jitter),
				randf_range(-jitter, jitter)
			)

			var coin: Node2D = coin_prefab.instantiate()
			add_child(coin)
			# Set global_position after entering the tree so it maps correctly
			# even if this spawner's parent is not at the world origin.
			coin.global_position = cell_center + jitter_offset
