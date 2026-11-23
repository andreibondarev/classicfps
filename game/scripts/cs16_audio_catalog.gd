class_name CS16AudioCatalog
extends RefCounted

const MATERIALS_PATH := "res://assets/sounds/classic/materials.txt"
const SOUND_ROOT := "res://assets/sounds/classic"

const CONCRETE := "C"
const METAL := "M"
const VENT := "V"
const DIRT := "D"
const SLOSH := "S"
const TILE := "T"
const GRATE := "G"
const WOOD := "W"
const COMPUTER := "P"
const GLASS := "Y"
const SNOW := "N"
const GRASS := "X"

const FOOTSTEP_FAMILIES := {
	CONCRETE: {"prefix": "pl_step", "count": 4},
	METAL: {"prefix": "pl_metal", "count": 4},
	VENT: {"prefix": "pl_duct", "count": 4},
	DIRT: {"prefix": "pl_dirt", "count": 4},
	SLOSH: {"prefix": "pl_slosh", "count": 4},
	TILE: {"prefix": "pl_tile", "count": 5},
	GRATE: {"prefix": "pl_grate", "count": 4},
	# GoldSrc falls these less common classes back to one of its stock step
	# families; CS does not ship a separate pl_wood/pl_glass/pl_computer set.
	WOOD: {"prefix": "pl_step", "count": 4},
	COMPUTER: {"prefix": "pl_metal", "count": 4},
	GLASS: {"prefix": "pl_tile", "count": 5},
	SNOW: {"prefix": "pl_snow", "count": 6},
	GRASS: {"prefix": "pl_dirt", "count": 4},
}

# Original v_*.mdl reload sequence event 5004 markers, rounded to 100 Hz.
# Same sequence is selected by MdlViewModel; silenced variants share markers.
const RELOAD_AUDIO_STAGES := {
	"ak47": [
		{"offset": 35, "event": "ak47.clip_out"},
		{"offset": 154, "event": "ak47.clip_in"},
	],
	"aug": [
		{"offset": 25, "event": "aug.reload_0"},
		{"offset": 125, "event": "aug.reload_1"},
		{"offset": 220, "event": "aug.reload_2"},
		{"offset": 280, "event": "aug.reload_3"},
	],
	"awp": [
		{"offset": 87, "event": "awp.reload_0"},
		{"offset": 177, "event": "awp.reload_1"},
	],
	"deagle": [
		{"offset": 47, "event": "deagle.clip_out"},
		{"offset": 113, "event": "deagle.clip_in"},
	],
	"elite": [
		{"offset": 20, "event": "elite.reload_0"},
		{"offset": 147, "event": "elite.reload_1"},
		{"offset": 243, "event": "elite.reload_2"},
		{"offset": 273, "event": "elite.reload_3"},
		{"offset": 373, "event": "elite.reload_4"},
		{"offset": 417, "event": "elite.reload_5"},
	],
	"famas": [
		{"offset": 50, "event": "famas.reload_0"},
		{"offset": 157, "event": "famas.reload_1"},
		{"offset": 217, "event": "famas.reload_2"},
	],
	"fiveseven": [
		{"offset": 50, "event": "fiveseven.reload_0"},
		{"offset": 137, "event": "fiveseven.reload_1"},
		{"offset": 250, "event": "fiveseven.reload_2"},
	],
	"g3sg1": [
		{"offset": 53, "event": "g3sg1.reload_0"},
		{"offset": 180, "event": "g3sg1.reload_1"},
		{"offset": 283, "event": "g3sg1.reload_2"},
		{"offset": 387, "event": "g3sg1.reload_3"},
	],
	"galil": [
		{"offset": 43, "event": "galil.reload_0"},
		{"offset": 134, "event": "galil.reload_1"},
		{"offset": 186, "event": "galil.reload_2"},
	],
	"glock18": [
		{"offset": 46, "event": "glock18.reload_0"},
		{"offset": 137, "event": "glock18.reload_1"},
		{"offset": 177, "event": "glock18.reload_2"},
	],
	"m249": [
		{"offset": 83, "event": "m249.reload_0"},
		{"offset": 153, "event": "m249.reload_1"},
		{"offset": 223, "event": "m249.reload_2"},
		{"offset": 290, "event": "m249.reload_3"},
		{"offset": 357, "event": "m249.reload_4"},
	],
	"m4a1": [
		{"offset": 68, "event": "m4a1.reload_0"},
		{"offset": 143, "event": "m4a1.reload_1"},
		{"offset": 238, "event": "m4a1.reload_2"},
	],
	"mac10": [
		{"offset": 63, "event": "mac10.reload_0"},
		{"offset": 157, "event": "mac10.reload_1"},
		{"offset": 249, "event": "mac10.reload_2"},
	],
	"mp5": [
		{"offset": 39, "event": "mp5.reload_0"},
		{"offset": 121, "event": "mp5.reload_1"},
		{"offset": 203, "event": "mp5.reload_2"},
	],
	"p228": [
		{"offset": 69, "event": "p228.reload_0"},
		{"offset": 140, "event": "p228.reload_1"},
		{"offset": 231, "event": "p228.reload_2"},
	],
	"p90": [
		{"offset": 43, "event": "p90.reload_0"},
		{"offset": 88, "event": "p90.reload_1"},
		{"offset": 188, "event": "p90.reload_2"},
		{"offset": 270, "event": "p90.reload_3"},
	],
	"scout": [
		{"offset": 43, "event": "scout.reload_0"},
		{"offset": 123, "event": "scout.reload_1"},
	],
	"sg550": [
		{"offset": 79, "event": "sg550.reload_0"},
		{"offset": 164, "event": "sg550.reload_1"},
		{"offset": 293, "event": "sg550.reload_2"},
	],
	"sg552": [
		{"offset": 43, "event": "sg552.reload_0"},
		{"offset": 165, "event": "sg552.reload_1"},
		{"offset": 243, "event": "sg552.reload_2"},
	],
	"tmp": [
		{"offset": 48, "event": "tmp.reload_0"},
		{"offset": 128, "event": "tmp.reload_1"},
	],
	"ump45": [
		{"offset": 70, "event": "ump45.reload_0"},
		{"offset": 179, "event": "ump45.reload_1"},
		{"offset": 261, "event": "ump45.reload_2"},
	],
	"usp": [
		{"offset": 46, "event": "usp.reload_0"},
		{"offset": 108, "event": "usp.reload_1"},
		{"offset": 222, "event": "usp.reload_2"},
	],
}

# Original v_*.mdl draw/deploy sequence event 5004 markers, rounded to the
# authoritative 100 Hz clock. Weapons whose stock model has no sound marker
# deliberately remain silent here.
const DEPLOY_AUDIO_STAGES := {
	"ak47": [{"offset": 37, "event": "ak47.bolt"}],
	"aug": [{"offset": 26, "event": "aug.deploy"}],
	"elite": [{"offset": 3, "event": "elite.deploy"}],
	"famas": [{"offset": 29, "event": "famas.deploy"}],
	"fiveseven": [{"offset": 43, "event": "fiveseven.deploy"}],
	"galil": [{"offset": 29, "event": "galil.deploy"}],
	"glock18": [{"offset": 38, "event": "glock18.deploy"}],
	"knife": [{"offset": 0, "event": "knife.deploy"}],
	"m249": [{"offset": 70, "event": "m249.deploy"}],
	"m3": [{"offset": 37, "event": "m3.deploy"}],
	"m4a1": [
		{"offset": 3, "event": "m4a1.deploy"},
		{"offset": 43, "event": "m4a1.deploy_bolt"},
	],
	"mac10": [{"offset": 67, "event": "mac10.deploy"}],
	"mp5": [{"offset": 37, "event": "mp5.deploy"}],
	"p228": [
		{"offset": 3, "event": "p228.deploy"},
		{"offset": 50, "event": "p228.deploy_slide"},
	],
	"p90": [{"offset": 30, "event": "p90.deploy"}],
	"sg552": [{"offset": 32, "event": "sg552.deploy"}],
	"tmp": [{"offset": 89, "event": "tmp.deploy"}],
	"usp": [
		{"offset": 2, "event": "usp.deploy"},
		{"offset": 54, "event": "usp.deploy_slide"},
	],
	"xm1014": [{"offset": 3, "event": "xm1014.deploy"}],
}

# v_c4.mdl pressbutton event markers (frames 39, 47, 54, 62, 70, 78, 84
# at 33 fps). The schedule is cancelled if planting is interrupted.
const C4_ARM_AUDIO_STAGES := [118, 142, 164, 188, 212, 236, 255]

# Shared request whitelist for the reliable team-radio network action. The
# client is allowed to ask for only these stock radio IDs; the host owns the
# sender name, team and displayed text.
const RADIO_MESSAGES := {
	"ct_coverme": "Cover me!",
	"takepoint": "You take the point.",
	"position": "Hold this position.",
	"regroup": "Regroup, team.",
	"followme": "Follow me.",
	"fireassis": "Taking fire... need assistance!",
	"com_go": "Go go go!",
	"fallback": "Team, fall back!",
	"sticktog": "Stick together, team.",
	"com_getinpos": "Get in position and wait for my go.",
	"stormfront": "Storm the front!",
	"com_reportin": "Report in, team.",
	"ct_affirm": "Affirmative.",
	"ct_enemys": "Enemy spotted.",
	"ct_backup": "Need backup.",
	"clear": "Sector clear.",
	"ct_inpos": "I'm in position.",
	"ct_reportingin": "Reporting in.",
	"blow": "She's gonna blow!",
	"negative": "Negative.",
	"enemydown": "Enemy down.",
}

const EVENT_SAMPLES := {
	"player.spray": ["player/sprayer.wav"],
	# BuyGunAmmo emits this cue only after GiveAmmo succeeds. Keeping it in the
	# catalog lets the same authoritative event reach local and remote humans.
	"buy.ammo": ["items/9mmclip1.wav"],
	# CItemKevlar and CItemAssaultSuit both emit this after the armor grant is
	# accepted. The standalone helmet upgrade uses the same armor family.
	"buy.armor": ["items/ammopickup2.wav"],
	"buy.defuser": ["items/kevlar.wav"],
	"buy.nvgs": ["items/equip_nvg.wav"],
	# CBasePlayerItem::DefaultTouch uses this exact CHAN_ITEM cue after a weapon
	# has actually joined the player's inventory. Purchases use the same grant
	# path in CS, so bought guns and successful world pickups share the sound.
	"weapon.acquire": ["items/gunpickup2.wav"],
	"weapon.drop": ["items/weapondrop1.wav"],
	"aug.deploy": ["weapons/aug_forearm.wav"],
	"elite.deploy": ["weapons/elite_deploy.wav"],
	"famas.deploy": ["weapons/famas_forearm.wav"],
	"fiveseven.deploy": ["weapons/fiveseven_slidepull.wav"],
	"galil.deploy": ["weapons/galil_boltpull.wav"],
	"glock18.deploy": ["weapons/slideback1.wav"],
	"knife.deploy": ["weapons/knife_deploy1.wav"],
	"m249.deploy": ["weapons/slideback1.wav"],
	"m3.deploy": ["weapons/m3_pump.wav"],
	"m4a1.deploy": ["weapons/m4a1_deploy.wav"],
	"m4a1.deploy_bolt": ["weapons/m4a1_boltpull.wav"],
	"mac10.deploy": ["items/cliprelease1.wav"],
	"mp5.deploy": ["weapons/mp5_slideback.wav"],
	"p228.deploy": ["weapons/de_deploy.wav"],
	"p228.deploy_slide": ["weapons/p228_slidepull.wav"],
	"p90.deploy": ["weapons/p90_boltpull.wav"],
	"sg552.deploy": ["weapons/sg552_boltpull.wav"],
	"tmp.deploy": ["items/cliprelease1.wav"],
	"usp.deploy": ["weapons/de_deploy.wav"],
	"usp.deploy_slide": ["weapons/usp_slideback.wav"],
	"xm1014.deploy": ["weapons/de_deploy.wav"],
	"aug.reload_0": ["weapons/aug_boltpull.wav"],
	"aug.reload_1": ["weapons/aug_clipout.wav"],
	"aug.reload_2": ["weapons/aug_clipin.wav"],
	"aug.reload_3": ["weapons/aug_boltslap.wav"],
	"awp.reload_0": ["weapons/awp_clipout.wav"],
	"awp.reload_1": ["weapons/awp_clipin.wav"],
	"elite.reload_0": ["weapons/elite_reloadstart.wav"],
	"elite.reload_1": ["weapons/elite_leftclipin.wav"],
	"elite.reload_2": ["weapons/elite_clipout.wav"],
	"elite.reload_3": ["weapons/elite_sliderelease.wav"],
	"elite.reload_4": ["weapons/elite_rightclipin.wav"],
	"elite.reload_5": ["weapons/elite_sliderelease.wav"],
	"famas.reload_0": ["weapons/famas_clipout.wav"],
	"famas.reload_1": ["weapons/famas_clipin.wav"],
	"famas.reload_2": ["weapons/famas_forearm.wav"],
	"fiveseven.reload_0": ["weapons/fiveseven_clipout.wav"],
	"fiveseven.reload_1": ["weapons/fiveseven_clipin.wav"],
	"fiveseven.reload_2": ["weapons/fiveseven_sliderelease.wav"],
	"g3sg1.reload_0": ["weapons/g3sg1_slide.wav"],
	"g3sg1.reload_1": ["weapons/g3sg1_clipout.wav"],
	"g3sg1.reload_2": ["weapons/g3sg1_clipin.wav"],
	"g3sg1.reload_3": ["weapons/g3sg1_slide.wav"],
	"galil.reload_0": ["weapons/galil_clipout.wav"],
	"galil.reload_1": ["weapons/galil_clipin.wav"],
	"galil.reload_2": ["weapons/galil_boltpull.wav"],
	"glock18.reload_0": ["weapons/clipout1.wav"],
	"glock18.reload_1": ["weapons/clipin1.wav"],
	"glock18.reload_2": ["weapons/sliderelease1.wav"],
	"m249.reload_0": ["weapons/m249_coverup.wav"],
	"m249.reload_1": ["weapons/m249_boxout.wav"],
	"m249.reload_2": ["weapons/m249_boxin.wav"],
	"m249.reload_3": ["weapons/m249_chain.wav"],
	"m249.reload_4": ["weapons/m249_coverdown.wav"],
	"m4a1.reload_0": ["weapons/m4a1_clipout.wav"],
	"m4a1.reload_1": ["weapons/m4a1_clipin.wav"],
	"m4a1.reload_2": ["weapons/m4a1_boltpull.wav"],
	"mac10.reload_0": ["weapons/mac10_clipout.wav"],
	"mac10.reload_1": ["weapons/mac10_clipin.wav"],
	"mac10.reload_2": ["weapons/mac10_boltpull.wav"],
	"mp5.reload_0": ["weapons/mp5_clipout.wav"],
	"mp5.reload_1": ["weapons/mp5_clipin.wav"],
	"mp5.reload_2": ["weapons/mp5_slideback.wav"],
	"p228.reload_0": ["weapons/p228_clipout.wav"],
	"p228.reload_1": ["weapons/p228_clipin.wav"],
	"p228.reload_2": ["weapons/p228_sliderelease.wav"],
	"p90.reload_0": ["weapons/p90_cliprelease.wav"],
	"p90.reload_1": ["weapons/p90_clipout.wav"],
	"p90.reload_2": ["weapons/p90_clipin.wav"],
	"p90.reload_3": ["weapons/p90_boltpull.wav"],
	"scout.reload_0": ["weapons/scout_clipout.wav"],
	"scout.reload_1": ["weapons/scout_clipin.wav"],
	"sg550.reload_0": ["weapons/sg550_clipout.wav"],
	"sg550.reload_1": ["weapons/sg550_clipin.wav"],
	"sg550.reload_2": ["weapons/sg550_boltpull.wav"],
	"sg552.reload_0": ["weapons/sg552_clipout.wav"],
	"sg552.reload_1": ["weapons/sg552_clipin.wav"],
	"sg552.reload_2": ["weapons/sg552_boltpull.wav"],
	"tmp.reload_0": ["weapons/clipout1.wav"],
	"tmp.reload_1": ["weapons/clipin1.wav"],
	"ump45.reload_0": ["weapons/ump45_clipout.wav"],
	"ump45.reload_1": ["weapons/ump45_clipin.wav"],
	"ump45.reload_2": ["weapons/ump45_boltslap.wav"],
	"usp.reload_0": ["weapons/usp_clipout.wav"],
	"usp.reload_1": ["weapons/usp_clipin.wav"],
	"usp.reload_2": ["weapons/usp_sliderelease.wav"],
	"shotgun.insert": ["weapons/reload1.wav", "weapons/reload3.wav"],
	"m3.insert": ["weapons/m3_insertshell.wav"],
	"m3.pump": ["weapons/m3_pump.wav"],
	"xm1014.reload_start": ["items/cliprelease1.wav"],
	"p228.fire": ["weapons/p228-1.wav"],
	"scout.fire": ["weapons/scout_fire-1.wav"],
	"xm1014.fire": ["weapons/xm1014-1.wav"],
	"mac10.fire": ["weapons/mac10-1.wav"],
	"aug.fire": ["weapons/aug-1.wav"],
	"elite.fire": ["weapons/elite_fire.wav"],
	"fiveseven.fire": ["weapons/fiveseven-1.wav"],
	"ump45.fire": ["weapons/ump45-1.wav"],
	"sg550.fire": ["weapons/sg550-1.wav"],
	"galil.fire": ["weapons/galil-1.wav", "weapons/galil-2.wav"],
	"famas.fire": ["weapons/famas-1.wav", "weapons/famas-2.wav"],
	"famas.fire_burst": ["weapons/famas-burst.wav"],
	"glock18.fire": ["weapons/glock18-2.wav"],
	"glock18.fire_burst": ["weapons/glock18-1.wav"],
	"usp.fire": ["weapons/usp_unsil-1.wav"],
	"usp.fire_silenced": ["weapons/usp1.wav", "weapons/usp2.wav"],
	"usp.silencer_on": ["weapons/usp_silencer_on.wav"],
	"usp.silencer_off": ["weapons/usp_silencer_off.wav"],
	"awp.fire": ["weapons/awp1.wav"],
	"mp5.fire": ["weapons/mp5-1.wav", "weapons/mp5-2.wav"],
	"m249.fire": ["weapons/m249-1.wav", "weapons/m249-2.wav"],
	"m3.fire": ["weapons/m3-1.wav"],
	"m4a1.fire": ["weapons/m4a1_unsil-1.wav", "weapons/m4a1_unsil-2.wav"],
	"m4a1.fire_silenced": ["weapons/m4a1-1.wav"],
	"m4a1.silencer_on": ["weapons/m4a1_silencer_on.wav"],
	"m4a1.silencer_off": ["weapons/m4a1_silencer_off.wav"],
	"tmp.fire": ["weapons/tmp-1.wav", "weapons/tmp-2.wav"],
	"g3sg1.fire": ["weapons/g3sg1-1.wav"],
	"sg552.fire": ["weapons/sg552-1.wav", "weapons/sg552-2.wav"],
	"p90.fire": ["weapons/p90-1.wav"],
	"ak47.fire": ["weapons/ak47-1.wav", "weapons/ak47-2.wav"],
	"ak47.clip_out": ["weapons/ak47_clipout.wav"],
	"ak47.clip_in": ["weapons/ak47_clipin.wav"],
	"ak47.bolt": ["weapons/ak47_boltpull.wav"],
	"deagle.fire": ["weapons/deagle-1.wav", "weapons/deagle-2.wav"],
	"deagle.clip_out": ["weapons/de_clipout.wav"],
	"deagle.clip_in": ["weapons/de_clipin.wav"],
	"deagle.deploy": ["weapons/de_deploy.wav"],
	"knife.slash": ["weapons/knife_slash1.wav", "weapons/knife_slash2.wav"],
	"knife.hit": [
		"weapons/knife_hit1.wav",
		"weapons/knife_hit2.wav",
		"weapons/knife_hit3.wav",
		"weapons/knife_hit4.wav",
	],
	"knife.hit_wall": ["weapons/knife_hitwall1.wav"],
	"knife.stab": ["weapons/knife_stab.wav"],
	# v_hegrenade.mdl sequence event 5004, frame 27 at 41 fps.
	"he.pull_pin": ["weapons/pinpull.wav"],
	# CGrenade::BounceSound selects the CS-specific sample for HE damage > 50.
	"he.bounce": ["weapons/he_bounce-1.wav"],
	"he.explode": [
		"weapons/explode3.wav",
		"weapons/explode4.wav",
		"weapons/explode5.wav",
	],
	"he.debris": [
		"weapons/debris1.wav",
		"weapons/debris2.wav",
		"weapons/debris3.wav",
	],
	"flash.explode": ["weapons/flashbang-1.wav", "weapons/flashbang-2.wav"],
	"smoke.explode": ["weapons/sg_explode.wav"],
	"weapon.empty_pistol": ["weapons/dryfire_pistol.wav"],
	"weapon.empty_rifle": ["weapons/dryfire_rifle.wav"],
	"weapon.zoom": ["weapons/zoom.wav"],
	"weapon.mode_switch": ["common/wpn_select.wav"],
	"impact.bullet": ["weapons/bullet_hit1.wav", "weapons/bullet_hit2.wav"],
	"impact.ricochet": [
		"weapons/ric1.wav",
		"weapons/ric2.wav",
		"weapons/ric3.wav",
		"weapons/ric4.wav",
		"weapons/ric5.wav",
	],
	"impact.ricochet_metal": ["weapons/ric_metal-1.wav", "weapons/ric_metal-2.wav"],
	"player.hit_flesh": [
		"player/bhit_flesh-1.wav",
		"player/bhit_flesh-2.wav",
		"player/bhit_flesh-3.wav",
	],
	"player.hit_kevlar": ["player/bhit_kevlar-1.wav"],
	"player.hit_helmet": ["player/bhit_helmet-1.wav"],
	"player.pain": [
		"player/pl_pain2.wav",
		"player/pl_pain4.wav",
		"player/pl_pain5.wav",
		"player/pl_pain6.wav",
		"player/pl_pain7.wav",
	],
	"player.death": [
		"player/die1.wav",
		"player/die2.wav",
		"player/die3.wav",
		"player/death6.wav",
	],
	"player.headshot_death": [
		"player/headshot1.wav",
		"player/headshot2.wav",
		"player/headshot3.wav",
	],
	"c4.plant": ["weapons/c4_plant.wav"],
	"c4.click": ["weapons/c4_click.wav"],
	"c4.disarm": ["weapons/c4_disarm.wav"],
	"c4.disarmed": ["weapons/c4_disarmed.wav"],
	"c4.beep1": ["weapons/c4_beep1.wav"],
	"c4.beep2": ["weapons/c4_beep2.wav"],
	"c4.beep3": ["weapons/c4_beep3.wav"],
	"c4.beep4": ["weapons/c4_beep4.wav"],
	"c4.beep5": ["weapons/c4_beep5.wav"],
	"c4.explode": ["weapons/c4_explode1.wav"],
	"radio.bomb_planted": ["radio/bombpl.wav"],
	"round.ct_win": ["radio/ctwin.wav"],
	"round.t_win": ["radio/terwin.wav"],
	"round.draw": ["radio/rounddraw.wav"],
	"door.move1": ["doors/doormove1.wav"],
	"door.move2": ["doors/doormove2.wav"],
	"door.move3": ["doors/doormove3.wav"],
	"door.move4": ["doors/doormove4.wav"],
	"door.move5": ["doors/doormove5.wav"],
	"door.move6": ["doors/doormove6.wav"],
	"door.move7": ["doors/doormove7.wav"],
	"door.move8": ["doors/doormove8.wav"],
	"door.move9": ["doors/doormove9.wav"],
	"door.move10": ["doors/doormove10.wav"],
	"door.stop1": ["doors/doorstop1.wav"],
	"door.stop2": ["doors/doorstop2.wav"],
	"door.stop3": ["doors/doorstop3.wav"],
	"door.stop4": ["doors/doorstop4.wav"],
	"door.stop5": ["doors/doorstop5.wav"],
	"door.stop6": ["doors/doorstop6.wav"],
	"door.stop7": ["doors/doorstop7.wav"],
	"door.stop8": ["doors/doorstop8.wav"],
	"button.press1": ["buttons/button1.wav"],
	"button.press2": ["buttons/button2.wav"],
	"button.press3": ["buttons/button3.wav"],
	"button.press4": ["buttons/button4.wav"],
	"button.press5": ["buttons/button5.wav"],
	"button.press6": ["buttons/button6.wav"],
	"button.press7": ["buttons/button7.wav"],
	"button.press8": ["buttons/button8.wav"],
	"button.press9": ["buttons/button9.wav"],
	"button.press10": ["buttons/button10.wav"],
	"button.press11": ["buttons/button11.wav"],
	"button.press12": ["buttons/latchlocked1.wav"],
	"button.press13": ["buttons/latchunlocked1.wav"],
	"button.press14": ["buttons/lightswitch2.wav"],
}

static var _material_types: Dictionary = {}


static func material_code(texture_name: String) -> String:
	_ensure_material_types()
	var normalized := texture_name.strip_edges().to_lower().substr(0, 12)
	match normalized:
		"concrete":
			return CONCRETE
		"metal":
			return METAL
		"vent":
			return VENT
		"dirt":
			return DIRT
		"slosh":
			return SLOSH
		"tile":
			return TILE
		"grate":
			return GRATE
		"wood":
			return WOOD
		"computer":
			return COMPUTER
		"glass":
			return GLASS
		"snow":
			return SNOW
		"grass":
			return GRASS
	var literal_code := normalized.to_upper()
	if normalized.length() == 1 and FOOTSTEP_FAMILIES.has(literal_code):
		return literal_code
	return str(_material_types.get(normalized, CONCRETE))


static func footstep_sample(texture_name: String, step_index: int) -> String:
	var family: Dictionary = FOOTSTEP_FAMILIES.get(
		material_code(texture_name),
		FOOTSTEP_FAMILIES[CONCRETE],
	)
	var count := int(family.count)
	var sample_index := posmod(step_index, count) + 1
	return "%s/player/%s%d.wav" % [SOUND_ROOT, str(family.prefix), sample_index]


static func network_event_samples(event_name: String) -> Array[String]:
	## Network audio normally comes from the fixed event catalog. Footsteps are
	## the one intentional dynamic family: GoldSrc derives the event from the
	## material under the actor, while the selected sample still has to belong
	## to that exact material family.
	if EVENT_SAMPLES.has(event_name):
		var catalog_samples: Array[String] = []
		for sample: Variant in EVENT_SAMPLES[event_name]:
			catalog_samples.append(str(sample))
		return catalog_samples
	var prefix := "player.step."
	if not event_name.begins_with(prefix):
		return []
	var code := event_name.trim_prefix(prefix)
	if code.length() != 1 or not FOOTSTEP_FAMILIES.has(code):
		return []
	var family: Dictionary = FOOTSTEP_FAMILIES[code]
	var samples: Array[String] = []
	for index in range(1, int(family.count) + 1):
		samples.append("player/%s%d.wav" % [str(family.prefix), index])
	return samples


static func network_audio_sample_valid(event_name: String, sample: String) -> bool:
	if event_name == "weapon.mode_switch":
		return false
	return sample in network_event_samples(event_name)


static func event_sample(event_name: String, variant_index := 0) -> String:
	var variants: Array = EVENT_SAMPLES.get(event_name, [])
	if variants.is_empty():
		return ""
	return "%s/%s" % [SOUND_ROOT, str(variants[posmod(variant_index, variants.size())])]


static func door_move_event(sound_ordinal: int) -> String:
	return (
		"door.move%d" % sound_ordinal
		if sound_ordinal >= 1 and sound_ordinal <= 10
		else ""
	)


static func door_stop_event(sound_ordinal: int) -> String:
	return (
		"door.stop%d" % sound_ordinal
		if sound_ordinal >= 1 and sound_ordinal <= 8
		else ""
	)


static func button_press_event(sound_ordinal: int) -> String:
	return (
		"button.press%d" % sound_ordinal
		if sound_ordinal >= 1 and sound_ordinal <= 14
		else ""
	)


static func footstep_descriptor(
	texture_name: String,
	left_foot: bool,
	volume: float,
) -> Dictionary:
	var code := material_code(texture_name)
	var family: Dictionary = FOOTSTEP_FAMILIES.get(
		code,
		FOOTSTEP_FAMILIES[CONCRETE],
	)
	var prefix := str(family.prefix)
	var count := int(family.count)
	var indices := [2, 4] if left_foot else [1, 3]
	var samples: Array[String] = []
	for index in indices:
		if index <= count:
			samples.append("player/%s%d.wav" % [prefix, index])
	# Tile's fifth variant is selected one time in five by PM_PlayStepSound.
	# Keep it in the descriptor so the original sample is addressable; exact
	# one-in-five scheduling remains owned by the live footstep state machine.
	if code == TILE and count >= 5:
		samples.append("player/%s5.wav" % prefix)
	return {
		"samples": samples,
		"channel": 4, # CHAN_BODY; kept numeric to avoid a catalog/router cycle.
		"volume": clampf(volume, 0.0, 1.0),
		"attenuation": 0.8,
		"pitch_min": 100,
		"pitch_max": 100,
		"flags": 0,
	}


static func footstep_volume(texture_name: String) -> float:
	match material_code(texture_name):
		DIRT:
			return 0.55
		VENT:
			return 0.7
	return 0.5


static func _ensure_material_types() -> void:
	if not _material_types.is_empty():
		return
	var file := FileAccess.open(MATERIALS_PATH, FileAccess.READ)
	if file == null:
		push_error("Missing CS material sound table: %s" % MATERIALS_PATH)
		return
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("//"):
			continue
		var separator := line.find(" ")
		if separator <= 0:
			continue
		var code := line.substr(0, separator).strip_edges().to_upper()
		var texture := line.substr(separator + 1).strip_edges().to_lower().substr(0, 12)
		if code.length() == 1 and not texture.is_empty():
			_material_types[texture] = code
