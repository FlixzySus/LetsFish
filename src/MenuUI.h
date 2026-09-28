#pragma once
#import <UIKit/UIKit.h>

// Floating in-game mod menu: draggable bubble that toggles a panel of
// switches/sliders, plus Status / RNG / Dev tabs.
@interface LF2Menu : NSObject
+ (instancetype)shared;
- (void)show;
@end
