extends RefCounted
class_name OutfitCatalog
## 服装目录：分类定义 + 每个分类下可选的服装。
##
## 换装逻辑（装备/卸下/改色/存档）都不在这里，这里**只有数据**。
## 想加一件新衣服：在对应分类的数组里加一行 `OutfitItem.create(...)`。
##
## 当前模型的网格（Skeleton3D 下）：
##   Cube（身体）、上衣抹胸、短袖、短裤、网格002、网格002_1、鞋子、手套、头发01

const CATEGORIES := [
	{"id": "shirt", "label": "上衣"},
	{"id": "pants", "label": "裤子"},
	{"id": "shoes", "label": "鞋子"},
	{"id": "hair", "label": "头发"},
	{"id": "hat", "label": "帽子"},
	{"id": "accessory", "label": "配饰"},
	{"id": "skin", "label": "肤色"},
]

## 身体网格，永远显示，不属于任何分类。
const BODY_MESHES := ["Cube"]


static func category_label(category: String) -> String:
	for entry in CATEGORIES:
		if String(entry["id"]) == category:
			return String(entry["label"])
	return category


static func category_ids() -> Array:
	var ids: Array = []
	for entry in CATEGORIES:
		ids.append(String(entry["id"]))
	return ids


## 构建目录：分类 id -> Array[OutfitItem]
static func build() -> Dictionary:
	var catalog := {}

	catalog["shirt"] = [
		OutfitItem.create("shirt_home", "主场球衣", "shirt",
			["上衣抹胸", "短袖"], Color("2f7cf6"), true, "带袖"),
		OutfitItem.create("shirt_away", "客场球衣", "shirt",
			["上衣抹胸"], Color("f2f5fa"), true, "无袖"),
		OutfitItem.create("shirt_training", "训练背心", "shirt",
			["短袖"], Color("ffb03a"), true, "只有袖子"),
	]

	catalog["pants"] = [
		OutfitItem.create("pants_short", "比赛短裤", "pants",
			["短裤", "网格002", "网格002_1"], Color("1d2430"), true),
		OutfitItem.create("pants_skin", "紧身裤", "pants",
			["网格002", "网格002_1"], Color("39424f"), true),
	]

	catalog["shoes"] = [
		OutfitItem.create("shoes_cleat", "钉鞋", "shoes",
			["鞋子"], Color("f2f5fa"), true),
		OutfitItem.create("shoes_dark", "黑色球鞋", "shoes",
			["鞋子"], Color("23262b"), true),
	]

	catalog["hair"] = [
		OutfitItem.create("hair_long", "长发", "hair",
			["头发01"], Color("2a1d16"), true),
		OutfitItem.create("hair_ash", "亚麻色长发", "hair",
			["头发01"], Color("b98a4c"), true),
	]

	# 当前模型没有帽子网格，分类保留但暂无内容（UI 会显示"暂无"）。
	catalog["hat"] = []

	# 肤色：改的是整个躯干（Cube）的颜色
	catalog["skin"] = [
		OutfitItem.create("skin_light", "浅肤色", "skin", ["Cube"], Color("e8b98d"), true),
		OutfitItem.create("skin_tan", "小麦色", "skin", ["Cube"], Color("c98f63"), true),
		OutfitItem.create("skin_dark", "深肤色", "skin", ["Cube"], Color("8d5a3b"), true),
	]

	catalog["accessory"] = [
		OutfitItem.create("acc_gloves", "接球手套", "accessory",
			["手套"], Color("e2543f"), true),
		OutfitItem.create("acc_gloves_white", "白色手套", "accessory",
			["手套"], Color("f4ead7"), true),
	]

	return catalog
