#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_AUTHOR "Zamounet"
#define PLUGIN_VERSION "0.0.1"

#define SPECMODE_NONE 				0
#define SPECMODE_FIRSTPERSON 		4
#define SPECMODE_3RDPERSON 			5
#define SPECMODE_FREELOOK	 		6

#define TEMPENT_MAX_LIFETIME 0.7
#define MAX_TRAJECTORIES 512

#include <clientprefs>
#include <sourcemod>
#include <sdktools>
#include <morecolors>
#include <queue>
#include <sdkhooks>
#include <topmenus>
#include <adminmenu>
#include <trikz_autoboost>

#include <boost-fix>
#include <pvsutils>

#undef REQUIRE_PLUGIN
#include <trikz_solid>
#include <bTimes-teams>


bool g_bLateLoaded = false;
EngineVersion g_Game;

ConVar sv_gravity;
ConVar sm_gtrajectory;
ConVar sm_gtrajectory_admin;
ConVar sm_gtrajectory_size;
ConVar sm_gtrajectory_timestep;
ConVar sm_gtrajectory_delay;
ConVar sm_gtrajectory_throw;
ConVar sm_gtrajectory_lob;
ConVar sm_gtrajectory_roll;

int g_Trail;

bool g_needsDraw[MAXPLAYERS];
bool g_bInQueue[MAXPLAYERS][MAX_TRAJECTORIES];
Queue g_DrawQueue[MAXPLAYERS];


int gTELimitData[8];
int gTELimitDataSize;
Address gTELimitAddress;

bool g_bMultiplayerSolidity;

public Plugin myinfo = {
    name = "Auto Trikz boosting",
    author = PLUGIN_AUTHOR,
    description = "Helps flying trikz map solo.",
    version = PLUGIN_VERSION,
    url = ""
};

enum struct TrajectorySegments {
    float time;
    float start[3];
    float end[3];
    float velocity[3];

    void Draw(const int[] iClients, int iNumClients, int iTrail, float fWidth, int iTrailColor[4], float fLifespan) {
        TE_SetupBeamPoints(this.start, this.end, iTrail, 0, 0, 0, fLifespan, fWidth, fWidth, 0, 0.0, iTrailColor, 0);
        TE_Send(iClients, iNumClients);
    }
}

enum struct Trajectory {
    ArrayList segments;

    float startTime;
    float endTime;

    float fPosition[3];
    float fEndPosition[3];
    float fVelocity[3];
    float fThrowAngle[3];
    float fThrowVector[3];
    float fTimeStep;
    float fDisp;
    float fGravity;
    float fFactor;

    int iSpeed;
    int iAngle;

    bool crouched;
    float fWaitTime;

    void New(int iClient, float fPosition[3], float fVelocity[3], float fThrowAngle[3], bool bAdjustAngle = true, float fTimeStep, float fDisp, float fGravity, float fFactor, bool crouched, float fWaitTime, float fStartTime = -20.0, float fEndTime = -20.0) {
        float fThrowVector[3], fwd[3], right[3], left[3];

        this.segments = new ArrayList(sizeof(TrajectorySegments));

        this.startTime = (fStartTime == -20.0) ? 0.0 : fStartTime;
        this.endTime = (fEndTime == -20.0) ? 1.0 : fEndTime; // GetDetonationTime("weapon_flashbang") changed to 1.0 for performance issue
    
        this.fPosition = fPosition;
        this.fVelocity = fVelocity;
        this.fTimeStep = fTimeStep;
        this.fDisp = fDisp;
        this.fGravity = fGravity;
        this.fFactor = fFactor;

        this.fWaitTime = fWaitTime;

        if (bAdjustAngle)
            fThrowAngle[0] = -10.0 + fThrowAngle[0] + FloatAbs(fThrowAngle[0]) * 10.0 / 90.0;
        GetAngleVectors(fThrowAngle, fwd, right, left);
        NormalizeVector(fwd, fThrowVector);

        this.fThrowAngle = fThrowAngle;
        this.fThrowVector = fThrowVector;

        this.crouched = crouched;

        this.iSpeed = RoundToNearest(SquareRoot(fVelocity[0] * fVelocity[0] + fVelocity[1] * fVelocity[1]));
        this.iAngle = RoundToNearest(fThrowAngle[0] * -1);

        if (this.crouched)
            this.SetSpeed(iClient, 90);
        else
            this.SetSpeed(iClient, 250);

        if (!this.IsJumpThrow())
            this.ToggleThrow(iClient);

        this.GenerateTrajectory(iClient);
    }

    void ChangePosition(int iClient, float fPosition[3], float fThrowAngle[3], bool crouched) {
        float fThrowVector[3], fwd[3], right[3], left[3];

        fThrowAngle[0] = -10.0 + fThrowAngle[0] + FloatAbs(fThrowAngle[0]) * 10.0 / 90.0;

        GetAngleVectors(fThrowAngle, fwd, right, left);
        NormalizeVector(fwd, fThrowVector);

        this.fPosition = fPosition;
        this.fThrowAngle = fThrowAngle;
        this.fThrowVector = fThrowVector;

        this.crouched = crouched;

        this.SetSpeed(iClient, this.iSpeed);
        this.iAngle = RoundToNearest(fThrowAngle[0] * -1);
        

        this.segments.Clear();
        this.GenerateTrajectory(iClient);
    }

    void SetSpeed(int iClient, int speed) {
        float fNormalizedAngle[3];
        NormalizeVector(this.fThrowVector, fNormalizedAngle);

        this.fVelocity[0] = fNormalizedAngle[0] * speed;
        this.fVelocity[1] = fNormalizedAngle[1] * speed;

        this.iSpeed = speed;

        this.segments.Clear();
        this.GenerateTrajectory(iClient);
    }

    void SetAngle(int iClient, int angle) {
        float fwd[3], right[3], left[3];

        this.fThrowAngle[0] = float(angle) * -1;

        GetAngleVectors(this.fThrowAngle, fwd, right, left);
        NormalizeVector(fwd, this.fThrowVector);

        this.iAngle = angle;

        this.segments.Clear();
        this.GenerateTrajectory(iClient);
    }

    bool IsJumpThrow() {
        return (this.fVelocity[2] > 200);
    }

    void ToggleThrow(int iClient) {
        if (this.IsJumpThrow()) {
            this.fVelocity[2] = 0.0;
        } else {
            this.fVelocity[2] = 290.0;
        }

        this.segments.Clear();
        this.GenerateTrajectory(iClient);
    }

    void ToggleCrouch(int iClient) {
        if (this.crouched) {
            this.fPosition[2] += 27.0;
        } else {
            this.fPosition[2] -= 27.0;
        }

        this.crouched = !this.crouched;

        if (this.crouched)
            this.SetSpeed(iClient, 90);
        else
            this.SetSpeed(iClient, 250);


        this.segments.Clear();
        this.GenerateTrajectory(iClient);
    }

    float Hit(int iClient, float position[3], float velocity[3]) {
        TrajectorySegments segment;
        float mins[3] = {-16.0, -2.0, -2.0}, maxs[3] = {16.0, 2.0, 2.0};
        for (int index = 0; index < this.segments.Length; index++) {
            this.segments.GetArray(index, segment);

            if (this.endTime < segment.time)
                return 0.0;
            if (this.startTime > segment.time)
                continue;

            Handle gRayTrace = TR_TraceHullFilterEx(segment.start, segment.end, mins, maxs, CONTENTS_HITBOX, TraceFilter_FilterOtherPlayers, iClient);
            float fraction = TR_GetFraction(gRayTrace);
            
            if (fraction == 1.0) {
                delete gRayTrace;
                continue;
            } 
            
            if (TR_GetEntityIndex(gRayTrace) == iClient) {
                TR_GetEndPosition(position, gRayTrace);
                velocity = segment.velocity;
                delete gRayTrace;
                return fraction;
            } else {
                delete gRayTrace;
                return 0.0;
            }
        }
        return 0.0;
    }

    void GenerateTrajectory(int client) {
        ArrayList segments = this.segments;

        float dtime = GetDetonationTime("weapon_flashbang");
            
        float GrenadeVelocity[3], PlayerVelocity[3], ThrowVelocity;
        float gStart[3], gEnd[3];

        gStart = this.fPosition;
        for (int i = 0; i < 3; i++)
            gStart[i] += this.fThrowVector[i] * 16.0;
    
        gStart[2] += this.fDisp;
    
        PlayerVelocity = this.fVelocity;
    
        switch (g_Game)
        {
            case Engine_CSS:
            {
                ThrowVelocity = (90.0 - this.fThrowAngle[0]) * 6.0;
                if (ThrowVelocity > 750.0)
                    ThrowVelocity = 750.0;
            }
        
            case Engine_CSGO:
            {
                ThrowVelocity = 750.0 * this.fFactor;
                ScaleVector(PlayerVelocity, 1.25);
            }
        }
    
        for (int i = 0; i < 3; i++)
            GrenadeVelocity[i] = this.fThrowVector[i] * ThrowVelocity + PlayerVelocity[i];

        if (this.iAngle >= 65) { // Fixes MH being hard to hit
            TrajectorySegments startSegment;

            startSegment.start = this.fPosition;
            startSegment.end = gStart;
            startSegment.time = 0.0;
            startSegment.velocity = GrenadeVelocity;
            segments.PushArray(startSegment);
        }
    
        float dt = this.fTimeStep;
        for (float t = 0.0; t <= dtime; t += dt)
        {
            TrajectorySegments segment;

            gEnd[0] = gStart[0] + GrenadeVelocity[0] * dt;
            gEnd[1] = gStart[1] + GrenadeVelocity[1] * dt;
        
            float gForce = 0.4 * this.fGravity;
            float NewVelocity = GrenadeVelocity[2] - gForce * dt;
            float AvgVelocity = (GrenadeVelocity[2] + NewVelocity) / 2.0;
        
            segment.velocity = GrenadeVelocity;
        

            gEnd[2] = gStart[2] + AvgVelocity * dt;
            GrenadeVelocity[2] = NewVelocity;
        
            float mins[3] = {-2.0, -2.0, -2.0}, maxs[3] = {2.0, 2.0, 2.0};
            Handle gRayTrace = TR_TraceHullFilterEx(gStart, gEnd, mins, maxs, MASK_SHOT_HULL, TraceFilter_FilterPlayer, client);
            if (TR_GetFraction(gRayTrace) != 1.0) 
            {
                if (TR_GetEntityIndex(gRayTrace) <= MaxClients && t == 0.0)
                {
                    CloseHandle(gRayTrace);
                    gStart = gEnd;
                    continue;
                }
            
                TR_GetEndPosition(gEnd, gRayTrace);
            
                float NVector[3];
                TR_GetPlaneNormal(gRayTrace, NVector);
                float Impulse = 2.0 * GetVectorDotProduct(NVector, GrenadeVelocity);
                for (int i = 0; i < 3; i++)
                {
                    GrenadeVelocity[i] -= Impulse * NVector[i];
                
                    if (FloatAbs(GrenadeVelocity[i]) < 0.1)
                        GrenadeVelocity[i] = 0.0;
                }
            
                float SurfaceElasticity = GetEntPropFloat(TR_GetEntityIndex(gRayTrace), Prop_Send, "m_flElasticity");
                float elasticity = 0.45 * SurfaceElasticity;
                ScaleVector(GrenadeVelocity, elasticity);
            }
            CloseHandle(gRayTrace);
        
            segment.start = gStart;
            segment.end = gEnd;
            segment.time = t;
        
            segments.PushArray(segment);
            gStart = gEnd;
        }
        this.fEndPosition = gEnd;
    }

    void Draw(int iClient, int iTrail, float fWidth, int iTrailColor[4], float fLifespan) {
        TrajectorySegments segment;
        int clientsToDraw[MAXPLAYERS];

        int iClientsFound;

        iClientsFound = GetClientAndSpectators(iClient, clientsToDraw, MAXPLAYERS);

        for (int index = 0; index < this.segments.Length; index++) {
            this.segments.GetArray(index, segment);
            if (this.startTime <= segment.time && this.endTime >= segment.time)
            {
                segment.Draw(clientsToDraw, iClientsFound, iTrail, fWidth, iTrailColor, fLifespan);
            }
        }
    }

    void Export(char[] buffer, int buffer_size) {
        Format(buffer, buffer_size, "%.2f|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f|%d|%.2f|%.2f|%.2f",
            this.fPosition[0], this.fPosition[1], this.fPosition[2],
            this.fVelocity[0], this.fVelocity[1], this.fVelocity[2],
            this.fThrowAngle[0], this.fThrowAngle[1], this.fThrowAngle[2],
            this.fGravity, this.crouched ? 1 : 0, this.fWaitTime,
            this.startTime, this.endTime
        );
    }

    bool Import(int iClient, const char[] data, float fTimeStep, float fDisp, float fFactor) {
        char sExplodedString[20][MAX_BUFFER_LENGTH];
        int retrieved = ExplodeString(data, "|", sExplodedString, 20, MAX_BUFFER_LENGTH, false);
        
        if (retrieved < 14) { // Max number of parameters
            return false;
        }
        
        float velocity[3];
        float position[3];
        float angle[3];

        for(int i = 0; i < 3; i++) {
            position[i] = StringToFloat(sExplodedString[i]);
            velocity[i] = StringToFloat(sExplodedString[i+3]);
            angle[i] = StringToFloat(sExplodedString[i+6]);
        }

        this.New(
            iClient, position, velocity, angle, false,
            fTimeStep, fDisp, StringToFloat(sExplodedString[9]), fFactor,
            (StringToInt(sExplodedString[10]) == 1) ? true : false,
            StringToFloat(sExplodedString[11]), StringToFloat(sExplodedString[12]),
            StringToFloat(sExplodedString[13])
        );
        return true;
    }

    ArrayList Clone() {
        ArrayList newList = new ArrayList(sizeof(TrajectorySegments));
        TrajectorySegments segment;
        
        for (int i = 0; i < this.segments.Length; i++) {
            this.segments.GetArray(i, segment);
            newList.PushArray(segment);
        }
        return newList;
    }

    void Delete() {
        delete this.segments;
    }

}

enum struct AutoBoostPlayer {
    int client;
    bool enabled;

    int trail;
    float width;

    float disp;
    float factor;

    float waitTime;

    bool velocityMatchPlayer;
    float velocity[3];

    int trailColor[4];
    int activeTrailColor[4];
    int editTrailColor[4];
    int disabledTrailColor[4];

    float gravity;
    float timeStep;

    bool flashPreviewEnabled;
    bool profileDisplayEnabled;

    float flashPreviewNextDraw;
    float profileDisplayNextDraw;

    Handle thinkTimer;

    bool canHit;
    Handle hitTimer;

    Queue DrawQueue;

    int activeTrajectory;
    int editTrajectory;

    ArrayList trajectories;
    StringMap trajectoryClusterTrie;

    void New(int iClient, int iTrail, float fWidth, float fDisp, float fFactor, float fGravity, float fTimeStep, float fWaitTime) {
        this.client = iClient;
        this.enabled = false;

        this.trail = iTrail;
        this.width = fWidth;

        this.disp = fDisp;
        this.factor = fFactor;

        this.waitTime = fWaitTime;

        this.trailColor = { 0, 255, 255, 50 };
        this.activeTrailColor = { 255, 0, 255, 255 };
        this.editTrailColor = {255, 255, 0, 255};
        this.disabledTrailColor = {255, 0, 0, 255};

        this.gravity = fGravity;
        this.timeStep = fTimeStep;

        this.velocityMatchPlayer = true;

        this.flashPreviewEnabled = false;
        this.profileDisplayEnabled = false;

        this.flashPreviewNextDraw = -1.0;
        this.profileDisplayNextDraw = -1.0;

        this.thinkTimer = INVALID_HANDLE;

        this.canHit = true;
        this.hitTimer = INVALID_HANDLE;

        this.activeTrajectory = 0;
        this.editTrajectory = -1;

        this.trajectories = new ArrayList(sizeof(Trajectory));
        this.trajectoryClusterTrie = CreateTrie();

        this.DrawQueue = new Queue();
        g_DrawQueue[this.client] = this.DrawQueue;
    }

    bool Toggle() {
        if (!this.enabled) {
            this.Enable();
        }
        else {
            this.Disable();
        }
        return this.enabled;
    }

    void Enable() {
        this.enabled = true;

        this.DisplayFlashPreview(this.flashPreviewEnabled);
        this.DisplayProfileView(this.profileDisplayEnabled);
        SDKHook(this.client, SDKHook_PostThinkPost, Hook_PostThinkPost);

        this.thinkTimer = CreateTimer(0.2, Timer_PlayerThink, this.client, TIMER_REPEAT);
    }

    
    void Disable() {
        this.enabled = false;
        this.canHit = true;
        SDKUnhook(this.client, SDKHook_PostThinkPost, Hook_PostThinkPost);
        
        this.DrawQueue.Clear();
        g_needsDraw[this.client] = false;

        if (this.thinkTimer != INVALID_HANDLE) {
            delete this.thinkTimer;
            this.thinkTimer = INVALID_HANDLE;
        }

        if (this.hitTimer != INVALID_HANDLE) {
            delete this.hitTimer;
            this.hitTimer = INVALID_HANDLE;
        }
    }

    void SetActiveTrajectory(int index) {
        this.activeTrajectory = index;
        this.canHit = true;

        if (this.hitTimer != INVALID_HANDLE) {
            delete this.hitTimer;
            this.hitTimer = INVALID_HANDLE;
        }
    }

    void DisplayFlashPreview(bool state) {
        this.flashPreviewEnabled = state;
    }

    bool ToggleFlashPreview() {
        this.DisplayFlashPreview(!this.flashPreviewEnabled);
        return this.flashPreviewEnabled;
    }

    void DisplayProfileView(bool state) {
        this.profileDisplayEnabled = state;
    }

    bool ToggleProfileView() {
        this.DisplayProfileView(!this.profileDisplayEnabled);
        return this.profileDisplayEnabled;
    }

    void NewTrajectory(bool silent = false) {
        float fPosition[3], fVelocity[3], fThrowAngle[3];
        Trajectory trajectory;
        bool crouched;

        GetClientEyePosition(this.client, fPosition);
        
        GetEntPropVector(this.client, Prop_Data, "m_vecAbsVelocity", fVelocity);
        
        GetClientEyeAngles(this.client, fThrowAngle);

        crouched = view_as<bool>(GetEntProp(this.client, Prop_Data, "m_bDucked", 4, 0));

        trajectory.New(this.client, fPosition, fVelocity, fThrowAngle, _, this.timeStep, this.disp, this.gravity, this.factor, crouched, this.waitTime);
        this.trajectories.PushArray(trajectory);

        int cluster = GetClusterForOrigin(trajectory.fPosition);
        this.AddTrajectoryIndexToClusterTrie(this.GetTrajectoryCount()-1, cluster);

        if (!silent && this.client > 0) {
            char flash_export[MAX_BUFFER_LENGTH];

            trajectory.Export(flash_export, sizeof(flash_export));

            int count = this.GetTrajectoryCount();
            ColorPrintToChat(this.client, "\"%N\" Current Trajectory Saved: #%d. Use sm_activatetraj #%d. To Recreate use: sm_savetraj %s", this.client, count, count, flash_export);
        }
    }

    void ChangeTrajectoryPosition(int trajectory_index) {
        float fPosition[3], fThrowAngle[3];
        Trajectory trajectory;

        bool crouched;

        GetClientEyePosition(this.client, fPosition);
        
        GetClientEyeAngles(this.client, fThrowAngle);

        crouched = ((GetClientButtons(this.client) & IN_DUCK) > 0);
            
        this.trajectories.GetArray(trajectory_index, trajectory);
        trajectory.ChangePosition(this.client, fPosition, fThrowAngle, crouched);
        this.trajectories.SetArray(trajectory_index, trajectory);
        this.RebuildClusterTrie();
    }

    bool ImportTrajectory(int index = -1, const char[] data) {
        Trajectory trajectory;

        if (index > this.GetTrajectoryCount())
            return false;

        bool success = trajectory.Import(this.client, data, this.timeStep, this.disp, this.factor);

        if (!success)
            return false;

        if (index != -1 && index < this.GetTrajectoryCount()) {
            this.SetTrajectory(index, trajectory);
            this.RebuildClusterTrie();
        } else {
            this.trajectories.PushArray(trajectory);
            int cluster = GetClusterForOrigin(trajectory.fPosition);
            this.AddTrajectoryIndexToClusterTrie(this.GetTrajectoryCount()-1, cluster);
        }

        return true;
    }

    void DeleteTrajectories() {
        Trajectory eTrajectory;

        if (this.trajectories != null) {
            for (int index = 0; this.trajectories && this.trajectories.Length > index; index++) {
                this.trajectories.GetArray(index, eTrajectory);

                eTrajectory.Delete();
            }
            delete this.trajectories;
            this.trajectories = null;
        }
    }

    bool CopyTrajectories(ArrayList trajectories) {

        if (trajectories == null)
            return false;

        this.DeleteTrajectories();
        this.trajectories = this.Clone(trajectories);
        this.RebuildClusterTrie();
        return true;
    }

    void Hit() {
        if (!this.canHit)
            return;

        float position[3], velocity[3];
        float fraction;
        Trajectory eTrajectory;

        if (!this.GetTrajectory(this.activeTrajectory, eTrajectory)) {
            return;
        }
    
        fraction =  eTrajectory.Hit(this.client, position, velocity);

        if (fraction == 0.0)
            return;

        velocity[2] = velocity[2] - (0.4 * this.gravity) * (this.timeStep * fraction);
        bool boosted = BoostFix_BoostClient(this.client, position, velocity);

        if (boosted) {
            Trajectory trajectory;
            
            this.canHit = false;
            
            for (int i = 1; i <= MaxClients; i++)
            {
                if (IsClientInGame(i))
                {
                    int iSpecMode = GetEntProp(i, Prop_Send, "m_iObserverMode");
                    if (iSpecMode == SPECMODE_FIRSTPERSON || iSpecMode == SPECMODE_3RDPERSON) {
			            int iTarget = GetEntPropEnt(i, Prop_Send, "m_hObserverTarget");
			            if (iTarget == this.client) {
                            EmitSoundToClient(i, "weapons/flashbang/grenade_hit1.wav", _, _, _, _, 0.75, _, _, position); 
                        }
                    }   
                }
            } 

            EmitSoundToClient(this.client, "weapons/flashbang/grenade_hit1.wav", _, _, _, _, 0.75, _, _, position); 

            if (this.GetTrajectory(this.activeTrajectory + 1, trajectory)){
                this.activeTrajectory = this.activeTrajectory + 1;
                this.hitTimer = CreateTimer(trajectory.fWaitTime, Timer_PlayerHit, this.client, TIMER_FLAG_NO_MAPCHANGE);
            } else {
                this.activeTrajectory = -1;
            }

        }
    }

    void DrawTrajectories() {
        int pvs_clusters[512];
        int found = GetPVSForClient(this.client, pvs_clusters, sizeof(pvs_clusters));

        int iTrajectoriesIndexes[512] = {0, ...};
        char sClusterIndex[10];
    
        int size;

        for (int i = 0; i < found; i++) {
            IntToString(pvs_clusters[i], sClusterIndex, sizeof(sClusterIndex));
            if (!this.trajectoryClusterTrie.GetArray(sClusterIndex, iTrajectoriesIndexes, sizeof(iTrajectoriesIndexes), size))
                continue;

            for (int index = 0; index < size; index++) {
                this.DrawTrajectory(iTrajectoriesIndexes[index]);
            }
        }
    }

    void DrawTrajectory(int index) {
        Trajectory eTrajectory;

        if (g_bInQueue[this.client][index])
            return;
        if (this.GetTrajectory(index, eTrajectory)) {
            g_DrawQueue[this.client].Push(index);
            g_bInQueue[this.client][index] = true;
            if (!(g_needsDraw[this.client])){
                RequestFrame(OnGameFrame_DrawQueue, this.client);
                g_needsDraw[this.client] = true;
            }
        }
    }

    void _DrawTrajectory(int index, int iTrailIndex, float fWidth, int trail_color[4], float lifespan) {
        Trajectory eTrajectory;

        if (this.GetTrajectory(index, eTrajectory)) {
            eTrajectory.Draw(this.client, iTrailIndex, fWidth, trail_color, lifespan);
        }
    }

    bool GetTrajectory(int index, Trajectory trajectory) {
        if (this.trajectories.Length-1 >= index && index >= 0) {
            this.trajectories.GetArray(index, trajectory);
            return true;
        }
        return false;
    }

    void SetTrajectory(int index, Trajectory trajectory) {
        if (this.trajectories.Length-1 >= index) {
            Trajectory oldTrajectory;
            this.trajectories.GetArray(index, oldTrajectory);

            oldTrajectory.Delete();

            this.trajectories.SetArray(index, trajectory);
            this.RebuildClusterTrie();
        }
    }

    bool OrderTrajectory(int index, int new_index) {
        if (new_index < 0 || new_index >= this.trajectories.Length)
            return false;
        if (index < 0 || index >= this.trajectories.Length)
            return false;

        this.trajectories.SwapAt(index, new_index);
        this.RebuildClusterTrie();
        return true;
    }

    void DeleteTrajectory(int index) {
        Trajectory trajectory;
        this.trajectories.GetArray(index, trajectory);

        trajectory.Delete();

        this.trajectories.Erase(index);
        this.RebuildClusterTrie();
    }      

    int GetTrajectoryCount() {
        return this.trajectories.Length;
    }

    void AddTrajectoryIndexToClusterTrie(int iTrajectoryIndex, int iClusterIndex) {
        int iTrajectoriesIndexes[512] = {0, ...};
        char sClusterIndex[10];
        int size = 0;

        if (this.trajectoryClusterTrie == INVALID_HANDLE)
            return;

        IntToString(iClusterIndex, sClusterIndex, sizeof(sClusterIndex));

        if (!this.trajectoryClusterTrie.ContainsKey(sClusterIndex))
            size = 0;
        else
            this.trajectoryClusterTrie.GetArray(sClusterIndex, iTrajectoriesIndexes, sizeof(iTrajectoriesIndexes), size);
        
        iTrajectoriesIndexes[size] = iTrajectoryIndex;
        this.trajectoryClusterTrie.SetArray(sClusterIndex, iTrajectoriesIndexes, size+1, true);
    }

    void RebuildClusterTrie() {
        Trajectory trajectory;
        int size = this.trajectories.Length;

        if (this.trajectoryClusterTrie != null) {
            delete this.trajectoryClusterTrie;
            this.trajectoryClusterTrie = null;
        }

        this.trajectoryClusterTrie = CreateTrie();
        

        for (int i = 0; i < size; i++) {
            if (!this.GetTrajectory(i, trajectory))
                continue;
            int cluster = GetClusterForOrigin(trajectory.fPosition);
            this.AddTrajectoryIndexToClusterTrie(i, cluster);
        }
    }

    void ToggleTrajectoryThrow(int index) {
        Trajectory trajectory;
            
        this.trajectories.GetArray(index, trajectory);
        trajectory.ToggleThrow(this.client);
        this.trajectories.SetArray(index, trajectory);
    }

    void ToggleTrajectoryCrouch(int index) {
        Trajectory trajectory;
            
        this.trajectories.GetArray(index, trajectory);
        trajectory.ToggleCrouch(this.client);
        this.trajectories.SetArray(index, trajectory);
    }

    void SetTrajectorySpeed(int index, int speed) {
        Trajectory trajectory;
            
        this.trajectories.GetArray(index, trajectory);
        trajectory.SetSpeed(this.client, speed);
        this.trajectories.SetArray(index, trajectory);
    }

    void SetTrajectoryAngle(int index, int angle) {
        Trajectory trajectory;
            
        this.trajectories.GetArray(index, trajectory);
        trajectory.SetAngle(this.client, angle);
        this.trajectories.SetArray(index, trajectory);
    }

    void SetTrajectoryDelay(int index, float delay) {
        Trajectory trajectory;
            
        this.trajectories.GetArray(index, trajectory);
        trajectory.fWaitTime = delay;
        this.trajectories.SetArray(index, trajectory);
    }

    void SetTrajectoryLifespan(int index, float startTime, float endTime) {
        Trajectory trajectory;
            
        this.trajectories.GetArray(index, trajectory);
        trajectory.startTime = startTime;
        trajectory.endTime = endTime;
        this.trajectories.SetArray(index, trajectory);
    }

    bool ExportTrajectories(int index = -1) {
        if (!this.trajectories || this.trajectories.Length == 0 || (index != -1 && index > this.trajectories.Length-1))
            return false;
        
        Trajectory trajectory;

        char buffer[MAX_BUFFER_LENGTH];

        if (index >= 0) {
            this.trajectories.GetArray(index, trajectory);
            trajectory.Export(buffer, sizeof(buffer));
            PrintToConsole(this.client, "sm_savetraj %s;", buffer);
            return true;
        }

        for (int i = 0; i < this.trajectories.Length; i++) {
            this.trajectories.GetArray(i, trajectory);
            
            trajectory.Export(buffer, sizeof(buffer));
            PrintToConsole(this.client, "sm_savetraj %s %d;", buffer, i+1);
        }
        return true;
    }

    ArrayList Clone(ArrayList trajectories) {

        ArrayList newList;
        Trajectory trajectory;
        Trajectory newTrajectory;

        newList = new ArrayList(trajectories.BlockSize);

        for (int i = 0; i < trajectories.Length; i++) {
            trajectories.GetArray(i, trajectory);
            
            newTrajectory = trajectory;
            newTrajectory.segments = trajectory.Clone();

            newList.PushArray(newTrajectory);
        }
        return newList;
    }

    void Delete() {

        delete this.DrawQueue;
        if (this.client > 0) {
            g_DrawQueue[this.client] = null;
        }

        SDKUnhook(this.client, SDKHook_PostThinkPost, Hook_PostThinkPost);
    
        this.client = -1;

        this.flashPreviewEnabled = false;
        this.profileDisplayEnabled = false;

        this.activeTrajectory = -1;
        this.editTrajectory = -1;
        this.flashPreviewNextDraw = -1.0;
        this.profileDisplayNextDraw = -1.0;

        if (this.thinkTimer != INVALID_HANDLE) {
            delete this.thinkTimer;
            this.thinkTimer = INVALID_HANDLE;
        }

        if (this.hitTimer != INVALID_HANDLE) {
            delete this.hitTimer;
            this.hitTimer = INVALID_HANDLE;
        }

        for (int index = 0; this.trajectories && this.trajectories.Length > index; index++) {
            Trajectory eTrajectory;
            this.trajectories.GetArray(index, eTrajectory);

            eTrajectory.Delete();
        }

        delete this.trajectories;
        this.trajectories = null;

        delete this.trajectoryClusterTrie;
        this.trajectoryClusterTrie = null;
    }
}

AutoBoostPlayer TBPLAYERARRAY[MAXPLAYERS];

/*
// HOOKS
*/

public void Hook_PostThinkPost(int client) {
    TBPLAYER(client).Hit();

}

/*
// TIMERS
*/

public Action Timer_PlayerThink(Handle timer, int client) {

    if (TBPLAYER(client).activeTrajectory != -1 && TBPLAYER(client).canHit) {
        TBPLAYER(client).DrawTrajectory(TBPLAYER(client).activeTrajectory);
    }
    if (TBPLAYER(client).editTrajectory != -1) {
        TBPLAYER(client).DrawTrajectory(TBPLAYER(client).editTrajectory);
    }

    float engine_time;
    engine_time = GetEngineTime();

    if (TBPLAYER(client).profileDisplayEnabled ) {
        TBPLAYER(client).DrawTrajectories();
    }

    if (TBPLAYER(client).flashPreviewEnabled)
        ShowTrajectory(client, 0.2);

    return Plugin_Continue;
}

public Action Timer_PlayerHit(Handle timer, int client) {
    TBPLAYER(client).canHit = true;
    TBPLAYER(client).hitTimer = INVALID_HANDLE;

    return Plugin_Stop;
}

/*
// Main drawing function
*/

public void OnGameFrame_DrawQueue(int client) {    
    int index;
    int trail_color[4];
    float lifespan = 0.4;
    bool force = true;
    
    if (!g_DrawQueue[client] || g_DrawQueue[client].Empty) {
        g_needsDraw[client] = false;
        return;
    }

    index = g_DrawQueue[client].Pop();
    g_bInQueue[client][index] = false;
        
    if (index == TBPLAYER(client).editTrajectory) {
        trail_color = TBPLAYER(client).editTrailColor;
    } else if (index == TBPLAYER(client).activeTrajectory) {
        trail_color = TBPLAYER(client).activeTrailColor;
    } else {
        trail_color = TBPLAYER(client).trailColor;
        lifespan = TEMPENT_MAX_LIFETIME;
        force =  false;
    }

    TBPLAYER(client)._DrawTrajectory(index, TBPLAYER(client).trail, TBPLAYER(client).width, trail_color, lifespan);

    if (g_DrawQueue[client] && g_DrawQueue[client].Empty) {
        g_needsDraw[client] = false;
        return;
    }

    RequestFrame(OnGameFrame_DrawQueue, client);
}

/*
// FILTERS
*/

bool TraceFilter_FilterPlayer(int entity, int mask, int client) {
    if (entity <= MaxClients)
        return false;

    if (g_bMultiplayerSolidity) {
        if (Timer_GetPartner(client) == 0)
            client = 0;

        if (Trikz_IsEntityToggleable(entity))
            return Trikz_IsToggleableEnabledForPlayer(entity, client);
    }

    return true;
}

bool TraceFilter_FilterOtherPlayers(int entity, int mask, int client) {
    if (entity == client)
        return true;

    if (entity <= MaxClients)
        return false;

    if (g_bMultiplayerSolidity) {
        if (Timer_GetPartner(client) == 0)
            client = 0;

        if (Trikz_IsEntityToggleable(entity))
            return Trikz_IsToggleableEnabledForPlayer(entity, client);
    }

    return true;
}

/* 
// This is everything related to menus
*/

int OpenAutoBoostMenu(int client) {
    char text[512];
    Handle menu = CreateMenu(Menu_AutoBoosting, MENU_ACTIONS_DEFAULT);
    
    SetMenuTitle(menu, "AutoBoosting Menu\n \n");
    SetMenuPagination(menu, MENU_NO_PAGINATION);
    SetMenuExitButton(menu, true);
    
    Format(text, sizeof(text), "%s AutoBoost", TBPLAYER(client).enabled ? "Disable" : "Enable");
    AddMenuItem(menu, "enable_auto_boost", text);

    text = "Trajectory Menu";
    AddMenuItem(menu, "trajectorymenu", text);

    AddMenuItem(menu, "trajectorymenu", "", ITEMDRAW_SPACER);

    text = "Add current trajectory";
    AddMenuItem(menu, "addcurrenttrajectory", text);

    AddMenuItem(menu, "copyplayertrajectory", "Copy player's trajectories");

    AddMenuItem(menu, "trajectorymenu", "", ITEMDRAW_SPACER);

    text = "Show all trajectories";
    AddMenuItem(menu, "showalltrajectories", text);

    Format(text, sizeof(text), "%s Flash Preview", TBPLAYER(client).flashPreviewEnabled ? "Disable" : "Enable");
    AddMenuItem(menu, "flashpreview", text);

    AddMenuItem(menu, "flashexport", "Export");
    
    DisplayMenu(menu, client, MENU_TIME_FOREVER);
    return 0;
}

public int Menu_AutoBoosting(Handle menu, MenuAction action, int param1, int param2) {
    if (action == MenuAction_Select)
    {
        char info[32];
        GetMenuItem(menu, param2, info, sizeof(info));
        if (StrEqual(info, "enable_auto_boost", true))
        {
            TBPLAYER(param1).Toggle();
            OpenAutoBoostMenu(param1);
        }
        else if (StrEqual(info, "flashpreview", true))
        {
            bool preview_state = TBPLAYER(param1).ToggleFlashPreview();
            ColorPrintToChat(param1, "%s Flash Preview.", preview_state ? "Enabled" : "Disabled");
            OpenAutoBoostMenu(param1);
        }
        else if (StrEqual(info, "addcurrenttrajectory", true))
        {
            TBPLAYER(param1).NewTrajectory();
            OpenAutoBoostMenu(param1);
        }
        else if (StrEqual(info, "showalltrajectories", true))
        {
            bool profile_state = TBPLAYER(param1).ToggleProfileView();
            ColorPrintToChat(param1, "All trajectories are being %s.", profile_state ? "shown" : "hidden");
            OpenAutoBoostMenu(param1);
        }
        else if (StrEqual(info, "trajectorymenu", true))
        {
            if (TBPLAYER(param1).GetTrajectoryCount() < 1){
                ColorPrintToChat(param1, "You currently have no trajectories.");
                OpenAutoBoostMenu(param1);
            } else {
                OpenTrajectoryMenu(param1, 0);
            }
        }
        else if (StrEqual(info, "flashexport", true))
        {
            bool success;
            success = TBPLAYER(param1).ExportTrajectories(-1);

            if (success) {
                ColorPrintToChat(param1, "Output in console.");
            }
            OpenAutoBoostMenu(param1);
        }
        else if (StrEqual(info, "copyplayertrajectory", true))
        {
            
            OpenPlayerSelectMenu(param1);
        }
        
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }
    return 0;
}

int OpenPlayerSelectMenu(int client) {
    Handle menu = CreateMenu(Menu_PlayerSelectMenu, MENU_ACTIONS_DEFAULT);
    SetMenuTitle(menu, "Select A player\n \n");
    SetMenuExitButton(menu, true);

    char sDisplay[64];
    char sInfo[8];

    for (int i = 1; i <= MaxClients; i++)
	{
		if (i >= 1 && i <= MaxClients && IsClientInGame(i) && !IsClientSourceTV(i) && !IsFakeClient(i) && i != client)
		{
            GetClientName(i, sDisplay, sizeof(sDisplay));
            IntToString(i, sInfo, sizeof(sInfo));   
            AddMenuItem(menu, sInfo, sDisplay);
		}
	}

    if (GetMenuItemCount(menu) == 0)
	{
        ColorPrintToChat(client, "You are alone.");
        delete menu;
        OpenAutoBoostMenu(client);
        return 0;
    }
    
    DisplayMenu(menu, client, MENU_TIME_FOREVER);
    return 0;
}

public int Menu_PlayerSelectMenu(Handle menu, MenuAction action, int param1, int param2) {
    if (action == MenuAction_Select)
    {
        char info[32];

        GetMenuItem(menu, param2, info, sizeof(info));
        int target = StringToInt(info);

        if (target == param1) {
            ColorPrintToChat(param1, "Cannot target yourself.");
            OpenAutoBoostMenu(param1);
            return 0;
        }


        TBPLAYER(param1).CopyTrajectories(TBPLAYER(target).trajectories);
        
        OpenAutoBoostMenu(param1);
        
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }
    return 0;
}

int OpenTrajectoryMenu(int client, int trajectory_index) {
    Trajectory trajectory;
    char info[64];

    bool found = TBPLAYER(client).GetTrajectory(trajectory_index, trajectory);
    int trajectory_count = TBPLAYER(client).GetTrajectoryCount();

    if (!found) {
        ColorPrintToChat(client, "Invalid Trajectory Index.");
        TBPLAYER(client).editTrajectory = -1;
        return 0;
    }

    TBPLAYER(client).editTrajectory = trajectory_index;

    Handle menu = CreateMenu(Menu_Trajectory, MENU_ACTIONS_DEFAULT);
    SetMenuPagination(menu, MENU_NO_PAGINATION);

    Format(info, sizeof(info), "Trajectory %d", trajectory_index+1);
    SetMenuTitle(menu, info);


    AddMenuItem(menu, "trajectorymenu_active", "Set to active");

    AddMenuItem(menu, "trajectorymenu", "", ITEMDRAW_SPACER);

    Format(info, sizeof(info), "Modify speed: %d | %s", trajectory.iSpeed, trajectory.IsJumpThrow() ? "Jump" : "No Jump");
    AddMenuItem(menu, "trajectorymenu_modify_speed", info);

    Format(info, sizeof(info), "Modify position: %d | %s", trajectory.iAngle, trajectory.crouched ? "crouched" : "standing");
    AddMenuItem(menu, "trajectorymenu_modify_position", info);

    AddMenuItem(menu, "trajectorymenu_change_order", "Change order");

    AddMenuItem(menu, "trajectorymenu_delete", "Delete");

    AddMenuItem(menu, "trajectorymenu", "", ITEMDRAW_SPACER);
    
    AddMenuItem(menu, "trajectorymenu_prev", "prev", trajectory_index > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_SPACER);
    
    AddMenuItem(menu, "trajectorymenu_next", "next", trajectory_count-1 >  trajectory_index ? ITEMDRAW_DEFAULT : ITEMDRAW_SPACER);
    
    AddMenuItem(menu, "BackToAutoBoost", "Back to Autoboost Menu", ITEMDRAW_CONTROL);

    DisplayMenu(menu, client, MENU_TIME_FOREVER);
    return 0;
}

public int Menu_Trajectory(Handle menu, MenuAction action, int param1, int param2) {
    if (action == MenuAction_Select)
    {
        char info[32];
        GetMenuItem(menu, param2, info, sizeof(info));
        if (StrEqual(info, "BackToAutoBoost", true)) {
            TBPLAYER(param1).editTrajectory = -1;
            OpenAutoBoostMenu(param1);
        }
        else if (StrEqual(info, "trajectorymenu_active", true)) {
            TBPLAYER(param1).SetActiveTrajectory(TBPLAYER(param1).editTrajectory);
            OpenTrajectoryMenu(param1, TBPLAYER(param1).editTrajectory);
        }
        else if (StrEqual(info, "trajectorymenu_modify_speed", true)) {
            OpenTrajectorySpeedMenu(param1);
        }
        else if (StrEqual(info, "trajectorymenu_modify_position", true)) {
            OpenTrajectoryPositionMenu(param1);
        }
        else if (StrEqual(info, "trajectorymenu_change_order", true)) {
            OpenTrajectoryOrderingMenu(param1);
        }
        else if (StrEqual(info, "trajectorymenu_delete", true)) {
            TBPLAYER(param1).DeleteTrajectory(TBPLAYER(param1).editTrajectory);
            if (TBPLAYER(param1).editTrajectory >= TBPLAYER(param1).GetTrajectoryCount())
                TBPLAYER(param1).editTrajectory = TBPLAYER(param1).editTrajectory - 1;
            
            if (TBPLAYER(param1).editTrajectory >= 0)
                OpenTrajectoryMenu(param1, TBPLAYER(param1).editTrajectory);
            else
                OpenAutoBoostMenu(param1);
        }
        else if (StrEqual(info, "trajectorymenu_prev", true)) {
            OpenTrajectoryMenu(param1, TBPLAYER(param1).editTrajectory-1);
        }
        else if (StrEqual(info, "trajectorymenu_next", true)) {
            OpenTrajectoryMenu(param1, TBPLAYER(param1).editTrajectory+1);
        }
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }
    else if (action == MenuAction_Cancel)
    {
        TBPLAYER(param1).editTrajectory = -1;
    }
    return 0;
}

int OpenTrajectorySpeedMenu(int client) {
    Trajectory trajectory;
    char info[64];

    bool found = TBPLAYER(client).GetTrajectory(TBPLAYER(client).editTrajectory, trajectory);
    if (!found) {
        ColorPrintToChat(client, "Invalid Trajectory Index.");
        TBPLAYER(client).editTrajectory = -1;
        return 0;
    }


    Handle menu = CreateMenu(Menu_TrajectorySpeed, MENU_ACTIONS_DEFAULT);
    SetMenuExitButton(menu, true);

    Format(info, sizeof(info), "Trajectory %d", TBPLAYER(client).editTrajectory+1);
    SetMenuTitle(menu, info);

    Format(info, sizeof(info), "Speed: %d", trajectory.iSpeed);
    AddMenuItem(menu, "trajectorymenuordering_speed", info);

    Format(info, sizeof(info), "Throw type: %s", trajectory.IsJumpThrow() ? "Jump" : "No Jump");
    AddMenuItem(menu, "trajectorymenuordering_standing", info);

    Format(info, sizeof(info), "Delay: %f", trajectory.fWaitTime);
    AddMenuItem(menu, "trajectorymenuordering_delay", info);

    DisplayMenu(menu, client, MENU_TIME_FOREVER);
    return 0;
}

public int Menu_TrajectorySpeed(Handle menu, MenuAction action, int param1, int param2) {
    if (action == MenuAction_Select)
    {
        char info[64];
        GetMenuItem(menu, param2, info, sizeof(info));
        if (StrEqual(info, "trajectorymenuordering_speed", true)) {
            OpenTrajectorySpeedModification(param1);
        }
        else if (StrEqual(info, "trajectorymenuordering_standing", true)) {
            TBPLAYER(param1).ToggleTrajectoryThrow(TBPLAYER(param1).editTrajectory);
            OpenTrajectorySpeedMenu(param1);
        }
        else if (StrEqual(info, "trajectorymenuordering_delay", true)) {
            Trajectory trajectory;
            if (TBPLAYER(param1).GetTrajectory(TBPLAYER(param1).editTrajectory, trajectory)) {
                float delay = trajectory.fWaitTime + 0.5;
                if (delay > 10.0)
                    delay = 0.0;
                TBPLAYER(param1).SetTrajectoryDelay(TBPLAYER(param1).editTrajectory, delay);
            }
            OpenTrajectorySpeedMenu(param1);
        }
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }
    else if (action == MenuAction_Cancel)
    {
        if (param2 == MenuCancel_Exit){
             OpenTrajectoryMenu(param1, TBPLAYER(param1).editTrajectory);
        } else {
            TBPLAYER(param1).editTrajectory = -1;
        }
    }
    return 0;
}

int OpenTrajectorySpeedModification(int client) {
    Trajectory trajectory;  
    char info[64];

    bool found = TBPLAYER(client).GetTrajectory(TBPLAYER(client).editTrajectory, trajectory);
    if (!found) {
        ColorPrintToChat(client, "Invalid Trajectory Index.");
        TBPLAYER(client).editTrajectory = -1;
        return 0;
    }

    Handle menu = CreateMenu(Menu_TrajectorySpeedModification, MENU_ACTIONS_DEFAULT);
    SetMenuPagination(menu, MENU_NO_PAGINATION);
    SetMenuExitButton(menu, true);

    Format(info, sizeof(info), "Trajectory %d: speed %d", TBPLAYER(client).editTrajectory+1, trajectory.iSpeed);
    SetMenuTitle(menu, info);

    AddMenuItem(menu, "set_to_0", "Set to 0");
    AddMenuItem(menu, "set_to_90", "Set to 90");
    AddMenuItem(menu, "set_to_250", "Set to 250");
    AddMenuItem(menu, "trajectorymenu", "", ITEMDRAW_SPACER);
    AddMenuItem(menu, "increment_5", "Increment 5");
    AddMenuItem(menu, "increment_10", "Increment 10");
    AddMenuItem(menu, "trajectorymenu", "", ITEMDRAW_SPACER);
    AddMenuItem(menu, "decrement_5", "Decrement 5");
    AddMenuItem(menu, "decrement_10", "Decrement 10");


    DisplayMenu(menu, client, MENU_TIME_FOREVER);
    return 0;
}

public int Menu_TrajectorySpeedModification(Handle menu, MenuAction action, int param1, int param2) {
    if (action == MenuAction_Select)
    {
        char info[64];
        Trajectory trajectory;

        if (!TBPLAYER(param1).GetTrajectory(TBPLAYER(param1).editTrajectory, trajectory)) {
            CloseHandle(menu);
            TBPLAYER(param1).editTrajectory = -1;
        }

        int iSpeed = trajectory.iSpeed;
        GetMenuItem(menu, param2, info, sizeof(info));
        if (StrEqual(info, "set_to_0", true)) {
            iSpeed = 0;
        }
        else if (StrEqual(info, "set_to_90", true)) {
            iSpeed = 90;            
        }
        else if (StrEqual(info, "set_to_250", true)) {
            iSpeed = 250; 
        }
        else if (StrEqual(info, "increment_5", true)) {
           iSpeed = trajectory.iSpeed + 5;
        }
        else if (StrEqual(info, "increment_10", true)) {
           iSpeed = trajectory.iSpeed + 10;
        }
        else if (StrEqual(info, "decrement_5", true)) {
            iSpeed = trajectory.iSpeed - 5;
        }
        else if (StrEqual(info, "decrement_10", true)) {
            iSpeed = trajectory.iSpeed - 10;
        }
        TBPLAYER(param1).SetTrajectorySpeed(TBPLAYER(param1).editTrajectory, iSpeed);
        OpenTrajectorySpeedModification(param1);
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }
    else if (action == MenuAction_Cancel)
    {
        if (param2 == MenuCancel_Exit){
            OpenTrajectorySpeedMenu(param1);
        } else {
            TBPLAYER(param1).editTrajectory = -1;
        }
    }
    return 0;
}

int OpenTrajectoryPositionMenu(int client) {
    Trajectory trajectory;  
    char info[64];

    bool found = TBPLAYER(client).GetTrajectory(TBPLAYER(client).editTrajectory, trajectory);
    if (!found) {
        ColorPrintToChat(client, "Invalid Trajectory Index.");
        TBPLAYER(client).editTrajectory = -1;
        return 0;
    }




    Handle menu = CreateMenu(Menu_TrajectoryPosition, MENU_ACTIONS_DEFAULT);
    SetMenuExitButton(menu, true);

    Format(info, sizeof(info), "Trajectory %d", TBPLAYER(client).editTrajectory+1);
    SetMenuTitle(menu, info);

    Format(info, sizeof(info), "Height: %s", trajectory.crouched ? "Crouched" : "Standing");
    AddMenuItem(menu, "trajectorymenuordering_height", info);

    Format(info, sizeof(info), "Angle: %d", trajectory.iAngle);
    AddMenuItem(menu, "trajectorymenuordering_angle", info);

    AddMenuItem(menu, "trajectorymenuordering_lifespan", "Modify lifespan");

    AddMenuItem(menu, "trajectorymenuordering_snap", "Snap to current position");

    DisplayMenu(menu, client, MENU_TIME_FOREVER);
    return 0;
}

public int Menu_TrajectoryPosition(Handle menu, MenuAction action, int param1, int param2) {
    if (action == MenuAction_Select)
    {
        char info[64];
        GetMenuItem(menu, param2, info, sizeof(info));
        if (StrEqual(info, "trajectorymenuordering_height", true)) {
            Trajectory trajectory;

            if (TBPLAYER(param1).GetTrajectory(TBPLAYER(param1).editTrajectory, trajectory)) {
                TBPLAYER(param1).ToggleTrajectoryCrouch(TBPLAYER(param1).editTrajectory);
                if (trajectory.crouched && trajectory.iSpeed > 90) {
                    TBPLAYER(param1).SetTrajectorySpeed(TBPLAYER(param1).editTrajectory, 90);
                } else if (!trajectory.crouched && trajectory.iSpeed == 90){
                    TBPLAYER(param1).SetTrajectorySpeed(TBPLAYER(param1).editTrajectory, 250);
                }
            }
            OpenTrajectoryPositionMenu(param1);
        }
        else if (StrEqual(info, "trajectorymenuordering_angle", true)) {
            OpenTrajectoryPositionAngleMenu(param1);
        }
        else if (StrEqual(info, "trajectorymenuordering_lifespan", true)) {
            OpenTrajectoryPositionLifespanMenu(param1);
        }
        else if (StrEqual(info, "trajectorymenuordering_snap", true)) {
            TBPLAYER(param1).ChangeTrajectoryPosition(TBPLAYER(param1).editTrajectory);
            OpenTrajectoryPositionMenu(param1);
        }
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }
    else if (action == MenuAction_Cancel)
    {
        if (param2 == MenuCancel_Exit){
             OpenTrajectoryMenu(param1, TBPLAYER(param1).editTrajectory);
        } else {
            TBPLAYER(param1).editTrajectory = -1;
        }
    }
    return 0;
}

int OpenTrajectoryPositionAngleMenu(int client) {
    Trajectory trajectory;  
    char info[64];

    bool found = TBPLAYER(client).GetTrajectory(TBPLAYER(client).editTrajectory, trajectory);
    if (!found) {
        ColorPrintToChat(client, "Invalid Trajectory Index.");
        TBPLAYER(client).editTrajectory = -1;
        return 0;
    }

    Handle menu = CreateMenu(Menu_TrajectoryPositionAngle, MENU_ACTIONS_DEFAULT);
    SetMenuExitButton(menu, true);

    Format(info, sizeof(info), "Trajectory %d: Angle %d", TBPLAYER(client).editTrajectory+1, trajectory.iAngle);
    SetMenuTitle(menu, info);

    AddMenuItem(menu, "trajectorymenuordering_increment_1", "Increment 1");
    AddMenuItem(menu, "trajectorymenuordering_increment_5", "Increment 5");
    AddMenuItem(menu, "trajectorymenuordering_increment_10", "Increment 10");
    AddMenuItem(menu, "trajectorymenu", "", ITEMDRAW_SPACER);
    AddMenuItem(menu, "trajectorymenuordering_decrement_1", "Decrement 1");
    AddMenuItem(menu, "trajectorymenuordering_decrement_5", "Decrement 5");
    AddMenuItem(menu, "trajectorymenuordering_decrement_10", "Decrement 10");

    DisplayMenu(menu, client, MENU_TIME_FOREVER);
    return 0;
}

public int Menu_TrajectoryPositionAngle(Handle menu, MenuAction action, int param1, int param2) {
    if (action == MenuAction_Select)
    {
        char info[64];
        Trajectory trajectory;

        if (!TBPLAYER(param1).GetTrajectory(TBPLAYER(param1).editTrajectory, trajectory)) {
            CloseHandle(menu);
            TBPLAYER(param1).editTrajectory = -1;
        }

        int iAngle = trajectory.iAngle;
        GetMenuItem(menu, param2, info, sizeof(info));
        if (StrEqual(info, "trajectorymenuordering_increment_1", true)) {
            iAngle = trajectory.iAngle + 1;
        }
        else if (StrEqual(info, "trajectorymenuordering_increment_5", true)) {
            iAngle = trajectory.iAngle + 5;            
        }
        else if (StrEqual(info, "trajectorymenuordering_increment_10", true)) {
            iAngle = trajectory.iAngle + 10;
        }
        else if (StrEqual(info, "trajectorymenuordering_decrement_1", true)) {
           iAngle = trajectory.iAngle - 1;
        }
        else if (StrEqual(info, "trajectorymenuordering_decrement_5", true)) {
            iAngle = trajectory.iAngle - 5;
        }
        else if (StrEqual(info, "trajectorymenuordering_decrement_10", true)) {
            iAngle = trajectory.iAngle - 10;
        }
        if (iAngle > 90)
            iAngle = 90;
        else if (iAngle < -90)
            iAngle = -90;
        TBPLAYER(param1).SetTrajectoryAngle(TBPLAYER(param1).editTrajectory, iAngle);
        OpenTrajectoryPositionAngleMenu(param1);
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }
    else if (action == MenuAction_Cancel)
    {
        if (param2 == MenuCancel_Exit){
             OpenTrajectoryPositionMenu(param1);
        } else {
            TBPLAYER(param1).editTrajectory = -1;
        }
    }
    return 0;
}

int OpenTrajectoryPositionLifespanMenu(int client) {
    Trajectory trajectory;  
    char info[64];

    bool found = TBPLAYER(client).GetTrajectory(TBPLAYER(client).editTrajectory, trajectory);
    if (!found) {
        ColorPrintToChat(client, "Invalid Trajectory Index.");
        TBPLAYER(client).editTrajectory = -1;
        return 0;
    }




    Handle menu = CreateMenu(Menu_TrajectoryPositionLifespan, MENU_ACTIONS_DEFAULT);
    SetMenuExitButton(menu, true);

    Format(info, sizeof(info), "Trajectory %d", TBPLAYER(client).editTrajectory+1);
    SetMenuTitle(menu, info);

    Format(info, sizeof(info), "Start Time %f", trajectory.startTime);
    AddMenuItem(menu, "trajectorymenuordering_increment_info", info, ITEMDRAW_DISABLED);
    
    AddMenuItem(menu, "trajectorymenuordering_increment_start", "Increment Start Time");
    AddMenuItem(menu, "trajectorymenuordering_decrement_start", "Decrement Start Time");
    
    AddMenuItem(menu, "trajectorymenu", "", ITEMDRAW_SPACER);

    Format(info, sizeof(info), "Start Time %f", trajectory.endTime);  
    AddMenuItem(menu, "trajectorymenuordering_increment_info", info, ITEMDRAW_DISABLED);
    
    AddMenuItem(menu, "trajectorymenuordering_increment_end", "Increment End Time");
    AddMenuItem(menu, "trajectorymenuordering_decrement_end", "Decrement End Time");

    DisplayMenu(menu, client, MENU_TIME_FOREVER);
    return 0;
}

public int Menu_TrajectoryPositionLifespan(Handle menu, MenuAction action, int param1, int param2) {
    if (action == MenuAction_Select)
    {
        char info[64];
        Trajectory trajectory;

        if (!TBPLAYER(param1).GetTrajectory(TBPLAYER(param1).editTrajectory, trajectory)) {
            CloseHandle(menu);
            TBPLAYER(param1).editTrajectory = -1;
        }

        float startTime = trajectory.startTime;
        float endTime = trajectory.endTime;

        GetMenuItem(menu, param2, info, sizeof(info));
        if (StrEqual(info, "trajectorymenuordering_increment_start", true)) {
            startTime = startTime + TBPLAYER(param1).timeStep;
        }
        else if (StrEqual(info, "trajectorymenuordering_decrement_start", true)) {
            startTime = startTime - TBPLAYER(param1).timeStep;           
        }
        else if (StrEqual(info, "trajectorymenuordering_increment_end", true)) {
            endTime = endTime + TBPLAYER(param1).timeStep;
        }
        else if (StrEqual(info, "trajectorymenuordering_decrement_end", true)) {
           endTime = endTime - TBPLAYER(param1).timeStep;
        }
        TBPLAYER(param1).SetTrajectoryLifespan(TBPLAYER(param1).editTrajectory, startTime, endTime);
        OpenTrajectoryPositionLifespanMenu(param1);
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }
    else if (action == MenuAction_Cancel)
    {
        if (param2 == MenuCancel_Exit){
             OpenTrajectoryPositionMenu(param1);
        } else {
            TBPLAYER(param1).editTrajectory = -1;
        }
    }
    return 0;
}

int OpenTrajectoryOrderingMenu(int client) {
    char info[64];
    int trajectory_count = TBPLAYER(client).GetTrajectoryCount();

    Handle menu = CreateMenu(Menu_TrajectoryOrdering, MENU_ACTIONS_DEFAULT);
    SetMenuExitButton(menu, true);

    Format(info, sizeof(info), "Trajectory %d", TBPLAYER(client).editTrajectory+1);
    SetMenuTitle(menu, info);


    AddMenuItem(menu, "trajectorymenuordering_move_up", "Move UP", TBPLAYER(client).editTrajectory >= trajectory_count-1 ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);

    AddMenuItem(menu, "trajectorymenuordering_move_down", "Move Down", TBPLAYER(client).editTrajectory < 1 ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);

    DisplayMenu(menu, client, MENU_TIME_FOREVER);
    return 0;
}

public int Menu_TrajectoryOrdering(Handle menu, MenuAction action, int param1, int param2) {
    if (action == MenuAction_Select)
    {
        char info[64];
        GetMenuItem(menu, param2, info, sizeof(info));
        if (StrEqual(info, "trajectorymenuordering_move_up", true)) {
            bool success = TBPLAYER(param1).OrderTrajectory(TBPLAYER(param1).editTrajectory, TBPLAYER(param1).editTrajectory+1);
            if (success)
                TBPLAYER(param1).editTrajectory = TBPLAYER(param1).editTrajectory + 1;
            OpenTrajectoryOrderingMenu(param1);
        }
        else if (StrEqual(info, "trajectorymenuordering_move_down", true)) {
            bool success = TBPLAYER(param1).OrderTrajectory(TBPLAYER(param1).editTrajectory, TBPLAYER(param1).editTrajectory-1);
            if (success)
                TBPLAYER(param1).editTrajectory = TBPLAYER(param1).editTrajectory - 1;
            OpenTrajectoryOrderingMenu(param1);
        }
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu);
    }
    else if (action == MenuAction_Cancel)
    {
        if (param2 == MenuCancel_Exit){
             OpenTrajectoryMenu(param1, TBPLAYER(param1).editTrajectory);
        } else {
            TBPLAYER(param1).editTrajectory = -1;
        }
    }
    return 0;
}

/*
// MENU END
*/

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    g_bLateLoaded = late;

    RegPluginLibrary("trikz_autoboost");
    MarkNativeAsOptional("Timer_GetPartner");
    MarkNativeAsOptional("Trikz_IsEntityToggleable");
    MarkNativeAsOptional("Trikz_IsToggleableEnabledForPlayer");

    CreateNative("TrikzAutoBoost_GetActivePlayertrajectory", Native_GetActivePlayertrajectory);
    CreateNative("TrikzAutoBoost_SetActivePlayertrajectory", Native_SetActivePlayertrajectory);

    return APLRes_Success;
}

public void OnPluginStart() {
    g_Game = GetEngineVersion();
    if(g_Game != Engine_CSGO && g_Game != Engine_CSS)
    {
        SetFailState("This plugin is for CSGO/CSS only.");
    }
    
    sv_gravity = FindConVar("sv_gravity");
    sm_gtrajectory = CreateConVar("sm_gtrajectory", "1.0", "Enable/Disable", FCVAR_NOTIFY | FCVAR_DONTRECORD, true, 0.0, true, 1.0);
    sm_gtrajectory_admin = CreateConVar("sm_gtrajectory", "0.0", "Enable/disable grenade prediction for admin only", FCVAR_NOTIFY | FCVAR_DONTRECORD, true, 0.0, true, 1.0);
    sm_gtrajectory_size = CreateConVar("sm_gtrajectory_size", "0.5", "Thickness of predicted trail", FCVAR_NOTIFY | FCVAR_DONTRECORD, true, 0.1, true, 10.0);
    sm_gtrajectory_timestep = CreateConVar("sm_gtrajectory_timestep", "0.05", "Time step for the loop, smaller = better accuracy", FCVAR_NOTIFY | FCVAR_DONTRECORD, true, 0.001, true, 0.5);
    sm_gtrajectory_delay= CreateConVar("sm_gtrajectory_delay", "0.0", "Delay set with other plugins", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    sm_gtrajectory_throw= CreateConVar("sm_gtrajectory_throw", "0.9", "Grenade throwing speed adjustment: IN_ATTACK", FCVAR_NOTIFY | FCVAR_DONTRECORD, true, 0.0, true, 1.0);
    sm_gtrajectory_lob= CreateConVar("sm_gtrajectory_lob", "0.6", "Grenade throwing speed adjustment: IN_ATTACK + IN_ATTACK2", FCVAR_NOTIFY | FCVAR_DONTRECORD, true, 0.0, true, 1.0);
    sm_gtrajectory_roll= CreateConVar("sm_gtrajectory_roll", "0.27", "Grenade throwing speed adjustment: IN_ATTACK2", FCVAR_NOTIFY | FCVAR_DONTRECORD, true, 0.0, true, 1.0);

    RegConsoleCmd("sm_autoboost", SM_AutoBoost, "Opens the boosting menu.");
    RegConsoleCmd("sm_savetraj", SM_SaveTrajectory, "Creates a trajectory.");
    RegConsoleCmd("sm_exporttraj", SM_ExportTrajectory, "Export a trajectory or all trajectories.");
    RegConsoleCmd("sm_copytraj", SM_CopyTrajectory, "Copy a player's trajectory.");

    Handle hGameData = LoadGameConfigFile("trikz-autoboost.games");
    if (!hGameData)
        SetFailState("Failed to load trikz-autoboost gamedata.");

    if(g_Game == Engine_CSS)
		BytePatchTELimit(hGameData);

    g_bMultiplayerSolidity = CheckMultiplayerSolidity();
}

public void OnPluginEnd() {
	if(gTELimitAddress == Address_Null)
		return;
	
	for(int i = 0; i < gTELimitDataSize; i++)
		StoreToAddress(gTELimitAddress, gTELimitData[i], NumberType_Int8);
}

public void OnMapStart() {
    bool success;
    
    g_Trail = PrecacheModel("sprites/laserbeam.spr");
    success = PrecacheSound("weapons/flashbang/grenade_hit1.wav", false);

    if (g_bLateLoaded)
        ResetBoostPlayers();
}

public void OnClientPutInServer(int client) {
    if(!IsFakeClient(client) && IsClientInGame(client))
    {
        float width = GetConVarFloat(sm_gtrajectory_size);
        float factor = GetConVarFloat(sm_gtrajectory_throw);
        float disp = 0.0;
        float fGravity = float(sv_gravity.IntValue);
        float fTimeStep = sm_gtrajectory_timestep.FloatValue;

        TBPLAYER(client).New(client, g_Trail, width, disp, factor, fGravity, fTimeStep, 0.5);
    }
}

void OnNotifyPluginUnloaded(Handle plugin) {
    g_bMultiplayerSolidity = CheckMultiplayerSolidity();
}

public void OnClientDisconnect(int client) {
    if(!IsFakeClient(client))
    {
        TBPLAYER(client).Delete();
    }
}

stock void BytePatchTELimit(Handle gconf) {
	//TELimit
    gTELimitAddress = GameConfGetAddress(gconf, "TELimit");
    gTELimitDataSize = GameConfGetOffset(gconf, "TELimitSize");

    if (gTELimitAddress == Address_Null || gTELimitDataSize == 0) {
        PrintToServer("TELimit BytePatch failed. Some trajectories might not display properly");
        return;
    }

    for(int i = 0; i < gTELimitDataSize; i++)
		gTELimitData[i] = LoadFromAddress(view_as<Address>(gTELimitAddress + i), NumberType_Int8);
	
    StoreToAddress(gTELimitAddress, 0x90909090, NumberType_Int32);
}

bool CheckMultiplayerSolidity() {
    return (GetFeatureStatus( FeatureType_Native, "Timer_GetPartner" ) == FeatureStatus_Available &&
            GetFeatureStatus( FeatureType_Native, "Trikz_IsEntityToggleable" ) == FeatureStatus_Available &&
            GetFeatureStatus( FeatureType_Native, "Trikz_IsToggleableEnabledForPlayer" ) == FeatureStatus_Available
    );
}

/*
// UTILS
*/

stock void ShowTrajectory(int iClient, float fLifespan) {
    float fVelocity[3];
    if (g_BoostPlayers[iClient].velocityMatchPlayer)
        GetEntPropVector(iClient, Prop_Data, "m_vecAbsVelocity", fVelocity);

    float dtime = GetDetonationTime("weapon_flashbang");
            
    float GrenadeVelocity[3], PlayerVelocity[3], ThrowAngle[3], ThrowVector[3], ThrowVelocity;
    float gStart[3], gEnd[3], fwd[3], right[3], up[3];
    
    GetClientEyeAngles(iClient, ThrowAngle);
    ThrowAngle[0] = -10.0 + ThrowAngle[0] + FloatAbs(ThrowAngle[0]) * 10.0 / 90.0;
    
    GetAngleVectors(ThrowAngle, fwd, right, up);
    NormalizeVector(fwd, ThrowVector);
    
    GetClientEyePosition(iClient, gStart);
    for (int i = 0; i < 3; i++)
        gStart[i] += ThrowVector[i] * 16.0;
    
    gStart[2] += g_BoostPlayers[iClient].disp;
    
    PlayerVelocity = fVelocity;
    
    switch (g_Game)
    {
        case Engine_CSS:
        {
            ThrowVelocity = (90.0 - ThrowAngle[0]) * 6.0;
            if (ThrowVelocity > 750.0)
                ThrowVelocity = 750.0;
        }
        
        case Engine_CSGO:
        {
            ThrowVelocity = 750.0 * g_BoostPlayers[iClient].factor;
            ScaleVector(PlayerVelocity, 1.25);
        }
    }
    
    for (int i = 0; i < 3; i++)
        GrenadeVelocity[i] = ThrowVector[i] * ThrowVelocity + PlayerVelocity[i];
    
    float dt = g_BoostPlayers[iClient].timeStep;
    for (float t = 0.0; t <= dtime; t += dt)
    {
        gEnd[0] = gStart[0] + GrenadeVelocity[0] * dt;
        gEnd[1] = gStart[1] + GrenadeVelocity[1] * dt;
        
        float gForce = 0.4 * g_BoostPlayers[iClient].gravity;
        float NewVelocity = GrenadeVelocity[2] - gForce * dt;
        float AvgVelocity = (GrenadeVelocity[2] + NewVelocity) / 2.0;
        
        gEnd[2] = gStart[2] + AvgVelocity * dt;
        GrenadeVelocity[2] = NewVelocity;
        
        float mins[3] = {-2.0, -2.0, -2.0}, maxs[3] = {2.0, 2.0, 2.0};
        Handle gRayTrace = TR_TraceHullFilterEx(gStart, gEnd, mins, maxs, MASK_SHOT_HULL, TraceFilter_FilterPlayer, iClient);
        if (TR_GetFraction(gRayTrace) != 1.0) 
        {
            if (TR_GetEntityIndex(gRayTrace) == iClient && t == 0.0)
            {
                CloseHandle(gRayTrace);
                gStart = gEnd;
                continue;
            }
            
            TR_GetEndPosition(gEnd, gRayTrace);
            
            float NVector[3];
            TR_GetPlaneNormal(gRayTrace, NVector);
            float Impulse = 2.0 * GetVectorDotProduct(NVector, GrenadeVelocity);
            for (int i = 0; i < 3; i++)
            {
                GrenadeVelocity[i] -= Impulse * NVector[i];
                
                if (FloatAbs(GrenadeVelocity[i]) < 0.1)
                    GrenadeVelocity[i] = 0.0;
            }
            
            float SurfaceElasticity = GetEntPropFloat(TR_GetEntityIndex(gRayTrace), Prop_Send, "m_flElasticity");
            float elasticity = 0.45 * SurfaceElasticity;
            ScaleVector(GrenadeVelocity, elasticity);
        }
        CloseHandle(gRayTrace);
        
        TE_SetupBeamPoints(gStart, gEnd, g_BoostPlayers[iClient].trail, 0, 0, 0, fLifespan, g_BoostPlayers[iClient].width, g_BoostPlayers[iClient].width, 0, 0.0, g_BoostPlayers[iClient].trailColor, 0);
        TE_SendToClient(iClient, 0.0);
        
        gStart = gEnd;
    }
}

stock float GetDetonationTime(const char[] weapon) {
    ConVar fDelay = FindConVar("sm_gtrajectory_delay");
    float dtime;

    if (StrContains("weapon_hegrenade weapon_flashbang", weapon, false) != -1)
        dtime = 1.5 + GetConVarFloat(fDelay);
    else
        dtime = 3.0 + GetConVarFloat(fDelay);

    return dtime;
}

public void ResetBoostPlayers() {
    for (int i=1; i < MaxClients; i++) {
        g_BoostPlayers[i].Delete();
        if (IsClientInGame(i) && (!IsFakeClient(i))) {
            float width = GetConVarFloat(sm_gtrajectory_size);
            float factor = GetConVarFloat(sm_gtrajectory_throw);
            float disp = 0.0;
            float fGravity = float(sv_gravity.IntValue);
            float fTimeStep = sm_gtrajectory_timestep.FloatValue;
            g_BoostPlayers[i].New(i, g_Trail, width, disp, factor, fGravity, fTimeStep, 0.5);
        }
      }
}

int GetClientAndSpectators(int client, int[] clients, int size) {

    int counter;

    clients[counter++] = client;
    for (int spectator = 1; spectator <= MaxClients; spectator++)
    {
        if (counter >= size)
            return counter;

        if (IsClientInGame(spectator))
        {
            int iSpecMode = GetEntProp(spectator, Prop_Send, "m_iObserverMode");
            if (iSpecMode == SPECMODE_FIRSTPERSON || iSpecMode == SPECMODE_3RDPERSON) {
	            int iTarget = GetEntPropEnt(spectator, Prop_Send, "m_hObserverTarget");
	            if (iTarget == client) {
                    clients[counter++] = spectator;
                }
            }  
        }
    }
    return counter;
}

/*
// Console Commands
*/

public Action SM_AutoBoost(int client, int args) {
    if(client == 0)
	{
		ReplyToCommand(client, "This command may be only performed in-game.");

		return Plugin_Handled;
	}

    if(AreClientCookiesCached(client))
    {
        OpenAutoBoostMenu(client);
    }
    return Plugin_Continue;
}

public Action SM_CreateTrajectory(int client, int args) {
    if(client == 0)
	{
		ReplyToCommand(client, "This command may be only performed in-game.");

		return Plugin_Handled;
	}

    if (args == 0) {
        ColorPrintToChat(client, "Usage: sm_createtrajectory <data> [index]");
        return Plugin_Handled;
    }

    if (!TBPLAYER(client).enabled) {
        ColorPrintToChat(client, "AutoBoost is disabled.");
        return Plugin_Handled;
    }

    int trajectory_index = -1;

    char data[512];
    GetCmdArg(1, data, sizeof(data));

    if (args >= 2) {
        char data2[8];
        GetCmdArg(2, data2, sizeof(data2));
        trajectory_index = StringToInt(data2);
    }

    return Plugin_Handled;
}

public Action SM_SaveTrajectory(int client, int args) {
    if (client == 0)
	{
		ReplyToCommand(client, "This command may be only performed in-game.");

		return Plugin_Handled;
	}
    
    if (!TBPLAYER(client).enabled) {
        ColorPrintToChat(client, "AutoBoost is disabled.");
        return Plugin_Handled;
    }

    if (args == 0) {
        TBPLAYER(client).NewTrajectory();
        return Plugin_Handled;
    }

    int trajectory_index = 0;

    char data[MAX_BUFFER_LENGTH];
    GetCmdArg(1, data, sizeof(data));

    if (args >= 2) {
        char data2[8];
        GetCmdArg(2, data2, sizeof(data2));
        trajectory_index = StringToInt(data2);
    }

    if (trajectory_index < 0 || trajectory_index-1 > TBPLAYER(client).GetTrajectoryCount()) {
        ColorPrintToChat(client, "Cannot import trajectory at invalid index.");
        return Plugin_Handled;
    }

    bool success = TBPLAYER(client).ImportTrajectory(trajectory_index-1, data);
    if (success) {
        ColorPrintToChat(client, "Trajectory #%d imported successfully.", (trajectory_index == 0) ? TBPLAYER(client).GetTrajectoryCount() : trajectory_index);
    } else {
        ColorPrintToChat(client, "Error occured while importing.");
    }

    return Plugin_Handled;
}

public Action SM_ExportTrajectory(int client, int args) {
    if (client == 0)
	{
		ReplyToCommand(client, "This command may be only performed in-game.");
		return Plugin_Handled;
	}

    if (TBPLAYER(client).GetTrajectoryCount() == 0) {
        ColorPrintToChat(client, "There is nothing to export.");
        return Plugin_Handled;
    }

    int trajectory_index = 0;
    if (args >= 1) {
        char data2[8];
        GetCmdArg(1, data2, sizeof(data2));
        trajectory_index = StringToInt(data2);
    }

    if (trajectory_index < 0 || trajectory_index-1 >= TBPLAYER(client).GetTrajectoryCount()) {
        ColorPrintToChat(client, "Cannot export trajectory at invalid index.");
        return Plugin_Handled;
    }

    bool success;
    success = TBPLAYER(client).ExportTrajectories(trajectory_index-1);

    if (success) {
        ColorPrintToChat(client, "Output in console.");
    } else {
        ColorPrintToChat(client, "Problem occured during exporting.");
    }

    return Plugin_Handled;
}

public Action SM_CopyTrajectory(int client, int args) {
    if (client == 0)
	{
		ReplyToCommand(client, "This command may be only performed in-game.");
		return Plugin_Handled;
	}
    if (args < 1) {
        ColorPrintToChat(client, "Usage: <client>");
        return Plugin_Handled;
    }
    
    char data2[MAX_BUFFER_LENGTH];
    GetCmdArg(1, data2, sizeof(data2));
    int target = FindTarget(client, data2, true, false);

    if (target == -1) {
        ColorPrintToChat(client, "No matching target found.");
        return Plugin_Handled;
    }

    if (target == client) {
        ColorPrintToChat(client, "Cannot target yourself.");
        return Plugin_Handled;
    }

    TBPLAYER(client).CopyTrajectories(TBPLAYER(target).trajectories);

    return Plugin_Handled;
}

//

stock void ColorPrintToChat(int client, const char[] message, any ...) {
    char buffer[MAX_BUFFER_LENGTH], buffer2[MAX_BUFFER_LENGTH];

    SetGlobalTransTarget(client);

    Format(buffer, sizeof(buffer), "\x01{default}[{red}AutoBoost{default}] {white}%s", message);

    VFormat(buffer2, sizeof(buffer2), buffer, 3);
    CPrintToChat(client, buffer2);
}

/*
// NATIVES
*/

public int Native_GetActivePlayertrajectory(Handle plugin, int numParams) {
    int client = GetNativeCell(1);

    
    return TBPLAYER(client).activeTrajectory;
    
}

public int Native_SetActivePlayertrajectory(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    int index = GetNativeCell(2);


    TBPLAYER(client).SetActiveTrajectory(index);
    return index;
}