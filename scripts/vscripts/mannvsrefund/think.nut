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


function CheckRefundButtons(now)
{
    local inZone = false
    for (local i = 1; i <= Constants.Server.MAX_PLAYERS; i++)
    {
        local client = PlayerInstanceFromIndex(i)
        if (client == null || !client.IsValid())
            continue

        if (client.GetTeam() < Constants.ETFTeam.TF_TEAM_RED)
            continue

        local state = refundState[i]
        // Dead players never get the prompt or the trigger
        local zone = NetProps.GetPropInt(client, "m_lifeState") == 0 &&
                     NetProps.GetPropBool(client, "m_Shared.m_bInUpgradeZone")
        if (!zone)
        {
            if (state.opened)
            {
                HideHudText(client, state)
                state.opened = false
                state.held = false
            }
            continue
        }

        inZone = true

        // Avoid accidental presses of the button(TM)
        local held = (NetProps.GetPropInt(client, "m_nButtons") & Constants.FButtons.IN_RELOAD) != 0
        if (state.opened)
        {
            if (held && !state.held)
                DoRefund(client, i)
        }
        else
        {
            state.opened = true
        }
        state.held = held

        if (now >= state.nextHud)
        {
            ShowHudText(client, state, "vscript_refund_hud",
                        REFUND_PROMPT, REFUND_HUD_CHANNEL, REFUND_HUD_INTERVAL + 0.15, 0.135)
            state.nextHud = now + REFUND_HUD_INTERVAL
        }
    }
    return inZone
}

// Runs on worldspawn's think.
function OnWorldSpawnThink()
{
    local now = Time()
    local waiting = IsWaitingForPlayers()
    if (now >= slowWorkTime)
    {
        slowWorkTime = now + SLOW_WORK_INTERVAL
        // But nobody came.
        if (!waiting)
        {
            ProcessPendingWipes(WIPE_BATCH_COUNT)
            UpdateBuildingsDuringSetup()
            WatchCanteenPurchases()
        }
    }

    // Check here so that we can have a fast path...
    local refundZone = CheckRefundButtons(now)

    if (!roundRunning || arenaMode)
    {
        ClearBuybackHuds()
        return refundZone ? BUYBACK_THINK_INTERVAL : BUYBACK_IDLE_INTERVAL
    }

    // The dead players being tracked. This is copied.
    local dead = []
    foreach (idx, state in buybackState)
    {
        if (state.deathTime >= 0.0)
            dead.append(idx)
    }

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
        if (NetProps.GetPropInt(client, "m_lifeState") == 0 || client.GetTeam() < Constants.ETFTeam.TF_TEAM_RED)
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
        local held = (NetProps.GetPropInt(client, "m_nButtons") & Constants.FButtons.IN_RELOAD) != 0
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
            HideHudText(client, state)
            continue
        }

        fast = true
        local price = GetBuybackPrice(state.window, remaining)
        if (pressed)
        {
            TryBuyback(client, price, state)
            continue
        }

        if (price != state.lastPrice && now >= state.nextHud)
        {
            state.lastPrice = price
            state.nextHud = now + BUYBACK_HUD_INTERVAL
            ShowHudText(client, state, "vscript_buyback_hud",
                        format("Press RELOAD to buy back into the game for $%d", price),
                        BUYBACK_HUD_CHANNEL, BUYBACK_HUD_INTERVAL, 0.33)
        }
    }

    return (fast || refundZone) ? BUYBACK_THINK_INTERVAL : BUYBACK_IDLE_INTERVAL
}