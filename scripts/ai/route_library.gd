extends RefCounted
class_name RouteLibrary
## 标准接球路线库：每条路线生成一串世界坐标路径点。
##
## 约定：
##   · start = 接球手起跑位置（世界坐标）
##   · direction = +1 朝 +Z 进攻，-1 朝 -Z 进攻
##   · 返回的点已经夹在白色边线以内
##   · 队员沿点依次跑，最后一段跑完后由 main 的自由跑逻辑接管

const MIN_X := -12.6
const MAX_X := 12.6

const ROUTES := [
	"go", "slant", "out", "in", "curl", "post", "corner", "drag", "short_out",
]

const LABELS := {
	"go": "Go 直线纵深",
	"slant": "Slant 斜插",
	"out": "Out 外切",
	"in": "In 内切",
	"curl": "Curl 回身",
	"post": "Post 后柱",
	"corner": "Corner 角柱",
	"drag": "Drag 横穿",
	"short_out": "短出线",
}


static func has_route(route_id: String) -> bool:
	return ROUTES.has(route_id)


## 生成路线点（世界坐标）
static func build(route_id: String, start: Vector3, direction: float) -> Array:
	var offsets: Array = _offsets(route_id)
	var points: Array = []
	for offset in offsets:
		var point := Vector3(
			clampf(start.x + float(offset.x) * direction, MIN_X, MAX_X),
			0.0,
			start.z + float(offset.y) * direction)
		points.append(point)
	return points


## 路线的相对偏移（x = 横向，y = 向前的码数）
static func _offsets(route_id: String) -> Array:
	match route_id:
		"go":
			return [Vector2(0.0, 9.0), Vector2(0.0, 18.0), Vector2(0.0, 27.0)]
		"slant":
			return [Vector2(0.0, 4.5), Vector2(1.6, 8.0), Vector2(3.4, 11.5)]
		"out":
			return [Vector2(0.0, 6.0), Vector2(0.4, 10.0), Vector2(4.5, 10.5)]
		"in":
			return [Vector2(0.0, 7.0), Vector2(-0.3, 11.0), Vector2(-5.0, 12.0)]
		"curl":
			return [Vector2(0.0, 8.0), Vector2(0.0, 12.0), Vector2(0.0, 7.5)]
		"post":
			return [Vector2(0.0, 9.0), Vector2(0.3, 14.0), Vector2(-6.5, 21.0)]
		"corner":
			return [Vector2(0.0, 9.0), Vector2(-0.6, 14.0), Vector2(5.5, 20.0)]
		"drag":
			return [Vector2(0.0, 3.0), Vector2(-4.0, 4.0), Vector2(-12.0, 5.0)]
		"short_out":
			return [Vector2(0.0, 2.0), Vector2(1.6, 4.0), Vector2(3.6, 5.0)]
		_:
			return [Vector2(0.0, 8.0), Vector2(0.0, 16.0)]
