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

function GetBuybackDelay()
{
    return 2.0 + GetConvarFloat("spec_freeze_traveltime", 0.4) + GetConvarFloat("spec_freeze_time", 4.0)
}

function ShowHudText(client, state, targetname, text, channel, holdtime, ypos)
{
    if (state.hud == null || !state.hud.IsValid())
    {
        state.hud = SpawnEntityFromTable("game_text",
        {
            targetname  = targetname,
            message     = text,
            x           = -1,
            y           = ypos,
            effect      = 0,
            color       = "255 255 255",
            color2      = "255 255 255",
            fadein      = 0,
            fadeout     = 0,
            holdtime    = holdtime,
            channel     = channel,
            spawnflags  = 0
        })
    }

    state.hud.KeyValueFromString("message", text)
    EntFireByHandle(state.hud, "Display", "", 0.0, client, client)
}

function HideHudText(client, state)
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
    foreach (idx, state in buybackState)
    {
        if (state.hud != null && state.deathTime >= 0.0)
            HideHudText(PlayerInstanceFromIndex(idx), state)
    }
}

function ResetBuybackState(idx)
{
    local state = buybackState[idx]
    HideHudText(PlayerInstanceFromIndex(idx), state)

    state.deathTime = -1.0
    state.window = -1.0
    state.held = false
    state.nextHud = 0.0
    state.estimate = -1.0
    state.skip = false
    state.opened = false
    state.lastPrice = 0.0
}

function ResetRefundState(idx)
{
    local state = refundState[idx]
    HideHudText(PlayerInstanceFromIndex(idx), state)

    state.held = false
    state.opened = false
    state.nextHud = 0.0
}

function StartBuybackTracking(victim)
{
    local idx = victim.entindex()
    ResetBuybackState(idx)
    buybackState[idx].deathTime = Time()
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
    foreach (team in [Constants.ETFTeam.TF_TEAM_RED, Constants.ETFTeam.TF_TEAM_BLUE])
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

    ClientPrint(null, Constants.EHudNotify.HUD_PRINTTALK, finalMessage)
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

    HideHudText(client, state)
    state.estimate = -1.0
    client.ForceRespawn()

    BroadcastTeamColoredMessage(client, format("has \x05bought back\x01 into the game for %d credits!", price))

    EmitSoundEx({
        sound_name  = BUYBACK_BOUGHT_IN_SOUND,
        entity      = client
    })
}