#pragma once
// ============================================================================
//  GAME-SPECIFIC HOOK TABLE
//
//  Every entry is resolved BY NAME at runtime through the il2cpp API, so you
//  never need offsets. The namespace/class/method strings below are educated
//  guesses for a Unity fishing game and MUST be verified against dump.cs
//  (Il2CppDumper output for this exact build). Run:
//
//      python3 tools/find_targets.py path/to/dump.cs
//
//  and paste the suggested lines here. Unresolved entries are harmless: they
//  show up as "unresolved" in the in-game menu's Status tab and are skipped.
//
//  Kinds:
//    HK_RETURN_TRUE   bool method -> true          (when feature enabled)
//    HK_RETURN_FALSE  bool method -> false
//    HK_RETURN_ZERO   int/long method -> 0
//    HK_RETURN_ZERO_F float/double method -> 0
//    HK_NOP           void method -> skipped
//    HK_CAPTURE_THIS  always calls original; remembers `this` under the feature key
//    HK_RESOLVE_ONLY  not hooked; just looked up so it can be invoked (bot / dev menu)
// ============================================================================
#include "Config.h"

enum HookKind {
    HK_RETURN_TRUE,
    HK_RETURN_FALSE,
    HK_RETURN_ZERO,
    HK_RETURN_ZERO_F,
    HK_NOP,
    HK_CAPTURE_THIS,
    HK_RESOLVE_ONLY,
};

struct HookTarget {
    const char* feature;   // Feat::* key (or "<feature>.<role>" for capture/resolve entries)
    const char* ns;        // IL namespace ("" for global)
    const char* klass;     // class name, "Outer/Inner" for nested
    const char* method;    // method name
    int         argc;      // parameter count (excluding `this`)
    HookKind    kind;
};

// Capture / resolve roles used by Hooks.mm.
#define ROLE_BOT_CONTROLLER "bot.controller"   // CAPTURE_THIS on the fishing controller
#define ROLE_BOT_CAST       "bot.cast"         // RESOLVE_ONLY: instance method on that controller
#define ROLE_BOT_REEL       "bot.reel"         // RESOLVE_ONLY: instance method on that controller
#define ROLE_FISH_CAPTURE   "fishesp.capture"  // CAPTURE_THIS on the fish/bite object

static const HookTarget kTargets[] = {
    // --- Fishing mechanics -------------------------------------------------- TODO: verify names
    { Feat::AUTOCATCH,    "LetsFish.Fishing", "ReelMinigame",     "IsSuccessful",   0, HK_RETURN_TRUE  },
    { Feat::AUTOCATCH,    "LetsFish.Fishing", "CatchResolver",    "CanFishBeLost",  0, HK_RETURN_FALSE },
    { Feat::INSTANT_BITE, "LetsFish.Fishing", "BiteController",   "GetWaitTime",    0, HK_RETURN_ZERO_F},
    { Feat::NO_TENSION,   "LetsFish.Fishing", "LineTension",      "ShouldBreak",    0, HK_RETURN_FALSE },
    { Feat::NO_TENSION,   "LetsFish.Fishing", "LineTension",      "ApplyDamage",    1, HK_NOP          },
    { Feat::NO_ESCAPE,    "LetsFish.Fishing", "FishBehaviour",    "TryEscape",      0, HK_RETURN_FALSE },

    // --- Bot (auto-cast + auto-reel) ---------------------------------------- TODO: verify names
    { ROLE_BOT_CONTROLLER,"LetsFish.Fishing", "FishingController","Update",         0, HK_CAPTURE_THIS },
    { ROLE_BOT_CAST,      "LetsFish.Fishing", "FishingController","Cast",           0, HK_RESOLVE_ONLY },
    { ROLE_BOT_REEL,      "LetsFish.Fishing", "FishingController","Reel",           0, HK_RESOLVE_ONLY },

    // --- Fish ESP: capture the fish object as soon as the client knows it ---- TODO: verify names
    { ROLE_FISH_CAPTURE,  "LetsFish.Fishing", "HookedFish",       "Initialize",     1, HK_CAPTURE_THIS },

    // --- Unlocks (client-side checks only; server still gates real use) ------ TODO: verify names
    { Feat::UNLOCK_LOC,   "LetsFish.Map",     "Location",         "IsUnlocked",     0, HK_RETURN_TRUE  },
    { Feat::UNLOCK_LOC,   "LetsFish.Map",     "Location",         "get_IsLocked",   0, HK_RETURN_FALSE },
    { Feat::COSMETICS,    "LetsFish.Shop",    "CosmeticItem",     "get_IsOwned",    0, HK_RETURN_TRUE  },

    // --- Ads ---------------------------------------------------------------- TODO: verify names
    { Feat::NO_ADS,       "LetsFish.Ads",     "AdsManager",       "ShowInterstitial", 0, HK_NOP        },
    { Feat::NO_ADS,       "LetsFish.Ads",     "AdsManager",       "ShowInterstitial", 1, HK_NOP        },
};
static const int kTargetCount = sizeof(kTargets) / sizeof(kTargets[0]);

// Fields read off the captured fish object for the ESP overlay.
static const char* kFishFields[] = { "speciesId", "weight", "length", "rarity", "isTrophy" };
static const int kFishFieldCount = sizeof(kFishFields) / sizeof(kFishFields[0]);

// Static methods exposed as buttons in the menu's "Dev" tab. Games often ship
// their debug/cheat classes with the UI stripped but the code intact — grep
// dump.cs for Cheat, Debug, GodMode, DevMenu.
struct DevMethod { const char* label; const char* ns; const char* klass; const char* method; };
static const DevMethod kDevMethods[] = {
    { "Open debug menu",   "LetsFish.Debug", "DebugMenu",   "Show",        },  // TODO: verify
    { "Toggle cheat mode", "LetsFish.Debug", "CheatManager","ToggleCheats" },  // TODO: verify
};
static const int kDevMethodCount = sizeof(kDevMethods) / sizeof(kDevMethods[0]);
