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

function OnGameEvent_teamplay_round_start(params)
{
    if (DEBUG)
        printl("round_start: full_reset=" + params.full_reset)

    teamKills[Constants.ETFTeam.TF_TEAM_RED] = 0
    teamKills[Constants.ETFTeam.TF_TEAM_BLUE] = 0
    roundRunning = false

    if (IsWaitingForPlayers())
        return

    arenaMode = IsArenaMode()
    for (local i = 1; i <= Constants.Server.MAX_PLAYERS; i++)
        ResetBuybackState(i)

    ClearReviveMarkers()
    ForceEnableUpgrades(2)
    ResetCanteens()
    EnsureUpgradeZonesAtResupply()

    RecountTeamPlayers()
    PrecacheAssets()

    ClientPrint(null, Constants.EHudNotify.HUD_PRINTTALK, CREDITS_MESSAGE)

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

    if (params.full_round || changedFile)
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
        // We need to defer the upgrade reset on high-edict scenarios...
        EnqueueWipe(client.entindex())

        client.SetCurrency(START_CASH)
        earnedCash[client.entindex()] = START_CASH
        hasRecievedCash[client.entindex()] = true
    }
}

function OnGameEvent_player_disconnect(params)
{
    local client = GetPlayerFromUserID(params.userid)
    if (client != null && client.IsValid())
    {
        RemoveReviveMarker(client)
        ResetPlayerData(client.entindex())

        // We shouldn't reset players that are gone...
        local gone = resetQueue.find(client.entindex())
        if (gone != null)
            resetQueue.remove(gone)
    }
}

function OnGameEvent_player_team(params)
{
    ApplyTeamScaling(params.oldteam, -1)

    if (params.disconnect)
        return

    ApplyTeamScaling(params.team, 1)

    if (params.team == params.oldteam)
        return

    // Only skip if the player came from spectator mode.
    if (params.team < 2)
        return

    local client = GetPlayerFromUserID(params.userid)
    if (client == null || !client.IsValid())
        return

    local idx = client.GetEntityIndex()
    // I love autobalance!
    RemoveReviveMarker(client)

    canteenWatch[idx] <- { charges = 0, currency = 0 }

    // Nuh-uh.
    if (idx in buybackState)
    {
        HideHudText(client, buybackState[idx])
        ResetBuybackState(idx)
    }

    ResetRefundState(idx)

    // Give the player an average of what their team has,
    // if their team has literally nothing, just give them
    // the default starting amount of cash.
    local avg = GetTeamAverageCash(params.team)
    if (avg == null)
        avg = START_CASH

    client.SetCurrency(avg)
    earnedCash[idx] = avg
    EnqueueWipe(idx)
}

// Wipes a batch of player's upgrades, we need to do this otherwise
// we can accidentally spike the edict count past the limit, crashing
// the server in the process.
//
// *ahem* Cowerhouse *ahem* Hacksaw *ahem* 40-player Dustbowl
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
function OnGameEvent_player_death(params)
{
    if (params.death_flags & FLAG_DEAD_RINGER)
        return

    local attacker = GetPlayerFromUserID(params.attacker)
    local assister = GetPlayerFromUserID(params.assister)
    local victim = GetPlayerFromUserID(params.userid)
    local silent = "silent_kill" in params && params.silent_kill

    if (victim != null)
        StartBuybackTracking(victim)

    // Do we have a medic? If so spawn a reanimator for said medic.
    // FIXME: This probably should be generalized to a medic in general?
    if (victim != null && TeamHasAliveMedic(victim.GetTeam()) && !silent)
        SpawnReviveMarker(victim)

    if (!roundRunning)
        return

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
        }
    }

    if (assister != null)
    {
        if (assister != victim && assister.GetTeam() != victim.GetTeam())
        {
            if (assister.GetPlayerClass() == Constants.ETFClass.TF_CLASS_MEDIC)
            {
                AddCurrency(assister, MEDIC_ASSIST_CASH)
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
    if (!roundRunning)
        return

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
    if (!roundRunning)
        return

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

function OnGameEvent_upgrades_file_changed(params)
{
    changedFile = true
}

function OnScriptHook_OnTakeDamage(params)
{
    // Try to escape this path as quick as possible.
    if (!(params.damage_type & Constants.FDmgType.DMG_SLASH) ||
          params.damage_stats != Constants.ETFDmgCustom.TF_DMG_CUSTOM_BURNING)
        return

    local weapon = params.weapon
    if (weapon == null || weapon.GetClassname() != "tf_weapon_jar_gas")
        return

    if (DEBUG)
        printl("gas burst: damage " + params.damage + " -> " + GAS_BLAST_DAMAGE + ", type " + params.damage_type)

    params.damage = GAS_BLAST_DAMAGE
    params.damage_type = params.damage_type | Constants.FDmgType.DMG_BLAST | Constants.FDmgType.DMG_BURN
}