#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#include "drug.sp"

#pragma semicolon 1

#define PLUGIN_VERSION "2.0"

#define FLASH 0

#define SOUND_FREEZE	"physics/glass/glass_impact_bullet4.wav"
#define SOUND_FREEZE_EXPLODE	"ui/freeze_cam.wav"

// Sound that plays when a decoy grenade explodes
#define SOUND_DECOY_EXPLODE "player/death1.wav"

#define FragColor  {255,75,75,255}
#define TAGColor	{155,50,168,255}
#define FlashColor	{252,246,172,255}
#define FreezeColor	{86,191,252,255}
#define MAX_HIT_TARGETS 64

int g_HitTargets[MAXPLAYERS + 1][MAX_HIT_TARGETS];
int g_HitCount[MAXPLAYERS + 1];
Handle g_HitTimers[MAXPLAYERS + 1];

int IceRef[MAXPLAYERS + 1];
int SnowRef[MAXPLAYERS + 1];
char g_FreezeSound[PLATFORM_MAX_PATH];
bool bAdminFreeze[MAXPLAYERS + 1];
bool allowFreeze[MAXPLAYERS + 1] = {true, ...};

Handle hIcetimer[MAXPLAYERS + 1] = {INVALID_HANDLE, ...};
Handle hSoundtimer[MAXPLAYERS + 1] = {INVALID_HANDLE, ...};

ConVar g_hDecoyRadius;
float fVolume;

#define IceModel "models/weapons/eminem/ice_cube/ice_cube.mdl"
#define IceCube3d "materials/weapons/eminem/ice_cube/ice_cube.vmt"

new Float:NULL_VELOCITY[3] = {0.0, 0.0, 0.0};

new BeamSprite, GlowSprite, g_beamsprite, g_halosprite;

new Handle:h_greneffects_enable, bool:b_enable,
	Handle:h_greneffects_trails, bool:b_trails,
	Handle:h_greneffects_he_freeze, bool:b_he_freeze,
	Handle:h_greneffects_he_freeze_distance, Float:f_he_freeze_distance,
	Handle:h_greneffects_he_freeze_duration, Float:f_he_freeze_duration,
	Handle:h_greneffects_tag_drug, bool:b_tag_drug,
	Handle:h_greneffects_tag_drug_distance, Float:f_tag_drug_distance,


Handle:h_freeze_timer[MAXPLAYERS+1] = {INVALID_HANDLE, ...};

// 添加这个函数，在玩家被这些投掷物伤害时调用
void RecordHit(int attacker, int victim, const char[] weapon)
{
    if (!IsClientInGame(attacker) || !IsClientInGame(victim))
        return;

    // 避免重复记录
    for (int i = 0; i < g_HitCount[attacker]; i++)
    {
        if (g_HitTargets[attacker][i] == victim)
            return;
    }

    g_HitTargets[attacker][g_HitCount[attacker]++] = victim;

    // 第一次命中，设置定时器延迟广播
    if (g_HitCount[attacker] == 1)
    {
        if (g_HitTimers[attacker] != INVALID_HANDLE)
        {
            CloseHandle(g_HitTimers[attacker]);
        }

        DataPack pack = new DataPack();
        pack.WriteCell(attacker);
        pack.WriteString(weapon);
        g_HitTimers[attacker] = CreateTimer(0.1, Timer_AnnounceHits, pack);
    }
}

public Action Timer_AnnounceHits(Handle timer, DataPack pack)
{
    pack.Reset();
    int attacker = pack.ReadCell();
    char weapon[32];
    pack.ReadString(weapon, sizeof(weapon));
    delete pack;

    g_HitTimers[attacker] = INVALID_HANDLE;

    if (!IsClientInGame(attacker))
        return Plugin_Stop;

    char name[64];
    GetClientName(attacker, name, sizeof(name));

    char victimList[256];
    for (int i = 0; i < g_HitCount[attacker]; i++)
    {
        int victim = g_HitTargets[attacker][i];
        if (!IsClientInGame(victim))
            continue;

        char victimName[64];
        GetClientName(victim, victimName, sizeof(victimName));

        if (victimList[0] != '\0')
        {
            StrCat(victimList, sizeof(victimList), "、");
        }
        StrCat(victimList, sizeof(victimList), victimName);
    }

    if (victimList[0] != '\0')
    {
        PrintToChatAll("[提示] %s 扔出的 %s 击中了 %s", name, weapon, victimList);
    }

    g_HitCount[attacker] = 0;
    return Plugin_Stop;
}


public Plugin myinfo = {
    name = "Util Effects",
    author = "Cinyan10",
    description = "grenades effects for util tournament",
    version = "1.1",
    url = "https://axekz.com/"
};


public OnPluginStart()
{
	CreateConVar("sm_greneffect_version", PLUGIN_VERSION, "The plugin's version", 0|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_CHEAT|FCVAR_DONTRECORD);
	
	h_greneffects_enable = CreateConVar("sm_greneffect_enable", "1", "Enables/Disables the plugin", 0, true, 0.0, true, 1.0);
	h_greneffects_trails = CreateConVar("sm_greneffect_trails", "1", "Enables/Disables Grenade Trails", 0, true, 0.0, true, 1.0);
	
	h_greneffects_he_freeze = CreateConVar("sm_greneffect_he_freeze", "1", "Changes a hegrenade to a freeze grenade", 0, true, 0.0, true, 1.0);
	h_greneffects_he_freeze_distance = CreateConVar("sm_greneffect_he_freeze_distance", "350", "The freeze grenade distance", 0, true, 100.0);
	h_greneffects_he_freeze_duration = CreateConVar("sm_greneffect_he_freeze_duration", "4", "The freeze duration in seconds", 0, true, 1.0);

	h_greneffects_tag_drug = CreateConVar("sm_greneffect_tag_drug", "1", "Changes a tagrenade to drug", 0, true, 0.0, true, 1.0);
	h_greneffects_tag_drug_distance = CreateConVar("sm_greneffect_tag_drug_distance", "350", "Drug distance", 0, true, 100.0);
	g_hDecoyRadius = CreateConVar("sm_decoy_radius", "250.0", "Decoy 爆炸影响半径", _, true, 0.0, true, 1000.0);

	b_enable = GetConVarBool(h_greneffects_enable);
	b_trails = GetConVarBool(h_greneffects_trails);
	b_he_freeze = GetConVarBool(h_greneffects_he_freeze);
	b_tag_drug = GetConVarBool(h_greneffects_tag_drug);
	
	f_he_freeze_distance = GetConVarFloat(h_greneffects_he_freeze_distance);
	f_he_freeze_duration = GetConVarFloat(h_greneffects_he_freeze_duration);
	f_tag_drug_distance = GetConVarFloat(h_greneffects_tag_drug_distance);
	
	HookConVarChange(h_greneffects_enable, OnConVarChanged);
	HookConVarChange(h_greneffects_trails, OnConVarChanged);

	HookConVarChange(h_greneffects_he_freeze, OnConVarChanged);
	HookConVarChange(h_greneffects_he_freeze_distance, OnConVarChanged);
	HookConVarChange(h_greneffects_he_freeze_duration, OnConVarChanged);

	HookConVarChange(h_greneffects_tag_drug, OnConVarChanged);
	HookConVarChange(h_greneffects_tag_drug_distance, OnConVarChanged);

    HookEvent("hegrenade_detonate", OnHeDetonate);
    HookEvent("tagrenade_detonate", OnTagrenadeDetonate);
    // Hook decoy grenade explosions for custom behaviour
	HookEvent("weapon_fire", OnWeaponFire);
    HookEvent("decoy_detonate", OnDecoyDetonate);
    AddNormalSoundHook(NormalSHook);
}

public OnConVarChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (convar == h_greneffects_enable)
	{
		b_enable = bool:StringToInt(newValue);
	}
	else if (convar == h_greneffects_trails)
	{
		b_trails = bool:StringToInt(newValue);
	}
	else if (convar == h_greneffects_he_freeze)
	{
		b_he_freeze = bool:StringToInt(newValue);
	}
	else if (convar == h_greneffects_he_freeze_distance)
	{
		f_he_freeze_distance = StringToFloat(newValue);
	}
	else if (convar == h_greneffects_he_freeze_duration)
	{
		f_he_freeze_duration = StringToFloat(newValue);
	}
	else if (convar == h_greneffects_tag_drug)
	{
		b_tag_drug = bool:StringToInt(newValue);
	}
	else if (convar == h_greneffects_tag_drug_distance)
	{
		f_tag_drug_distance = StringToFloat(newValue);
	}
}

public OnMapStart() 
{
	// Ice cube model
	AddFileToDownloadsTable("materials/models/weapons/eminem/ice_cube/ice_cube.vtf");
	AddFileToDownloadsTable("materials/models/weapons/eminem/ice_cube/ice_cube_normal.vtf");
	AddFileToDownloadsTable("materials/models/weapons/eminem/ice_cube/ice_cube.vmt");

	AddFileToDownloadsTable("models/weapons/eminem/ice_cube/ice_cube.phy");
	AddFileToDownloadsTable("models/weapons/eminem/ice_cube/ice_cube.vvd");
	AddFileToDownloadsTable("models/weapons/eminem/ice_cube/ice_cube.dx90.vtx");
	AddFileToDownloadsTable("models/weapons/eminem/ice_cube/ice_cube.mdl");
	
	AddFileToDownloadsTable("materials/sprites/laserbeam.vmt");
	AddFileToDownloadsTable("materials/sprites/glow_test02.vmt");
	AddFileToDownloadsTable("materials/sprites/lgtning.vmt");
	AddFileToDownloadsTable("materials/sprites/halo01.vmt");
	
	
	// Prencher
	PrecacheModel("models/weapons/eminem/ice_cube/ice_cube.mdl",true);
	PrecacheModel("materials/models/weapons/eminem/ice_cube/ice_cube.vmt",true);
	
	// Snow effect
	PrecacheModel("particle/snow.vmt",true);
	
	BeamSprite = PrecacheModel("sprites/laserbeam.vmt");
	GlowSprite = PrecacheModel("sprites/glow_test02.vmt");
	
	g_beamsprite = PrecacheModel("sprites/lgtning.vmt");
	g_halosprite = PrecacheModel("sprites/halo01.vmt");
	
    PrecacheSound(SOUND_FREEZE);
    PrecacheSound(SOUND_FREEZE_EXPLODE);
    // Precache decoy explosion sound so that it can be played instantly
    PrecacheSound(SOUND_DECOY_EXPLODE, true);
	// Freeze sound
	Handle gameConfig = LoadGameConfigFile("funcommands.games");
	
	if (GameConfGetKeyValue(gameConfig, "SoundFreeze", g_FreezeSound, sizeof(g_FreezeSound)) && g_FreezeSound[0])
	{
		PrecacheSound(g_FreezeSound, true);
	}
}

public OnClientDisconnect(client)
{
	if (IsClientInGame(client))
		ExtinguishEntity(client);
	if (h_freeze_timer[client] != INVALID_HANDLE)
	{
		KillTimer(h_freeze_timer[client]);
		h_freeze_timer[client] = INVALID_HANDLE;
	}
}

public void OnClientPutInServer(int i)
{
	SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if(IsValidClient(victim)){
		if(damagetype == DMG_BURN){
			if (h_freeze_timer[victim] != INVALID_HANDLE)
			{
				Unfreeze(h_freeze_timer[victim], victim);
			}
		}
	}
	return Plugin_Continue;
}

public OnHeDetonate(Handle:event, const String:name[], bool:dontBroadcast) 
{
	if (!b_enable || !b_he_freeze)
	{
		return;
	}
	
	new Float:origin[3];
	origin[0] = GetEventFloat(event, "x"); 
	origin[1] = GetEventFloat(event, "y"); 
	origin[2] = GetEventFloat(event, "z");
	
	new index = MaxClients+1; 
	decl Float:xyz[3];
	while ((index = FindEntityByClassname(index, "hegrenade_projectile")) != -1)
	{
		GetEntPropVector(index, Prop_Send, "m_vecOrigin", xyz);
		if (xyz[0] == origin[0] && xyz[1] == origin[1] && xyz[2] == origin[2])
		{
			AcceptEntityInput(index, "kill");
		}
	}
	
	origin[2] += 10.0;

	// 用于记录命中的玩家名
	char hitNames[256] = "";
	int attacker = GetClientOfUserId(GetEventInt(event, "userid"));

	new Float:targetOrigin[3];
	for (new i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;
		
		GetClientAbsOrigin(i, targetOrigin);
		targetOrigin[2] += 2.0;

		if (GetVectorDistance(origin, targetOrigin) <= f_he_freeze_distance)
		{
			new Handle:trace = TR_TraceRayFilterEx(origin, targetOrigin, MASK_SOLID, RayType_EndPoint, FilterTarget, i);
			bool hit = false;

			if ((TR_DidHit(trace) && TR_GetEntityIndex(trace) == i) || (GetVectorDistance(origin, targetOrigin) <= 100.0))
			{
				hit = true;
			}
			else
			{
				CloseHandle(trace);
				GetClientEyePosition(i, targetOrigin);
				targetOrigin[2] -= 2.0;
				trace = TR_TraceRayFilterEx(origin, targetOrigin, MASK_SOLID, RayType_EndPoint, FilterTarget, i);
				if ((TR_DidHit(trace) && TR_GetEntityIndex(trace) == i) || (GetVectorDistance(origin, targetOrigin) <= 100.0))
				{
					hit = true;
				}
			}

			CloseHandle(trace);

			if (hit)
			{
				Freeze(i, f_he_freeze_duration);

				// 拼接被击中玩家名
				char victimName[64];
				GetClientName(i, victimName, sizeof(victimName));

				if (hitNames[0] != '\0')
					StrCat(hitNames, sizeof(hitNames), "、");

				StrCat(hitNames, sizeof(hitNames), "\x02");  // 红色
				StrCat(hitNames, sizeof(hitNames), victimName);

			}
		}
	}

	if (hitNames[0] != '\0' && IsClientInGame(attacker))
	{
		char attackerName[64];
		GetClientName(attacker, attackerName, sizeof(attackerName));
		PrintToChatAll("\x03[AUT] \x04%s\x01 扔出的手雷击中了 %s \x01!", attackerName, hitNames);
	}

	TE_SetupBeamRingPoint(origin, 10.0, f_he_freeze_distance, g_beamsprite, g_halosprite, 1, 1, 0.2, 100.0, 1.0, FreezeColor, 0, 0);
	TE_SendToAll();
}

/*
 * Event handler for weapon_fire.  We intercept this event so that when a
 * player uses the weapon_healthshot (the healing syringe) we can perform
 * additional logic: remove any freeze or drug effects and apply an instant
 * health boost.  A short timer is used to delay the heal just long enough
 * for the engine to register the usage and consume the item.
 */
public void OnWeaponFire(Handle:event, const String:name[], bool:dontBroadcast)
{
    int userid = GetEventInt(event, "userid");
    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client) || !IsPlayerAlive(client))
    {
        return;
    }
    char weapon[64];
    GetEventString(event, "weapon", weapon, sizeof(weapon));
    // Check for various representations of the healthshot class name
    if (StrEqual(weapon, "weapon_healthshot", false) || StrEqual(weapon, "healthshot", false) || StrEqual(weapon, "Healthshot", false))
    {
        // Delay slightly so the game finishes processing the weapon usage
        CreateTimer(1.0, Timer_HealthShot, client);
    }
}

public Action Timer_HealthShot(Handle timer, any client)
{
    if (!IsValidClient(client) || !IsPlayerAlive(client))
    {
        return Plugin_Stop;
    }
    // Cancel freeze timer and remove freeze effects
    if (h_freeze_timer[client] != INVALID_HANDLE)
    {
        KillTimer(h_freeze_timer[client]);
        h_freeze_timer[client] = INVALID_HANDLE;
    }
    UnFreezeee(client);

    // Remove drug effect
    KillDrug(client);

    // Heal the client by 50 HP (clamped to 100)
    int curHp = GetClientHealth(client);
    int newHp = curHp + 50;
    if (newHp > 100)
    {
        newHp = 100;
    }
    SetEntityHealth(client, newHp);

    // Optionally display a hint
    char msg[32];
    Format(msg, sizeof(msg), "+%d HP", 50);
    PrintHintText(client, msg);

    return Plugin_Stop;
}


public OnTagrenadeDetonate(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!b_enable || !b_tag_drug)
		return;

	float origin[3];
	origin[0] = GetEventFloat(event, "x");
	origin[1] = GetEventFloat(event, "y");
	origin[2] = GetEventFloat(event, "z") + 10.0;

	int attacker = GetClientOfUserId(GetEventInt(event, "userid"));

	float targetOrigin[3];
	char hitNames[256] = "";

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i))
			continue;

		GetClientAbsOrigin(i, targetOrigin);
		targetOrigin[2] += 2.0;

		if (GetVectorDistance(origin, targetOrigin) <= f_tag_drug_distance)
		{
			Handle trace = TR_TraceRayFilterEx(origin, targetOrigin, MASK_SOLID, RayType_EndPoint, FilterTarget, i);
			bool hit = false;

			if ((TR_DidHit(trace) && TR_GetEntityIndex(trace) == i) || GetVectorDistance(origin, targetOrigin) <= 100.0)
			{
				hit = true;
			}
			else
			{
				CloseHandle(trace);
				GetClientEyePosition(i, targetOrigin);
				targetOrigin[2] -= 2.0;
				trace = TR_TraceRayFilterEx(origin, targetOrigin, MASK_SOLID, RayType_EndPoint, FilterTarget, i);
				if ((TR_DidHit(trace) && TR_GetEntityIndex(trace) == i) || GetVectorDistance(origin, targetOrigin) <= 100.0)
				{
					hit = true;
				}
			}
			CloseHandle(trace);

			if (hit)
			{
				CreateDrug(i);

				char victimName[64];
				GetClientName(i, victimName, sizeof(victimName));
				if (hitNames[0] != '\0') StrCat(hitNames, sizeof(hitNames), "、");
				StrCat(hitNames, sizeof(hitNames), "\x02");
				StrCat(hitNames, sizeof(hitNames), victimName);
			}
		}
	}

	if (hitNames[0] != '\0' && IsValidClient(attacker))
	{
		char attackerName[64];
		GetClientName(attacker, attackerName, sizeof(attackerName));
		PrintToChatAll("\x03[AUT] \x04%s\x01 扔出的标记弹击中了 %s \x01!", attackerName, hitNames);
	}

	TE_SetupBeamRingPoint(origin, 10.0, f_he_freeze_distance, g_beamsprite, g_halosprite, 1, 1, 0.2, 100.0, 1.0, FreezeColor, 0, 0);
	TE_SendToAll();
}


/**
 * Fired when a decoy grenade explodes.
 * This handler plays a custom sound and issues a restart command.
 */
public Action OnDecoyDetonate(Event event, const char[] name, bool dontBroadcast)
{
	float origin[3];
	origin[0] = event.GetFloat("x");
	origin[1] = event.GetFloat("y");
	origin[2] = event.GetFloat("z");

	float radius = g_hDecoyRadius.FloatValue;
	char hitNames[256] = "";
	int attacker = GetClientOfUserId(event.GetInt("userid"));

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i)) continue;

		float clientOrigin[3];
		GetClientAbsOrigin(i, clientOrigin);

		if (GetVectorDistance(origin, clientOrigin) <= radius)
		{
			EmitSoundToClient(i, "player/death1.wav", i);
			FakeClientCommand(i, "sm_restart");

			char victimName[64];
			GetClientName(i, victimName, sizeof(victimName));
			if (hitNames[0] != '\0') StrCat(hitNames, sizeof(hitNames), "、");
			StrCat(hitNames, sizeof(hitNames), "\x02");
			StrCat(hitNames, sizeof(hitNames), victimName);
		}
	}

	if (hitNames[0] != '\0' && IsValidClient(attacker))
	{
		char attackerName[64];
		GetClientName(attacker, attackerName, sizeof(attackerName));
		PrintToChatAll("\x03[AUT] \x04%s\x01 扔出的诱饵弹击中了 %s \x01!", attackerName, hitNames);
	}

	return Plugin_Continue;
}


public float IntToFloat(int integer)
{
	char s[300];
	IntToString(integer,s,sizeof(s));
	return StringToFloat(s);
}

void CreateIce(int client, int time)
{
	// Generate unique id for the client so we can set the parenting
	// through parentname.
	char StrName[64]; Format(StrName, sizeof(StrName), "Client%i", client);
	DispatchKeyValue(client, "targetname", StrName);

	// Create the hat entity
	if( allowFreeze[client] )
	{
		SetEntityMoveType(client, MOVETYPE_NONE);
		
		float pos[3];
		GetClientAbsOrigin(client, pos);
		int model = CreateEntityByName("prop_dynamic_override");
		DispatchKeyValue(model, "parentname", StrName);
		DispatchKeyValue(model, "model", IceModel);
		DispatchKeyValue(model, "solid", "0");
		DispatchKeyValue(model, "spawnflags", "256");
		SetEntPropEnt(model, Prop_Send, "m_hOwnerEntity", client);
		SetEntityMoveType(model, MOVETYPE_NOCLIP);
		SetEntProp(model, Prop_Data, "m_CollisionGroup", 0);  
		DispatchSpawn(model);	
		TeleportEntity(model, pos, NULL_VECTOR, NULL_VECTOR); 
		SetVariantString(StrName);
		AcceptEntityInput(model, "SetParent", model, model, 0);
		allowFreeze[client] = false;//variavel global
		IceRef[client] = EntIndexToEntRef(model);
		// has unfreeze time
		if(time > 0)
		{
			float ftime = IntToFloat(time);
			hIcetimer[client] = CreateTimer(ftime, UnIceTimer, client);
		}
		
		// create sound timer
		if (g_FreezeSound[0])
		{
			hSoundtimer[client] = CreateTimer(1.0, SoundTimer, client, TIMER_REPEAT);
		}
	}
}

public Action UnIceTimer(Handle timer, int client)
{
	if (hIcetimer[client] != INVALID_HANDLE)
	{
		KillTimer(hIcetimer[client]);
		return Plugin_Stop;
	}
	hIcetimer[client] = INVALID_HANDLE;
	
	bAdminFreeze[client] = false;
	
	UnFreezeee(client);
	PrintHintText(client, "%t", "Unfrozen");
	return Plugin_Continue;
}

public Action SoundTimer(Handle timer, int client)
{
	float vec[3];
	GetClientEyePosition(client, vec);
	EmitAmbientSound(g_FreezeSound, vec, client, SNDLEVEL_RAIDSIREN, _, fVolume);
	return Plugin_Continue;
}

void CreateSnow(int client)
{
	int ent = CreateEntityByName("env_smokestack");
	if(ent == -1) return;
	
	float eyePosition[3];
	GetClientEyePosition(client, eyePosition);
	
	eyePosition[2] +=25.0;
	DispatchKeyValueVector(ent,"Origin", eyePosition);
	DispatchKeyValueFloat(ent,"BaseSpread", 50.0);
	DispatchKeyValue(ent,"SpreadSpeed", "100");
	DispatchKeyValue(ent,"Speed", "25");
	DispatchKeyValueFloat(ent,"StartSize", 1.0);
	DispatchKeyValueFloat(ent,"EndSize", 1.0);
	DispatchKeyValue(ent,"Rate", "125");
	DispatchKeyValue(ent,"JetLength", "300");
	DispatchKeyValueFloat(ent,"Twist", 200.0);
	DispatchKeyValue(ent,"RenderColor", "255 255 255");
	DispatchKeyValue(ent,"RenderAmt", "200");
	DispatchKeyValue(ent,"RenderMode", "18");
	DispatchKeyValue(ent,"SmokeMaterial", "particle/snow");
	DispatchKeyValue(ent,"Angles", "180 0 0");
	
	DispatchSpawn(ent);
	ActivateEntity(ent);
	
	eyePosition[2] += 50;
	TeleportEntity(ent, eyePosition, NULL_VECTOR, NULL_VECTOR);
	
	SetVariantString("!activator");
	AcceptEntityInput(ent, "SetParent", client);
	
	AcceptEntityInput(ent, "TurnOn");
	
	SnowRef[client] = EntIndexToEntRef(ent);
}

public bool:FilterTarget(entity, contentsMask, any:data)
{
	return (data == entity);
}

bool:Freeze(client, &Float:time)
{
	new Action:result, Float:dummy_duration = time;
	
	switch (result)
	{
		case Plugin_Handled, Plugin_Stop :
		{
			return false;
		}
		case Plugin_Continue :
		{
			dummy_duration = time;
		}
	}
	
	if (h_freeze_timer[client] != INVALID_HANDLE)
	{
		KillTimer(h_freeze_timer[client]);
		h_freeze_timer[client] = INVALID_HANDLE;
	}
	
	SetEntityMoveType(client, MOVETYPE_NONE);
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, NULL_VELOCITY);
	CreateIce(client, 1);
	// CreateSnow(client);
	
	new Float:vec[3];
	GetClientEyePosition(client, vec);
	vec[2] -= 50.0;
	EmitAmbientSound(SOUND_FREEZE, vec, client, SNDLEVEL_RAIDSIREN);

	TE_SetupGlowSprite(vec, GlowSprite, dummy_duration, 2.0, 50);
	TE_SendToAll();
	
	h_freeze_timer[client] = CreateTimer(dummy_duration, Unfreeze, client, TIMER_FLAG_NO_MAPCHANGE);
	
	return true;
}

public Action:Unfreeze(Handle:timer, any:client)
{
	if (h_freeze_timer[client] != INVALID_HANDLE)
	{
		SetEntityMoveType(client, MOVETYPE_WALK);
		h_freeze_timer[client] = INVALID_HANDLE;
	}
	SetEntityMoveType(client, MOVETYPE_WALK);
	allowFreeze[client] = true;
	int entity = EntRefToEntIndex(IceRef[client]);
	if(entity != INVALID_ENT_REFERENCE && IsValidEdict(entity) && entity != 0)
	{
		AcceptEntityInput(entity, "Kill");
		IceRef[client] = INVALID_ENT_REFERENCE;
	}
	
	if (hSoundtimer[client] != INVALID_HANDLE)
	{
		KillTimer(hSoundtimer[client]);
	}
	hSoundtimer[client] = INVALID_HANDLE;
	
	SnowOff(client);
}

public OnEntityCreated(entity, const String:classname[])
{
	if (!b_enable)
	{
		return;
	}
	
	if (!strcmp(classname, "decoy_projectile"))
	{
		BeamFollowCreate(entity, FlashColor);
	}
	if (!strcmp(classname, "flashbang_projectile"))
	{
		BeamFollowCreate(entity, FlashColor);
	}
	if (!strcmp(classname, "tagrenade_projectile"))
	{
		BeamFollowCreate(entity, TAGColor);
	}
	else if (!strcmp(classname, "hegrenade_projectile"))
	{
		if (b_he_freeze)
		{
			BeamFollowCreate(entity, FreezeColor);
		}
		else
		{
			BeamFollowCreate(entity, FragColor);
		}
	}
}

void SnowOff(int client)
{ 
	int entity = EntRefToEntIndex(SnowRef[client]);
	if(entity != INVALID_ENT_REFERENCE && IsValidEdict(entity) && entity != 0)
	{
		AcceptEntityInput(entity, "TurnOff"); 
		AcceptEntityInput(entity, "Kill"); 
		SnowRef[client] = INVALID_ENT_REFERENCE;
	}
}

void UnFreezeee(int client)
{
	// admin freeze
	if(bAdminFreeze[client])	return;
	
	SetEntityMoveType(client, MOVETYPE_WALK);
	allowFreeze[client] = true;
	int entity = EntRefToEntIndex(IceRef[client]);
	if(entity != INVALID_ENT_REFERENCE && IsValidEdict(entity) && entity != 0)
	{
		AcceptEntityInput(entity, "Kill");
		IceRef[client] = INVALID_ENT_REFERENCE;
	}
	
	if (hSoundtimer[client] != INVALID_HANDLE)
	{
		KillTimer(hSoundtimer[client]);
	}
	hSoundtimer[client] = INVALID_HANDLE;
	
	SnowOff(client);
}

BeamFollowCreate(entity, color[4])
{
	if (b_trails)
	{
		TE_SetupBeamFollow(entity, BeamSprite,	0, 1.0, 10.0, 10.0, 5, color);
		TE_SendToAll();	
	}
}

public Action:Delete(Handle:timer, any:entity)
{
	if (IsValidEdict(entity))
	{
		AcceptEntityInput(entity, "kill");
	}
}

public Action:NormalSHook(clients[64], &numClients, String:sample[PLATFORM_MAX_PATH], &entity, &channel, &Float:volume, &level, &pitch, &flags)
{
	if (b_he_freeze && !strcmp(sample, "^weapons/smokegrenade/sg_explode.wav"))
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

stock bool IsValidClient(int client)
{
	if (client <= 0) return false;
	if (client > MaxClients) return false;
	if (!IsClientConnected(client)) return false;
	return IsClientInGame(client);
}

