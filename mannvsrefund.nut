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
const NUM_CLASSES = 9
const UPGRADE_VO_COUNT = 11
const FLAG_DEAD_RINGER = 32

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

// MvM sounds aren't precached on non-MvM maps
function PrecacheUpgradeSounds()
{
    PrecacheSound(MONEY_VANISH_SOUND)
    for (local i = 1; i <= UPGRADE_VO_COUNT; i++)
        PrecacheSound(format("vo/mvm_get_to_upgrade%02d.mp3", i))
}
PrecacheUpgradeSounds()

hasRecievedCash <- {}
deathStreak <- {}
earnedCash <- {} // Total currency each player has received this round
reviveMarkers <- {} // Each player's current revive marker entity, if any
teamKills <- {}  // Kills per team this round, used for steamroll detection
teamKills[TEAM_RED] <- 0
teamKills[TEAM_BLU] <- 0
for (local i = 1; i <= Constants.Server.MAX_PLAYERS; i++)
{
    hasRecievedCash[i] <- false
    deathStreak[i] <- 0
    earnedCash[i] <- 0
    reviveMarkers[i] <- null
}

function OnGameEvent_teamplay_round_start(params)
{
    if (DEBUG)
        printl("round_start: full_reset=" + params.full_reset)

    teamKills[TEAM_RED] = 0
    teamKills[TEAM_BLU] = 0

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

    if (params.full_round)
        ResetPlayers()
}

function OnGameEvent_teamplay_restart_round(params)
{
    ResetPlayers()
}

function OnGameEvent_player_spawn(params)
{
    local client = GetPlayerFromUserID(params.userid)
    if (client == null)
        return

    // Spawning, whether revived or respawned normally, ends their marker
    RemoveReviveMarker(client)

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

function AddCurrency(client, cash)
{
    // The losing team of a steamroll earns extra
    if (client.GetTeam() == GetSteamrolledTeam())
        cash = (cash * STEAMROLL_BONUS + 0.5).tointeger()

    client.SetCurrency(client.GetCurrency() + cash)
    earnedCash[client.entindex()] += cash
}

function OnGameEvent_player_death(params)
{
    if (params.death_flags & FLAG_DEAD_RINGER)
        return

    local attacker = GetPlayerFromUserID(params.attacker)
    local assister = GetPlayerFromUserID(params.assister)
    local victim = GetPlayerFromUserID(params.userid)

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
            if (!IsArenaMode())
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

__CollectGameEventCallbacks(this)
