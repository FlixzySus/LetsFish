#import <Foundation/Foundation.h>
#include "Config.h"

static NSString* key(const char* k) {
    return [NSString stringWithFormat:@"lf2mod.%s", k];
}

namespace Config {

bool enabled(const char* k) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key(k)];
}
void setEnabled(const char* k, bool on) {
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:key(k)];
}
float number(const char* k, float def) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key(k)];
    return v ? [v floatValue] : def;
}
void setNumber(const char* k, float v) {
    [[NSUserDefaults standardUserDefaults] setFloat:v forKey:key(k)];
}
int integer(const char* k, int def) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key(k)];
    return v ? [v intValue] : def;
}
void setInteger(const char* k, int v) {
    [[NSUserDefaults standardUserDefaults] setInteger:v forKey:key(k)];
}

}
