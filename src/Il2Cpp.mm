#import <Foundation/Foundation.h>
#import <substrate.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <cstring>
#include <cstdio>
#include "Il2Cpp.h"
#include "Log.h"

namespace il2cpp {

int            (*init)(const char*) = nullptr;
Il2CppDomain*  (*domain_get)() = nullptr;
Il2CppAssembly**(*domain_get_assemblies)(const Il2CppDomain*, size_t*) = nullptr;
const Il2CppImage* (*assembly_get_image)(const Il2CppAssembly*) = nullptr;
Il2CppClass*   (*class_from_name)(const Il2CppImage*, const char*, const char*) = nullptr;
const MethodInfo* (*class_get_method_from_name)(Il2CppClass*, const char*, int) = nullptr;
const MethodInfo* (*class_get_methods)(Il2CppClass*, void**) = nullptr;
FieldInfo*     (*class_get_field_from_name)(Il2CppClass*, const char*) = nullptr;
Il2CppClass*   (*class_get_nested_types)(Il2CppClass*, void**) = nullptr;
const char*    (*class_get_name)(Il2CppClass*) = nullptr;
bool           (*class_is_enum)(const Il2CppClass*) = nullptr;
Il2CppClass*   (*class_from_type)(const Il2CppType*) = nullptr;
Il2CppClass*   (*object_get_class)(Il2CppObject*) = nullptr;
const char*    (*method_get_name)(const MethodInfo*) = nullptr;
uint32_t       (*method_get_param_count)(const MethodInfo*) = nullptr;
const Il2CppType* (*method_get_param)(const MethodInfo*, uint32_t) = nullptr;
const Il2CppType* (*method_get_return_type)(const MethodInfo*) = nullptr;
char*          (*type_get_name)(const Il2CppType*) = nullptr;
const Il2CppType* (*field_get_type)(FieldInfo*) = nullptr;
void           (*field_get_value)(Il2CppObject*, FieldInfo*, void*) = nullptr;
void           (*field_static_get_value)(FieldInfo*, void*) = nullptr;
Il2CppObject*  (*runtime_invoke)(const MethodInfo*, void*, void**, Il2CppException**) = nullptr;
Il2CppString*  (*string_new)(const char*) = nullptr;
int32_t        (*string_length)(Il2CppString*) = nullptr;
uint16_t*      (*string_chars)(Il2CppString*) = nullptr;
void           (*free_)(void*) = nullptr;
Il2CppThread*  (*thread_attach)(Il2CppDomain*) = nullptr;
void*          (*object_unbox)(Il2CppObject*) = nullptr;

static void* g_handle = nullptr;
static bool  g_ready = false;

void* symbol(const char* name) {
    return g_handle ? dlsym(g_handle, name) : nullptr;
}

static void* findUnityFramework() {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char* path = _dyld_get_image_name(i);
        if (path && strstr(path, "UnityFramework.framework/UnityFramework")) {
            return dlopen(path, RTLD_NOW | RTLD_NOLOAD);
        }
    }
    // Fallback: the framework is normally linked, so the symbol is already global.
    if (dlsym(RTLD_DEFAULT, "il2cpp_init")) return RTLD_DEFAULT;
    return nullptr;
}

#define BIND(sym) do { \
    sym = (decltype(sym))dlsym(g_handle, "il2cpp_" #sym); \
    if (!sym) { LOG("missing symbol il2cpp_" #sym); ok = false; } \
} while (0)

bool bind() {
    g_handle = findUnityFramework();
    if (!g_handle) return false;
    bool ok = true;
    BIND(init);
    BIND(domain_get);
    BIND(domain_get_assemblies);
    BIND(assembly_get_image);
    BIND(class_from_name);
    BIND(class_get_method_from_name);
    BIND(class_get_methods);
    BIND(class_get_field_from_name);
    BIND(class_get_nested_types);
    BIND(class_get_name);
    BIND(class_is_enum);
    BIND(class_from_type);
    BIND(object_get_class);
    BIND(method_get_name);
    BIND(method_get_param_count);
    BIND(method_get_param);
    BIND(method_get_return_type);
    BIND(type_get_name);
    BIND(field_get_type);
    BIND(field_get_value);
    BIND(field_static_get_value);
    BIND(runtime_invoke);
    BIND(string_new);
    BIND(string_length);
    BIND(string_chars);
    BIND(thread_attach);
    BIND(object_unbox);
    free_ = (decltype(free_))dlsym(g_handle, "il2cpp_free");
    return ok;
}
#undef BIND

bool ready() { return g_ready; }
void markReady() { g_ready = true; }

Il2CppClass* findClass(const char* ns, const char* fullName) {
    if (!g_ready) return nullptr;
    std::string name(fullName);
    std::string outer = name, inner;
    size_t slash = name.find('/');
    if (slash != std::string::npos) {
        outer = name.substr(0, slash);
        inner = name.substr(slash + 1);
    }

    size_t count = 0;
    Il2CppAssembly** assemblies = domain_get_assemblies(domain_get(), &count);
    for (size_t i = 0; i < count; i++) {
        const Il2CppImage* image = assembly_get_image(assemblies[i]);
        Il2CppClass* klass = class_from_name(image, ns, outer.c_str());
        if (!klass) continue;
        if (inner.empty()) return klass;
        // Walk nested types (supports one level of "Outer/Inner").
        void* iter = nullptr;
        while (Il2CppClass* nested = class_get_nested_types(klass, &iter)) {
            if (inner == class_get_name(nested)) return nested;
        }
    }
    return nullptr;
}

const MethodInfo* findMethod(Il2CppClass* klass, const char* name, int argc) {
    if (!klass) return nullptr;
    return class_get_method_from_name(klass, name, argc);
}

static std::string typeName(const Il2CppType* t) {
    char* raw = type_get_name(t);
    std::string s = raw ? raw : "";
    if (raw && free_) free_(raw);
    return s;
}

const MethodInfo* findMethodBySig(Il2CppClass* klass, const char* name,
                                  const std::vector<std::string>& paramTypes) {
    if (!klass) return nullptr;
    void* iter = nullptr;
    while (const MethodInfo* m = class_get_methods(klass, &iter)) {
        if (strcmp(method_get_name(m), name) != 0) continue;
        if (method_get_param_count(m) != paramTypes.size()) continue;
        bool match = true;
        for (uint32_t i = 0; i < paramTypes.size() && match; i++) {
            match = typeName(method_get_param(m, i)) == paramTypes[i];
        }
        if (match) return m;
    }
    return nullptr;
}

std::string returnTypeName(const MethodInfo* m) {
    return m ? typeName(method_get_return_type(m)) : "";
}

bool hook(const MethodInfo* m, void* replacement, void** original) {
    if (!m || !m->methodPointer) return false;
    MSHookFunction((void*)m->methodPointer, replacement, original);
    return true;
}

Il2CppObject* invoke(const MethodInfo* m, void* self, void** args) {
    if (!m) return nullptr;
    Il2CppException* exc = nullptr;
    Il2CppObject* r = runtime_invoke(m, self, args, &exc);
    if (exc) LOG("invoke %s threw a managed exception", method_get_name(m));
    return r;
}

std::string toStdString(Il2CppString* s) {
    if (!s) return "(null)";
    int32_t len = string_length(s);
    uint16_t* chars = string_chars(s);
    NSString* ns = [[NSString alloc] initWithCharacters:chars length:(NSUInteger)len];
    return std::string(ns.UTF8String ?: "");
}

std::string readField(Il2CppObject* obj, const char* fieldName) {
    if (!obj) return "?";
    Il2CppClass* klass = object_get_class(obj);
    FieldInfo* f = class_get_field_from_name(klass, fieldName);
    if (!f) return "<no field>";
    const Il2CppType* t = field_get_type(f);
    std::string tn = typeName(t);
    Il2CppClass* fc = class_from_type(t);
    bool isEnum = fc && class_is_enum(fc);

    // Only copy out types whose size we know; anything else (large structs)
    // is reported by name instead of risking an overflow.
    union { int32_t i32; int64_t i64; float f32; double f64; bool b; Il2CppString* str; } v = {0};
    char out[64];
    if (tn == "System.Int32" || isEnum) {
        field_get_value(obj, f, &v); snprintf(out, sizeof out, "%d", v.i32);
    } else if (tn == "System.Single") {
        field_get_value(obj, f, &v); snprintf(out, sizeof out, "%.3f", v.f32);
    } else if (tn == "System.Double") {
        field_get_value(obj, f, &v); snprintf(out, sizeof out, "%.3f", v.f64);
    } else if (tn == "System.Boolean") {
        field_get_value(obj, f, &v); return v.b ? "true" : "false";
    } else if (tn == "System.Int64") {
        field_get_value(obj, f, &v); snprintf(out, sizeof out, "%lld", (long long)v.i64);
    } else if (tn == "System.String") {
        field_get_value(obj, f, &v); return toStdString(v.str);
    } else {
        snprintf(out, sizeof out, "<%s>", tn.c_str());
    }
    return out;
}

std::string describeObject(Il2CppObject* obj, const std::vector<std::string>& fields) {
    std::string s;
    for (auto& f : fields) {
        if (!s.empty()) s += "  ";
        s += f + "=" + readField(obj, f.c_str());
    }
    return s;
}

} // namespace il2cpp
