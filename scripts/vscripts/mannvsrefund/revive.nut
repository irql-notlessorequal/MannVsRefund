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
    local found = []
    local ent = null
    while (ent = Entities.FindByClassname(ent, "entity_revive_marker"))
        found.append(ent)
    foreach (e in found)
        if (e != null && e.IsValid())
            e.Kill()

    for (local i = 1; i <= Constants.Server.MAX_PLAYERS; i++)
        reviveMarkers[i] = null
}

// Mirrors CTFReviveMarker::Create's logic, spawn the marker slightly
// above the player, then set the owner entity, team and class bodygroup
function SpawnReviveMarker(victim)
{
    RemoveReviveMarker(victim)

    local ang = victim.GetAbsAngles()
    local spawnTable =
    {
        origin  = victim.GetOrigin() + Vector(0, 0, 50),
        angles  = Vector(0, ang.y, 0)
    }

    local marker = SpawnEntityFromTable("entity_revive_marker", spawnTable)
    if (marker == null)
        return

    NetProps.SetPropEntity(marker, "m_hOwner", victim)
    marker.SetTeam(victim.GetTeam())
    marker.SetBodygroup(1, victim.GetPlayerClass() - 1)

    if (hasCompanion)
    {
        NetProps.SetPropInt(marker, "m_nModelIndex", PrecacheModel(TEAMCOLOR_TOMBSTONE_MODEL))
        marker.SetSkin(victim.GetTeam() == Constants.ETFTeam.TF_TEAM_BLUE ? 1 : 0)
    }

    reviveMarkers[victim.entindex()] = marker
}