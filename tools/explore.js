// Frida exploration script (uses frida-il2cpp-bridge) for finding real
// class/method names on-device before committing them to src/Targets.h.
//
//   npm i -g frida-tools && npm i frida-il2cpp-bridge
//   frida -U -n LetsFish2 -l explore.js
//
// Adjust FILTER to whatever you're hunting for (bite, tension, reel, ...).
// Every matching method is traced with its arguments and return value.

import "frida-il2cpp-bridge";

const FILTER = /bite|tension|reel|escape|catch|unlock|isowned|interstitial|cheat|debug/i;

Il2Cpp.perform(() => {
    const asm = Il2Cpp.domain.assembly("Assembly-CSharp").image;
    console.log(`Assembly-CSharp: ${asm.classes.length} classes`);

    // 1. Dump every class whose name (or namespace) matches.
    for (const klass of asm.classes) {
        if (!FILTER.test(klass.name) && !FILTER.test(klass.namespace)) continue;
        console.log(`\n[${klass.namespace}] ${klass.name}`);
        for (const m of klass.methods) {
            const params = m.parameters.map(p => `${p.type.name} ${p.name}`).join(", ");
            console.log(`   ${m.returnType.name} ${m.name}(${params})  @ 0x${m.relativeVirtualAddress.toString(16)}`);
        }
    }

    // 2. Trace calls to matching methods so you can see which one fires on a bite.
    Il2Cpp.trace(true)
        .assemblies(asm)
        .filterMethods(m => FILTER.test(m.name) || FILTER.test(m.class.name))
        .and()
        .attach();
});
