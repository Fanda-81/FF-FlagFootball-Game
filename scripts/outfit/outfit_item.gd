extends Resource
class_name OutfitItem
## 一件服装 / 配饰的数据定义。
##
## 目前角色是"一个模型里自带多块网格"的形式，所以用 mesh_names 指向角色 Skeleton3D
## 下的 MeshInstance3D 节点名；以后换成独立的服装 GLB 时，只要把 mesh_names 换成
## 那套网格的节点名，其余逻辑不用动。

@export var id: String = ""
@export var display_name: String = ""
## 分类：shirt / pants / shoes / hair / hat / accessory
@export var category: String = ""
## 这件服装用到的网格节点名（可以多块，比如球衣 = 上衣 + 短袖）
@export var mesh_names: PackedStringArray = PackedStringArray()
## 默认颜色（穿上时自动应用）
@export var default_color: Color = Color("8a8f98")
## 是否允许玩家改颜色
@export var color_editable: bool = true
## 缩略图（留空时 UI 用色块代替）
@export var thumbnail: Texture2D = null
## 备注，UI 上可以显示成小字
@export var note: String = ""


static func create(p_id: String, p_name: String, p_category: String, p_meshes: Array,
		p_color: Color, p_editable := true, p_note := "") -> OutfitItem:
	var item := OutfitItem.new()
	item.id = p_id
	item.display_name = p_name
	item.category = p_category
	item.mesh_names = PackedStringArray(p_meshes)
	item.default_color = p_color
	item.color_editable = p_editable
	item.note = p_note
	return item
