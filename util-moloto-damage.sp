#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

static const char g_szBurnSounds[][] = {
    "player/burn_damage1.wav",
    "player/burn_damage2.wav",
    "player/burn_damage3.wav",
    "player/burn_damage4.wav",
    "player/burn_damage5.wav"
};

static const char g_szDeathSounds[][] = {
    "player/death1.wav",
    "player/death2.wav",
    "player/death3.wav",
    "player/death4.wav",
    "player/death5.wav"
};

ConVar g_hDamageScale;
float g_fLastBurnSoundTime[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name        = "GOKZ Molotov Damage",
    author      = "Cinyan10",
    description = "Make Molotov deal damage even in godmode in GOKZ",
    version     = "1.5"
};

public void OnPluginStart()
{
    g_hDamageScale = CreateConVar("sm_molotov_damage_scale", "0.7", "燃烧瓶伤害缩放系数，默认为 0.7", _, true, 0.0, true, 1.0);
}

public void OnMapStart()
{
    for (int i = 0; i < sizeof(g_szBurnSounds); i++)
    {
        PrecacheSound(g_szBurnSounds[i], true);
    }

    for (int i = 0; i < sizeof(g_szDeathSounds); i++)
    {
        PrecacheSound(g_szDeathSounds[i], true);
    }
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage,
                           int &damagetype, int &weapon, float damageForce[3], float damagePos[3])
{
    if (!IsClientInGame(victim))
        return Plugin_Continue;

    char classname[64];
    GetEdictClassname(inflictor, classname, sizeof(classname));

    if (StrEqual(classname, "inferno", false) ||
        (damagetype & DMG_BURN) || (damagetype & DMG_SLOWBURN))
    {
        int hp = GetClientHealth(victim);

        float scale = g_hDamageScale.FloatValue;
        float scaled = damage * scale;
        int dmg = RoundToNearest(scaled);
        int newHp = hp - dmg;

        float pos[3];
        GetClientAbsOrigin(victim, pos);
        pos[2] += 5.0;

        if (newHp > 1)
        {
            SetEntityHealth(victim, newHp);

            float now = GetEngineTime();
            if (now - g_fLastBurnSoundTime[victim] >= 0.5) // 1秒冷却
            {
                g_fLastBurnSoundTime[victim] = now;

                int index = GetRandomInt(0, sizeof(g_szBurnSounds) - 1);
                EmitAmbientSound(g_szBurnSounds[index], pos, victim, SNDLEVEL_RAIDSIREN);
            }
        }
        else
        {
            FakeClientCommand(victim, "sm_restart");
            SetEntityHealth(victim, 100);

            int index = GetRandomInt(0, sizeof(g_szDeathSounds) - 1);
            EmitAmbientSound(g_szDeathSounds[index], pos, victim, SNDLEVEL_RAIDSIREN);

            if (IsClientInGame(attacker) && attacker != victim)
            {
                char attackerName[64], victimName[64];
                GetClientName(attacker, attackerName, sizeof(attackerName));
                GetClientName(victim, victimName, sizeof(victimName));
                PrintToChatAll("\x04[AUT] \x04%s\x01 使用燃烧瓶击杀了 \x02%s", attackerName, victimName);
            }
        }

        return Plugin_Handled;
    }

    return Plugin_Continue;
}
