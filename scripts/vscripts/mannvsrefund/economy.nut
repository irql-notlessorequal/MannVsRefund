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

function GetTeamAverageCash(team)
{
    local total = 0
    local count = 0
    for (local i = 1; i <= Constants.Server.MAX_PLAYERS; i++)
    {
        local client = PlayerInstanceFromIndex(i)
        if (client == null || !client.IsValid())
            continue
        if (client.GetTeam() != team)
            continue
        if (!(i in earnedCash))
            continue
        total += earnedCash[i]
        count++
    }
    if (count == 0)
        return null
    return total / count
}

function ShareKillCurrency(killer, cash)
{
    local share = (cash * TEAM_KILL_SHARE + 0.5).tointeger()
    local team = killer.GetTeam()
    local steamrolled = GetSteamrolledTeam()

    for (local i = 1; i <= Constants.Server.MAX_PLAYERS; i++)
    {
        local player = PlayerInstanceFromIndex(i)
        if (player == null || player == killer)
            continue

        if (player.GetTeam() == team)
            AddCurrency(player, share, steamrolled)
    }
}

// Returns the team that is being steamrolled, or -1 if there isn't a steamroll
function GetSteamrolledTeam()
{
    local red = teamKills[Constants.ETFTeam.TF_TEAM_RED]
    local blu = teamKills[Constants.ETFTeam.TF_TEAM_BLUE]

    if (red + blu < STEAMROLL_MIN_KILLS)
        return -1
    if (red >= blu * STEAMROLL_RATIO)
        return Constants.ETFTeam.TF_TEAM_BLUE
    if (blu >= red * STEAMROLL_RATIO)
        return Constants.ETFTeam.TF_TEAM_RED
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

function RecountTeamPlayers()
{
    cashScale.red = 0
    cashScale.blu = 0

    local player = null
    while (player = Entities.FindByClassname(player, "player"))
    {
        local team = player.GetTeam()
        if (team == Constants.ETFTeam.TF_TEAM_RED)
            cashScale.red++
        else if (team == Constants.ETFTeam.TF_TEAM_BLUE)
            cashScale.blu++
    }
}

function GetCashScale(team)
{
    local count = team == Constants.ETFTeam.TF_TEAM_RED ? cashScale.red : cashScale.blu
    if (count <= CASH_SCALE_REF_COUNT)
        return 1.0

    local steps = (count - CASH_SCALE_REF_COUNT + CASH_SCALE_STEP_PLAYERS - 1) / CASH_SCALE_STEP_PLAYERS
    local mult = 1.0 - steps * CASH_SCALE_STEP
    if (mult < CASH_SCALE_MIN)
        mult = CASH_SCALE_MIN
    return mult
}

function ApplyTeamScaling(team, delta)
{
    if (team == Constants.ETFTeam.TF_TEAM_RED)
        cashScale.red += delta
    else if (team == Constants.ETFTeam.TF_TEAM_BLUE)
        cashScale.blu += delta
}

function GetScaledCash(client, cash, steamrolled)
{
    // The losing team of a steamroll earns extra
    if (client.GetTeam() == steamrolled)
        cash *= STEAMROLL_BONUS

    // Scale the awarded money with the team/player count
    cash *= GetCashScale(client.GetTeam())

    if (cash > 0)
    {
        cash = (cash / CASH_ROUND_TO + 0.5).tointeger() * CASH_ROUND_TO
        if (cash < CASH_ROUND_TO)
            cash = CASH_ROUND_TO
    }
    return cash
}

function AddCurrency(client, cash, steamrolled = -2)
{
    if (steamrolled == -2)
        steamrolled = GetSteamrolledTeam()

    cash = GetScaledCash(client, cash, steamrolled)

    client.SetCurrency(client.GetCurrency() + cash)
    earnedCash[client.entindex()] += cash

    if (cash > 0)
        PlayMoneySound(client)
}