extends RefCounted
## FF · 传球参数（原样搬自 FFSIMU `football_pass_tuning.gd`）
##
## 平传和短传用 30 m/s 的平直球速，高球用 20 m/s 的吊球球速；
## 滞空时间按距离换算后夹在 0.55–2.2 秒之间。
## 这两个数决定了同样的距离下"高球明显更慢、弧线更高"，也是 FFSIMU 手感的核心。

const FLAT_TRAVEL_SPEED := 30.0
const HIGH_TRAVEL_SPEED := 20.0
const MIN_FLIGHT_TIME := 0.55
const MAX_FLIGHT_TIME := 2.2


static func flight_time(distance: float, high_ball: bool) -> float:
	var speed := HIGH_TRAVEL_SPEED if high_ball else FLAT_TRAVEL_SPEED
	return clampf(distance / speed, MIN_FLIGHT_TIME, MAX_FLIGHT_TIME)
