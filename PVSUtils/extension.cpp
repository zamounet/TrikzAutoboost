#include "extension.h"

IServerGameClients *serverClients = NULL;

PVSUtils g_PVSUtils;
SMEXT_LINK(&g_PVSUtils);

static cell_t GetClusterForOrigin(IPluginContext *pContext, const cell_t *params)
{
    cell_t *origin;
	pContext->LocalToPhysAddr(params[1], &origin);
        
    Vector vOrigin(sp_ctof(origin[0]), sp_ctof(origin[1]), sp_ctof(origin[2]));

    int cluster = engine->GetClusterForOrigin( vOrigin );
        
    return cluster;
}

static cell_t GetClusterCount(IPluginContext *pContext, const cell_t *params)
{        
    return engine->GetClusterCount();
}

static cell_t GetPVSForCluster(IPluginContext *pContext, const cell_t *params)
{
	int index;
	int found;
	
	int cluster = params[1];

	cell_t *cluster_list;
	pContext->LocalToPhysAddr(params[2], &cluster_list);

	int max_size = params[3];

	int pvs_size = ceil(engine->GetClusterCount() / 8.0f);

	byte* pvs = new byte[pvs_size];

	int found_size = engine->GetPVSForCluster(cluster, pvs_size, pvs);

	for (index= 0, found = 0; index < found_size && found < max_size; index++)
	{
		if (pvs[index] != 0) {
			for (int i = 0; i < 8; i++) {
				if ((pvs[index] >> i) & 0x01) {
					cluster_list[found] = (index * 8) + i;
					found++;
				}
			}
		}
	}
    return found;
}

static cell_t GetPVSForClient(IPluginContext *pContext, const cell_t *params)
{
	int index;
	int found;

	IGamePlayer *player = playerhelpers->GetGamePlayer(params[1]);
	if (player == NULL)
	{
		return pContext->ThrowNativeError("Invalid client index %d", params[1]);
	}
	if (!player->IsInGame())
	{
		return pContext->ThrowNativeError("Client %d is not in game", params[1]);
	}

	Vector pos;
	serverClients->ClientEarPosition(player->GetEdict(), &pos);

	int cluster = engine->GetClusterForOrigin( pos );

	cell_t *cluster_list;
	pContext->LocalToPhysAddr(params[2], &cluster_list);

	int max_size = params[3];

	int pvs_size = ceil(engine->GetClusterCount() / 8.0f);

	byte* pvs = new byte[pvs_size];

	int found_size = engine->GetPVSForCluster(cluster, pvs_size, pvs);

	for (index= 0, found = 0; index < found_size && found < max_size; index++)
	{
		if (pvs[index] != 0) {
			for (int i = 0; i < 8; i++) {
				if ((pvs[index] >> i) & 0x01) {
					cluster_list[found] = (index * 8) + i;
					found++;
				}
			}
		}
	}
    return found;
}


const sp_nativeinfo_t MyNatives[] = 
{
	{"GetPVSForClient",		GetPVSForClient},
	{"GetPVSForCluster",		GetPVSForCluster},
	{"GetClusterForOrigin",		GetClusterForOrigin},
	{"GetClusterCount",		GetClusterCount},
	{NULL,			NULL},
};

bool PVSUtils::SDK_OnLoad(char *error, size_t maxlen, bool late)
{
	sharesys->AddNatives(myself, MyNatives);

	return true;
}

bool PVSUtils::SDK_OnMetamodLoad(ISmmAPI *ismm, char *error, size_t maxlen, bool late)
{
	GET_V_IFACE_ANY(GetServerFactory, serverClients, IServerGameClients, INTERFACEVERSION_SERVERGAMECLIENTS);

	return true;
}
