class_name DungeonGenerator
extends RefCounted

enum RoomType {
	START       = 0,
	COMBAT      = 1,
	SHOP        = 2,
	BOSS        = 3,
	MINIBOSS    = 4,
	TREASURE    = 5,
	GAMBLE      = 6,
	RIDDLE_MAN  = 7,
	PVP         = 8,
	SACRIFICE   = 9,
	HEAL        = 10,
}

enum FloorTheme { DUNGEON = 0, GARDEN = 1, HEAVEN = 2, HELL = 3 }

const GRID_SIZE  := 11
const CENTER     := Vector2i(5, 5)
const MIN_ROOMS  := 8
const MAX_ROOMS  := 14
const _DIRS: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]


static func theme_for_floor(floor_num: int) -> FloorTheme:
	match (floor_num - 1) % 4:
		0: return FloorTheme.DUNGEON
		1: return FloorTheme.GARDEN
		2: return FloorTheme.HEAVEN
		3: return FloorTheme.HELL
	return FloorTheme.DUNGEON


# Returns Array[Dictionary]:
#   pos:       Vector2i
#   type:      RoomType
#   neighbors: Array[Vector2i]  (grid positions of adjacent rooms)
static func generate(floor_level: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var grid:   Dictionary      = {}
	var order:  Array[Vector2i] = []

	grid[CENTER] = true
	order.append(CENTER)

	var target := rng.randi_range(MIN_ROOMS, MAX_ROOMS)
	for _try in range(2000):
		if order.size() >= target:
			break
		var base: Vector2i = order[rng.randi() % order.size()]
		for d: Vector2i in _dirs_shuffled(rng):
			var nxt := base + d
			if nxt.x < 1 or nxt.x >= GRID_SIZE - 1 or nxt.y < 1 or nxt.y >= GRID_SIZE - 1:
				continue
			if grid.has(nxt):
				continue
			# Allow only single-connection expansion to prevent loops
			var nc := 0
			for dd: Vector2i in _DIRS:
				if grid.has(nxt + dd):
					nc += 1
			if nc > 1:
				continue
			grid[nxt] = true
			order.append(nxt)
			break

	var boss_pos  := _bfs_furthest(CENTER, grid)

	var dead_ends: Array[Vector2i] = []
	for pos: Vector2i in order:
		if pos == CENTER or pos == boss_pos:
			continue
		var nc := 0
		for d: Vector2i in _DIRS:
			if grid.has(pos + d):
				nc += 1
		if nc == 1:
			dead_ends.append(pos)
	_shuffle_arr(dead_ends, rng)

	var special_pool: Array[int] = [
		RoomType.SHOP, RoomType.TREASURE, RoomType.HEAL,
		RoomType.SACRIFICE, RoomType.GAMBLE, RoomType.RIDDLE_MAN, RoomType.MINIBOSS,
	]
	if floor_level >= 2:
		special_pool.append(RoomType.PVP)

	var assigned: Dictionary = {}
	assigned[CENTER]   = RoomType.START
	assigned[boss_pos] = RoomType.BOSS
	var si := 0
	for de: Vector2i in dead_ends:
		assigned[de] = special_pool[si % special_pool.size()] as RoomType
		si += 1

	var result: Array[Dictionary] = []
	for pos: Vector2i in order:
		if not assigned.has(pos):
			assigned[pos] = RoomType.COMBAT
		var neighbors: Array[Vector2i] = []
		for d: Vector2i in _DIRS:
			if grid.has(pos + d):
				neighbors.append(pos + d)
		result.append({"pos": pos, "type": assigned[pos] as RoomType, "neighbors": neighbors})
	return result


static func _bfs_furthest(start: Vector2i, grid: Dictionary) -> Vector2i:
	var dist: Dictionary       = {start: 0}
	var queue: Array[Vector2i] = [start]
	var furthest               := start
	var max_d                  := 0
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d: Vector2i in _DIRS:
			var nb := cur + d
			if grid.has(nb) and not dist.has(nb):
				dist[nb] = dist[cur] + 1
				if dist[nb] > max_d:
					max_d    = dist[nb]
					furthest = nb
				queue.append(nb)
	return furthest


static func _dirs_shuffled(rng: RandomNumberGenerator) -> Array[Vector2i]:
	var a: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for i in range(3, 0, -1):
		var j := rng.randi() % (i + 1)
		var t := a[i]; a[i] = a[j]; a[j] = t
	return a


static func _shuffle_arr(arr: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t := arr[i]; arr[i] = arr[j]; arr[j] = t
