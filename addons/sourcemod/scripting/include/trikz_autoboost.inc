#pragma newdecls required

#if defined _trikz_autoboost_included
 #endinput
#endif
#define _trikz_autoboost_included

#define TBPLAYERARRAY g_BoostPlayers

#define TBPLAYER(%1) TBPLAYERARRAY[%1]

/*
* Return the current active trajectory for a client
* 
* @param client		Client index.
* 
* @return			int, The index of the current Active trajectory
*/
native int TrikzAutoBoost_GetActivePlayertrajectory(int client);

/*
* Set the Player's current active trajectory
* 
* @param client		Client index.
* @param entity		Trajectory index.
* 
*/
native void TrikzAutoBoost_SetActivePlayertrajectory(int client, int index);

public SharedPlugin __pl_trikz_autoboost = 
{
    name = "trikz_autoboost",
    file = "trikz_autoboost.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_trikz_autoboost_SetNTVOptional()
{
    MarkNativeAsOptional("TrikzAutoBoost_GetActivePlayertrajectory");
    MarkNativeAsOptional("TrikzAutoBoost_SetActivePlayertrajectory");
}
#endif