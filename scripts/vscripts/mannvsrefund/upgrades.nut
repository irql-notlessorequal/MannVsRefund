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

function DoRefund(client)
{
    // A player could just switch loadout at the resupply
    // locker and keep some of their upgrades for free...
    RemoveUpgradesFromAllClasses(client)

    // Reset all canteens on the player...
    ResetCanteens(client)

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

    // Respawn the player
    client.ForceRespawn()
}

function ResetPlayerData(idx)
{
    hasRecievedCash[idx] = false
    earnedCash[idx] = 0
    moneySoundTime[idx] = 0.0
    canteenWatch[idx] = { charges = 0, currency = 0 }
    ResetRefundState(idx)
    ResetBuybackState(idx)
}

function ResetPlayers()
{
    for (local i = 1; i <= Constants.Server.MAX_PLAYERS; i++)
    {
        ResetPlayerData(i)
    }

    changedFile = false
}

function ProcessPendingWipes(maxPerTick)
{
    local done = 0
    local i = 0
    while (i < resetQueue.len() && done < maxPerTick)
    {
        local idx = resetQueue[i]
        local client = PlayerInstanceFromIndex(idx)

        if (client == null || !client.IsValid())
        {
            resetQueue.remove(i)
            continue
        }

        if (client.GetTeam() < 2)
        {
            resetQueue.remove(i)
            continue
        }

        // Player may have disconnected and another client reused the slot;
        // only wipe if this slot already got its start cash this round.
        if (!hasRecievedCash[idx])
        {
            resetQueue.remove(i)
            continue
        }

        // Wiping cycles through classes and regenerates, so wait until they're alive again
        if (NetProps.GetPropInt(client, "m_lifeState") != 0)
        {
            i++
            continue
        }

        RemoveUpgradesFromAllClasses(client, client.GetMaxHealth())
        resetQueue.remove(i)
        done++
    }
}

function EnqueueWipe(idx)
{
    if (resetQueue.find(idx) == null)
        resetQueue.append(idx)
}

// Floor-average spendable cash from the current team
// This excludes money spent on buybacks or canteen spam
function RemoveUpgradesFromAllClasses(client, health = null)
{
    local playerClass = client.GetPlayerClass()
    if (health == null)
        health = client.GetHealth()

    for (local i = 1; i <= Constants.ETFClass.TF_CLASS_ENGINEER; i++)
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

function ResetCanteens(client = null)
{
    local ent = null
    while (ent = Entities.FindByClassname(ent, "tf_powerup_bottle"))
    {
        if (client != null && NetProps.GetPropEntity(ent, "m_hOwnerEntity") != client)
            continue

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
    local found = []
    local ent = null
    while (ent = Entities.FindByName(ent, "vscript_upgrade_station"))
        found.append(ent)
    foreach (e in found)
        if (e != null && e.IsValid())
            e.Kill()
}

// Spawns an upgrade zone over every resupply locker trigger on the map
function EnsureUpgradeZonesAtResupply()
{
    if (!setupUpgrades)
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

            brush.KeyValueFromInt("solid", Constants.ESolidType.SOLID_BBOX)
            brush.SetSize(mins, maxs)
        }
        setupUpgrades = true
    }
}