/**
 * taser_freeze_trace.sp
 *
 * A SourceMod plugin that freezes players when they are struck by the Zeus x27
 * taser.  This version hooks SDKHooks' TraceAttack forward instead of
 * OnTakeDamage so that the freeze effect still triggers even when players
 * are immune to damage (for example, while in god mode).  The TraceAttack
 * callback is invoked whenever an attack trace hits an entity, before any
 * damage is actually applied【494801432218117†L76-L79】.  By checking the
 * attacker's active weapon during this callback, we can identify taser
 * strikes and apply our custom freeze logic without relying on damage being
 * dealt.
 *
 * The freeze effect locks the victim's movement, plays a sound, tints the
 * player blue and attaches an ice cube model to their position.  After a
 * configurable duration the player is unfrozen, their movement is restored
 * and the ice model is removed.  Two console variables control the plugin:
 *
 *   sm_taserfreeze_enable   – Master switch to toggle the plugin on or off.
 *   sm_taserfreeze_duration – Time in seconds that a victim remains frozen.
 *
 * This implementation reuses the model and sound assets from the original
 * taser_freeze example.  They must exist on the server or the plugin will
 * log warnings when precaching.
 */

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include "hit_announce.inc"

// Plugin information
public Plugin myinfo =
{
    name        = "Taser Freeze (Trace)",
    author      = "Cinyan10",
    description = "Freezes players on Zeus x27 (taser) hits even in god mode",
    version     = "1.0",
    url         = ""
};

// ConVars
ConVar g_CvarEnable;
ConVar g_CvarDuration;

// State tracking arrays
int g_IceRef[MAXPLAYERS + 1];       // Reference to the attached ice prop per client
Handle g_FreezeTimer[MAXPLAYERS + 1]; // Timer handle for unfreezing per client
bool g_AllowFreeze[MAXPLAYERS + 1];    // Whether a client can be frozen again

// Model and sound resources for the freeze effect
#define ICE_MODEL "models/weapons/eminem/ice_cube/ice_cube.mdl"
#define ICE_VMT   "materials/models/weapons/eminem/ice_cube/ice_cube.vmt"
#define FREEZE_SOUND "physics/glass/glass_impact_bullet4.wav"
#define TASER_HIT_SOUND "player/death_taser_m_01.wav"

/**
 * Called when the plugin starts.  Initializes configuration variables,
 * precaches assets and hooks TraceAttack on all connected clients.
 */
public void OnPluginStart()
{
    // Create configuration variables
    g_CvarEnable = CreateConVar("sm_taserfreeze_enable", "1",
        "Enable/disable the taser freeze plugin", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_CvarDuration = CreateConVar("sm_taserfreeze_duration", "3.0",
        "Number of seconds players remain frozen after being hit by a taser", FCVAR_NOTIFY, true, 1.0);

    // Generate a config file under cfg/sourcemod/taserfreeze_trace.cfg
    AutoExecConfig(true, "taserfreeze_trace");

    // Initialize arrays
    for (int i = 1; i <= MaxClients; i++)
    {
        g_IceRef[i] = INVALID_ENT_REFERENCE;
        g_FreezeTimer[i] = INVALID_HANDLE;
        g_AllowFreeze[i] = true;
    }

    // Hook TraceAttack for all clients currently in the server
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client))
        {
            OnClientPutInServer(client);
        }
    }
}

public void OnMapStart()
{
    // Precache assets used for the freeze effect
    PrecacheModel(ICE_MODEL, true);
    PrecacheModel(ICE_VMT, true);
    PrecacheSound(FREEZE_SOUND, true);
    PrecacheSound("player/death_taser_m_01.wav", true);
}


/**
 * Called whenever a client is fully put in game.  We hook TraceAttack so
 * that we can detect hits even when damage isn't applied.
 */
public void OnClientPutInServer(int client)
{
    // Only hook human clients; bots can be frozen but hooking them as
    // attackers is unnecessary.  We simply hook all clients for simplicity.
    SDKHook(client, SDKHook_TraceAttack, OnTraceAttack);
}

/**
 * Called when a client disconnects.  Unhook TraceAttack to clean up.
 */
public void OnClientDisconnect(int client)
{
    SDKUnhook(client, SDKHook_TraceAttack, OnTraceAttack);

    // If they were frozen, clean up the timer and model
    if (g_FreezeTimer[client] != INVALID_HANDLE)
    {
        KillTimer(g_FreezeTimer[client]);
        g_FreezeTimer[client] = INVALID_HANDLE;
    }
    int ent = EntRefToEntIndex(g_IceRef[client]);
    if (ent != INVALID_ENT_REFERENCE && IsValidEdict(ent) && ent != 0)
    {
        AcceptEntityInput(ent, "Kill");
    }
    g_IceRef[client] = INVALID_ENT_REFERENCE;
    g_AllowFreeze[client] = true;
}

/**
 * TraceAttack callback.  This is invoked whenever an attack trace hits an
 * entity.  It fires before any damage is applied, so it still runs when
 * god mode or other plugins prevent damage from occurring【494801432218117†L76-L79】.
 *
 * @param victim      Entity index that was hit
 * @param attacker    Index of the entity that attacked
 * @param inflictor   Entity index of the weapon or source of the attack
 * @param damage      Amount of damage that would be inflicted
 * @param damagetype  Damage bitmask
 * @param ammotype    Ammo type used
 * @param hitbox      Hitbox index hit
 * @param hitgroup    Hitgroup index hit
 * @return            Plugin_Continue if we don't handle the hit; Plugin_Changed
 *                    if we modify the damage value
 */
public Action OnTraceAttack(int victim, int &attacker, int &inflictor, float &damage,
    int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
    // Abort if plugin disabled
    if (!g_CvarEnable.BoolValue)
    {
        return Plugin_Continue;
    }

    // We only care about player vs player interactions
    if (!IsValidClient(victim) || !IsValidClient(attacker))
    {
        return Plugin_Continue;
    }

    // Ensure attacker is not the victim (don't freeze self‑damage)
    if (victim == attacker)
    {
        return Plugin_Continue;
    }

    // Retrieve the attacker's current weapon.  GetClientWeapon returns the
    // weapon's entity classname without the edict prefix.
    char weapon[64];
    GetClientWeapon(attacker, weapon, sizeof(weapon));

    // Check for the taser.  The Zeus x27 uses "weapon_taser" as its classname.
    // Accept both forms with and without the "weapon_" prefix for safety.
    if (StrEqual(weapon, "weapon_taser", false) || StrEqual(weapon, "taser", false))
    {
        // Only freeze if allowed and not already frozen
        if (g_AllowFreeze[victim])
        {
            float duration = g_CvarDuration.FloatValue;
            FreezePlayer(victim, duration);

            // 多人击中暂时只支持1人，加到数组中以复用 AnnounceMultiHit
            int victimList[64];
            victimList[0] = victim;
            AnnounceMultiHit(attacker, "电击枪", victimList, 1);
          
            float pos[3];
            GetClientAbsOrigin(victim, pos);
            pos[2] += 5.0;
            EmitAmbientSound(TASER_HIT_SOUND, pos, victim, SNDLEVEL_RAIDSIREN);
        }

        // Zero out damage to prevent the taser from killing the target.  Since
        // TraceAttack runs before OnTakeDamage, returning Plugin_Changed will
        // apply our modified damage value【494801432218117†L76-L79】.
        damage = 0.0;
        return Plugin_Changed;
    }

    return Plugin_Continue;
}

/**
 * Freeze a player by locking their movement, playing a sound and attaching
 * an ice cube model.  A timer is created to unfreeze the player after
 * `duration` seconds.
 *
 * @param client   Client index to freeze
 * @param duration Length of time (seconds) to remain frozen
 */
void FreezePlayer(int client, float duration)
{
    // Cancel any existing freeze timer
    if (g_FreezeTimer[client] != INVALID_HANDLE)
    {
        KillTimer(g_FreezeTimer[client]);
        g_FreezeTimer[client] = INVALID_HANDLE;
    }

    // Disallow additional freezes until the current one expires
    g_AllowFreeze[client] = false;

    // Lock player movement and stop their velocity
    SetEntityMoveType(client, MOVETYPE_NONE);
    float nullVel[3] = {0.0, 0.0, 0.0};
    TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, nullVel);

    // Play freeze sound at the player's location
    float pos[3];
    GetClientAbsOrigin(client, pos);
    pos[2] += 10.0;
    EmitAmbientSound(FREEZE_SOUND, pos, client, SNDLEVEL_RAIDSIREN);

    // Attach the ice model to the player.  We assign a unique targetname
    // matching the client index so we can parent the entity correctly.  Once
    // parented, the model will follow the player even if they turn.
    char parentName[64];
    Format(parentName, sizeof(parentName), "TraceFrozen%d", client);
    DispatchKeyValue(client, "targetname", parentName);

    int iceEnt = CreateEntityByName("prop_dynamic_override");
    if (iceEnt != -1)
    {
        DispatchKeyValue(iceEnt, "model", ICE_MODEL);
        DispatchKeyValue(iceEnt, "parentname", parentName);
        DispatchKeyValue(iceEnt, "solid", "0");
        DispatchKeyValue(iceEnt, "spawnflags", "256");
        SetEntPropEnt(iceEnt, Prop_Send, "m_hOwnerEntity", client);
        SetEntityMoveType(iceEnt, MOVETYPE_NOCLIP);
        SetEntProp(iceEnt, Prop_Data, "m_CollisionGroup", 0);
        DispatchSpawn(iceEnt);
        TeleportEntity(iceEnt, pos, NULL_VECTOR, NULL_VECTOR);
        SetVariantString(parentName);
        AcceptEntityInput(iceEnt, "SetParent", iceEnt, iceEnt, 0);
        // Store a reference so we can remove the model later
        g_IceRef[client] = EntIndexToEntRef(iceEnt);
    }

    // Create a timer to remove the freeze after the specified duration
    g_FreezeTimer[client] = CreateTimer(duration, Timer_Unfreeze, client, TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * Timer callback that restores a player's movement and removes the ice model.
 */
public Action Timer_Unfreeze(Handle timer, any client)
{
    // Clear timer handle
    g_FreezeTimer[client] = INVALID_HANDLE;

    // Restore player movement
    if (IsValidClient(client))
    {
        SetEntityMoveType(client, MOVETYPE_WALK);
    }

    // Remove the attached ice model if it exists
    int ent = EntRefToEntIndex(g_IceRef[client]);
    if (ent != INVALID_ENT_REFERENCE && IsValidEdict(ent) && ent != 0)
    {
        AcceptEntityInput(ent, "Kill");
    }
    g_IceRef[client] = INVALID_ENT_REFERENCE;

    // Allow the client to be frozen again
    g_AllowFreeze[client] = true;

    return Plugin_Stop;
}

/**
 * Helper to determine if a client slot refers to a real, in‑game player.
 */
bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}