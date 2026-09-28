#import <Foundation/Foundation.h>
#import <substrate.h>
#include "Il2Cpp.h"
#include "Mod.h"
#include "MenuUI.h"
#include "Log.h"

// The tweak is injected before main(), when UnityFramework is loaded but the
// IL2CPP domain does not exist yet. Hook il2cpp_init so hooks are installed
// the moment the managed assemblies become resolvable.
static int (*orig_il2cpp_init)(const char*);

static int hook_il2cpp_init(const char* domainName) {
    int r = orig_il2cpp_init(domainName);
    Mod::onRuntimeReady();
    // Give Unity a few seconds to create its UIWindow before overlaying ours.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [[LF2Menu shared] show]; });
    return r;
}

%ctor {
    @autoreleasepool {
        if (!il2cpp::bind()) {
            LOG("UnityFramework / il2cpp API not found — is this really the Unity build?");
            return;
        }
        void* sym = il2cpp::symbol("il2cpp_init");
        MSHookFunction(sym, (void*)hook_il2cpp_init, (void**)&orig_il2cpp_init);
        LOG("loaded, waiting for il2cpp_init");
    }
}
