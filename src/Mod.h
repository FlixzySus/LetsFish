#pragma once
#include <string>
#include <vector>

namespace Mod {
// Called once il2cpp_init has returned. Installs every hook from Targets.h.
void onRuntimeReady();

// Per-target resolution result for the menu's Status tab.
struct Status { std::string feature; std::string where; bool resolved; };
std::vector<Status> statuses();

// Feature entry points used by the menu.
void applySpeed();                      // push Feat::SPEED_VALUE into Time.timeScale
void setBotRunning(bool on);
bool invokeDevMethod(int index);        // kDevMethods[index]
std::vector<std::string> rngLog();      // most recent Random.Range calls
std::string lastFishInfo();
}
