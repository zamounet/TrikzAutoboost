/*GNU GENERAL PUBLIC LICENSE

VERSION 2, JUNE 1991

Copyright (C) 1989, 1991 Free Software Foundation, Inc.
51 Franklin Street, Fith Floor, Boston, MA 02110-1301, USA

Everyone is permitted to copy and distribute verbatim copies
of this license document, but changing it is not allowed.*/

/*GNU GENERAL PUBLIC LICENSE VERSION 3, 29 June 2007
Copyright (C) 2007 Free Software Foundation, Inc. {http://fsf.org/}
Everyone is permitted to copy and distribute verbatim copies
of this license document, but changing it is not allowed.

						Preamble

	The GNU General Public License is a free, copyleft license for
software and other kinds of works.

	The licenses for most software and other practical works are designed
	to take away your freedom to share and change the works. By contrast,
	the GNU General Public license is intended to guarantee your freedom to 
	share and change all versions of a progrm--to make sure it remins free
	software for all its users. We, the Free Software Foundation, use the
	GNU General Public license for most of our software; it applies also to
	any other work released this way by its authors. You can apply it to
	your programs, too.*/
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <boost-fix>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
	name        = "boost-fix",
	author      = "Tengu, Smesh",
	description = "<insert_description_here>",
	version     = "0.1",
	url         = "http://steamcommunity.com/id/tengulawl/"
}

int g_skyFrame[MAXPLAYERS + 1];
int g_skyStep[MAXPLAYERS + 1];
float g_skyVel[MAXPLAYERS + 1][3];
float g_fallSpeed[MAXPLAYERS + 1];
int g_boostStep[MAXPLAYERS + 1];
int g_boostEnt[MAXPLAYERS + 1];
float g_boostVel[MAXPLAYERS + 1][3];
float g_boostTime[MAXPLAYERS + 1];
float g_playerVel[MAXPLAYERS + 1][3];
int g_playerFlags[MAXPLAYERS + 1];
bool g_groundBoost[MAXPLAYERS + 1];
bool g_bouncedOff[2048];
int gI_other[MAXPLAYERS + 1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{   
    CreateNative("BoostFix_BoostClient", Native_BoostClient);
    RegPluginLibrary("boost-fix");
}

bool IsValidClient(int client, bool alive = false)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) && (!alive || IsPlayerAlive(client));
}

public void OnMapStart()
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_StartTouch, Client_StartTouch);
	SDKHook(client, SDKHook_PostThinkPost, Client_PostThinkPost);
}

public void OnClientDisconnect(int client)
{
	g_skyFrame[client] = 0;
	g_skyStep[client] = 0;
	g_boostStep[client] = 0;
	g_boostTime[client] = 0.0;
	g_playerFlags[client] = 0;
}

Action Client_StartTouch(int client, int other)
{
	if(!IsValidClient(other, true) || g_playerFlags[other] & FL_ONGROUND || g_skyFrame[other] || g_boostStep[client] || GetGameTime() - g_boostTime[client] < 0.15)
	{
		return Plugin_Handled;
	}
	
	gI_other[client] = other;
	
	float clientOrigin[3];
	GetClientAbsOrigin(client, clientOrigin);

	float otherOrigin[3];
	GetClientAbsOrigin(other, otherOrigin);

	float clientMaxs[3];
	GetClientMaxs(client, clientMaxs);

	float delta = otherOrigin[2] - clientOrigin[2] - clientMaxs[2];

	if(delta > 0.0 && delta < 2.0)
	{
		float velocity[3];
		GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);
		
		if(0.0 < velocity[2] < 300.0 && !(GetClientButtons(other) & IN_DUCK) && !(GetEntProp(client , Prop_Data, "m_bDucked", 4) > 0 || GetEntProp(client, Prop_Data, "m_bDucking", 4) > 0 || GetEntPropFloat(client, Prop_Data, "m_flDucktime") > 0.0))
		{
			g_skyFrame[other] = 1;
			g_skyStep[other] = 1;
			g_skyVel[other] = velocity;
			GetEntPropVector(other, Prop_Data, "m_vecAbsVelocity", velocity);
			g_fallSpeed[other] = FloatAbs(velocity[2]);
		}
	}
	
	return Plugin_Continue;
}

void Client_PostThinkPost(int client)
{
	if(g_skyFrame[client])
	{	
		if(g_boostStep[client] || (++g_skyFrame[client] > 4 && g_skyStep[client] != 2 && g_skyStep[client] != 3))
		{
			g_skyFrame[client] = 0;
			g_skyStep[client] = 0;
		}
	}

	if(g_boostStep[client] == 1)
	{
		int entity = EntRefToEntIndex(g_boostEnt[client]);

		if(entity != INVALID_ENT_REFERENCE)
		{
			float velocity[3];
			GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", velocity);

			if(velocity[2] > 0.0)
			{
				velocity[0] = g_boostVel[client][0] * 0.135;
				velocity[1] = g_boostVel[client][1] * 0.135;
				velocity[2] = g_boostVel[client][2] * -0.135;
				TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, velocity);
			}
		}
		g_boostStep[client] = 2;
	}
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	g_playerFlags[client] = GetEntityFlags(client);

	if(g_skyFrame[client] && g_boostStep[client])
	{
		g_skyFrame[client] = 0;
		g_skyStep[client] = 0;
	}

	if(!g_skyStep[client] && !g_boostStep[client])
	{
		if(GetGameTime() - g_boostTime[client] < 0.15)
		{
			float basevel[3];
			SetEntPropVector(client, Prop_Data, "m_vecBaseVelocity", basevel);
		}
		
		return Plugin_Continue;
	}

	float velocity[3];
	SetEntPropVector(client, Prop_Data, "m_vecBaseVelocity", velocity);

	if(g_skyStep[client])
	{
		if(g_skyStep[client] == 1)
		{
			int flags = g_playerFlags[client];
			int oldButtons = GetEntProp(client, Prop_Data, "m_nOldButtons");

			if(flags & FL_ONGROUND && buttons & IN_JUMP && !(oldButtons & IN_JUMP))
			{
				g_skyStep[client] = 2;
			}
		}
		
		else if(g_skyStep[client] == 2)
		{
			GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);

			velocity[0] -= g_skyVel[client][0];
			velocity[1] -= g_skyVel[client][1];
			
			if(GetEntityFlags(gI_other[client]) & FL_INWATER)
			{
				velocity[2] += g_skyVel[client][2];
			}
			
			else
			{
				velocity[2] += g_skyVel[client][2] - 65; //518.986755
				velocity[2] += 20.0;
				if(velocity[2] < 518.986755)
					velocity[2] = 518.986755;
				
			}

			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, velocity);

			g_skyStep[client] = 3;
		}
		
		else if(g_skyStep[client] == 3)
		{
			GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);

			if(g_fallSpeed[client] < 300.0)
			{
				g_skyVel[client][2] *= g_fallSpeed[client] / 300.0;
			}

			velocity[0] += g_skyVel[client][0];
			velocity[1] += g_skyVel[client][1];
			velocity[2] += g_skyVel[client][2];
			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, velocity);

			g_skyStep[client] = 0;
		}
	}

	if(g_boostStep[client])
	{
		if(g_boostStep[client] == 2)
		{
			velocity[0] = g_playerVel[client][0] - g_boostVel[client][0];
			velocity[1] = g_playerVel[client][1] - g_boostVel[client][1];
			velocity[2] = g_boostVel[client][2];
			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, velocity);
			
			g_boostStep[client] = 3;
		}
		
		else if(g_boostStep[client] == 3)
		{
			GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", velocity);
			
			if(g_groundBoost[client])
			{
				velocity[0] += g_boostVel[client][0];
				velocity[1] += g_boostVel[client][1];
				velocity[2] += g_boostVel[client][2];
			}
			
			else
			{
				velocity[0] += g_boostVel[client][0] * 0.135;
				velocity[1] += g_boostVel[client][1] * 0.135;
			}
			
			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, velocity);

			g_boostStep[client] = 0;
		}
	}

	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrContains(classname, "_projectile") != -1)
	{
		g_bouncedOff[entity] = false;
		
		SDKHook(entity, SDKHook_StartTouch, Projectile_StartTouch);
		SDKHook(entity, SDKHook_EndTouch, Projectile_EndTouch);
	}
}

Action Projectile_StartTouch(int entity, int client)
{
	if(!IsValidClient(client, true))
	{
		return Plugin_Continue;
	}
	
	if(g_boostStep[client] || g_playerFlags[client] & FL_ONGROUND)
	{
		return Plugin_Continue;
	}
	
	float entityOrigin[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", entityOrigin);

	float clientOrigin[3];
	GetClientAbsOrigin(client, clientOrigin);

	float entityMaxs[3];
	GetEntPropVector(entity, Prop_Send, "m_vecMaxs", entityMaxs);

	float delta = clientOrigin[2] - entityOrigin[2] - entityMaxs[2];
	if(delta > 0.0 && delta < 2.0)
	{
		g_boostStep[client] = 1;
		g_boostEnt[client] = EntIndexToEntRef(entity);
		GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", g_boostVel[client]);
		GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", g_playerVel[client]);
		g_groundBoost[client] = g_bouncedOff[entity];
		g_boostTime[client] = GetGameTime();
		SetEntProp(entity, Prop_Data, "m_nSolidType", 0); //No solid model
	}
 
	return Plugin_Continue;
}
 
Action Projectile_EndTouch(int entity, int other)
{
	if(!other)
	{
		g_bouncedOff[entity] = true;
	}
}

public any Native_BoostClient(Handle plugin, int numParams) {

	int client = GetNativeCell(1);

	float entityOrigin[3];
	GetNativeArray(2, entityOrigin, sizeof(entityOrigin));

	float entityVelocity[3];
	GetNativeArray(3, entityVelocity, sizeof(entityVelocity));

	if(!IsValidClient(client, true))
	{
		return false;
	}
	
	if(g_boostStep[client] || g_playerFlags[client] & FL_ONGROUND)
	{
		return false;
	}

	float clientOrigin[3];
	GetClientAbsOrigin(client, clientOrigin);

	float entityMaxs[3] = {2.0, 2.0, 2.0};

	float delta = clientOrigin[2] - entityOrigin[2] - entityMaxs[2];
	if(delta > -2.0 && delta < 2.0)
	{
		g_boostStep[client] = 1;
		g_boostEnt[client] = client;
		g_boostVel[client] = entityVelocity;
		GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", g_playerVel[client]);
		g_boostTime[client] = GetGameTime();
		return true;
	}
	return false;
}