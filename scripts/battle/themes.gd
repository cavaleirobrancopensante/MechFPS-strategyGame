extends RefCounted
## Looks for battle zones: sky, light, colours, weather, map layout and
## props. Each mission picks one from its seed, so zones look different.

const THEMES := [
	{
		"id": "coast_dawn", "name": "Coastal Ruins · Dawn", "layout": "ruins", "weather": "none",
		"sky_top": Color(0.04, 0.02, 0.09), "sky_horizon": Color(0.5, 0.2, 0.16), "stars": 1.0, "planet": true,
		"ridge_far": Color(0.24, 0.1, 0.13), "ridge_near": Color(0.15, 0.06, 0.09), "fog": Color(0.24, 0.12, 0.13),
		"ground_far": Color(0.26, 0.14, 0.12), "ground_near": Color(0.13, 0.09, 0.08), "ground_top": Color(0.27, 0.15, 0.13),
		"walls": {"empty": Color(0.38, 0.25, 0.2), "ruin": Color(0.58, 0.52, 0.45), "metal": Color(0.42, 0.48, 0.56), "organic": Color(0.55, 0.2, 0.42), "platform": Color(0.5, 0.5, 0.53), "rubble": Color(0.42, 0.37, 0.33)},
		"platform_top": Color(0.36, 0.36, 0.39), "window": Color(0.06, 0.04, 0.05), "lit": 0.0,
		"tint": Color(1, 1, 1), "props": ["rock", "rock", "crystal", "barrel"], "prop_density": 1.0,
	},
	{
		"id": "rain_city", "name": "Drowned City · Night Rain", "layout": "town", "weather": "rain",
		"sky_top": Color(0.01, 0.02, 0.05), "sky_horizon": Color(0.1, 0.13, 0.22), "stars": 0.2, "planet": true,
		"ridge_far": Color(0.07, 0.08, 0.13), "ridge_near": Color(0.04, 0.05, 0.08), "fog": Color(0.07, 0.09, 0.15),
		"ground_far": Color(0.12, 0.13, 0.17), "ground_near": Color(0.06, 0.06, 0.08), "ground_top": Color(0.14, 0.15, 0.19),
		"walls": {"empty": Color(0.2, 0.2, 0.24), "ruin": Color(0.36, 0.38, 0.45), "metal": Color(0.28, 0.33, 0.4), "organic": Color(0.5, 0.15, 0.5), "platform": Color(0.38, 0.38, 0.44), "rubble": Color(0.28, 0.28, 0.32)},
		"platform_top": Color(0.22, 0.23, 0.28), "window": Color(0.04, 0.05, 0.08), "lit": 0.4,
		"tint": Color(0.72, 0.78, 0.98), "props": ["car", "car", "barrel", "rock"], "prop_density": 1.2,
	},
	{
		"id": "quarry_noon", "name": "Sunlit Quarry · Noon", "layout": "quarry", "weather": "dust",
		"sky_top": Color(0.22, 0.42, 0.78), "sky_horizon": Color(0.78, 0.84, 0.9), "stars": 0.0, "planet": true,
		"ridge_far": Color(0.62, 0.55, 0.5), "ridge_near": Color(0.55, 0.45, 0.36), "fog": Color(0.72, 0.7, 0.64),
		"ground_far": Color(0.68, 0.54, 0.38), "ground_near": Color(0.5, 0.38, 0.25), "ground_top": Color(0.66, 0.52, 0.36),
		"walls": {"empty": Color(0.6, 0.46, 0.3), "ruin": Color(0.8, 0.68, 0.5), "metal": Color(0.55, 0.52, 0.48), "organic": Color(0.6, 0.25, 0.42), "platform": Color(0.72, 0.7, 0.64), "rubble": Color(0.62, 0.55, 0.45)},
		"platform_top": Color(0.62, 0.6, 0.55), "window": Color(0.25, 0.18, 0.12), "lit": 0.0,
		"tint": Color(1.05, 1.0, 0.94), "props": ["rock", "rock", "barrel", "car"], "prop_density": 1.0,
	},
	{
		"id": "snow_village", "name": "Snowbound Village · Overcast", "layout": "village", "weather": "snow",
		"sky_top": Color(0.5, 0.55, 0.64), "sky_horizon": Color(0.86, 0.88, 0.92), "stars": 0.0, "planet": false,
		"ridge_far": Color(0.7, 0.73, 0.78), "ridge_near": Color(0.58, 0.62, 0.68), "fog": Color(0.82, 0.84, 0.88),
		"ground_far": Color(0.88, 0.9, 0.94), "ground_near": Color(0.72, 0.75, 0.8), "ground_top": Color(0.9, 0.92, 0.96),
		"walls": {"empty": Color(0.78, 0.8, 0.85), "ruin": Color(0.55, 0.5, 0.47), "metal": Color(0.4, 0.42, 0.47), "organic": Color(0.55, 0.2, 0.45), "platform": Color(0.6, 0.6, 0.64), "rubble": Color(0.5, 0.48, 0.46)},
		"platform_top": Color(0.85, 0.87, 0.9), "window": Color(0.12, 0.1, 0.1), "lit": 0.25,
		"tint": Color(0.95, 0.98, 1.06), "props": ["pine", "pine", "pine", "rock"], "prop_density": 1.6,
	},
	{
		"id": "bog_forest", "name": "Bog Forest · Dusk Mist", "layout": "forest", "weather": "fireflies",
		"sky_top": Color(0.12, 0.08, 0.22), "sky_horizon": Color(0.85, 0.45, 0.3), "stars": 0.5, "planet": true,
		"ridge_far": Color(0.2, 0.18, 0.2), "ridge_near": Color(0.1, 0.13, 0.08), "fog": Color(0.32, 0.3, 0.3),
		"ground_far": Color(0.2, 0.26, 0.13), "ground_near": Color(0.08, 0.12, 0.06), "ground_top": Color(0.22, 0.28, 0.14),
		"walls": {"empty": Color(0.24, 0.2, 0.12), "ruin": Color(0.45, 0.33, 0.22), "metal": Color(0.35, 0.37, 0.33), "organic": Color(0.5, 0.18, 0.4), "platform": Color(0.45, 0.45, 0.42), "rubble": Color(0.35, 0.28, 0.2)},
		"platform_top": Color(0.3, 0.32, 0.28), "window": Color(0.08, 0.06, 0.04), "lit": 0.1,
		"tint": Color(0.98, 0.9, 0.85), "props": ["tree", "tree", "pine", "pine", "rock"], "prop_density": 2.6,
	},
	{
		"id": "docks_smog", "name": "Industrial Docks · Smog", "layout": "industrial", "weather": "ash",
		"sky_top": Color(0.3, 0.33, 0.18), "sky_horizon": Color(0.72, 0.66, 0.36), "stars": 0.0, "planet": true,
		"ridge_far": Color(0.4, 0.38, 0.26), "ridge_near": Color(0.26, 0.25, 0.18), "fog": Color(0.5, 0.48, 0.3),
		"ground_far": Color(0.42, 0.41, 0.38), "ground_near": Color(0.24, 0.24, 0.23), "ground_top": Color(0.42, 0.42, 0.4),
		"walls": {"empty": Color(0.35, 0.35, 0.33), "ruin": Color(0.56, 0.56, 0.53), "metal": Color(0.58, 0.33, 0.2), "organic": Color(0.5, 0.2, 0.4), "platform": Color(0.5, 0.5, 0.48), "rubble": Color(0.42, 0.4, 0.37)},
		"platform_top": Color(0.45, 0.45, 0.43), "window": Color(0.1, 0.1, 0.08), "lit": 0.05,
		"tint": Color(1.0, 0.95, 0.82), "props": ["barrel", "barrel", "car", "rock"], "prop_density": 1.4,
	},
	{
		"id": "infested", "name": "Infested Zone · Alien Night", "layout": "ruins", "weather": "spores",
		"sky_top": Color(0.07, 0.01, 0.1), "sky_horizon": Color(0.38, 0.08, 0.35), "stars": 0.6, "planet": true,
		"ridge_far": Color(0.18, 0.04, 0.18), "ridge_near": Color(0.1, 0.02, 0.1), "fog": Color(0.2, 0.05, 0.22),
		"ground_far": Color(0.22, 0.08, 0.2), "ground_near": Color(0.08, 0.03, 0.08), "ground_top": Color(0.24, 0.1, 0.22),
		"walls": {"empty": Color(0.3, 0.15, 0.28), "ruin": Color(0.42, 0.34, 0.4), "metal": Color(0.32, 0.3, 0.42), "organic": Color(0.72, 0.2, 0.58), "platform": Color(0.42, 0.38, 0.46), "rubble": Color(0.35, 0.25, 0.32)},
		"platform_top": Color(0.3, 0.25, 0.33), "window": Color(0.08, 0.02, 0.08), "lit": 0.0,
		"tint": Color(0.92, 0.8, 1.0), "props": ["crystal", "crystal", "rock"], "prop_density": 1.4, "organic_extra": true,
	},
]


static func pick(seed_value: int) -> Dictionary:
	return THEMES[posmod(seed_value, THEMES.size())]
