extends Node2D

export(float) var timer = .2
export(Array, PackedScene) var items

const TILE_SIZE = 32
const LEVEL_SIZES = [
	Vector2(30, 30),
	Vector2(35, 35),
	Vector2(40, 40),
	Vector2(45, 45),
	Vector2(50, 50),
]
const ROOM_COUNT = [5, 7, 9, 12, 15]
const ITEM_COUNT = [2, 4, 6, 8, 10]
const MAX_ROOM_SIZE = 8
const MIN_ROOM_SIZE = 5

enum Tile {Door, Wall, Floor, Stairs, Stone}
signal setPlayerPosition(x, y)

var levelNum = 0
var map = []
var rooms = []
var levelSize
var player_tile

onready var tileMap = $TileMap
onready var visMap = $VisibilityMap
onready var player = $Player
onready var cam = $Player/Camera2D

func _ready():
	OS.set_window_size(Vector2(1280, 720))
	randomize()
	build_level()

func _process(delta):
	if Input.is_action_just_pressed("zoomOut"):
		cam.zoom.x += 1
		cam.zoom.y += 1
	
	if Input.is_action_just_pressed("ZoomIn"):
		cam.zoom.x -= 1
		cam.zoom.y -= 1

func build_level():
	rooms.clear()
	map.clear()
	tileMap.clear()
	
	# Build Rooms
	levelSize = LEVEL_SIZES[levelNum]
	for x in range(levelSize.x):
		map.append([])
		for y in range(levelSize.y):
			map[x].append(Tile.Stone)
			tileMap.set_cell(x, y, Tile.Stone) 
			visMap.set_cell(x, y, 0)
	
	var freeRegions = [Rect2(Vector2(2, 2), levelSize - Vector2(4, 4))]
	var numRooms = ROOM_COUNT[levelNum]
	for i in range(numRooms):
		add_room(freeRegions)
		if freeRegions.empty():
			break
	
	connect_rooms()
	
	#Place Player
	var startRoom = rooms.front()
	var playerX = startRoom.position.x + 1 + randi() % int(startRoom.size.x - 2)
	var playerY = startRoom.position.y + 1 + randi() % int(startRoom.size.y - 2)
	player_tile = Vector2(playerX, playerY)
	yield(get_tree().create_timer(timer), "timeout")
	call_deferred("update_sight")
	
	#Place items
	var numItems = ITEM_COUNT[levelNum]
	for i in range(numItems):
		#Random Room / Position
		var room = rooms[randi() % (rooms.size())]
		var x = room.position.x + 1 + randi() % int(room.size.x - 2)
		var y = room.position.y + 1 + randi() % int(room.size.y - 2)
		
		#Random Item
		items.shuffle()
		var item = items.front()
		var createItem = item.instance()
		var Ip = get_tree().current_scene.get_node("ItemsPlacement")
		Ip.add_child(createItem)
		createItem.position.x = x * TILE_SIZE
		createItem.position.y = y * TILE_SIZE
	
	#Place Exit
	var endRoom = rooms.back()
	var stairsX = endRoom.position.x + 1 + randi() % int(endRoom.size.x - 2)
	var stairsY = endRoom.position.y + 1 + randi() % int(endRoom.size.y - 2)
	set_tile(stairsX, stairsY, Tile.Stairs)

func _on_Player_attemptMovement(Direction):
	match Direction:
		"Up":
			try_move(0, -1)
		"Left":
			try_move(-1, 0)
		"Down":
			try_move(0, 1)
		"Right":
			try_move(1, 0)

func try_move(dx, dy):
	var x = player_tile.x + dx
	var y = player_tile.y + dy
	
	var tileType = Tile.Stone
	if x >= 0 && x < levelSize.x && y >= 0 && y < levelSize.y:
		tileType = map[x][y]
	
	match tileType:
		Tile.Floor:
			player_tile = Vector2(x, y)
		
		Tile.Door:
			set_tile(x, y, Tile.Floor)
		
		Tile.Stairs:
			levelNum += 1
			if levelNum < LEVEL_SIZES.size():
				build_level()
				yield(get_tree().create_timer(timer), "timeout")
				call_deferred("update_sight")
			else:
				print("win")
	
	call_deferred("update_sight")

func update_sight():
	emit_signal("setPlayerPosition", player_tile.x * TILE_SIZE, player_tile.y * TILE_SIZE)
	var playerCenter = tile_to_pixel_center(player_tile.x, player_tile.y)
	var spaceState = get_world_2d().direct_space_state
	for x in range(levelSize.x):
		for y in range(levelSize.y):
			if visMap.get_cell(x, y) == 0:
				var xDir = 1 if x < player_tile.x else -1
				var yDir = 1 if y < player_tile.y else -1
				var testPoint = tile_to_pixel_center(x, y) + Vector2(xDir, yDir) * TILE_SIZE / 2
				
				var occlusion = spaceState.intersect_ray(playerCenter, testPoint)
				if !occlusion || (occlusion.position - testPoint).length() < 1:
					print(str(x) + " , " + str(y) + "Pos Visiable")
					visMap.set_cell(x, y, -1)

func tile_to_pixel_center(x, y):
	return Vector2((x + 0.5) * TILE_SIZE, (y + 0.5) * TILE_SIZE)

#Sub Scripts Building Level
func connect_rooms():
	var stoneGraph = AStar.new()
	var pointId = 0
	for x in range(levelSize.x):
		for y in range(levelSize.y):
			if map[x][y] == Tile.Stone:
				stoneGraph.add_point(pointId, Vector3(x, y, 0))
				
				if x > 0 && map[x - 1][y] == Tile.Stone:
					var leftPoint = stoneGraph.get_closest_point(Vector3(x - 1, y, 0))
					stoneGraph.connect_points(pointId, leftPoint)
				
				if y > 0 && map[x][y - 1] == Tile.Stone:
					var abovePoint = stoneGraph.get_closest_point(Vector3(x, y - 1, 0))
					stoneGraph.connect_points(pointId, abovePoint)
				
				pointId += 1
	
	var roomGraph = AStar.new()
	pointId = 0
	for room in rooms:
		var roomCenter = room.position + room.size / 2
		roomGraph.add_point(pointId, Vector3(roomCenter.x, roomCenter.y, 0))
		pointId += 1
	
	while !is_everything_connected(roomGraph):
		add_random_connection(stoneGraph, roomGraph)

func is_everything_connected(graph):
	var points = graph.get_points()
	var start = points.pop_back()
	for point in points:
		var path = graph.get_point_path(start, point)
		if !path:
			return false
	
	return true

func add_random_connection(stoneGraph, roomGraph):
	var startRoomId = get_least_connected_point(roomGraph)
	var endRoomId = get_nearest_unconnected_point(roomGraph, startRoomId)
	
	var startPosition = pick_random_door_location(rooms[startRoomId])
	var endPosition = pick_random_door_location(rooms[endRoomId])
	
	var closestStartPoint = stoneGraph.get_closest_point(startPosition)
	var closestEndPoint = stoneGraph.get_closest_point(endPosition)
	
	var path = stoneGraph.get_point_path(closestStartPoint, closestEndPoint)
	
	set_tile(startPosition.x, startPosition.y, Tile.Door)
	set_tile(endPosition.x, endPosition.y, Tile.Door)
	
	for position in path:
		set_tile(position.x, position.y, Tile.Floor)
	
	roomGraph.connect_points(startRoomId, endRoomId)

func get_least_connected_point(graph):
	var pointsId = graph.get_points()
	
	var least
	var tiedForLeast = []
	
	for point in pointsId:
		var count = graph.get_point_connections(point).size()
		if !least || count < least:
			least = count
			tiedForLeast = [point]
		elif count == least:
			tiedForLeast.append(point)
	
	return tiedForLeast[randi() % tiedForLeast.size()]

func get_nearest_unconnected_point(graph, targetPoint):
	var targetPosition = graph.get_point_position(targetPoint)
	var pointIds = graph.get_points()
	
	var nearest
	var tiedForNearest = []
	
	for point in pointIds:
		if point == targetPoint:
			continue
		
		var path = graph.get_point_path(point, targetPoint)
		if path:
			continue
		
		var dist = (graph.get_point_position(point) - targetPosition).length()
		if !nearest || dist < nearest:
			nearest = dist
			tiedForNearest = [point]
		elif dist == nearest:
			tiedForNearest.append(point)
	
	return tiedForNearest[randi() % tiedForNearest.size()]

func pick_random_door_location(room):
	var options = []
	
	for x in range(room.position.x + 1, room.end.x - 2):
		options.append(Vector3(x, room.position.y, 0))
		options.append(Vector3(x, room.end.y - 1, 0))
	
	for y in range(room.position.y + 1, room.end.y - 2):
		options.append(Vector3(room.position.x, y, 0))
		options.append(Vector3(room.end.x - 1, y, 0))
	
	return options[randi() % options.size()]

func add_room(freeRegions):
	var region = freeRegions[randi() % freeRegions.size()]
	
	var size_x = MIN_ROOM_SIZE
	if region.size.x > MIN_ROOM_SIZE:
		size_x += randi() % int(region.size.x - MIN_ROOM_SIZE)
	
	var size_y = MIN_ROOM_SIZE
	if region.size.y > MIN_ROOM_SIZE:
		size_y += randi() % int(region.size.y - MIN_ROOM_SIZE)
	
	size_x = min(size_x, MAX_ROOM_SIZE)
	size_y = min(size_y, MAX_ROOM_SIZE)
	
	var start_x = region.position.x
	if region.size.x > size_x:
		start_x += randi() % int(region.size.x - size_x)
	
	var start_y = region.position.y
	if region.size.y > size_y:
		start_y += randi() % int(region.size.y - size_y)
	
	var room = Rect2(start_x, start_y, size_x, size_y)
	rooms.append(room)
	
	for x in range(start_x, start_x + size_x):
		set_tile(x, start_y, Tile.Wall)
		set_tile(x, start_y + size_y - 1, Tile.Wall)
	
	for y in range(start_y + 1, start_y + size_y - 1):
		set_tile(start_x, y, Tile.Wall)
		set_tile(start_x + size_x - 1, y, Tile.Wall)
		
		for x in range(start_x + 1, start_x + size_x - 1):
			set_tile(x, y, Tile.Floor)
	
	cut_regions(freeRegions, room)

func cut_regions(freeRegions, regionToRemove):
	var removalQueue = []
	var additionQueue = []
	
	for region in freeRegions:
		if region.intersects(regionToRemove):
			removalQueue.append(region)
			
			var leftoverLeft = regionToRemove.position.x - region.position.x - 1
			var leftoverRight = region.end.x - regionToRemove.end.x - 1
			var leftoverAbove = regionToRemove.position.y - region.position.y - 1
			var leftoverBelow = region.end.y - regionToRemove.end.y - 1
			
			if leftoverLeft >= MIN_ROOM_SIZE:
				additionQueue.append(Rect2(region.position, Vector2(leftoverLeft, region.size.y)))
			if leftoverRight >= MIN_ROOM_SIZE:
				additionQueue.append(Rect2(Vector2(regionToRemove.end.x + 1, region.position.y), Vector2(leftoverRight, region.size.y)))
			if leftoverAbove >= MIN_ROOM_SIZE:
				additionQueue.append(Rect2(region.position, Vector2(region.size.x, leftoverAbove)))
			if leftoverBelow >= MIN_ROOM_SIZE:
				additionQueue.append(Rect2(Vector2(region.position.x, regionToRemove.end.y + 1), Vector2(region.size.x, leftoverBelow)))
			
	
	for region in removalQueue:
		freeRegions.erase(region)
	for region in additionQueue:
		freeRegions.append(region)

func set_tile(x, y, type):
	map[x][y] = type
	tileMap.set_cell(x, y, type)
