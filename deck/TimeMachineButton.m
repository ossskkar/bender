// Injected by the Mac's time machine (deck.py travel) into builds of Arisu
// from before 11.0, which have no time machine of their own (Oscar,
// 2026-10-02: "easy time travel across versions from within the app"). A
// small button in the corner opens the deck's version list inside the app;
// a tap there builds and installs any version, this one's future included.
// Objective-C so that +load can install it without touching the old code.
#import <UIKit/UIKit.h>
#import <SafariServices/SafariServices.h>

@interface ArisuTimeMachineButton : NSObject
@end

@implementation ArisuTimeMachineButton

static UIButton *button;
// Filled in by deck.py for each build it makes: whether this build needs the
// corner button (only those from before 11.0), which commit it is, and what
// to tell him when he lands here (Oscar, 2026-10-02: "every time I switch
// version display a summary of this version and what it can and cannot do").
static BOOL const kButton = __BUTTON__;
static NSString *const kSha = @"__SHA__";
static NSString *const kTitle = @"__TITLE__";
static NSString *const kSummary = @"__SUMMARY__";

+ (void)load {
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                     queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { [self later]; }];
}

/// A second after the app's own view is up, and again every two seconds, so
/// it stays on top of whatever the old app adds to its window.
+ (void)later {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self show]; });
}

+ (UIWindow *)window {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class])
            for (UIWindow *w in ((UIWindowScene *)s).windows)
                if (!w.hidden) return w;
    return nil;
}

+ (void)show {
    UIWindow *w = [self window];
    if (!w) return;
    [self summarise:w];
    if (!kButton) return;
    if (!button) {
        button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:@"⟲ TIME MACHINE" forState:UIControlStateNormal];
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightBold];
        button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];
        button.layer.cornerRadius = 10;
        button.layer.borderWidth = 1.5;
        button.layer.borderColor = [UIColor colorWithRed:1 green:0.36 blue:0.62 alpha:1].CGColor;
        button.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin;
        [button addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *t) { [self show]; }];
    }
    if (button.superview != w) [w addSubview:button];
    button.frame = CGRectMake(16, w.bounds.size.height - 64, 196, 44);
    [w bringSubviewToFront:button];
}

/// Once per landing: which version this is, what it does and does not do.
+ (void)summarise:(UIWindow *)w {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if ([[d stringForKey:@"arisu.timemachine.seen"] isEqualToString:kSha]) return;
    UIViewController *top = w.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if (!top || top.isBeingPresented) return;
    [d setObject:kSha forKey:@"arisu.timemachine.seen"];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:kTitle message:kSummary
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [top presentViewController:a animated:YES completion:nil];
}

+ (void)open {
    NSURL *u = [NSURL URLWithString:@"https://oscars-macbook-pro.tailaa64e9.ts.net:8443/deck/travel"];
    SFSafariViewController *page = [[SFSafariViewController alloc] initWithURL:u];
    UIViewController *top = button.window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:page animated:YES completion:nil];
}

@end
