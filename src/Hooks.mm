#import <Foundation/Foundation.h>
#include <cstring>
#include <mutex>
#include <deque>
#include <unordered_map>
#include "Il2Cpp.h"
#include "Config.h"
#include "Targets.h"
#include "Mod.h"
#include "Log.h"

// ============================================================================
//  Generic hook slots
//
//  IL2CPP compiles `ret Class::Method(args..., MethodInfo*)` to a plain C
//  function (instance methods take `this` in x0). Each slot forwards the first
//  eight integer registers untouched and returns through the correct register
//  class for the method's return type (x0 / s0 / d0), which is all we need to
//  either short-circuit a value or pass the call through to the original.
// ============================================================================
namespace {

constexpr int kMaxSlots = 48;
static_assert(kTargetCount <= kMaxSlots, "raise kMaxSlots");

struct Slot {
    const HookTarget* t = nullptr;
    void* orig = nullptr;
};
Slot g_slots[kMaxSlots];

typedef uint64_t (*Fn8)(void*, void*, void*, void*, void*, void*, void*, void*);
typedef float    (*FnF8)(void*, void*, void*, void*, void*, void*, void*, void*);
typedef double   (*FnD8)(void*, void*, void*, void*, void*, void*, void*, void*);

std::mutex g_captureMx;
std::unordered_map<std::string, void*> g_captured;   // role -> last `this`
std::string g_lastFish;

void onCapture(const char* role, void* self) {
    {
        std::lock_guard<std::mutex> l(g_captureMx);
        g_captured[role] = self;
    }
    if (strcmp(role, ROLE_FISH_CAPTURE) == 0 && Config::enabled(Feat::FISH_ESP)) {
        std::vector<std::string> fields(kFishFields, kFishFields + kFishFieldCount);
        std::string info = il2cpp::describeObject((Il2CppObject*)self, fields);
        std::lock_guard<std::mutex> l(g_captureMx);
        g_lastFish = info;
        LOG("fish: %s", info.c_str());
    }
}

void* captured(const char* role) {
    std::lock_guard<std::mutex> l(g_captureMx);
    auto it = g_captured.find(role);
    return it == g_captured.end() ? nullptr : it->second;
}

template <int I>
uint64_t slot_u64(void* a0, void* a1, void* a2, void* a3, void* a4, void* a5, void* a6, void* a7) {
    Slot& s = g_slots[I];
    bool on = Config::enabled(s.t->feature);
    switch (s.t->kind) {
        case HK_RETURN_TRUE:  if (on) return 1; break;
        case HK_RETURN_FALSE: if (on) return 0; break;
        case HK_RETURN_ZERO:  if (on) return 0; break;
        case HK_NOP:          if (on) return 0; break;
        case HK_CAPTURE_THIS: onCapture(s.t->feature, a0); break;
        default: break;
    }
    return ((Fn8)s.orig)(a0, a1, a2, a3, a4, a5, a6, a7);
}

template <int I>
float slot_f32(void* a0, void* a1, void* a2, void* a3, void* a4, void* a5, void* a6, void* a7) {
    Slot& s = g_slots[I];
    if (s.t->kind == HK_RETURN_ZERO_F && Config::enabled(s.t->feature)) return 0.0f;
    if (s.t->kind == HK_CAPTURE_THIS) onCapture(s.t->feature, a0);
    return ((FnF8)s.orig)(a0, a1, a2, a3, a4, a5, a6, a7);
}

template <int I>
double slot_f64(void* a0, void* a1, void* a2, void* a3, void* a4, void* a5, void* a6, void* a7) {
    Slot& s = g_slots[I];
    if (s.t->kind == HK_RETURN_ZERO_F && Config::enabled(s.t->feature)) return 0.0;
    if (s.t->kind == HK_CAPTURE_THIS) onCapture(s.t->feature, a0);
    return ((FnD8)s.orig)(a0, a1, a2, a3, a4, a5, a6, a7);
}

// Instantiate one replacement per slot for each return class.
#define S8(F, B) (void*)F<B+0>, (void*)F<B+1>, (void*)F<B+2>, (void*)F<B+3>, \
                 (void*)F<B+4>, (void*)F<B+5>, (void*)F<B+6>, (void*)F<B+7>
#define S48(F) S8(F,0), S8(F,8), S8(F,16), S8(F,24), S8(F,32), S8(F,40)
void* const kSlotU64[kMaxSlots] = { S48(slot_u64) };
void* const kSlotF32[kMaxSlots] = { S48(slot_f32) };
void* const kSlotF64[kMaxSlots] = { S48(slot_f64) };
#undef S48
#undef S8

std::vector<Mod::Status> g_status;
const MethodInfo* g_resolved[kMaxSlots];

std::string where(const HookTarget& t) {
    std::string s = t.ns;
    if (!s.empty()) s += ".";
    s += t.klass; s += "::"; s += t.method; s += "(" + std::to_string(t.argc) + ")";
    return s;
}

void installTargets() {
    for (int i = 0; i < kTargetCount; i++) {
        const HookTarget& t = kTargets[i];
        Il2CppClass* klass = il2cpp::findClass(t.ns, t.klass);
        const MethodInfo* m = il2cpp::findMethod(klass, t.method, t.argc);
        g_resolved[i] = m;
        g_status.push_back({ t.feature, where(t), m != nullptr });
        if (!m) { LOG("unresolved: %s", where(t).c_str()); continue; }
        if (t.kind == HK_RESOLVE_ONLY) continue;

        g_slots[i].t = &t;
        std::string rt = il2cpp::returnTypeName(m);
        void* repl = kSlotU64[i];
        if (rt == "System.Single") repl = kSlotF32[i];
        else if (rt == "System.Double") repl = kSlotF64[i];
        if (il2cpp::hook(m, repl, &g_slots[i].orig)) LOG("hooked %s", where(t).c_str());
    }
}

// ---------------------------------------------------------------------------
//  Speed hack: UnityEngine.Time.set_timeScale (real Unity API, no guessing)
// ---------------------------------------------------------------------------
const MethodInfo* g_setTimeScale = nullptr;
void (*orig_setTimeScale)(float, const MethodInfo*) = nullptr;

void hook_setTimeScale(float v, const MethodInfo* mi) {
    if (Config::enabled(Feat::SPEED)) v = Config::number(Feat::SPEED_VALUE, 2.0f);
    orig_setTimeScale(v, mi);
}

void installSpeed() {
    Il2CppClass* time = il2cpp::findClass("UnityEngine", "Time");
    g_setTimeScale = il2cpp::findMethodBySig(time, "set_timeScale", {"System.Single"});
    bool ok = il2cpp::hook(g_setTimeScale, (void*)hook_setTimeScale, (void**)&orig_setTimeScale);
    g_status.push_back({ Feat::SPEED, "UnityEngine.Time::set_timeScale", ok });
}

// ---------------------------------------------------------------------------
//  Skip animations: UnityEngine.Animator.set_speed multiplier
// ---------------------------------------------------------------------------
void (*orig_animSetSpeed)(void*, float, const MethodInfo*) = nullptr;

void hook_animSetSpeed(void* self, float v, const MethodInfo* mi) {
    if (Config::enabled(Feat::SKIP_ANIM)) v *= Config::number(Feat::SKIP_ANIM_MULT, 10.0f);
    orig_animSetSpeed(self, v, mi);
}

void installSkipAnim() {
    Il2CppClass* anim = il2cpp::findClass("UnityEngine", "Animator");
    const MethodInfo* m = il2cpp::findMethodBySig(anim, "set_speed", {"System.Single"});
    bool ok = il2cpp::hook(m, (void*)hook_animSetSpeed, (void**)&orig_animSetSpeed);
    g_status.push_back({ Feat::SKIP_ANIM, "UnityEngine.Animator::set_speed", ok });
}

// ---------------------------------------------------------------------------
//  RNG: log / override UnityEngine.Random.Range
// ---------------------------------------------------------------------------
std::mutex g_rngMx;
std::deque<std::string> g_rngLog;

void pushRng(const std::string& s) {
    std::lock_guard<std::mutex> l(g_rngMx);
    g_rngLog.push_back(s);
    if (g_rngLog.size() > 40) g_rngLog.pop_front();
}

float (*orig_rangeF)(float, float, const MethodInfo*) = nullptr;
int   (*orig_rangeI)(int, int, const MethodInfo*) = nullptr;

float hook_rangeF(float lo, float hi, const MethodInfo* mi) {
    float r = orig_rangeF(lo, hi, mi);
    int mode = Config::integer(Feat::RNG_MODE, 0);
    if (mode == 1) r = lo; else if (mode == 2) r = hi;
    if (Config::enabled(Feat::RNG_LOG)) {
        char b[96]; snprintf(b, sizeof b, "Range(%.2f, %.2f) -> %.3f", lo, hi, r); pushRng(b);
    }
    return r;
}

int hook_rangeI(int lo, int hi, const MethodInfo* mi) {
    int r = orig_rangeI(lo, hi, mi);
    int mode = Config::integer(Feat::RNG_MODE, 0);
    if (mode == 1) r = lo; else if (mode == 2 && hi > lo) r = hi - 1;   // int Range is [lo, hi)
    if (Config::enabled(Feat::RNG_LOG)) {
        char b[96]; snprintf(b, sizeof b, "Range(%d, %d) -> %d", lo, hi, r); pushRng(b);
    }
    return r;
}

void installRng() {
    Il2CppClass* rnd = il2cpp::findClass("UnityEngine", "Random");
    const MethodInfo* f = il2cpp::findMethodBySig(rnd, "Range", {"System.Single", "System.Single"});
    const MethodInfo* i = il2cpp::findMethodBySig(rnd, "Range", {"System.Int32", "System.Int32"});
    bool okF = il2cpp::hook(f, (void*)hook_rangeF, (void**)&orig_rangeF);
    bool okI = il2cpp::hook(i, (void*)hook_rangeI, (void**)&orig_rangeI);
    g_status.push_back({ Feat::RNG_LOG, "UnityEngine.Random::Range(float,float)", okF });
    g_status.push_back({ Feat::RNG_LOG, "UnityEngine.Random::Range(int,int)", okI });
}

// ---------------------------------------------------------------------------
//  Bot: alternate Cast / Reel on the captured controller from the main thread
//  (the Unity player loop runs on the app main thread on iOS, so it is already
//  attached to the il2cpp domain).
// ---------------------------------------------------------------------------
NSTimer* g_botTimer = nil;
bool g_botCastNext = true;

const MethodInfo* resolvedFor(const char* role) {
    for (int i = 0; i < kTargetCount; i++)
        if (strcmp(kTargets[i].feature, role) == 0) return g_resolved[i];
    return nullptr;
}

void botTick() {
    if (!Config::enabled(Feat::BOT)) return;
    void* ctrl = captured(ROLE_BOT_CONTROLLER);
    if (!ctrl) return;
    const MethodInfo* m = resolvedFor(g_botCastNext ? ROLE_BOT_CAST : ROLE_BOT_REEL);
    if (m) il2cpp::invoke(m, ctrl);
    g_botCastNext = !g_botCastNext;
}

} // namespace

// ============================================================================
//  Public API
// ============================================================================
namespace Mod {

void onRuntimeReady() {
    il2cpp::markReady();
    installSpeed();
    installSkipAnim();
    installRng();
    installTargets();
    LOG("runtime ready, %d hook targets processed", kTargetCount);
    dispatch_async(dispatch_get_main_queue(), ^{
        applySpeed();
        setBotRunning(Config::enabled(Feat::BOT));
    });
}

std::vector<Status> statuses() { return g_status; }

void applySpeed() {
    if (!g_setTimeScale) return;
    float v = Config::enabled(Feat::SPEED) ? Config::number(Feat::SPEED_VALUE, 2.0f) : 1.0f;
    void* args[] = { &v };
    il2cpp::invoke(g_setTimeScale, nullptr, args);
}

void setBotRunning(bool on) {
    [g_botTimer invalidate];
    g_botTimer = nil;
    if (!on) return;
    float interval = Config::number(Feat::BOT_INTERVAL, 1.5f);
    g_botTimer = [NSTimer scheduledTimerWithTimeInterval:interval repeats:YES block:^(NSTimer*) {
        botTick();
    }];
}

bool invokeDevMethod(int index) {
    if (index < 0 || index >= kDevMethodCount) return false;
    const DevMethod& d = kDevMethods[index];
    Il2CppClass* k = il2cpp::findClass(d.ns, d.klass);
    const MethodInfo* m = il2cpp::findMethod(k, d.method, 0);
    if (!m) { LOG("dev method unresolved: %s.%s::%s", d.ns, d.klass, d.method); return false; }
    il2cpp::invoke(m, nullptr);
    return true;
}

std::vector<std::string> rngLog() {
    std::lock_guard<std::mutex> l(g_rngMx);
    return std::vector<std::string>(g_rngLog.begin(), g_rngLog.end());
}

std::string lastFishInfo() {
    std::lock_guard<std::mutex> l(g_captureMx);
    return g_lastFish;
}

} // namespace Mod
