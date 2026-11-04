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

const CREDITS_MESSAGE = "\x01Mann versus Refund. Created by \x079E2A2Brake\x01."
const REFUND_PROMPT = "Hold RELOAD to reset your current upgrades."
const DEBUG = false // Set to true to print round info to the server console
const MONEY_VANISH_SOUND = "mvm/mvm_money_vanish.wav"
const FLAG_EVENT_CAPTURE = 2
const WIPE_BATCH_COUNT = 2
const SETUP_BUILDING_LEVEL = 3
const OBJECT_TYPE_SAPPER = 3
const UPGRADE_VO_COUNT = 11
const FLAG_DEAD_RINGER = 32
const REFUND_HUD_INTERVAL = 1.0

// This requires the custom model in the assets folder.
const TEAMCOLOR_TOMBSTONE_MODEL = "models/props_mvm/mvm_revive_tombstone_teamcolor.mdl"

// I'm going to be a jerk and just assume your spending it all on Crit Canteens
const CANTEEN_MAX_CHARGE_COST = 100

// Currency amounts
const START_CASH = 500
const KILL_CASH = 100
const ASSIST_CASH = 50
const MEDIC_ASSIST_CASH = 100
const POINT_CAPTURE_CASH = 100       // Whole team, on top of the game's own cap bonus
const FLAG_CAPTURE_CASH = 300        // Player who captured the flag
const FLAG_CAPTURE_TEAM_CASH = 200   // Rest of the capturer's team

// Currency scaling
const CASH_SCALE_REF_COUNT = 6      // Minimum team sized required for scaling
const CASH_SCALE_STEP_PLAYERS = 2   // Each ladder step spans this many extra players
const CASH_SCALE_STEP = 0.07        // ...and trims payouts by this fraction
const CASH_SCALE_MIN = 0.1          // The minimum scaling for the money no matter what.
const CASH_ROUND_TO = 5

// Fraction of a kill's credit given to each of the killer's teammates
// This doesn't apply in Arena Mode because we do it differently there.
const TEAM_KILL_SHARE = 0.5

// if one team is far ahead on kills this round, the other team earns more
const STEAMROLL_MIN_KILLS = 20   // Total kills needed before a steamroll can be declared
const STEAMROLL_RATIO = 2.0      // Leading team needs this many times the other team's kills
const STEAMROLL_BONUS = 1.1      // Income multiplier for the losing team

// MvM buyback logic.
const BUYBACK_MAX_COST = 300         // Price right after dying
const BUYBACK_MIN_COST = 100         // Price just before buy-back closes
const BUYBACK_CUTOFF = 3.0           // Buy-back closes this many seconds before the respawn
const BUYBACK_THINK_INTERVAL = 0.05  // How often dead players' buttons are checked
const BUYBACK_IDLE_INTERVAL = 0.25   // Think rate when nobody is dead
const BUYBACK_HUD_INTERVAL = 0.5     // How often the HUD text is refreshed
const BUYBACK_PRICE_STEP = 5         // The price drops in steps of this much
const BUYBACK_DENIED_SOUND = "replay/cameracontrolerror.wav"
const BUYBACK_BOUGHT_IN_SOUND = "mvm/mvm_bought_in.wav"
const BUYBACK_MIN_WINDOW = 5.0       // Buy-back must stay open at least this long to be offered at all (very short respawns skip it)

// hud text channels
const BUYBACK_HUD_CHANNEL = 1
const REFUND_HUD_CHANNEL = 2

// performance duct tape
const SLOW_WORK_INTERVAL = 0.25      // How often setup and canteen checks run
const WAVE_CACHE_INTERVAL = 0.5      // How often respawn wave lengths are recalculated

// Sound for receiving money
const MONEY_PICKUP_SOUND = "mvm/mvm_money_pickup.wav"
const MONEY_PICKUP_COOLDOWN = 1.0    // Adjust this to avoid hearing "mvm/mvm_money_pickup.wav" constantly

// Gas Passer Nerf
const GAS_BLAST_DAMAGE = 350         // Base damage before resistances applied.

// MvM sounds aren't precached on non-MvM maps
function PrecacheAssets()
{
    PrecacheSound(MONEY_VANISH_SOUND)
    PrecacheSound(MONEY_PICKUP_SOUND)
    PrecacheSound(BUYBACK_BOUGHT_IN_SOUND)
    PrecacheSound(BUYBACK_DENIED_SOUND)
    for (local i = 1; i <= UPGRADE_VO_COUNT; i++)
        PrecacheSound(format("vo/mvm_get_to_upgrade%02d.mp3", i))
}

function IsWaitingForPlayers()
{
    local rules = Entities.FindByClassname(null, "tf_gamerules")
    return rules != null && NetProps.GetPropBool(rules, "m_bInWaitingForPlayers")
}