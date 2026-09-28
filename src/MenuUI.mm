#import "MenuUI.h"
#include "Config.h"
#include "Mod.h"
#include "Log.h"

@interface LF2PassthroughView : UIView
@end

static const CGFloat kBubble = 46;
static const CGFloat kPanelW = 300;
static const CGFloat kPanelH = 440;

typedef NS_ENUM(NSInteger, LF2Tab) { LF2TabFeatures, LF2TabStatus, LF2TabRng, LF2TabDev };

@interface LF2Menu ()
@property (nonatomic, strong) UIWindow* window;
@property (nonatomic, strong) UIButton* bubble;
@property (nonatomic, strong) UIView* panel;
@property (nonatomic, strong) UIScrollView* content;
@property (nonatomic, strong) UILabel* fishLabel;
@property (nonatomic, strong) UISegmentedControl* tabs;
@property (nonatomic, strong) NSTimer* refresh;
@property (nonatomic, strong) NSMutableDictionary<NSNumber*, NSString*>* switchKeys;
@property (nonatomic, strong) NSMutableDictionary<NSNumber*, NSString*>* sliderKeys;
@end

@implementation LF2Menu

+ (instancetype)shared {
    static LF2Menu* m; static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [LF2Menu new]; });
    return m;
}

- (UIWindowScene*)activeScene {
    for (UIScene* s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class] && s.activationState == UISceneActivationStateForegroundActive)
            return (UIWindowScene*)s;
    for (UIScene* s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class]) return (UIWindowScene*)s;
    return nil;
}

- (void)show {
    if (self.window) return;
    self.switchKeys = [NSMutableDictionary new];
    self.sliderKeys = [NSMutableDictionary new];

    UIWindowScene* scene = [self activeScene];
    self.window = scene ? [[UIWindow alloc] initWithWindowScene:scene]
                        : [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.windowLevel = UIWindowLevelStatusBar + 100;
    self.window.backgroundColor = UIColor.clearColor;
    self.window.rootViewController = [UIViewController new];
    self.window.rootViewController.view.backgroundColor = UIColor.clearColor;
    self.window.hidden = NO;

    // The window must only swallow touches that land on our views.
    LF2PassthroughView* root = [[LF2PassthroughView alloc] initWithFrame:self.window.bounds];
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.window.rootViewController.view = root;

    [self buildBubble:root];
    [self buildPanel:root];
    [self buildFishOverlay:root];

    self.panel.hidden = !Config::enabled(Feat::MENU_VISIBLE);
    self.refresh = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer*) {
        [self tick];
    }];
    LOG("menu shown");
}

#pragma mark - Bubble

- (void)buildBubble:(UIView*)root {
    UIButton* b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(12, 120, kBubble, kBubble);
    b.layer.cornerRadius = kBubble / 2;
    b.backgroundColor = [UIColor colorWithRed:0.05 green:0.45 blue:0.85 alpha:0.9];
    [b setTitle:@"🎣" forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:22];
    [b addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer* pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
    [b addGestureRecognizer:pan];
    [root addSubview:b];
    self.bubble = b;
}

- (void)drag:(UIPanGestureRecognizer*)g {
    CGPoint t = [g translationInView:g.view.superview];
    CGPoint c = g.view.center;
    g.view.center = CGPointMake(c.x + t.x, c.y + t.y);
    [g setTranslation:CGPointZero inView:g.view.superview];
    self.panel.frame = [self panelFrame];
}

- (CGRect)panelFrame {
    CGRect b = self.bubble.frame;
    CGSize s = self.window.bounds.size;
    CGFloat x = MIN(CGRectGetMaxX(b) + 8, s.width - kPanelW - 8);
    CGFloat y = MIN(b.origin.y, s.height - kPanelH - 8);
    return CGRectMake(MAX(8, x), MAX(8, y), kPanelW, kPanelH);
}

- (void)togglePanel {
    self.panel.hidden = !self.panel.hidden;
    Config::setEnabled(Feat::MENU_VISIBLE, !self.panel.hidden);
    if (!self.panel.hidden) { self.panel.frame = [self panelFrame]; [self rebuild]; }
}

#pragma mark - Panel

- (void)buildPanel:(UIView*)root {
    UIView* p = [[UIView alloc] initWithFrame:[self panelFrame]];
    p.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.94];
    p.layer.cornerRadius = 12;
    p.clipsToBounds = YES;
    [root addSubview:p];
    self.panel = p;

    UILabel* title = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, kPanelW - 24, 22)];
    title.text = @"Let's Fish 2 — Mod Menu";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:15];
    [p addSubview:title];

    self.tabs = [[UISegmentedControl alloc] initWithItems:@[@"Features", @"Status", @"RNG", @"Dev"]];
    self.tabs.frame = CGRectMake(12, 34, kPanelW - 24, 28);
    self.tabs.selectedSegmentIndex = LF2TabFeatures;
    [self.tabs addTarget:self action:@selector(rebuild) forControlEvents:UIControlEventValueChanged];
    [p addSubview:self.tabs];

    self.content = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 70, kPanelW, kPanelH - 70)];
    [p addSubview:self.content];
    [self rebuild];
}

- (void)rebuild {
    for (UIView* v in self.content.subviews) [v removeFromSuperview];
    [self.switchKeys removeAllObjects];
    [self.sliderKeys removeAllObjects];
    __block CGFloat y = 4;

    switch ((LF2Tab)self.tabs.selectedSegmentIndex) {
    case LF2TabFeatures: {
        [self addHeader:@"Fishing" y:&y];
        [self addSwitch:Feat::AUTOCATCH title:@"Auto-catch (reel always succeeds)" y:&y];
        [self addSwitch:Feat::INSTANT_BITE title:@"Instant bite" y:&y];
        [self addSwitch:Feat::NO_TENSION title:@"Line never snaps" y:&y];
        [self addSwitch:Feat::NO_ESCAPE title:@"Fish never escapes" y:&y];
        [self addSwitch:Feat::BOT title:@"Bot: auto-cast + auto-reel" y:&y];
        [self addSlider:Feat::BOT_INTERVAL title:@"Bot interval (s)" min:0.3 max:5 def:1.5 y:&y];

        [self addHeader:@"Quality of life" y:&y];
        [self addSwitch:Feat::SPEED title:@"Speed hack" y:&y];
        [self addSlider:Feat::SPEED_VALUE title:@"Speed ×" min:0.5 max:10 def:2 y:&y];
        [self addSwitch:Feat::SKIP_ANIM title:@"Fast animations" y:&y];
        [self addSlider:Feat::SKIP_ANIM_MULT title:@"Animation ×" min:1 max:50 def:10 y:&y];
        [self addSwitch:Feat::NO_ADS title:@"No interstitial ads" y:&y];

        [self addHeader:@"Visual / info (client-side only)" y:&y];
        [self addSwitch:Feat::UNLOCK_LOC title:@"Show all locations unlocked" y:&y];
        [self addSwitch:Feat::COSMETICS title:@"Cosmetics appear owned" y:&y];
        [self addSwitch:Feat::FISH_ESP title:@"Fish ESP (species/weight on bite)" y:&y];
        [self addSwitch:Feat::RNG_LOG title:@"Log Random.Range calls" y:&y];
        [self addSegment:Feat::RNG_MODE title:@"RNG override" items:@[@"Off", @"Min", @"Max"] y:&y];
        break;
    }
    case LF2TabStatus: {
        [self addHeader:@"Hook resolution (fix names in Targets.h)" y:&y];
        for (auto& s : Mod::statuses()) {
            NSString* line = [NSString stringWithFormat:@"%@ %s\n    %s", s.resolved ? @"✅" : @"❌",
                              s.feature.c_str(), s.where.c_str()];
            [self addText:line color:s.resolved ? UIColor.greenColor : UIColor.systemRedColor y:&y];
        }
        break;
    }
    case LF2TabRng: {
        [self addHeader:@"Recent UnityEngine.Random.Range" y:&y];
        auto log = Mod::rngLog();
        if (log.empty()) [self addText:@"(enable 'Log Random.Range calls')" color:UIColor.lightGrayColor y:&y];
        for (auto it = log.rbegin(); it != log.rend(); ++it)
            [self addText:[NSString stringWithUTF8String:it->c_str()] color:UIColor.whiteColor y:&y];
        break;
    }
    case LF2TabDev: {
        [self addHeader:@"Invoke static methods (kDevMethods)" y:&y];
        [self addButton:@"Open debug menu" tag:0 y:&y];
        [self addButton:@"Toggle cheat mode" tag:1 y:&y];
        [self addText:@"Grep dump.cs for Cheat/Debug/GodMode and add\nentries to kDevMethods in Targets.h."
               color:UIColor.lightGrayColor y:&y];
        break;
    }
    }
    self.content.contentSize = CGSizeMake(kPanelW, y + 12);
}

#pragma mark - Row builders

- (void)addHeader:(NSString*)t y:(CGFloat*)y {
    UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(12, *y + 6, kPanelW - 24, 18)];
    l.text = t.uppercaseString;
    l.textColor = [UIColor colorWithWhite:0.6 alpha:1];
    l.font = [UIFont boldSystemFontOfSize:11];
    [self.content addSubview:l];
    *y += 28;
}

- (void)addSwitch:(const char*)key title:(NSString*)t y:(CGFloat*)y {
    UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(12, *y, kPanelW - 80, 30)];
    l.text = t; l.textColor = UIColor.whiteColor; l.font = [UIFont systemFontOfSize:13];
    l.adjustsFontSizeToFitWidth = YES;
    [self.content addSubview:l];
    UISwitch* s = [UISwitch new];
    s.frame = CGRectMake(kPanelW - 62, *y, 50, 30);
    s.transform = CGAffineTransformMakeScale(0.8, 0.8);
    s.on = Config::enabled(key);
    s.tag = (NSInteger)self.switchKeys.count + 1;
    self.switchKeys[@(s.tag)] = @(key);
    [s addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.content addSubview:s];
    *y += 34;
}

- (void)addSlider:(const char*)key title:(NSString*)t min:(float)mn max:(float)mx def:(float)def y:(CGFloat*)y {
    UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(12, *y, 130, 26)];
    l.textColor = UIColor.lightGrayColor; l.font = [UIFont systemFontOfSize:12];
    l.text = [NSString stringWithFormat:@"%@: %.1f", t, Config::number(key, def)];
    [self.content addSubview:l];
    UISlider* s = [[UISlider alloc] initWithFrame:CGRectMake(146, *y, kPanelW - 158, 26)];
    s.minimumValue = mn; s.maximumValue = mx; s.value = Config::number(key, def);
    s.tag = (NSInteger)self.sliderKeys.count + 1;
    self.sliderKeys[@(s.tag)] = @(key);
    [s addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.content addSubview:s];
    *y += 30;
}

- (void)addSegment:(const char*)key title:(NSString*)t items:(NSArray<NSString*>*)items y:(CGFloat*)y {
    UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(12, *y, 110, 28)];
    l.text = t; l.textColor = UIColor.whiteColor; l.font = [UIFont systemFontOfSize:13];
    [self.content addSubview:l];
    UISegmentedControl* sc = [[UISegmentedControl alloc] initWithItems:items];
    sc.frame = CGRectMake(126, *y, kPanelW - 138, 28);
    sc.selectedSegmentIndex = Config::integer(key, 0);
    sc.tag = (NSInteger)self.sliderKeys.count + 1000;
    self.sliderKeys[@(sc.tag)] = @(key);
    [sc addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    [self.content addSubview:sc];
    *y += 34;
}

- (void)addText:(NSString*)t color:(UIColor*)c y:(CGFloat*)y {
    UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(12, *y, kPanelW - 24, 0)];
    l.text = t; l.textColor = c; l.numberOfLines = 0;
    l.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10];
    [l sizeToFit];
    l.frame = CGRectMake(12, *y, kPanelW - 24, l.frame.size.height);
    [self.content addSubview:l];
    *y += l.frame.size.height + 6;
}

- (void)addButton:(NSString*)t tag:(NSInteger)tag y:(CGFloat*)y {
    UIButton* b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(12, *y, kPanelW - 24, 32);
    b.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    b.layer.cornerRadius = 6;
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.tag = tag;
    [b addTarget:self action:@selector(devTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.content addSubview:b];
    *y += 38;
}

#pragma mark - Actions

- (void)switchChanged:(UISwitch*)s {
    const char* key = self.switchKeys[@(s.tag)].UTF8String;
    Config::setEnabled(key, s.on);
    if (strcmp(key, Feat::SPEED) == 0) Mod::applySpeed();
    if (strcmp(key, Feat::BOT) == 0) Mod::setBotRunning(s.on);
    self.fishLabel.hidden = !Config::enabled(Feat::FISH_ESP);
}

- (void)sliderChanged:(UISlider*)s {
    const char* key = self.sliderKeys[@(s.tag)].UTF8String;
    Config::setNumber(key, s.value);
    if (strcmp(key, Feat::SPEED_VALUE) == 0) Mod::applySpeed();
    if (strcmp(key, Feat::BOT_INTERVAL) == 0 && Config::enabled(Feat::BOT)) Mod::setBotRunning(true);
    // Refresh the value label sitting to the left of the slider.
    for (UIView* v in self.content.subviews)
        if ([v isKindOfClass:UILabel.class] && fabs(v.frame.origin.y - s.frame.origin.y) < 1) {
            UILabel* l = (UILabel*)v;
            NSString* base = [l.text componentsSeparatedByString:@":"].firstObject;
            l.text = [NSString stringWithFormat:@"%@: %.1f", base, s.value];
        }
}

- (void)segmentChanged:(UISegmentedControl*)sc {
    Config::setInteger(self.sliderKeys[@(sc.tag)].UTF8String, (int)sc.selectedSegmentIndex);
}

- (void)devTapped:(UIButton*)b {
    bool ok = Mod::invokeDevMethod((int)b.tag);
    [b setTitle:ok ? @"✅ invoked" : @"❌ unresolved (see Status)" forState:UIControlStateNormal];
}

#pragma mark - Fish overlay

- (void)buildFishOverlay:(UIView*)root {
    UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(0, 50, root.bounds.size.width, 22)];
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    l.textAlignment = NSTextAlignmentCenter;
    l.textColor = UIColor.yellowColor;
    l.font = [UIFont boldSystemFontOfSize:12];
    l.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    l.hidden = !Config::enabled(Feat::FISH_ESP);
    [root addSubview:l];
    self.fishLabel = l;
}

- (void)tick {
    std::string fish = Mod::lastFishInfo();
    self.fishLabel.text = fish.empty() ? @"🐟 waiting for a bite…" : [NSString stringWithUTF8String:fish.c_str()];
    if (!self.panel.hidden && self.tabs.selectedSegmentIndex == LF2TabRng) [self rebuild];
}

@end

// A container that only intercepts touches on its own subviews so the game
// underneath keeps receiving input everywhere else.
@implementation LF2PassthroughView
- (UIView*)hitTest:(CGPoint)point withEvent:(UIEvent*)event {
    UIView* v = [super hitTest:point withEvent:event];
    return v == self ? nil : v;
}
@end
