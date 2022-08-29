untyped
global function GamemodePs_Init

struct Weapon {
    string name
    array<string> mods = []
    bool isOffhand = false
}

Weapon function NewWeapon(string name, array<string> mods, bool isOffhand = false) {
    Weapon w
    w.name = name
    w.mods = mods
    w.isOffhand = isOffhand
    return w
}

struct {
	array<entity> spawnzones
	
	entity militiaActiveSpawnZone
	entity imcActiveSpawnZone
	
	array<entity> militiaPreviousSpawnZones
	array<entity> imcPreviousSpawnZones

    // pvp gun game
    array<Weapon> weapons

    int killsForNextLoadout
    table<int, int> currentLoadoutScores
} file

void function GamemodePs_Init()
{
	Riff_ForceTitanAvailability( eTitanAvailability.Never )

	ScoreEvent_SetupEarnMeterValuesForMixedModes()
	SetTimeoutWinnerDecisionFunc( CheckScoreForDraw )

	SetShouldCreateMinimapSpawnZones( true )
	
	//AddCallback_OnPlayerKilled( CheckSpawnzoneSuspiciousDeaths )
	
	file.militiaPreviousSpawnZones = [ null, null, null ]
	file.imcPreviousSpawnZones = [ null, null, null ]

    // pvp gun game
    //SetLoadoutGracePeriodEnabled(false) 
    SetWeaponDropsEnabled(false)

    AddCallback_OnClientConnected(OnClientConnected)
    AddCallback_OnClientDisconnected(OnClientDisconnected)
    AddCallback_OnPlayerRespawned(OnPlayerRespawned)
    AddCallback_OnPlayerGetsNewPilotLoadout(OnPlayerGetsNewPilotLoadout)
	AddCallback_OnPlayerKilled(OnPlayerKilled)
    AddClientCommandCallback("ggnext", CommandNext) // testing

    file.weapons = [
	    NewWeapon("mp_weapon_car",            ["extended_ammo", "pas_fast_reload", "holosight"]),
	    NewWeapon("mp_weapon_alternator_smg", ["extended_ammo", "pas_fast_reload"]),
	    NewWeapon("mp_weapon_hemlok_smg",     ["extended_ammo", "pas_fast_reload", "holosight"]),
	    NewWeapon("mp_weapon_r97",            ["extended_ammo", "pas_fast_reload", "holosight"]),

        NewWeapon("mp_weapon_hemlok",         ["extended_ammo", "pas_fast_reload", "hcog"]),
	    NewWeapon("mp_weapon_vinson",         ["extended_ammo", "pas_fast_reload", "hcog"]),
	    NewWeapon("mp_weapon_rspn101",        ["extended_ammo", "pas_fast_reload", "hcog"]),
	    NewWeapon("mp_weapon_g2",             ["extended_ammo", "pas_fast_reload", "hcog"]),
	    NewWeapon("mp_weapon_rspn101_og",     ["extended_ammo", "pas_fast_reload", "hcog"]),

	    NewWeapon("mp_weapon_esaw",           ["extended_ammo", "pas_fast_reload"]),
	    NewWeapon("mp_weapon_lstar",          ["extended_ammo"]),
	    NewWeapon("mp_weapon_lmg",            ["extended_ammo", "pas_fast_reload"]),

	    NewWeapon("mp_weapon_shotgun",        ["extended_ammo", "pas_fast_reload"]),
	    NewWeapon("mp_weapon_mastiff",        ["extended_ammo", "pas_fast_reload"]),

	    NewWeapon("mp_weapon_softball",       ["extended_ammo", "pas_fast_reload"]),
	    NewWeapon("mp_weapon_epg",            ["extended_ammo", "pas_fast_reload"]),
	    NewWeapon("mp_weapon_smr",            ["extended_ammo", "pas_fast_reload"]),
	    NewWeapon("mp_weapon_pulse_lmg",      ["extended_ammo", "pas_fast_reload"]),

	    NewWeapon("mp_weapon_shotgun_pistol", ["extended_ammo", "pas_fast_reload"]),
	    NewWeapon("mp_weapon_wingman_n",      ["extended_ammo", "pas_fast_reload"]),

	    NewWeapon("mp_weapon_doubletake",     ["extended_ammo", "pas_fast_ads"]),
	    NewWeapon("mp_weapon_sniper",         ["extended_ammo", "pas_fast_ads"]),
	    NewWeapon("mp_weapon_dmr",            ["extended_ammo", "pas_fast_ads"]),

	    NewWeapon("mp_weapon_autopistol",     ["extended_ammo", "pas_fast_reload", "temp_sight"]),
	    NewWeapon("mp_weapon_semipistol",     ["extended_ammo", "pas_fast_reload"]),
	    NewWeapon("mp_weapon_wingman",        ["extended_ammo", "pas_fast_reload"]),

	    NewWeapon("mp_weapon_defender",       ["extended_ammo", "pas_fast_ads"]),
        NewWeapon("mp_weapon_grenade_sonar",  ["pas_power_cell", "amped_tacticals"], true)
    ]

    file.killsForNextLoadout = 0
    file.currentLoadoutScores = {}
}

int function CheckScoreForDraw()
{
	if ( GameRules_GetTeamScore( TEAM_IMC ) > GameRules_GetTeamScore( TEAM_MILITIA ) )
		return TEAM_IMC
	else if ( GameRules_GetTeamScore( TEAM_MILITIA ) > GameRules_GetTeamScore( TEAM_IMC ) )
		return TEAM_MILITIA

	return TEAM_UNASSIGNED
}

void function OnClientConnected(entity player) {
    UpdateKillsForNextLoadout()
}

void function OnClientDisconnected(entity player) {
    UpdateKillsForNextLoadout()
}

void function OnPlayerRespawned(entity player) {
    UpdateLoadout(player)
}

void function OnPlayerGetsNewPilotLoadout(entity player, PilotLoadoutDef _loadout) {
    UpdateLoadout(player)
}

void function OnPlayerKilled(entity victim, entity attacker, var damageInfo)
{
	if (victim == attacker || !victim.IsPlayer() || !attacker.IsPlayer() || GetGameState() != eGameState.Playing) {
        return
    }

    int damageSourceId = DamageInfo_GetDamageSourceIdentifier(damageInfo)
    string damageSource = DamageSourceIDToString(damageSourceId)
    Weapon teamWeapon = GetCurrentTeamWeapon(attacker.GetTeam())
    if (damageSource == teamWeapon.name) {
	    GiveTeamScore(attacker.GetTeam())
    }
}

void function GiveTeamScore(int team) {
    int loadoutScore = GetTeamLoadoutScore(team) + 1
    if (loadoutScore >= file.killsForNextLoadout) {
        EmitSoundToTeamPlayers("UI_CTF_3P_TeamReturnsFlag", team)
        EmitSoundToTeamPlayers("UI_CTF_3P_EnemyReturnsFlag", GetOtherTeam(team))

	    AddTeamScore(team, 1)
        if (GameRules_GetTeamScore(team) >= file.weapons.len()) {
            SetWinner(team)
            return
        }

        foreach (entity player in GetPlayerArrayOfTeam(team)) {
            UpdateLoadout(player)
        }

        loadoutScore = 0
    }

    SetTeamLoadoutScore(team, loadoutScore)
    UpdateKillsForNextLoadout()
}

bool function CommandNext(entity player, array<string> args) {
    GiveTeamScore(player.GetTeam())
    return true
}

void function UpdateLoadout(entity player) {
    Weapon weapon = GetCurrentTeamWeapon(player.GetTeam())
    
    foreach (entity mainWeapon in player.GetMainWeapons()) {
        player.TakeWeaponNow(mainWeapon.GetWeaponClassName())
    }

    if (weapon.isOffhand) {
        entity oldOffhandWeapon = player.GetOffhandWeapon(OFFHAND_RIGHT)
        foreach (entity offhandWeapon in player.GetOffhandWeapons()) {
            player.TakeWeaponNow(offhandWeapon.GetWeaponClassName())
        }
        if (oldOffhandWeapon != null) {
            player.GiveOffhandWeapon(oldOffhandWeapon.GetWeaponClassName(), OFFHAND_RIGHT, [])
        }

        player.GiveOffhandWeapon(weapon.name, OFFHAND_LEFT, weapon.mods)
        player.GiveOffhandWeapon("melee_pilot_emptyhanded", OFFHAND_MELEE, ["allow_as_primary"])
        player.SetActiveWeaponByName("melee_pilot_emptyhanded")
    } else {
        player.GiveWeapon(weapon.name, weapon.mods)
    }
}

Weapon function GetCurrentTeamWeapon(int team) {
    int weaponIndex = GameRules_GetTeamScore(team)
    if (weaponIndex >= file.weapons.len()) {
        weaponIndex = file.weapons.len() - 1
    }

    return file.weapons[weaponIndex]
}

int function GetTeamLoadoutScore(int team) {
    return team in file.currentLoadoutScores ? file.currentLoadoutScores[team] : 0
}

void function SetTeamLoadoutScore(int team, int score) {
    file.currentLoadoutScores[team] <- score
}

void function UpdateKillsForNextLoadout() {
    int oldCount = file.killsForNextLoadout

    int imcCount = GetPlayerArrayOfTeam(TEAM_IMC).len()
    int militiaCount = GetPlayerArrayOfTeam(TEAM_MILITIA).len()
    file.killsForNextLoadout = imcCount < militiaCount ? militiaCount : imcCount

    PrintKillsForNextLoadout(TEAM_IMC)
    PrintKillsForNextLoadout(TEAM_MILITIA)
}

void function PrintKillsForNextLoadout(int team) {
    int score = GetTeamLoadoutScore(team)
    int limit = file.killsForNextLoadout
    int remaining = limit - score
    string message = format("team gun score: %d/%d", score, limit)

    foreach (entity player in GetPlayerArrayOfTeam(team)) {
        SendHudMessage(player, message, -0.925, 0.4, 220, 224, 255, 255, 0.15, 9999, 1)
    }
}
