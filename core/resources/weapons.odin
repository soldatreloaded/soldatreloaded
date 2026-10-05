package resources

// Which weapons there are, and the numbers of each a server sets: server.config.json's
// `weapons` (serverconfig.odin), each weapon an object by its name in lower case, as the
// config writes enums ("desert_eagles"), its numbers keys of Weapon_Stats' names.

// Every weapon, in the order the game and the network number them.
Weapon :: enum {
	Punch,
	Desert_Eagles,
	MP5,
	AK74,
	Steyr_AUG,
	Spas12,
	Ruger77,
	M79,
	Barrett,
	Minimi,
	Minigun,
	USSOCOM,
	Knife,
	Chainsaw,
	LAW,
	Frag_Grenade,
	Thrown_Knife,
}

// A weapon's numbers, in the units of Soldat's weapons.ini: times in ticks, sixty a second.
Weapon_Stats :: struct {
	damage:             f32, // the hit's strength: times the bullet's speed and the hitbox's modifier
	fire_interval:      i32, // ticks between shots
	ammo:               i32, // rounds in a clip
	reload_time:        i32, // ticks a reload takes
	speed:              f32, // the bullet's, out of the muzzle
	start_up_time:      i32, // ticks of wind-up (minigun, LAW, Barrett)
	bink:               i32, // aim disturbed: negative a shot's own kick, positive given to whom it hits
	movement_accuracy:  f32, // inaccuracy while moving
	bullet_spread:      f32,
	push:               f32, // knockback on whom it hits
	inherited_velocity: f32, // the share of the shooter's velocity the bullet takes
	head_modifier:      f32, // the damage on each part, times this
	chest_modifier:     f32,
	leg_modifier:       f32,
}

// Every weapon's numbers, as the game plays by them.
Weapon_Table :: [Weapon]Weapon_Stats

// The weapons as the config has them: a field for each weapon a server sets, named as the
// config writes the weapon, so the JSON package reads and writes them as they are. (It
// would key a Weapon_Table by the names as the code spells them, "Desert_Eagles", and
// take only those back.) The thrown knife isn't one: it follows the knife.
Weapon_Settings :: struct {
	punch:         Weapon_Stats,
	desert_eagles: Weapon_Stats,
	mp5:           Weapon_Stats,
	ak74:          Weapon_Stats,
	steyr_aug:     Weapon_Stats,
	spas12:        Weapon_Stats,
	ruger77:       Weapon_Stats,
	m79:           Weapon_Stats,
	barrett:       Weapon_Stats,
	minimi:        Weapon_Stats,
	minigun:       Weapon_Stats,
	ussocom:       Weapon_Stats,
	knife:         Weapon_Stats,
	chainsaw:      Weapon_Stats,
	law:           Weapon_Stats,
	frag_grenade:  Weapon_Stats,
}

// The config's weapons as the game's table; the thrown knife's left for the game to
// work out from the knife's.
weapon_table :: proc(w: Weapon_Settings) -> Weapon_Table {
	return {
		.Punch         = w.punch,
		.Desert_Eagles = w.desert_eagles,
		.MP5           = w.mp5,
		.AK74          = w.ak74,
		.Steyr_AUG     = w.steyr_aug,
		.Spas12        = w.spas12,
		.Ruger77       = w.ruger77,
		.M79           = w.m79,
		.Barrett       = w.barrett,
		.Minimi        = w.minimi,
		.Minigun       = w.minigun,
		.USSOCOM       = w.ussocom,
		.Knife         = w.knife,
		.Chainsaw      = w.chainsaw,
		.LAW           = w.law,
		.Frag_Grenade  = w.frag_grenade,
		.Thrown_Knife  = {},
	}
}

// The GatherWM weapons mod (1.7.1v14[Y]), the one gathers play, as its weapons.ini has
// it: what a server plays by unless its config says otherwise.
GATHER_WEAPONS :: Weapon_Settings {
	//               damage  fire ammo reload speed  startup bink moveacc spread push     inherit head   chest  legs
	punch         = {330,    6,   1,   3,     5,     0,      0,   0,      0,     0,       0,      1.15,  1,     0.9},
	desert_eagles = {1.65,   23,  7,   70,    19,    0,      0,   0,      0.1,   0.023,   0.5,    1.03,  1,     1},
	mp5           = {1.01,   6,   25,  70,    18.5,  0,      0,   0,      0.15,  0.0114,  0.5,    1.02,  0.95,  0.9},
	ak74          = {1.007,  10,  35,  150,   25.25, 0,      0,   0.009,  0.02,  0.01379, 0.5,    1,     0.89,  0.79},
	steyr_aug     = {0.685,  7,   26,  88,    26.5,  0,      0,   0,      0.064, 0.0086,  0.5,    1,     0.92,  0.83},
	spas12        = {1.11,   33,  7,   175,   14.1,  0,      0,   0,      0.8,   0.0188,  0.5,    1,     0.97,  0.91},
	ruger77       = {2.87,   56,  3,   66,    31,    0,      0,   0.0156, 0,     0.0195,  0.5,    1.005, 1.005, 1},
	m79           = {1550,   6,   1,   180,   10.7,  0,      0,   0,      0,     0.036,   0.5,    1.15,  1,     0.9},
	barrett       = {4.45,   230, 10,  100,   55,    19,     73,  0.05,   0,     0.018,   0.5,    1,     1,     1},
	minimi        = {0.86,   9,   50,  170,   27,    0,      0,   0.013,  0.058, 0.0128,  0.5,    1,     0.9,   0.83},
	minigun       = {0.468,  3,   100, 480,   29,    25,     0,   0.0625, 0.3,   0.0135,  0.5,    1,     0.92,  0.81},
	ussocom       = {1.55,   8,   12,  67,    18,    0,      0,   0,      0,     0.02,    0.5,    1,     0.9,   0.8},
	knife         = {2310,   6,   1,   3,     6,     0,      0,   0,      0,     0.12,    0,      1.15,  1,     0.98},
	chainsaw      = {50,     2,   200, 110,   8,     0,      0,   0,      0,     0.0028,  0,      1.15,  1,     0.9},
	law           = {2150,   6,   1,   260,   23,    11,     0,   0,      0,     0.028,   0.5,    1.15,  1,     0.9},
	frag_grenade  = {1505,   80,  1,   20,    5,     0,      0,   0,      0,     0,       1,      1,     1,     1},
}
