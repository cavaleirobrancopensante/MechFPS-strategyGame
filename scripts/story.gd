extends RefCounted
## All the writing in the game: the cast, the 12 story missions, side
## operations, radio chatter and life at the Rock. See STORY.md.
## Edit freely: everything else reads from here.

const CAST := {
	"quill": {"name": "Cmdr. Quill", "role": "Commander", "color": Color(0.55, 0.75, 1.0)},
	"anselm": {"name": "Br. Anselm", "role": "Keeper of the Rock", "color": Color(1.0, 0.85, 0.45)},
	"mags": {"name": "Mags", "role": "Chief Engineer", "color": Color(1.0, 0.6, 0.3)},
	"sandoval": {"name": "Dr. Sandoval", "role": "Xenobiologist", "color": Color(0.6, 1.0, 0.5)},
	"rafa": {"name": "Rafa", "role": "Dropship Pilot", "color": Color(0.5, 0.95, 0.95)},
	"pip": {"name": "Pip", "role": "Radio & Drones", "color": Color(1.0, 0.6, 0.85)},
	"wren": {"name": "Wren", "role": "Pilot (you)", "color": Color(0.45, 1.0, 0.65)},
}

## Mission types: destroy, rescue, retrieve, survive, scout, boss.
const STORY_MISSIONS := [
	# ---------------- Act I: Landfall ----------------
	{
		"act": 1, "title": "First Drop", "zone": "Carrick Point", "type": "destroy", "hives": 1,
		"diff": 1, "fuel": 1, "reward": {"scrap": 25, "circuits": 3},
		"briefing": [
			["quill", "Morning, Wren. A seed came down at Carrick Point last night. It's already singing."],
			["mags", "Brigid's patched, fuelled and loaded. Bring her back with both arms, please."],
			["rafa", "I'll drop you, you burn the hive, you walk to the flare, I pick you up. Easy."],
		],
		"debrief": [
			["anselm", "One bell for the Gannet, one for Rafa, one for you. Welcome home, Wren. There's soup."],
			["quill", "First hive in this region to go quiet. Let's make it a habit."],
		],
	},
	{
		"act": 1, "title": "Lights in Kilbride", "zone": "Kilbride Harbour", "type": "rescue", "rescue": 3, "hives": 1,
		"diff": 1, "fuel": 1, "reward": {"scrap": 15},
		"briefing": [
			["pip", "Someone's flashing a torch in Kilbride. Morse. It says 'three of us, cellars, please'."],
			["quill", "The cellars are too tight for Brigid. You'll have to climb out and go in on foot."],
			["mags", "Park her somewhere sensible. And lock the hatch. Habit."],
		],
		"debrief": [
			["anselm", "Three more at the table tonight. I'll make the good bread."],
			["quill", "They can work. We'll find them bunks. Every pair of hands matters now."],
		],
	},
	{
		"act": 1, "title": "Dry Tanks", "zone": "Shannonmouth Depot", "type": "retrieve", "items": 4, "item_kind": "fuel",
		"diff": 2, "fuel": 1, "reward": {"fuel": 6, "scrap": 10},
		"briefing": [
			["rafa", "Bad news: the Gannet drinks fuel like I drink coffee. Good news: there's a depot."],
			["quill", "Four intact canisters at Shannonmouth. Climb out, carry them to the Chest, and we'll winch it all up."],
			["sandoval", "If you see anything unusual in the hives there, I want a description. A detailed one."],
		],
		"debrief": [
			["rafa", "Full tanks! I could kiss you. I won't. But I could."],
			["mags", "Build Sandoval his bioreactor and we'll never have to raid a depot again."],
		],
	},
	{
		"act": 1, "title": "Hold the Ridge", "zone": "Slievecarn Ridge", "type": "survive", "waves": 3,
		"diff": 2, "fuel": 1, "reward": {"scrap": 30, "circuits": 2},
		"briefing": [
			["rafa", "Uh. The Gannet's port engine just coughed up a bird. I can drop you, but pickup is going to take a while."],
			["quill", "Hold the ridge until Rafa's back. The Swarm will come in waves. Don't let them corner you."],
			["anselm", "I'll ring the bell when you're home. Make sure I get to."],
		],
		"debrief": [
			["rafa", "Engine's fixed, mostly. Thanks for not dying while I was gone."],
			["pip", "The way they came at you... they were organised. Waves. That's not animal behaviour."],
		],
	},
	# ---------------- Act II: The Singing ----------------
	{
		"act": 2, "title": "Echo Stations", "zone": "Ballymor Heights", "type": "scout", "beacons": 3, "hives": 1,
		"diff": 3, "fuel": 1, "reward": {"circuits": 8, "scrap": 10},
		"briefing": [
			["pip", "I think the hives are talking to each other. I can hear it in the static, but I need ears closer to them."],
			["pip", "There are three old relay masts on Ballymor Heights. Stand by each one until it's online."],
			["quill", "Pip's hunches have kept us alive twice. Go."],
		],
		"debrief": [
			["pip", "It's a song. An actual song, passed hive to hive. And it all points the same way: inland."],
			["sandoval", "Fascinating. Horrifying. Mostly fascinating."],
		],
	},
	{
		"act": 2, "title": "Sandoval's Sample", "zone": "Lough Derra Shore", "type": "destroy", "hives": 2,
		"diff": 3, "fuel": 2, "reward": {"biomass": 30, "circuits": 4},
		"briefing": [
			["sandoval", "I need hive tissue. Lots of it. Kill two hives, put on the hazmat suit and cut out what's left. Bring it back in the Chest."],
			["mags", "He means it as a compliment, Wren. He thinks you're a very good blender."],
			["quill", "Two hives on the lough shore. Brutes reported. Watch your armour."],
		],
		"debrief": [
			["sandoval", "Oh, these cells are wonderful. They burn hotter than diesel. We can make fuel from them!"],
			["anselm", "He was dancing in the chapel. I've asked him not to do that in the infirmary."],
		],
	},
	{
		"act": 2, "title": "The Choir Grows", "zone": "Old Ennistown", "type": "survive", "waves": 5,
		"diff": 4, "fuel": 1, "reward": {"scrap": 40, "circuits": 4},
		"briefing": [
			["pip", "The song changed. They're massing on Ennistown, and there are people in the church crypt."],
			["quill", "We'll get the civilians out by boat. You keep the Swarm busy until Rafa can lift you."],
			["rafa", "Five waves, they reckon. I'll bring snacks."],
		],
		"debrief": [
			["quill", "Twenty-two civilians made the boats. Because you held. I wrote it on the wall."],
			["anselm", "The bunks are full. I've started a list of who snores."],
		],
	},
	{
		"act": 2, "title": "Lost Shepherds", "zone": "Glenbeigh Valley", "type": "rescue", "rescue": 5, "hives": 1,
		"diff": 4, "fuel": 2, "reward": {"scrap": 20},
		"briefing": [
			["pip", "Drone spotted five survivors hiding in farm bunkers up the valley. They've got kids' drawings taped on the doors."],
			["mags", "Doorways too narrow for Brigid again. You know the drill."],
			["quill", "Bring them home, Wren."],
		],
		"debrief": [
			["anselm", "The children have named a beehive after you. It is the angriest beehive."],
			["quill", "That's thirty souls on the Rock now. We're not just surviving any more. We're a town."],
		],
	},
	# ---------------- Act III: The Brood Mother ----------------
	{
		"act": 3, "title": "Silence the Spires", "zone": "Ardnacrusha Dam", "type": "destroy", "hives": 3,
		"diff": 5, "fuel": 2, "reward": {"scrap": 35, "circuits": 6, "biomass": 20},
		"briefing": [
			["pip", "Three hives around the dam are relaying the song inland. Take them out and the signal breaks."],
			["sandoval", "Then we'll hear where it's coming from. The source. The mother."],
			["quill", "Three hives, heavy resistance. Load every rocket Mags can spare."],
		],
		"debrief": [
			["pip", "The relay's broken, and something big answered. Something very big, far inland."],
			["mags", "Brigid took a beating. Give me a day with her."],
		],
	},
	{
		"act": 3, "title": "Black Box", "zone": "Flight 1171 Crash Site", "type": "retrieve", "items": 5, "item_kind": "data",
		"diff": 5, "fuel": 2, "reward": {"circuits": 12},
		"briefing": [
			["quill", "An airliner went down on the first night. Its flight recorders filmed the seed falls. All of them."],
			["pip", "Five data cores scattered across the crash site. Get them all and I can triangulate the mother."],
			["rafa", "Don't drop anything. Especially not yourself."],
		],
		"debrief": [
			["pip", "Got it. The Brood Mother is in the old quarry at Moher Gap. It's huge. It's... growing."],
			["quill", "Then that's where this ends."],
		],
	},
	{
		"act": 3, "title": "Long Night", "zone": "Moher Gap Approach", "type": "survive", "waves": 7,
		"diff": 6, "fuel": 1, "reward": {"scrap": 50, "circuits": 6},
		"briefing": [
			["quill", "Before we hit the mother, we need a forward fuel cache at Moher Gap. Someone has to hold it all night."],
			["anselm", "I've packed you sandwiches. Wren. Eat them between the waves."],
			["rafa", "Seven waves. I'll be overhead the whole time. Mostly."],
		],
		"debrief": [
			["mags", "Brigid's got more patches than paint now. She's beautiful."],
			["quill", "Tomorrow we go for the mother. Get some sleep. That's an order."],
		],
	},
	{
		"act": 3, "title": "Brood Mother", "zone": "Moher Gap Quarry", "type": "boss", "hives": 2,
		"diff": 7, "fuel": 2, "reward": {"scrap": 60, "circuits": 10, "biomass": 60},
		"briefing": [
			["sandoval", "The Brood Mother feeds every hive in the region. Kill it and the song here stops."],
			["pip", "Two guard hives around it. Take them out or they'll keep feeding it."],
			["quill", "Everyone on the Rock is listening, Wren. Bring Brigid home."],
			["anselm", "The bell rope is in my hand. I'm waiting to ring it."],
		],
		"debrief": [
			["pip", "It's quiet. The whole region is quiet. I can't hear the Choir. I can hear birds."],
			["anselm", "The bell is rung, and rung, and rung. Welcome home, Wren."],
			["quill", "The Lantern's still up there. There are other regions, other mothers. But tonight, we eat."],
		],
	},
]

const ENDING := [
	["quill", "Operations continue. The Rock stands. Pick your fights from the map room."],
]

## Side operations: generated, with briefings filled from these.
const ZONES := [
	"Kilmona Crossroads", "Rathbeg Quarry", "Dunmore Pier", "Clonard Bog", "Ballinmore Rail Yard",
	"Lisdoon Ferry Port", "Castlegar Ruins", "Inchmore Wind Farm", "Ardmore Barracks", "Killeen Airstrip",
	"Tullagh Market", "Barna Water Works", "Knockroe Pass", "Derreen Forest", "Mullagh Motorway",
]

const SIDE_TEXT := {
	"destroy": {
		"titles": ["Burn the Nest", "Seed Fall", "Quiet the Choir", "Hive Sweep"],
		"briefing": [
			["pip", "New hives at {zone}. They're loud. Make them quiet."],
			["quill", "Hives at {zone} are threatening our salvage routes. Burn them."],
		],
	},
	"rescue": {
		"titles": ["Survivors at {zone}", "Signal Fire", "Cellar Voices"],
		"briefing": [
			["pip", "Drone saw survivors holed up at {zone}. Tight bunkers, so you'll go in on foot."],
			["anselm", "There are people waiting at {zone}. We have soup and bunks. Go and get them."],
		],
	},
	"retrieve": {
		"titles": ["Salvage Run", "Supply Drop", "Lost Cargo"],
		"briefing": [
			["mags", "Supply crates scattered around {zone}. I want everything you can find."],
			["rafa", "A convoy dumped its cargo at {zone} when the Swarm hit. Finders keepers."],
		],
	},
	"survive": {
		"titles": ["Hold the Line", "Last Stand", "Waiting for the Gannet"],
		"briefing": [
			["quill", "We need {zone} held while the boats evacuate. Survive until Rafa can lift you."],
			["rafa", "Bad weather over {zone}. I'll drop you, but pickup needs time. Stay alive till then."],
		],
	},
	"scout": {
		"titles": ["Relay Repair", "Ears in the Static", "Beacon Line"],
		"briefing": [
			["pip", "Old relay beacons around {zone}. Light them up and our maps get better."],
		],
	},
	"patrol": {
		"titles": ["Coast Patrol"],
		"briefing": [
			["rafa", "Short hop to the coast, barely costs a drop of fuel. One small hive. Easy pickings."],
		],
	},
}

## Radio lines during battle. Picked at random.
const RADIO := {
	"drop": [
		["rafa", "Green light! Out you go, Wren!"],
		["rafa", "Dropping in three... two... enjoy the fall!"],
		["rafa", "Hold onto something. Brigid lands heavy."],
	],
	"objective_done": [
		["quill", "That's the job done. Get to the landing zone, Wren."],
		["pip", "Objective complete! Flare's lit. Head for the green light."],
	],
	"extract_inbound": [
		["rafa", "I see your flare. Coming in. Keep them off my landing pad!"],
		["rafa", "Gannet inbound. Stay in the circle, Wren."],
	],
	"extracted": [
		["rafa", "Got you! Holding on? Good. Going home."],
	],
	"foot": [
		["mags", "You left her standing alone out there? Be quick."],
		["mags", "Lock the hatch. And don't get eaten, I'd have to train a new pilot."],
	],
	"low_armor": [
		["mags", "Brigid's hull is screaming, Wren! Get out of there!"],
	],
	"no_ammo": [
		["mags", "You're dry! Find an ammo crate or switch weapons!"],
	],
	"wave": [
		["pip", "Here comes another wave!"],
		["pip", "Movement on every side. Wave incoming!"],
	],
	"rescue": [
		["anselm", "Bless you, Wren. One more for the table."],
		["pip", "Survivor's with you! Walk them back to the Chest and strap them in."],
	],
	"hive": [
		["quill", "Hive down. Good work."],
		["sandoval", "Ah, what a waste of a magnificent organism. Do it again."],
	],
	"blast_civilian": [
		["anselm", "Oh, God rest them. Wren... careful with the rockets near people."],
		["quill", "Civilian casualty. Watch your fire, Wren. Rockets don't knock first."],
	],
	"cargo_lost": [
		["mags", "That was the cargo! Rockets and crates don't mix, Wren."],
	],
	"boss": [
		["sandoval", "That is the Brood Mother. It's... magnificent. Kill it!"],
	],
}

## Life at the Rock: lines shown in the base, one at a time.
const CHATTER := [
	["anselm", "The bees don't care about the end of the world. I find that comforting."],
	["anselm", "Bread is out of the oven. Mags will smell it in about four seconds."],
	["mags", "I gave Brigid new knee bearings. She walks like a dancer now. A heavy dancer."],
	["mags", "Ammo doesn't make itself. Well. The factory makes it. But it needs scrap."],
	["sandoval", "Biomass makes excellent fuel. And a dreadful smell. One cannot have everything."],
	["sandoval", "Bring me more biomass and I'll show you what research can really do."],
	["rafa", "The Gannet's purring today. That's either good or very bad."],
	["rafa", "I taught the kids to fold paper dropships. Brother Anselm confiscated forty of them."],
	["pip", "The Choir is quieter at night. I don't know why yet. I'm listening."],
	["pip", "More relays would mean more ops on the board. Just saying."],
	["quill", "Every module we build is a promise that we'll still be here next month."],
	["quill", "Survivors need bunks before they can work. Plan accordingly."],
	["anselm", "Someone keeps stealing honey. I suspect Rafa. I suspect Rafa because I saw him."],
	["mags", "If the factory's idle, it's because you haven't given it scrap. Or staff. Or both."],
]

const NIGHT := [
	["anselm", "The bell is rung. Everyone is home. Goodnight, Wren."],
	["anselm", "Soup tonight is 'whatever the garden had'. It's good, mostly."],
	["quill", "Another day held. Rest. The map room opens at dawn."],
	["rafa", "Fuelling the Gannet for tomorrow. Sleep, pilot."],
	["mags", "Brigid's in the hangar. I'll be with her a while yet."],
	["pip", "I'll keep the radio on. Someone always should."],
]
