/**
 * Extension Include for pvsutils.ext.2.css
 * Interface for getting pvs or cluster information
 * Author: Zamounet
 * 
 */

/**
 * Get the cluster of an origin
 *
 * @param float[3]		origin to check from
 * @return				origin index
 */
native int GetClusterForOrigin(const float origin[3]);

/**
 * Get the map cluster count
 *
 * @return				cluster_count
 */
native int GetClusterCount();

/**
 * Get the clusters of a cluster's pvs
 *
 * @param int		cluster index
 * @param int[]		output pvs_clusters
 * @param int		size of output
 * @return			cluster_count
 */
native int GetPVSForCluster(int cluster, int[] pvs_clusters, int size);

/**
 * Get the cluster of a client pvs
 *
 * @param int		client index
 * @param int[]		output pvs_clusters
 * @param int		size of output
 * @return			cluster_count
 */
native int GetPVSForClient(int client, int[] pvs_clusters, int size);

public Extension __ext_pvsutils = 
{
	name = "pvsutils",
	file = "pvsutils.ext",
#if defined AUTOLOAD_EXTENSIONS
	autoload = 1,
#else
	autoload = 0,
#endif
#if defined REQUIRE_EXTENSIONS
	required = 1,
#else
	required = 0,
#endif
};
