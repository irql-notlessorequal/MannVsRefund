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

hasCompanion <- false
changedFile <- false // Did the user change the upgrades file from the companion?
resetQueue <- [] // Queue for clients that need their upgrades to be reset.
hasRecievedCash <- {}
earnedCash <- {} // Total currency each player has received this round
reviveMarkers <- {} // Each player's current revive marker entity, if any
buybackState <- {} // Each player's buy-back tracking (time of death and current cost)
refundState <- {} // Each player's tracking of their resupply locker visit.
moneySoundTime <- {} // When each player last heard the pickup sound
canteenWatch <- {} // Each player's last seen canteen charges and money
waveCache <- { time = -100.0, rules = null, delay = 0.0, scaled = {}, unscaled = {} } // Wave lengths are expensive
slowWorkTime <- 0.0 // When the setup and canteen checks next run
roundRunning <- false // True while the round is live, which is when respawn waves run
arenaMode <- false // Arena has no respawn waves, so there's no buy-back there
setupActive <- false // True when we are in pre-round setup
setupUpgrades <- false // Did we place the upgrade station entities?
cashScale <- { red = 0, blu = 0 } // We need this for per-team currency scaling

teamKills <- {}  // Kills per team this round, used for steamroll detection
teamKills[Constants.ETFTeam.TF_TEAM_RED] <- 0
teamKills[Constants.ETFTeam.TF_TEAM_BLUE] <- 0

redWins <- 0 // Round tracking
blueWins <- 0
roundThreshold <- 0
multiStageMap <- false

for (local i = 1; i <= Constants.Server.MAX_PLAYERS; i++)
{
    hasRecievedCash[i] <- false
    earnedCash[i] <- 0
    reviveMarkers[i] <- null
    refundState[i] <- { hud = null, held = false, opened = false, nextHud = 0.0 }
    buybackState[i] <- { deathTime = -1.0, window = -1.0, held = false, nextHud = 0.0,
                         estimate = -1.0, hud = null, skip = false, opened = false, lastPrice = 0.0 }
    moneySoundTime[i] <- 0.0
    canteenWatch[i] <- { charges = 0, currency = 0, reset = false }
}