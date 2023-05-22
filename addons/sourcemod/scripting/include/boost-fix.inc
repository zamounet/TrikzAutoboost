#if defined _boost_fix_included
 #endinput
#endif
#define _boost_fix_included

/*
* Check's a given entities existance to the plugin
* 
* @param client		        Client index.
* @param entityOrigin		Entity Origin.
* @param entityVelocity		    Entity Velocity.

* 
* @return			false, if the entity is not a toggleable, true otherwise.
*/
native bool BoostFix_BoostClient(int client, float entityOrigin[3], float entityVelocity[3]);

#if !defined REQUIRE_PLUGIN
public __pl_boost_fix_SetNTVOptional()
{
    MarkNativeAsOptional("BoostFix_BoostClient");
}
#endif  

public SharedPlugin __pl_boost_fix = 
{
	name = "boost-fix",
	file = "boost-fix.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};