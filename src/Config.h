#pragma once
// Persistent settings (NSUserDefaults inside the app sandbox, keys prefixed "lf2mod.").

namespace Config {
bool  enabled(const char* key);
void  setEnabled(const char* key, bool on);
float number(const char* key, float def);
void  setNumber(const char* key, float v);
int   integer(const char* key, int def);
void  setInteger(const char* key, int v);
}

// Feature keys — shared by the hook table and the menu.
namespace Feat {
static const char* SPEED          = "speed";           // Time.timeScale override
static const char* SPEED_VALUE    = "speed.value";
static const char* AUTOCATCH      = "autocatch";       // reel minigame always succeeds
static const char* INSTANT_BITE   = "instantbite";     // bite wait timer = 0
static const char* NO_TENSION     = "notension";       // line never snaps
static const char* NO_ESCAPE      = "noescape";        // fish never escapes
static const char* SKIP_ANIM      = "skipanim";        // Animator speed multiplier
static const char* SKIP_ANIM_MULT = "skipanim.mult";
static const char* UNLOCK_LOC     = "unlocklocations"; // location lock check (client-side view)
static const char* NO_ADS         = "noads";           // interstitial ads suppressed
static const char* COSMETICS      = "cosmetics";       // skins/lures appear owned (visual only)
static const char* FISH_ESP       = "fishesp";         // show fish species/weight on bite
static const char* RNG_LOG        = "rnglog";          // log UnityEngine.Random.Range calls
static const char* RNG_MODE       = "rng.mode";        // 0 = passthrough, 1 = min, 2 = max
static const char* BOT            = "bot";             // auto-cast + auto-reel loop
static const char* BOT_INTERVAL   = "bot.interval";    // seconds between bot actions
static const char* MENU_VISIBLE   = "menu.visible";
}
