extends RefCounted
class_name OutfitCatalog
## 服装目录：分类定义 + 每个分类下可选的服装（morra.glb，25 骨）
##
## 网格：Cube（身体）、上衣抹胸、短袖、短裤、Left_Boot/Left_Stud_Tips、
## Right_Boot/Right_Stud_Tips、长袜主色/长袜副色、左侧腰旗/右侧腰旗、手套、头发01

const CATEGORIES := [
	{"id": "shirt", "label": "上衣"},
	{"id": "pants", "label": "裤子"},
	{"id": "shoe_l", "label": "左鞋"},
	{"id": "shoe_r", "label": "右鞋"},
	{"id": "socks", "label": "球袜"},
	{"id": "flag", "label": "腰旗"},
	{"id": "hair", "label": "头发"},
	{"id": "accessory", "label": "手套"},
	{"id": "skin", "label": "肤色"},
]

const BODY_MESHES := ["Cube"]
const FLAG_MESHES := ["左侧腰旗", "右侧腰旗"]


static func category_label(category: String) -> String:
	if category == "full":
		return "全身"
	for entry in CATEGORIES:
		if String(entry["id"]) == category:
			return String(entry["label"])
	return category


static func category_ids() -> Array:
	var ids: Array = []
	for entry in CATEGORIES:
		ids.append(String(entry["id"]))
	return ids


static func build() -> Dictionary:
	var catalog := {}

	catalog["shirt"] = [
		OutfitItem.create("shirt_home", "主场球衣", "shirt", ["上衣抹胸", "短袖"], Color("2f7cf6"), true, "带袖"),
		OutfitItem.create("shirt_away", "客场球衣", "shirt", ["上衣抹胸"], Color("f2f5fa"), true, "无袖"),
		OutfitItem.create("shirt_training", "训练背心", "shirt", ["短袖"], Color("ffb03a"), true, "只有袖子"),
	]

	catalog["pants"] = [
		OutfitItem.create("pants_match", "比赛短裤", "pants", ["短裤"], Color("1d2430"), true),
		OutfitItem.create("pants_white", "白色短裤", "pants", ["短裤"], Color("eef2f7"), true),
	]

	catalog["shoe_l"] = [
		OutfitItem.create("shoe_l_white", "左·白钉鞋", "shoe_l", ["Left_Boot", "Left_Stud_Tips"], Color("f2f5fa"), true),
		OutfitItem.create("shoe_l_dark", "左·黑钉鞋", "shoe_l", ["Left_Boot", "Left_Stud_Tips"], Color("23262b"), true),
		OutfitItem.create("shoe_l_red", "左·红钉鞋", "shoe_l", ["Left_Boot", "Left_Stud_Tips"], Color("d9333f"), true),
	]
	catalog["shoe_r"] = [
		OutfitItem.create("shoe_r_white", "右·白钉鞋", "shoe_r", ["Right_Boot", "Right_Stud_Tips"], Color("f2f5fa"), true),
		OutfitItem.create("shoe_r_dark", "右·黑钉鞋", "shoe_r", ["Right_Boot", "Right_Stud_Tips"], Color("23262b"), true),
		OutfitItem.create("shoe_r_red", "右·红钉鞋", "shoe_r", ["Right_Boot", "Right_Stud_Tips"], Color("d9333f"), true),
	]

	catalog["socks"] = [
		OutfitItem.create("socks_white", "白球袜", "socks", ["长袜主色", "长袜副色"], Color("f4f7fb"), true),
		OutfitItem.create("socks_dark", "黑球袜", "socks", ["长袜主色", "长袜副色"], Color("23262b"), true),
	]

	catalog["flag"] = [
		OutfitItem.create("flag_red", "红腰旗", "flag", ["左侧腰旗", "右侧腰旗"], Color("e2543f"), true),
		OutfitItem.create("flag_yellow", "黄腰旗", "flag", ["左侧腰旗", "右侧腰旗"], Color("ffd84b"), true),
	]

	catalog["hair"] = [
		OutfitItem.create("hair_dark", "黑长发", "hair", ["头发01"], Color("2a1d16"), true),
		OutfitItem.create("hair_ash", "亚麻长发", "hair", ["头发01"], Color("b98a4c"), true),
	]

	catalog["accessory"] = [
		OutfitItem.create("acc_gloves", "接球手套", "accessory", ["手套"], Color("e2543f"), true),
		OutfitItem.create("acc_gloves_white", "白色手套", "accessory", ["手套"], Color("f4ead7"), true),
	]

	catalog["skin"] = [
		OutfitItem.create("skin_light", "浅肤色", "skin", ["Cube"], Color("e8b98d"), true),
		OutfitItem.create("skin_tan", "小麦色", "skin", ["Cube"], Color("c98f63"), true),
		OutfitItem.create("skin_dark", "深肤色", "skin", ["Cube"], Color("8d5a3b"), true),
	]

	return catalog