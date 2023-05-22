#include <trikz_autoboost>
#include <shavit/core>
#include <shavit/checkpoints>

ArrayList gA_Checkpoints[MAXPLAYERS+1];

public void OnMapStart()
{
    for (int i = 0; i < MAXPLAYERS; i++) {
        gA_Checkpoints[i] = new ArrayList(1);
    }
}

public void OnClientPostAdminCheck(int client)
{
    if(!IsFakeClient(client) && IsClientInGame(client))
    {
        gA_Checkpoints[client].Clear();
    }
}

void FillCheckpointArrayToIndex(int client, int index) {
    while (gA_Checkpoints[client].Length < index) {
        gA_Checkpoints[client].Push(-1);
    }
}

public Action Shavit_OnTeleport(int client, int index, int target) {
    if (gA_Checkpoints[target].Length < index)
        return Plugin_Continue;
    
    int trajectory_index = gA_Checkpoints[target].Get(index-1);

    TrikzAutoBoost_SetActivePlayertrajectory(client, trajectory_index);
    return Plugin_Continue;
}

public Action Shavit_OnSave(int client, int index, bool overflow, bool duplicate) {
    if (gA_Checkpoints[client].Length-1 < index) {
        FillCheckpointArrayToIndex(client, index);
    }

    int trajectory_index = TrikzAutoBoost_GetActivePlayertrajectory(client);  
    gA_Checkpoints[client].Set(index-1, trajectory_index);
    
    return Plugin_Continue;
}