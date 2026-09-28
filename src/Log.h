#pragma once
#import <Foundation/Foundation.h>

// Filter in Console.app / idevicesyslog with: LF2Mod
#define LOG(fmt, ...) NSLog(@"[LF2Mod] " fmt, ##__VA_ARGS__)
