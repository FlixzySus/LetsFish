#pragma once
// Thin bridge to the IL2CPP runtime exported by UnityFramework.
// Everything is resolved by *name* at runtime through the public il2cpp_* API,
// so the tweak does not depend on hard-coded offsets that change every update.
#include <cstdint>
#include <cstddef>
#include <string>
#include <vector>

struct Il2CppDomain;
struct Il2CppAssembly;
struct Il2CppImage;
struct Il2CppClass;
struct Il2CppObject;
struct Il2CppString;
struct Il2CppType;
struct FieldInfo;
struct Il2CppException;
struct Il2CppThread;

typedef void (*Il2CppMethodPointer)();

// Only the first member is relied upon; it has been the first field of
// MethodInfo in every Unity release since 2017.
struct MethodInfo {
    Il2CppMethodPointer methodPointer;
};

namespace il2cpp {

// ---- raw API (bound with dlsym in bind()) ----
extern int            (*init)(const char* domainName);
extern Il2CppDomain*  (*domain_get)();
extern Il2CppAssembly**(*domain_get_assemblies)(const Il2CppDomain*, size_t* size);
extern const Il2CppImage* (*assembly_get_image)(const Il2CppAssembly*);
extern Il2CppClass*   (*class_from_name)(const Il2CppImage*, const char* ns, const char* name);
extern const MethodInfo* (*class_get_method_from_name)(Il2CppClass*, const char* name, int argsCount);
extern const MethodInfo* (*class_get_methods)(Il2CppClass*, void** iter);
extern FieldInfo*     (*class_get_field_from_name)(Il2CppClass*, const char* name);
extern Il2CppClass*   (*class_get_nested_types)(Il2CppClass*, void** iter);
extern const char*    (*class_get_name)(Il2CppClass*);
extern bool           (*class_is_enum)(const Il2CppClass*);
extern Il2CppClass*   (*class_from_type)(const Il2CppType*);
extern Il2CppClass*   (*object_get_class)(Il2CppObject*);
extern const char*    (*method_get_name)(const MethodInfo*);
extern uint32_t       (*method_get_param_count)(const MethodInfo*);
extern const Il2CppType* (*method_get_param)(const MethodInfo*, uint32_t index);
extern const Il2CppType* (*method_get_return_type)(const MethodInfo*);
extern char*          (*type_get_name)(const Il2CppType*);
extern const Il2CppType* (*field_get_type)(FieldInfo*);
extern void           (*field_get_value)(Il2CppObject*, FieldInfo*, void* value);
extern void           (*field_static_get_value)(FieldInfo*, void* value);
extern Il2CppObject*  (*runtime_invoke)(const MethodInfo*, void* obj, void** params, Il2CppException** exc);
extern Il2CppString*  (*string_new)(const char*);
extern int32_t        (*string_length)(Il2CppString*);
extern uint16_t*      (*string_chars)(Il2CppString*);
extern void           (*free_)(void*);
extern Il2CppThread*  (*thread_attach)(Il2CppDomain*);
extern void*          (*object_unbox)(Il2CppObject*);

// ---- helpers ----
bool  bind();                       // locate UnityFramework and dlsym the API above
void* symbol(const char* name);     // raw dlsym against UnityFramework
bool  ready();                      // il2cpp_init has completed
void  markReady();

// "Outer/Inner" nested class names are supported.
Il2CppClass*      findClass(const char* ns, const char* name);
const MethodInfo* findMethod(Il2CppClass* klass, const char* name, int argc);
// Disambiguates overloads: paramTypes e.g. {"System.Single","System.Single"}.
const MethodInfo* findMethodBySig(Il2CppClass* klass, const char* name,
                                  const std::vector<std::string>& paramTypes);
std::string       returnTypeName(const MethodInfo* m);

// Substrate/ElleKit hook on the method's native code.
bool hook(const MethodInfo* m, void* replacement, void** original);

// Must be called from an attached thread (the Unity main thread is).
Il2CppObject* invoke(const MethodInfo* m, void* self, void** args = nullptr);

std::string toStdString(Il2CppString* s);
// Reads a field of a common primitive/string/enum type and formats it.
std::string readField(Il2CppObject* obj, const char* fieldName);
std::string describeObject(Il2CppObject* obj, const std::vector<std::string>& fields);

} // namespace il2cpp
