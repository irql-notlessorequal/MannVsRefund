// MannVsRefund.
// Copyright (C) IRQL_NOT_LESS_OR_EQUAL
// Original "MvM upgrades" script by by Lazyneer.
//
// 
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
// 
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

const CREDITS_MESSAGE = "MannVsRefund by rake.\nBased on the MvM Upgrades script by Lazyneer."
const REFUND_OK = "\x05Upgrades reset, your money has been refunded.\x01"
const REFUND_HINT = "Type /refund or !refund in chat to reset your upgrades."
const REFUND_FAIL = "\x07AA0000You can only refund at a resupply locker.\x01"
const HUD_PRINTTALK = 3
const DEBUG = false // Set to true to print round info to the server console
const MONEY_VANISH_SOUND = "mvm/mvm_money_vanish.wav"
const FLAG_EVENT_CAPTURE = 2
const SETUP_BUILDING_LEVEL = 3
const OBJECT_TYPE_SAPPER = 3
const NUM_CLASSES = 9
const UPGRADE_VO_COUNT = 11
const FLAG_DEAD_RINGER = 32

// I'm going to be a jerk and just assume your spending it all on Crit Canteens
const CANTEEN_MAX_CHARGE_COST = 100

// Currency amounts
const START_CASH = 500
const KILL_CASH = 100
const ASSIST_CASH = 50
const MEDIC_ASSIST_CASH = 100
const DEATH_STREAK_CASH = 100
const DEATH_STREAK_THRESHOLD = 3     // Consecutive deaths needed for the bonus
const POINT_CAPTURE_CASH = 100       // Whole team, on top of the game's own cap bonus
const FLAG_CAPTURE_CASH = 300        // Player who captured the flag
const FLAG_CAPTURE_TEAM_CASH = 200   // Rest of the capturer's team

// Fraction of a kill's credit given to each of the killer's teammates
// This doesn't apply in Arena Mode because we do it differently there.
const TEAM_KILL_SHARE = 0.5

// if one team is far ahead on kills this round, the other team earns more
const TEAM_RED = 2
const TEAM_BLU = 3
const STEAMROLL_MIN_KILLS = 20   // Total kills needed before a steamroll can be declared
const STEAMROLL_RATIO = 2.0      // Leading team needs this many times the other team's kills
const STEAMROLL_BONUS = 1.1      // Income multiplier for the losing team

// MvM buyback logic.
const BUYBACK_MAX_COST = 300         // Price right after dying
const BUYBACK_MIN_COST = 100         // Price just before buy-back closes
const BUYBACK_CUTOFF = 3.0           // Buy-back closes this many seconds before the respawn
const BUYBACK_THINK_INTERVAL = 0.05  // How often dead players' buttons are checked
const BUYBACK_IDLE_INTERVAL = 0.25   // Think rate when nobody is dead
const BUYBACK_HUD_INTERVAL = 1.0     // How often the HUD text is refreshed
const BUYBACK_PRICE_STEP = 20        // The price drops in steps of this much (keep the min and max costs a multiple of it)
const BUYBACK_BUTTON = 8192          // IN_RELOAD
const BUYBACK_HUD_CHANNEL = 2        // game_text channel (0-5) used for the buy-back text
const BUYBACK_DENIED_SOUND = "replay/cameracontrolerror.wav"
const BUYBACK_BOUGHT_IN_SOUND = "mvm/mvm_bought_in.wav"
const BUYBACK_MIN_WINDOW = 5.0       // Buy-back must stay open at least this long to be offered at all (very short respawns skip it)

// performance duct tape
const SLOW_WORK_INTERVAL = 0.25      // How often setup and canteen checks run
const WAVE_CACHE_INTERVAL = 0.5      // How often respawn wave lengths are recalculated

// Sound for receiving money
const MONEY_PICKUP_SOUND = "mvm/mvm_money_pickup.wav"
const MONEY_PICKUP_COOLDOWN = 1.0    // Adjust this to avoid hearing "mvm/mvm_money_pickup.wav" constantly

// MvM sounds aren't precached on non-MvM maps
function PrecacheUpgradeSounds()
{
    PrecacheSound(MONEY_VANISH_SOUND)
    PrecacheSound(MONEY_PICKUP_SOUND)
    PrecacheSound(BUYBACK_BOUGHT_IN_SOUND)
    PrecacheSound(BUYBACK_DENIED_SOUND)
    for (local i = 1; i <= UPGRADE_VO_COUNT; i++)
        PrecacheSound(format("vo/mvm_get_to_upgrade%02d.mp3", i))
}
PrecacheUpgradeSounds()

hasRecievedCash <- {}
deathStreak <- {}
earnedCash <- {} // Total currency each player has received this round
reviveMarkers <- {} // Each player's current revive marker entity, if any
buybackState <- {} // Each player's buy-back tracking (time of death and current cost)
buybackDead <- {} // Players currently tracked as dead, so the think doesn't scan everyone
moneySoundTime <- {} // When each player last heard the pickup sound
canteenWatch <- {} // Each player's last seen canteen charges and money
waveCache <- { time = -100.0, rules = null, delay = 0.0, scaled = {}, unscaled = {} } // Wave lengths are expensive
slowWorkTime <- 0.0 // When the setup and canteen checks next run
roundRunning <- false // True while the round is live, which is when respawn waves run
arenaMode <- false // Arena has no respawn waves, so there's no buy-back there
setupActive <- false // True when we are in pre-round setup
teamKills <- {}  // Kills per team this round, used for steamroll detection
teamKills[TEAM_RED] <- 0
teamKills[TEAM_BLU] <- 0
for (local i = 1; i <= Constants.Server.MAX_PLAYERS; i++)
{
    hasRecievedCash[i] <- false
    deathStreak[i] <- 0
    earnedCash[i] <- 0
    reviveMarkers[i] <- null
    buybackState[i] <- { deathTime = -1.0, window = -1.0, held = false, nextHud = 0.0, estimate = -1.0, hud = null, skip = false, opened = false }
    moneySoundTime[i] <- 0.0
    canteenWatch[i] <- { charges = 0, currency = 0 }
}

function OnGameEvent_teamplay_round_start(params)
{
    if (DEBUG)
        printl("round_start: full_reset=" + params.full_reset)

    teamKills[TEAM_RED] = 0
    teamKills[TEAM_BLU] = 0

    roundRunning = false
    arenaMode = IsArenaMode()
    for (local i = 1; i <= Constants.Server.MAX_PLAYERS; i++)
        ResetBuybackState(i)

    ClearReviveMarkers()
    ForceEnableUpgrades(2)
    ClearUpgradeStations()
    ResetCanteens()
    SpawnUpgradeZonesAtResupply()

    PrecacheUpgradeSounds()

    ClientPrint(null, HUD_PRINTTALK, CREDITS_MESSAGE)

    // Wait out the round start freeze before playing the voice line
    local freeze = Convars.GetFloat("tf_player_movement_restart_freeze")
    if (freeze == null)
        freeze = 0.0
    if (DEBUG)
        printl("voice line delay: " + freeze)
    EntFire("worldspawn", "RunScriptCode", "PlayUpgradeVO()", freeze)
}

// Plays a random "get to the upgrade station" line to everyone.
// Defined on the root table so the delayed RunScriptCode call can find it from any scope
::PlayUpgradeVO <- function()
{
    // Why the hell does TF2 emit teamplay_round_start during Waiting For Players?
    local rules = Entities.FindByClassname(null, "tf_gamerules")
    if (rules != null && NetProps.GetPropBool(rules, "m_bInWaitingForPlayers"))
        return

    EmitSoundEx({
        sound_name  = format("vo/mvm_get_to_upgrade%02d.mp3", RandomInt(1, UPGRADE_VO_COUNT)),
        filter_type = Constants.EScriptRecipientFilter.RECIPIENT_FILTER_GLOBAL
    })
}

// full_round is false for the end of a mini-round (e.g. one stage of a multi-stage map),
// so cash and upgrades only get wiped once the whole round/map is actually over
function OnGameEvent_teamplay_round_win(params)
{
    if (DEBUG)
        printl("round_win: full_round=" + params.full_round)

    roundRunning = false

    if (params.full_round)
        ResetPlayers()
}

function OnGameEvent_teamplay_restart_round(params)
{
    roundRunning = false
    ResetPlayers()
}

function OnGameEvent_teamplay_round_active(params)
{
    roundRunning = true
}

function OnGameEvent_teamplay_round_stalemate(params)
{
    roundRunning = false
}

function OnGameEvent_player_spawn(params)
{
    local client = GetPlayerFromUserID(params.userid)
    if (client == null)
        return

    // Spawning, whether revived or respawned normally, ends their marker
    RemoveReviveMarker(client)

    // ...and their chance to buy back
    local buyback = buybackState[client.entindex()]
    if (DEBUG && buyback.estimate > 0.0)
        printl("buyback: respawn estimate was off by " + (Time() - buyback.estimate) + "s")
    ResetBuybackState(client.entindex())

    if (!hasRecievedCash[client.entindex()])
    {
        RemoveUpgradesFromAllClasses(client, client.GetMaxHealth())
        client.SetCurrency(START_CASH)
        earnedCash[client.entindex()] = START_CASH
        hasRecievedCash[client.entindex()] = true
    }

    if (deathStreak[client.entindex()] >= DEATH_STREAK_THRESHOLD)
    {
        AddCurrency(client, DEATH_STREAK_CASH)
        deathStreak[client.entindex()] = 0
    }

    if (!IsWaitingForPlayers())
        ClientPrint(client, HUD_PRINTTALK, REFUND_HINT)
}

function OnGameEvent_player_say(params)
{
    local client = GetPlayerFromUserID(params.userid)
    if (client == null)
        return

    local text = params.text.tolower()
    if (text == "/refund" || text == "!refund")
    {
        if (NetProps.GetPropBool(client, "m_Shared.m_bInUpgradeZone"))
        {
            // A player could just switch loadout at the resupply
            // locker and keep some of their upgrades for free...
            RemoveUpgradesFromAllClasses(client)

            // The refund flag removes upgrades but doesn't return the money,
            // so restore the player's total earnings for this round
            local earned = earnedCash[client.entindex()]
            if (earned > client.GetCurrency())
                client.SetCurrency(earned)

            EmitSoundEx({
                sound_name  = MONEY_VANISH_SOUND,
                entity      = client,
                filter_type = Constants.EScriptRecipientFilter.RECIPIENT_FILTER_SINGLE_PLAYER
            })

            ClientPrint(client, HUD_PRINTTALK, REFUND_OK)
        }
        else
        {
            ClientPrint(client, HUD_PRINTTALK, REFUND_FAIL)
        }
    }
}

function OnGameEvent_player_disconnect(params)
{
    local client = GetPlayerFromUserID(params.userid)
    if (client != null && client.IsValid())
    {
        hasRecievedCash[client.entindex()] = false
        deathStreak[client.entindex()] = 0
        earnedCash[client.entindex()] = 0
        ResetBuybackState(client.entindex())
    }
}

function ResetPlayers()
{
    for (local i = 1; i <= Constants.Server.MAX_PLAYERS; i++)
    {
        hasRecievedCash[i] = false
        deathStreak[i] = 0
        earnedCash[i] = 0
    }
}

function RemoveUpgradesFromAllClasses(client, health = null)
{
    local playerClass = client.GetPlayerClass()
    if (health == null)
        health = client.GetHealth()

    for (local i = 1; i <= NUM_CLASSES; i++)
    {
        client.SetPlayerClass(i)
        client.Regenerate(true)
        client.GrantOrRemoveAllUpgrades(true, false)
    }

    client.SetPlayerClass(playerClass)
    client.Regenerate(true)
    client.SetHealth(health)
}

function IsArenaMode()
{
    return Entities.FindByClassname(null, "tf_logic_arena") != null
}

function ResetCanteens()
{
    local ent = null
    while (ent = Entities.FindByClassname(ent, "tf_powerup_bottle"))
    {
        NetProps.SetPropInt(ent, "m_usNumCharges", 0)
        NetProps.SetPropBool(ent, "m_bActive", false)
        ent.RemoveAttribute("critboost")
        ent.RemoveAttribute("ubercharge")
        ent.RemoveAttribute("building instant upgrade")
        ent.RemoveAttribute("refill_ammo")
        ent.RemoveAttribute("recall")
    }
}

function ClearUpgradeStations()
{
    local ent = null
    while (ent = Entities.FindByName(ent, "vscript_upgrade_station"))
    {
        ent.Kill()
    }
}

// Gives every other player on the killer's team a share of the kill credit
function ShareKillCurrency(killer, cash)
{
    local share = (cash * TEAM_KILL_SHARE + 0.5).tointeger()
    local team = killer.GetTeam()

    for (local i = 1; i <= Constants.Server.MAX_PLAYERS; i++)
    {
        local player = PlayerInstanceFromIndex(i)
        if (player == null || player == killer)
            continue

        if (player.GetTeam() == team)
            AddCurrency(player, share)
    }
}

// Does the team have a medic that is not dead?
function TeamHasAliveMedic(team)
{
    for (local i = 1; i <= Constants.Server.MAX_PLAYERS; i++)
    {
        local player = PlayerInstanceFromIndex(i)
        if (player == null)
            continue

        if (player.GetTeam() != team)
            continue

        if (player.GetPlayerClass() != Constants.ETFClass.TF_CLASS_MEDIC)
            continue

        // 0 is alive; a Medic who is dying or dead doesn't count
        if (NetProps.GetPropInt(player, "m_lifeState") == 0)
            return true
    }
    return false
}

function RemoveReviveMarker(client)
{
    local idx = client.entindex()
    local marker = reviveMarkers[idx]
    if (marker != null && marker.IsValid())
        marker.Kill()

    reviveMarkers[idx] = null
}

function ClearReviveMarkers()
{
    local ent = null
    while (ent = Entities.FindByClassname(ent, "entity_revive_marker"))
    {
        ent.Kill()
    }

    for (local i = 1; i <= Constants.Server.MAX_PLAYERS; i++)
        reviveMarkers[i] = null
}

// Mirrors CTFReviveMarker::Create's logic, spawn the marker slightly
// above the player, then set the owner entity, team and class bodygroup
function SpawnReviveMarker(victim)
{
    RemoveReviveMarker(victim)

    local ang = victim.GetAbsAngles()
    local marker = SpawnEntityFromTable("entity_revive_marker",
    {
        origin  = victim.GetOrigin() + Vector(0, 0, 50),
        angles  = Vector(0, ang.y, 0)
    })

    if (marker == null)
        return

    NetProps.SetPropEntity(marker, "m_hOwner", victim)
    marker.SetTeam(victim.GetTeam())
    marker.SetBodygroup(1, victim.GetPlayerClass() - 1)
    reviveMarkers[victim.entindex()] = marker
}

// Spawns an upgrade zone over every resupply locker trigger on the map
function SpawnUpgradeZonesAtResupply()
{
    local ent = null
    while (ent = Entities.FindByClassname(ent, "func_regenerate"))
    {
        local mins = ent.GetBoundingMins()
        local maxs = ent.GetBoundingMaxs()

        local brush = SpawnEntityFromTable("func_upgradestation",
        {
            targetname  = "vscript_upgrade_station",
            origin      = ent.GetOrigin()
        })

        brush.KeyValueFromInt("solid", 2)
        brush.KeyValueFromString("mins", mins.x.tostring() + " " + mins.y.tostring() + " " + mins.z.tostring())
        brush.KeyValueFromString("maxs", maxs.x.tostring() + " " + maxs.y.tostring() + " " + maxs.z.tostring())
    }
}

// Returns the team that is being steamrolled, or -1 if there isn't a steamroll
function GetSteamrolledTeam()
{
    local red = teamKills[TEAM_RED]
    local blu = teamKills[TEAM_BLU]

    if (red + blu < STEAMROLL_MIN_KILLS)
        return -1
    if (red >= blu * STEAMROLL_RATIO)
        return TEAM_BLU
    if (blu >= red * STEAMROLL_RATIO)
        return TEAM_RED
    return -1
}

// Torments the player with that god-damned sound...
function PlayMoneySound(client)
{
    local idx = client.entindex()
    local now = Time()
    if (now - moneySoundTime[idx] < MONEY_PICKUP_COOLDOWN)
        return

    moneySoundTime[idx] = now
    EmitSoundEx({
        sound_name  = MONEY_PICKUP_SOUND,
        entity      = client,
        filter_type = Constants.EScriptRecipientFilter.RECIPIENT_FILTER_SINGLE_PLAYER
    })
}

function AddCurrency(client, cash)
{
    // The losing team of a steamroll earns extra
    if (client.GetTeam() == GetSteamrolledTeam())
        cash = (cash * STEAMROLL_BONUS + 0.5).tointeger()

    client.SetCurrency(client.GetCurrency() + cash)
    earnedCash[client.entindex()] += cash

    if (cash > 0)
        PlayMoneySound(client)
}

function IsWaitingForPlayers()
{
    local rules = Entities.FindByClassname(null, "tf_gamerules")
    return rules != null && NetProps.GetPropBool(rules, "m_bInWaitingForPlayers")
}

function GetBuybackDelay()
{
    return 2.0 + GetConvarFloat("spec_freeze_traveltime", 0.4) + GetConvarFloat("spec_freeze_time", 4.0)
}

function ShowBuybackHud(client, state, text)
{
    if (state.hud == null || !state.hud.IsValid())
    {
        state.hud = SpawnEntityFromTable("game_text",
        {
            targetname  = "vscript_buyback_hud",
            message     = text,
            x           = -1,
            y           = 0.7,
            effect      = 0,
            color       = "255 255 255",
            color2      = "255 255 255",
            fadein      = 0,
            fadeout     = 0,
            holdtime    = BUYBACK_HUD_INTERVAL + 0.25,
            channel     = BUYBACK_HUD_CHANNEL,
            spawnflags  = 0
        })
    }

    state.hud.KeyValueFromString("message", text)
    EntFireByHandle(state.hud, "Display", "", 0.0, client, client)
}

function RemoveBuybackHud(client, state)
{
    local hud = state.hud
    if (hud == null)
        return

    state.hud = null
    if (!hud.IsValid())
        return

    // FIXME: Is this workaround needed??
    if (client != null)
    {
        hud.KeyValueFromString("message", " ")
        hud.KeyValueFromFloat("holdtime", 0.1)
        EntFireByHandle(hud, "Display", "", 0.0, client, client)
    }

    EntFireByHandle(hud, "Kill", "", 0.1, null, null)
}

function ClearBuybackHuds()
{
    foreach (idx, tracked in buybackDead)
    {
        local state = buybackState[idx]
        if (state.hud != null)
            RemoveBuybackHud(PlayerInstanceFromIndex(idx), state)
    }
}

function ResetBuybackState(idx)
{
    local state = buybackState[idx]
    RemoveBuybackHud(PlayerInstanceFromIndex(idx), state)
    if (idx in buybackDead)
        delete buybackDead[idx]

    state.deathTime = -1.0
    state.window = -1.0
    state.held = false
    state.nextHud = 0.0
    state.estimate = -1.0
    state.skip = false
    state.opened = false
}

function StartBuybackTracking(victim)
{
    local idx = victim.entindex()
    ResetBuybackState(idx)
    buybackState[idx].deathTime = Time()
    buybackDead[idx] <- true
}

function GetConvarFloat(name, fallback)
{
    local value = Convars.GetFloat(name)
    return value == null ? fallback : value
}

function CountTeamPlayers(team)
{
    local count = 0
    local player = null
    while (player = Entities.FindByClassname(player, "player"))
    {
        if (player.GetTeam() == team)
            count++
    }
    return count
}

// Wave lengths and the freeze delay don't change often...
function RefreshWaveCache(now)
{
    if (now - waveCache.time < WAVE_CACHE_INTERVAL)
        return

    waveCache.time = now
    waveCache.rules = Entities.FindByClassname(null, "tf_gamerules")
    waveCache.delay = GetBuybackDelay()
    foreach (team in [TEAM_RED, TEAM_BLU])
    {
        waveCache.scaled[team] <- GetWaveLength(team, true)
        waveCache.unscaled[team] <- GetWaveLength(team, false)
    }
}

// Taken from CTeamplayRoundBasedRules::GetRespawnWaveMaxLength.
// Returns 0 when there are no respawn waves.
function GetWaveLength(team, scaled)
{
    local rules = Entities.FindByClassname(null, "tf_gamerules")
    if (rules == null || GetConvarFloat("mp_disable_respawn_times", 0.0) != 0.0)
        return 0.0

    // A team specific time (e.g. set by the map) overrides mp_respawnwavetime
    local length = NetProps.GetPropFloatArray(rules, "m_TeamRespawnWaveTimes", team)
    if (length < 0.0)
        length = GetConvarFloat("mp_respawnwavetime", 10.0)

    // Small teams get shorter waves, but never under 5 seconds
    if (scaled && length > 5.0)
    {
        local scalar = (CountTeamPlayers(team) - 1) / 7.0
        if (scalar < 0.0)
            scalar = 0.0
        if (scalar > 1.0)
            scalar = 1.0

        length = length * (0.25 + 0.75 * scalar)
        if (length < 5.0)
            length = 5.0
    }
    return length
}

// Taken from CTeamplayRoundBasedRules::GetNextRespawnWave.
// Returns the game time the player will respawn at, or -1 if it can't be worked out.
function GetRespawnTime(client)
{
    local state = buybackState[client.entindex()]
    local rules = waveCache.rules
    if (rules == null || !rules.IsValid() || state.deathTime < 0.0)
        return -1.0

    local team = client.GetTeam()
    if (!(team in waveCache.scaled))
        return -1.0

    local waveLength = waveCache.scaled[team]
    if (waveLength <= 0.0)
        return -1.0

    local nextWave = NetProps.GetPropFloatArray(rules, "m_flNextRespawnWave", team)
    if (nextWave <= 0.0)
        return -1.0

    // The earliest a player may spawn: the death animation
    // and freeze panel, plus one full unscaled wave
    local earliest = state.deathTime + waveCache.delay + waveCache.unscaled[team]

    // Waves keep coming every waveLength; they spawn in the first one that is late enough
    local guard = 0
    while (nextWave < earliest && guard < 100)
    {
        nextWave += waveLength
        guard++
    }
    return nextWave
}

// The price falls from BUYBACK_MAX_COST to BUYBACK_MIN_COST
// as the cutoff approaches, stepping by BUYBACK_PRICE_STEP
function GetBuybackPrice(window, remaining)
{
    local span = window - BUYBACK_CUTOFF
    local fraction = span > 0.0 ? (remaining - BUYBACK_CUTOFF) / span : 0.0
    if (fraction < 0.0)
        fraction = 0.0
    if (fraction > 1.0)
        fraction = 1.0

    local price = (BUYBACK_MIN_COST + (BUYBACK_MAX_COST - BUYBACK_MIN_COST) * fraction + 0.5).tointeger()
    return ((price + BUYBACK_PRICE_STEP / 2) / BUYBACK_PRICE_STEP) * BUYBACK_PRICE_STEP
}

function BroadcastTeamColoredMessage(player, actionText)
{
    if (player == null || !player.IsPlayer())
        return

    local teamNum = player.GetTeam()
    local colorCode = "\x01"

    if (teamNum == 2) {
        colorCode = "\x07FF3D3D"
    } else if (teamNum == 3) {
        colorCode = "\x079ACDFF"
    } else if (teamNum == 1) {
        colorCode = "\x07CCCCCC"
    }

    local playerName = NetProps.GetPropString(player, "m_szNetname")
    local coloredName = colorCode + playerName + "\x01"
    local finalMessage = coloredName + " " + actionText

    ClientPrint(null, HUD_PRINTTALK, finalMessage)
}

function TryBuyback(client, price, state)
{
    if (client.GetCurrency() < price)
    {
        EmitSoundEx({
            sound_name  = BUYBACK_DENIED_SOUND,
            entity      = client,
            filter_type = Constants.EScriptRecipientFilter.RECIPIENT_FILTER_SINGLE_PLAYER
        })
        return
    }

    client.SetCurrency(client.GetCurrency() - price)

    // Money spent on buy-back isn't refundable
    local idx = client.entindex()
    earnedCash[idx] -= price
    if (earnedCash[idx] < 0)
        earnedCash[idx] = 0

    RemoveBuybackHud(client, state)
    state.estimate = -1.0
    client.ForceRespawn()

    BroadcastTeamColoredMessage(client, format("has \x05bought back\x01 into the game for %d credits!", price))

    EmitSoundEx({
        sound_name  = BUYBACK_BOUGHT_IN_SOUND,
        entity      = client
    })
}

// MvM makes buildings free to build and upgrade between waves, we do it at setup time.
function UpdateBuildingsDuringSetup()
{
    local rules = Entities.FindByClassname(null, "tf_gamerules")
    local inSetup = !arenaMode && rules != null && NetProps.GetPropBool(rules, "m_bInSetup")
    if (inSetup == setupActive)
        return

    setupActive = inSetup

    // tf_cheapobjects and tf_fastbuild default to 0, so that's what they go back to
    local value = inSetup ? 1 : 0
    Convars.SetValue("tf_cheapobjects", value)
    Convars.SetValue("tf_fastbuild", value)
}

function OnGameEvent_player_builtobject(params)
{
    if (!setupActive || params.object == OBJECT_TYPE_SAPPER)
        return

    local building = EntIndexToHScript(params.index)
    if (building == null || !building.IsValid())
        return

    // Bring back the Level 3 Mini-Sentry bug...it's been so long...
    if (NetProps.HasProp(building, "m_bMiniBuilding") && NetProps.GetPropBool(building, "m_bMiniBuilding"))
        return

    local hasLevel = NetProps.HasProp(building, "m_iUpgradeLevel")
    if (DEBUG && hasLevel)
        printl("building level before: " + NetProps.GetPropInt(building, "m_iUpgradeLevel"))

    NetProps.SetPropInt(building, "m_nDefaultUpgradeLevel", SETUP_BUILDING_LEVEL - 1)
    building.AcceptInput("Enable", "", null, null)

    if (DEBUG && hasLevel)
        printl("building level after: " + NetProps.GetPropInt(building, "m_iUpgradeLevel"))
}

// Ugly hack to avoid people being able to buy a canteen charge, use
// some then immediately refund and get their full refund amount back.
function WatchCanteenPurchases()
{
    local seen = {}

    local bottle = null
    while (bottle = Entities.FindByClassname(bottle, "tf_powerup_bottle"))
    {
        local owner = NetProps.GetPropEntity(bottle, "m_hOwnerEntity")
        if (owner == null || !owner.IsPlayer())
            continue

        local idx = owner.entindex()
        local watch = canteenWatch[idx]
        local charges = NetProps.GetPropInt(bottle, "m_usNumCharges")
        local bought = charges - watch.charges
        if (bought > 0)
        {
            // Never count more than the charges could have cost,
            // as other upgrades can be bought in the same moment
            local spent = watch.currency - owner.GetCurrency()
            local cap = bought * CANTEEN_MAX_CHARGE_COST
            if (spent > cap)
                spent = cap

            if (spent > 0)
            {
                earnedCash[idx] -= spent
                if (earnedCash[idx] < 0)
                    earnedCash[idx] = 0
            }
        }

        watch.charges = charges
        seen[idx] <- true
    }

    local player = null
    while (player = Entities.FindByClassname(player, "player"))
    {
        local idx = player.entindex()
        local watch = canteenWatch[idx]
        if (!(idx in seen))
            watch.charges = 0
        watch.currency = player.GetCurrency()
    }
}

// Runs on worldspawn's think.
function OnWorldSpawnThink()
{
    local now = Time()
    if (now >= slowWorkTime)
    {
        slowWorkTime = now + SLOW_WORK_INTERVAL
        UpdateBuildingsDuringSetup()
        WatchCanteenPurchases()
    }

    if (!roundRunning || arenaMode)
    {
        ClearBuybackHuds()
        return BUYBACK_IDLE_INTERVAL
    }

    // The dead players being tracked. This is copied.
    local dead = []
    foreach (idx, tracked in buybackDead)
        dead.append(idx)

    if (dead.len() == 0)
        return BUYBACK_IDLE_INTERVAL

    RefreshWaveCache(now)

    local fast = false
    foreach (idx in dead)
    {
        local client = PlayerInstanceFromIndex(idx)
        if (client == null)
        {
            ResetBuybackState(idx)
            continue
        }

        local state = buybackState[idx]

        // Only dead players can buy back...
        if (NetProps.GetPropInt(client, "m_lifeState") == 0 || client.GetTeam() < TEAM_RED)
            continue

        local respawn = GetRespawnTime(client)
        if (respawn < 0.0)
            continue

        state.estimate = respawn

        // Buy-back window is after the freeze cam but shortly before respawning.
        local opens = state.deathTime + waveCache.delay
        local remaining = respawn - now
        if (now < opens)
            continue

        // Avoid accidental presses of the button(TM)
        local held = (NetProps.GetPropInt(client, "m_nButtons") & BUYBACK_BUTTON) != 0
        if (!state.opened)
        {
            state.opened = true
            state.held = held
        }
        local pressed = held && !state.held
        state.held = held

        // Is the buyback window worth opening to the player?
        if (state.window < 0.0)
        {
            state.window = respawn - opens
            if (state.window - BUYBACK_CUTOFF < BUYBACK_MIN_WINDOW)
                state.skip = true
        }

        if (state.skip)
            continue

        if (remaining - BUYBACK_CUTOFF <= 0.0)
        {
            RemoveBuybackHud(client, state)
            continue
        }

        fast = true
        local price = GetBuybackPrice(state.window, remaining)
        if (pressed)
        {
            TryBuyback(client, price, state)
            continue
        }

        if (now >= state.nextHud)
        {
            ShowBuybackHud(client, state, format("Press RELOAD to buy back into the game for $%d", price))
            state.nextHud = now + BUYBACK_HUD_INTERVAL
        }
    }

    return fast ? BUYBACK_THINK_INTERVAL : BUYBACK_IDLE_INTERVAL
}

function OnGameEvent_player_death(params)
{
    if (params.death_flags & FLAG_DEAD_RINGER)
        return

    local attacker = GetPlayerFromUserID(params.attacker)
    local assister = GetPlayerFromUserID(params.assister)
    local victim = GetPlayerFromUserID(params.userid)

    if (victim != null)
        StartBuybackTracking(victim)

    // Do we have a medic? If so spawn a reanimator for said medic.
    // FIXME: This probably should be generalized to a medic in general?
    if (victim != null && TeamHasAliveMedic(victim.GetTeam()))
        SpawnReviveMarker(victim)

    if (attacker != null)
    {
        if (attacker != victim && attacker.GetTeam() != victim.GetTeam())
        {
            local attackerTeam = attacker.GetTeam()
            if (attackerTeam in teamKills)
                teamKills[attackerTeam] += 1

            AddCurrency(attacker, KILL_CASH)
            if (!arenaMode)
                ShareKillCurrency(attacker, KILL_CASH)
            deathStreak[attacker.entindex()] = 0
            deathStreak[victim.entindex()] += 1
        }
    }

    if (assister != null)
    {
        if (assister != victim && assister.GetTeam() != victim.GetTeam())
        {
            if (assister.GetPlayerClass() == Constants.ETFClass.TF_CLASS_MEDIC)
            {
                AddCurrency(assister, MEDIC_ASSIST_CASH)
                deathStreak[assister.entindex()] = 0
            }
            else
            {
                AddCurrency(assister, ASSIST_CASH)
            }
        }
    }
}

function OnGameEvent_teamplay_point_captured(params)
{
    for (local i = 1; i <= Constants.Server.MAX_PLAYERS; i++)
    {
        local client = PlayerInstanceFromIndex(i)
        if (client == null)
            continue

        // 100 is added to the cappers without hooking this event
        // Cappers get 200, the rest of the team 100
        if (client.GetTeam() == params.team)
            AddCurrency(client, POINT_CAPTURE_CASH)
    }
}

function OnGameEvent_teamplay_flag_event(params)
{
    // Captured..
    if (params.eventtype == FLAG_EVENT_CAPTURE)
    {
        local player = PlayerInstanceFromIndex(params.player)
        for (local i = 1; i <= Constants.Server.MAX_PLAYERS; i++)
        {
            local client = PlayerInstanceFromIndex(i)
            if (client == null)
                continue

            if (client == player)
                AddCurrency(client, FLAG_CAPTURE_CASH)
            else if(client.GetTeam() == player.GetTeam())
                AddCurrency(client, FLAG_CAPTURE_TEAM_CASH)
        }
    }
}

// We actually need to check for this every round now.
arenaMode = IsArenaMode()

// worldspawn is never removed, so a think on it runs for the whole map.
// bindenv keeps the script's own functions and variables visible inside the think.
local world = Entities.FindByClassname(null, "worldspawn")
world.ValidateScriptScope()
world.GetScriptScope().OnWorldSpawnThink <- OnWorldSpawnThink.bindenv(this)
AddThinkToEnt(world, "OnWorldSpawnThink")

__CollectGameEventCallbacks(this)
