# LetsFish2 Mod Menu (rootless · Dopamine)

Client-side mod menu for **Let's Fish 2** (`com.tensquaregames.letsfish2`), built as a
Theos tweak for rootless jailbreaks (Dopamine / ElleKit).

Everything is resolved **by name** through the IL2CPP runtime API exported by
`UnityFramework`, so there are no hard-coded offsets to update after a game patch — only
class/method names, and those are collected in one file: [`src/Targets.h`](src/Targets.h).

> **Read first.** This modifies an online game. Server-authoritative state (coins, gold,
> XP, inventory, licenses, tournament results, shop) is *not* changeable from the client;
> the toggles below only affect what runs locally. Using client mods can violate the
> game's ToS and get an account banned. Use a throwaway account. This project deliberately
> contains nothing for IAP/receipt spoofing, currency injection or anti-cheat evasion.

## Features

| Menu toggle | What it hooks | Status |
|---|---|---|
| Speed hack (slider) | `UnityEngine.Time.set_timeScale` | works out of the box |
| Fast animations (slider) | `UnityEngine.Animator.set_speed` | works out of the box |
| Log Random.Range / RNG override | `UnityEngine.Random.Range` (float & int) | works out of the box |
| Auto-catch (reel always succeeds) | game reel-minigame result check | needs names from dump.cs |
| Instant bite | game bite wait-time getter | needs names |
| Line never snaps | game tension break check / damage | needs names |
| Fish never escapes | game escape roll | needs names |
| Bot: auto-cast + auto-reel | captures the fishing controller, invokes Cast/Reel on a timer | needs names |
| Fish ESP | captures the hooked-fish object, shows its fields in an overlay | needs names + field names |
| Show all locations unlocked | client-side `IsUnlocked` check | needs names |
| Cosmetics appear owned | client-side `IsOwned` check | needs names |
| No interstitial ads | ads manager `ShowInterstitial` | needs names |
| Dev tab | invokes leftover static debug/cheat methods | needs names |

The in-game **Status** tab lists every entry from `Targets.h` with ✅/❌ so you can see
exactly which names still need fixing — nothing crashes on an unresolved entry, it is
simply skipped.

## 1. Get the real names (one-time per game version)

```bash
# From the decrypted IPA:
unzip com.tensquaregames.letsfish2_1.0.506_decrypted.ipa
# Binary:   Payload/*.app/Frameworks/UnityFramework.framework/UnityFramework
# Metadata: Payload/*.app/Data/Managed/Metadata/global-metadata.dat

# https://github.com/Perfare/Il2CppDumper
Il2CppDumper UnityFramework global-metadata.dat out/
python3 tools/find_targets.py out/dump.cs            # prints HookTarget candidates
python3 tools/find_targets.py out/dump.cs bite       # one group only
```

Paste the correct lines into `kTargets` in `src/Targets.h`, and set `kFishFields` to the
real field names of the fish object. To confirm which method actually fires on a bite,
trace it live with Frida: `frida -U -n LetsFish2 -l tools/explore.js`.

Kinds available: `HK_RETURN_TRUE`, `HK_RETURN_FALSE`, `HK_RETURN_ZERO`,
`HK_RETURN_ZERO_F`, `HK_NOP`, `HK_CAPTURE_THIS`, `HK_RESOLVE_ONLY` (see the header).
Nested classes are written `Outer/Inner`; overloads are distinguished by `argc`.

## 2. Build

Requires [Theos](https://theos.dev) with the iOS SDK and the rootless toolchain.

```bash
export THEOS=~/theos
make clean package            # -> packages/com.flixzysus.letsfish2mod_0.1.0_iphoneos-arm64.deb
```

`THEOS_PACKAGE_SCHEME=rootless` is set in the Makefile, so the dylib installs under
`/var/jb/Library/MobileSubstrate/DynamicLibraries/` and links against ElleKit's
Substrate-compatible API.

## 3. Install on Dopamine

1. Copy the `.deb` to the device (AirDrop, Filza, or `scp` with the OpenSSH package).
2. Open it in **Sileo** (or `dpkg -i` over SSH), then respring / relaunch the game.
   With `THEOS_DEVICE_IP` set you can also run `make install`.
3. Make sure tweak injection is enabled for the game in Dopamine (Settings → Tweak
   Injection) and it is not blacklisted in Choicy if you use it.
4. Launch the game — a blue 🎣 bubble appears after ~3 s. Tap it for the menu; drag it
   anywhere. Settings persist between launches.

Logs are prefixed `[LF2Mod]` (Console.app / `idevicesyslog`).

## Layout

```
src/Tweak.xm     entry point — hooks il2cpp_init, installs everything once the domain exists
src/Il2Cpp.*     name-based IL2CPP bridge (class/method/field lookup, hook, invoke)
src/Hooks.mm     generic hook slots + speed / animation / RNG / bot / ESP implementations
src/Targets.h    ★ the only game-specific file: class/method names per feature
src/Config.*     persisted toggles (NSUserDefaults)
src/MenuUI.*     floating in-game menu (Features / Status / RNG / Dev tabs)
tools/           dump.cs scanner and Frida exploration script
```
