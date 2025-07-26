#include <sourcemod>
#include <sdktools>

ConVar gCvarAllowPlayerUse;

public Plugin myinfo = {
    name = "GiveNadePack",
    author = "Cinyan10",
    description = "Give player a full set of grenades",
    version = "1.1",
    url = "https://axekz.com/"
};

public void OnPluginStart() {
    // RegConsoleCmd("sm_nadepack", Command_GiveNadePack, "Give yourself a full grenade pack");
    // RegConsoleCmd("sm_np", Command_GiveNadePack, "Give yourself a full grenade pack");

    RegAdminCmd("sm_nadepackall", Command_GiveAllNadePack, ADMFLAG_GENERIC, "Give all players a full grenade pack");
    RegAdminCmd("sm_npall", Command_GiveAllNadePack, ADMFLAG_GENERIC, "Give all players a full grenade pack");

    gCvarAllowPlayerUse = CreateConVar("sm_nadepack_enable", "0", "是否允许普通玩家使用 sm_nadepack 指令 (1=启用, 0=禁用)", 0, true, 0.0, true, 1.0);
}

public Action Command_GiveNadePack(int client, int args) {
    if (!IsClientInGame(client) || !IsPlayerAlive(client)) {
        PrintToChat(client, "[AUT] 你必须在游戏中并且存活才能领取道具！");
        return Plugin_Handled;
    }

    if (!gCvarAllowPlayerUse.BoolValue && !CheckCommandAccess(client, "sm_nadepack", ADMFLAG_GENERIC)) {
        PrintToChat(client, "[AUT] 当前服务器不允许普通玩家领取道具！");
        return Plugin_Handled;
    }

    GiveNadePack(client);
    PrintToChat(client, "[AUT] 道具已发放！");
    return Plugin_Handled;
}

public Action Command_GiveAllNadePack(int client, int args) {
    int count = 0;
    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i) && IsPlayerAlive(i)) {
            GiveNadePack(i);
            count++;
        }
    }

    PrintToChatAll("[AUT] 管理员已为所有存活玩家发放道具！");
    PrintToChat(client, "[AUT] 共发放给 %d 名玩家。", count);
    return Plugin_Handled;
}

void GiveNadePack(int client) {
    GivePlayerGrenade(client, "weapon_flashbang", 3);
    GivePlayerGrenade(client, "weapon_smokegrenade", 1);
    GivePlayerGrenade(client, "weapon_hegrenade", 2);
    GivePlayerGrenade(client, "weapon_tagrenade", 1);
    GivePlayerGrenade(client, "weapon_decoy", 1);
    GivePlayerGrenade(client, "weapon_molotov", 1);
    GivePlayerGrenade(client, "weapon_healthshot", 1);
    GivePlayerGrenade(client, "weapon_taser", 1);
}

void GivePlayerGrenade(int client, const char[] weaponName, int count) {
    for (int i = 0; i < count; i++) {
        GivePlayerItem(client, weaponName);
    }
}
