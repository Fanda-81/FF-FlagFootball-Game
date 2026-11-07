# COORDINATE_SYSTEM.md — 球场坐标系统

## 唯一换算
```
yards = world_z + 10
world_z = yards - 10
```
- 实现：`scripts/rules/game_manager.gd`
  - `world_to_field_yards(world_z)`
  - `field_yards_to_world(yards)`
- **禁止**在其它脚本里另行换算。

## 球场范围
| 项 | 逻辑码数 | 世界 Z |
|---|---|---|
| 场地起点（蓝底线） | 0 | -10 |
| 蓝方达阵线 | 10 | 0 |
| 中场 | 35 | 25 |
| 红方达阵线 | 60 | 50 |
| 场地终点（红底线） | 70 | 60 |

## 进攻方向
- 蓝方 `+1`：码数增大，朝向红方端区
- 红方 `-1`：码数减小，朝向蓝方端区
- 取法：`GameManager.get_attacking_direction()`

## 首攻目标线
```
target_line_for(team, yards):
  蓝方：yards >= 35 ? 60 : 35
  红方：yards <= 35 ? 10 : 35
```
- 第一阶段目标 = 35（中场）
- 第二阶段目标 = 对方达阵线（蓝 60 / 红 10）

## 方向相关的硬编码（已修）
- QB 后撤：`z - DROPBACK_YARDS * _attack_dir`（曾写死 −Z，红方会撞向防守）
- 持球人跑向端区：`goal_z = 55 if dir > 0 else -5`
- 抄截回攻目标：`return_dir = -_attack_dir`
- 防守方合法一侧：`defender_los_z()` 按方向取 ±0.15
- WASD / 摇杆：屏幕方向映射，攻防转换后 180° 翻转

## 相机契约
- 俯视：屏幕上方 = +Z，屏幕右方 = **−X**
- 攻防转换后相机绕视线轴旋转 180°，屏幕方向整体反向
- 球场文字（END ZONE / 码数）随之双轴镜像

## 码数显示
- `yards_to_go_from(team, ball_yards, target)`：方向感知、`ceil(x - 0.001)`、越线返回 0
- HUD 与调试面板**必须**共用这一个函数