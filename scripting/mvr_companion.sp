// MannVsRefund.
// Copyright (C) IRQL_NOT_LESS_OR_EQUAL
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
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define MAX_UPGRADE_PATH 260

static const int STALEMATE_SERVER_TIMELIMIT = 2;
static const int WINREASON_TIMELIMIT = 6;
static const char ROUND_WIN_FULL[] = "mvm_end_last_wave_short.wav";
static const char ROUND_WIN_FULL_RAW[] = "sound/mvm_end_last_wave_short.wav";
static const char ROUND_WIN_STAGED[] = "music/mvm_end_mid_wave.wav";
static const char ROUND_LOSE[] = "music/mvm_lost_wave.wav";
static const char companionAvailable[] = "mvr_sourcemod";
static const char assets[][] =
{
    "models/props_mvm/mvm_revive_tombstone_teamcolor.mdl",
    "models/props_mvm/mvm_revive_tombstone_teamcolor.dx80.vtx",
    "models/props_mvm/mvm_revive_tombstone_teamcolor.dx90.vtx",
    "models/props_mvm/mvm_revive_tombstone_teamcolor.sw.vtx",
    "models/props_mvm/mvm_revive_tombstone_teamcolor.vvd",
    "models/props_mvm/mvm_revive_tombstone_teamcolor.phy",
};

static bool g_bUpgradeFilePending = false;
static bool g_bMapTimelimitStalemate = false;
static bool g_bGameOver = false;

char g_PendingUpgradeFile[MAX_UPGRADE_PATH];

public Plugin myinfo =
{
    name = "Mann vs. Refund Companion",
    author = "IRQL_NOT_LESS_OR_EQUAL",
    description = "Enables additional functionality",
    version = "2026.11.03",
    url = "https://github.com/irql-notlessorequal/MannVsRefund"
};

public void OnPluginStart()
{
    HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_Post);
    HookEvent("teamplay_round_stalemate", Event_RoundStalemate, EventHookMode_Post);
    HookEvent("teamplay_win_panel", Event_WinPanel, EventHookMode_Post);
    HookEvent("teamplay_round_win", Event_RoundWin, EventHookMode_Post);

    HookEvent("teamplay_broadcast_audio", Event_BroadcastAudio, EventHookMode_Pre);
    AddNormalSoundHook(view_as<NormalSHook>(Hook_NormalSound));

    RegAdminCmd(
        "sm_mvr_upgradefile",
        Command_SetMvmUpgrades, ADMFLAG_RCON,
        "Changes the upgrade file used by Mann vs. Refund on the next round"
    );
}

public void OnMapStart()
{
    for (int i = 0; i < sizeof(assets); i++)
        AddFileToDownloadsTable(assets[i]);

    AddFileToDownloadsTable(ROUND_WIN_FULL_RAW);

    PrecacheModel(assets[0], true);
    PrecacheSound(ROUND_WIN_FULL);
    PrecacheSound(ROUND_WIN_STAGED);
    PrecacheSound(ROUND_LOSE);
}

public void OnConfigsExecuted()
{
    int logicScript = CreateEntityByName("logic_script");
    if (IsValidEntity(logicScript))
    {
        DispatchKeyValue(logicScript, "vscripts", "mannvsrefund/main");
        DispatchKeyValue(logicScript, "targetname", companionAvailable);
        DispatchSpawn(logicScript);
    }
}

public Action Command_SetMvmUpgrades(int client, int args)
{
    if (args != 1)
    {
        ReplyToCommand(client, "Usage: sm_mvr_upgradefile <file>");
        return Plugin_Handled;
    }

    char path[MAX_UPGRADE_PATH];
    GetCmdArg(1, path, sizeof(path));

    if (!IsValidUpgradePath(path))
    {
        ReplyToCommand(client, "Invalid upgrade file path.");
        return Plugin_Handled;
    }

    if (!FileExists(path, true, "MOD"))
    {
        ReplyToCommand(client, "File not found (%s)", path);
        return Plugin_Handled;
    }

    // We can't make clients download it live without some rafmod
    // tier horrors, so we'll assume you know what you are doing.
    AddFileToDownloadsTable(path);

    strcopy(g_PendingUpgradeFile, sizeof(g_PendingUpgradeFile), path);
    g_bUpgradeFilePending = true;

    ReplyToCommand(
        client,
        "Queued the upgrade file for the next round.",
        path
    );

    return Plugin_Handled;
}

public Action Hook_NormalSound(int clients[MAXPLAYERS], int &numClients,
                               char sample[PLATFORM_MAX_PATH], int &entity,
                               int &channel, float &volume, int &level,
                               int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
    if (StrContains(sample, "your_team_won", false) != -1 || 
        StrContains(sample, "your_team_lost", false) != -1 || 
        StrContains(sample, "your_team_stalemate", false) != -1 ||
        StrContains(sample, "announcer_victory", false) != -1 ||
        StrContains(sample, "announcer_am_flawlessvictory", false) != -1)
    {
        return Plugin_Handled;
    }
    else
    {
        return Plugin_Continue;
    }
}

public Action Event_BroadcastAudio(Event event, const char[] name, bool dontBroadcast)
{
    char soundName[64];
    event.GetString("sound", soundName, sizeof(soundName));
    
    if (StrContains(soundName, "Game.YourTeam", false) == 0 ||
        StrContains(soundName, "Game.TeamWin", false) == 0 ||
        StrContains(soundName, "Game.Stalemate", false) == 0)
    {
        return Plugin_Handled;
    }
    else
    {
        return Plugin_Continue;
    }
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    g_bMapTimelimitStalemate = false;
    g_bGameOver = false;

    ApplyPendingUpgradeFile();
}

public void Event_RoundStalemate(Event event, const char[] name, bool dontBroadcast)
{
    g_bMapTimelimitStalemate =
        (event.GetInt("reason") == STALEMATE_SERVER_TIMELIMIT);
}

public void Event_WinPanel(Event event, const char[] name, bool dontBroadcast)
{
    g_bGameOver = (event.GetInt("game_over") != 0);
}

#define PLAY_SOUND_TO_CLIENT(%1,%2) \
    EmitSoundToClient(%1, %2, SOUND_FROM_PLAYER, \
                      SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, \
                      SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, \
                      NULL_VECTOR, NULL_VECTOR, true);

public void Event_RoundWin(Event event, const char[] name, bool dontBroadcast)
{
    int winningTeam = event.GetInt("team");
    int winReason = event.GetInt("winreason");

    bool endOfMap = g_bGameOver &&
        ((winReason == WINREASON_TIMELIMIT) ||
        g_bMapTimelimitStalemate);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            int playerTeam = GetClientTeam(i);
            
            if (playerTeam == winningTeam)
            {
                PLAY_SOUND_TO_CLIENT(i, (endOfMap ? ROUND_WIN_FULL : ROUND_WIN_STAGED))
            }
            else if (playerTeam > 1)
            {
                PLAY_SOUND_TO_CLIENT(i, ROUND_LOSE)
            }
        }
    }
}

#undef PLAY_SOUND_TO_CLIENT

stock bool IsValidUpgradePath(const char[] path)
{
    int len = strlen(path);

    if (len < 5 || len >= MAX_UPGRADE_PATH)
        return false;

    if (path[0] == '/' || StrContains(path, "..") != -1)
        return false;

    // TF2 expects a lowercase .txt extension.
    if (path[len - 4] != '.' ||
        path[len - 3] != 't' ||
        path[len - 2] != 'x' ||
        path[len - 1] != 't')
        return false;

    for (int i = 0; i < len; i++)
    {
        char c = path[i];

        bool valid =
            (c >= 'a' && c <= 'z') ||
            (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') ||
            c == '/' || c == '_' || c == '-' || c == '.';

        if (!valid)
            return false;
    }

    return true;
}

void ApplyPendingUpgradeFile()
{
    if (!g_bUpgradeFilePending)
        return;

    int gamerules = FindEntityByClassname(-1, "tf_gamerules");
    if (gamerules == -1)
    {
        PrintToServer("[Mann vs. Refund] Could not find tf_gamerules.");
        return;
    }

    SetVariantString(g_PendingUpgradeFile);

    if (!AcceptEntityInput(gamerules, "SetCustomUpgradesFile"))
    {
        PrintToServer("[Mann vs. Refund] Failed to set custom upgrades file.");
    }

    g_bUpgradeFilePending = false;
    g_PendingUpgradeFile[0] = '\0';
}
#undef MAX_UPGRADE_PATH