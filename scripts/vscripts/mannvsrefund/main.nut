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
local Refund = getroottable()

IncludeScript("mannvsrefund/constants.nut", Refund)
IncludeScript("mannvsrefund/state.nut", Refund)
IncludeScript("mannvsrefund/upgrades.nut", Refund)
IncludeScript("mannvsrefund/economy.nut", Refund)
IncludeScript("mannvsrefund/revive.nut", Refund)
IncludeScript("mannvsrefund/buyback.nut", Refund)
IncludeScript("mannvsrefund/think.nut", Refund)
IncludeScript("mannvsrefund/events.nut", Refund)

Refund.PrecacheAssets()

if ("self" in this && self.GetName() == "mvr_sourcemod")
{
    Refund.hasCompanion <- true
    printl("Mann vs. Refund companion was detected.")
}

// We actually need to check for this every round now.
Refund.arenaMode = IsArenaMode()

// worldspawn is never removed, so a think on it runs for the whole map.
// bindenv keeps the script's own functions and variables visible inside the think.
local world = Entities.FindByClassname(null, "worldspawn")
world.ValidateScriptScope()
world.GetScriptScope().OnWorldSpawnThink <- Refund.OnWorldSpawnThink.bindenv(this)
AddThinkToEnt(world, "OnWorldSpawnThink")

__CollectGameEventCallbacks(Refund)
