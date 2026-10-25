// SpotifyReverbUI.m
// Clean, Floating Draggable HUD & Control Overlay for SpotifyReverb
// Thread-safe, main-thread guaranteed, zero private APIs

#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import "SpotifyReverbUI.h"
#import "SpotifyReverb.h"

// Spotify Brand Accent Color: #1DB954
#define SPOTIFY_GREEN [UIColor colorWithRed:(29.0f/255.0f) green:(185.0f/255.0f) blue:(84.0f/255.0f) alpha:1.0f]

// ============================================================================
// Floating Draggable Pill Button
// ============================================================================
@interface SpotifyReverbFloatingButton : UIView

@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, copy) void (^tapHandler)(void);

@end

@implementation SpotifyReverbFloatingButton

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.layer.cornerRadius = frame.size.width / 2.0f;
        self.layer.masksToBounds = YES;
        self.layer.borderWidth = 1.5f;
        self.layer.borderColor = SPOTIFY_GREEN.CGColor;

        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        _blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
        _blurView.frame = self.bounds;
        _blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _blurView.userInteractionEnabled = NO;
        [self addSubview:_blurView];

        _label = [[UILabel alloc] initWithFrame:self.bounds];
        _label.text = @"🎛️";
        _label.font = [UIFont systemFontOfSize:22.0f];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _label.userInteractionEnabled = NO;
        [self addSubview:_label];

        // Gestures
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)handleTap:(UITapGestureRecognizer *)tap {
    if (self.tapHandler) {
        self.tapHandler();
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIView *superview = self.superview;
    if (!superview) return;

    CGPoint translation = [pan translationInView:superview];
    if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
        CGPoint center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);

        // Keep button safely inside visible window boundaries
        CGRect bounds = superview.bounds;
        CGFloat radius = self.bounds.size.width / 2.0f;
        CGFloat minX = radius + 8.0f;
        CGFloat maxX = bounds.size.width - radius - 8.0f;
        CGFloat minY = radius + 40.0f;
        CGFloat maxY = bounds.size.height - radius - 40.0f;

        center.x = MAX(minX, MIN(maxX, center.x));
        center.y = MAX(minY, MIN(maxY, center.y));

        self.center = center;
        [pan setTranslation:CGPointMake(0, 0) inView:superview];
    }
}

@end

// ============================================================================
// Modal Reverb HUD Control View
// ============================================================================
@interface SpotifyReverbHUDView : UIView

@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UISwitch *enableSwitch;
@property (nonatomic, strong) UISlider *mixSlider;
@property (nonatomic, strong) UILabel *mixLabel;
@property (nonatomic, strong) UISlider *roomSlider;
@property (nonatomic, strong) UILabel *roomLabel;
@property (nonatomic, strong) UISlider *dampingSlider;
@property (nonatomic, strong) UILabel *dampingLabel;
@property (nonatomic, copy) void (^closeHandler)(void);

- (void)refreshValues;

@end

@implementation SpotifyReverbHUDView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.layer.cornerRadius = 20.0f;
        self.layer.masksToBounds = YES;
        self.layer.borderWidth = 1.0f;
        self.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.15f].CGColor;

        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        _blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
        _blurView.frame = self.bounds;
        _blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_blurView];

        UIView *contentView = _blurView.contentView;
        CGFloat pad = 20.0f;
        CGFloat w = frame.size.width - (pad * 2.0f);
        CGFloat y = 16.0f;

        // Title Header
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, w - 40.0f, 26.0f)];
        titleLabel.text = @"Reverb DSP Controls";
        titleLabel.font = [UIFont boldSystemFontOfSize:17.0f];
        titleLabel.textColor = [UIColor whiteColor];
        [contentView addSubview:titleLabel];

        // Close Button
        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        closeBtn.frame = CGRectMake(frame.size.width - pad - 32.0f, y - 3.0f, 32.0f, 32.0f);
        [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
        closeBtn.titleLabel.font = [UIFont systemFontOfSize:18.0f weight:UIFontWeightMedium];
        [closeBtn setTitleColor:[UIColor colorWithWhite:0.8f alpha:1.0f] forState:UIControlStateNormal];
        [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [contentView addSubview:closeBtn];

        y += 38.0f;

        // Enable Switch Row
        UILabel *enableText = [[UILabel alloc] initWithFrame:CGRectMake(pad, y + 4.0f, w - 60.0f, 24.0f)];
        enableText.text = @"Enable Reverb";
        enableText.font = [UIFont systemFontOfSize:15.0f weight:UIFontWeightMedium];
        enableText.textColor = [UIColor whiteColor];
        [contentView addSubview:enableText];

        _enableSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(frame.size.width - pad - 51.0f, y, 51.0f, 31.0f)];
        _enableSwitch.onTintColor = SPOTIFY_GREEN;
        [_enableSwitch addTarget:self action:@selector(enableToggled:) forControlEvents:UIControlEventValueChanged];
        [contentView addSubview:_enableSwitch];

        y += 44.0f;

        // Separator
        UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(pad, y, w, 1.0f)];
        sep.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.1f];
        [contentView addSubview:sep];

        y += 12.0f;

        // Wet/Dry Mix Slider
        _mixLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, w, 18.0f)];
        _mixLabel.font = [UIFont systemFontOfSize:13.0f weight:UIFontWeightRegular];
        _mixLabel.textColor = [UIColor colorWithWhite:0.85f alpha:1.0f];
        [contentView addSubview:_mixLabel];

        y += 22.0f;
        _mixSlider = [[UISlider alloc] initWithFrame:CGRectMake(pad, y, w, 30.0f)];
        _mixSlider.minimumValue = 0.0f;
        _mixSlider.maximumValue = 1.0f;
        _mixSlider.minimumTrackTintColor = SPOTIFY_GREEN;
        [_mixSlider addTarget:self action:@selector(mixChanged:) forControlEvents:UIControlEventValueChanged];
        [contentView addSubview:_mixSlider];

        y += 38.0f;

        // Room Size Slider
        _roomLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, w, 18.0f)];
        _roomLabel.font = [UIFont systemFontOfSize:13.0f weight:UIFontWeightRegular];
        _roomLabel.textColor = [UIColor colorWithWhite:0.85f alpha:1.0f];
        [contentView addSubview:_roomLabel];

        y += 22.0f;
        _roomSlider = [[UISlider alloc] initWithFrame:CGRectMake(pad, y, w, 30.0f)];
        _roomSlider.minimumValue = 0.1f;
        _roomSlider.maximumValue = 0.98f;
        _roomSlider.minimumTrackTintColor = SPOTIFY_GREEN;
        [_roomSlider addTarget:self action:@selector(roomChanged:) forControlEvents:UIControlEventValueChanged];
        [contentView addSubview:_roomSlider];

        y += 38.0f;

        // Damping Slider
        _dampingLabel = [[UILabel alloc] initWithFrame:CGRectMake(pad, y, w, 18.0f)];
        _dampingLabel.font = [UIFont systemFontOfSize:13.0f weight:UIFontWeightRegular];
        _dampingLabel.textColor = [UIColor colorWithWhite:0.85f alpha:1.0f];
        [contentView addSubview:_dampingLabel];

        y += 22.0f;
        _dampingSlider = [[UISlider alloc] initWithFrame:CGRectMake(pad, y, w, 30.0f)];
        _dampingSlider.minimumValue = 0.0f;
        _dampingSlider.maximumValue = 1.0f;
        _dampingSlider.minimumTrackTintColor = SPOTIFY_GREEN;
        [_dampingSlider addTarget:self action:@selector(dampingChanged:) forControlEvents:UIControlEventValueChanged];
        [contentView addSubview:_dampingSlider];

        y += 42.0f;

        // Reset Defaults Button
        UIButton *resetBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        resetBtn.frame = CGRectMake(pad, y, w, 32.0f);
        [resetBtn setTitle:@"Reset to Studio Defaults" forState:UIControlStateNormal];
        [resetBtn setTitleColor:[UIColor colorWithWhite:0.75f alpha:1.0f] forState:UIControlStateNormal];
        resetBtn.titleLabel.font = [UIFont systemFontOfSize:13.0f weight:UIFontWeightMedium];
        resetBtn.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.06f];
        resetBtn.layer.cornerRadius = 8.0f;
        [resetBtn addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
        [contentView addSubview:resetBtn];

        [self refreshValues];
    }
    return self;
}

- (void)refreshValues {
    self.enableSwitch.on = SpotifyReverb_IsEnabled();

    float wet = SpotifyReverb_GetWet();
    float dry = SpotifyReverb_GetDry();
    self.mixSlider.value = wet;
    self.mixLabel.text = [NSString stringWithFormat:@"Mix: Dry %.0f%% / Wet %.0f%%", dry * 100.0f, wet * 100.0f];

    float room = SpotifyReverb_GetRoomSize();
    self.roomSlider.value = room;
    self.roomLabel.text = [NSString stringWithFormat:@"Room Size (Decay): %.2f", room];

    float damp = SpotifyReverb_GetDamping();
    self.dampingSlider.value = damp;
    self.dampingLabel.text = [NSString stringWithFormat:@"Damping (Tone): %.2f", damp];
}

- (void)enableToggled:(UISwitch *)sender {
    SpotifyReverb_SetEnabled(sender.on);
}

- (void)mixChanged:(UISlider *)sender {
    float wet = sender.value;
    float dry = 1.0f - (wet * 0.5f);
    SpotifyReverb_SetWetDry(wet, dry);
    self.mixLabel.text = [NSString stringWithFormat:@"Mix: Dry %.0f%% / Wet %.0f%%", dry * 100.0f, wet * 100.0f];
}

- (void)roomChanged:(UISlider *)sender {
    SpotifyReverb_SetRoomSize(sender.value);
    self.roomLabel.text = [NSString stringWithFormat:@"Room Size (Decay): %.2f", sender.value];
}

- (void)dampingChanged:(UISlider *)sender {
    SpotifyReverb_SetDamping(sender.value);
    self.dampingLabel.text = [NSString stringWithFormat:@"Damping (Tone): %.2f", sender.value];
}

- (void)resetTapped {
    SpotifyReverb_ResetDefaults();
    [self refreshValues];
}

- (void)closeTapped {
    if (self.closeHandler) {
        self.closeHandler();
    }
}

@end

// ============================================================================
// HUD Manager Singleton
// ============================================================================
@interface SpotifyReverbHUDManager ()
@property (nonatomic, strong) SpotifyReverbFloatingButton *floatingButton;
@property (nonatomic, strong) UIView *dimBackgroundView;
@property (nonatomic, strong) SpotifyReverbHUDView *hudView;
@property (nonatomic, assign) BOOL isHUDVisible;
@end

@implementation SpotifyReverbHUDManager

+ (instancetype)sharedManager {
    static SpotifyReverbHUDManager *sShared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sShared = [[SpotifyReverbHUDManager alloc] init];
    });
    return sShared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isHUDVisible = NO;
    }
    return self;
}

- (UIWindow *)findKeyWindow {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *w in windowScene.windows) {
                    if (w.isKeyWindow) return w;
                }
                if (windowScene.windows.count > 0) return windowScene.windows.firstObject;
            }
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIApplication sharedApplication].keyWindow ?: [UIApplication sharedApplication].windows.firstObject;
#pragma clang diagnostic pop
}

- (void)startOverlay {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [self findKeyWindow];
        if (!window) return;

        if (!self.floatingButton) {
            CGFloat btnSize = 52.0f;
            CGFloat x = window.bounds.size.width - btnSize - 16.0f;
            CGFloat y = window.bounds.size.height - btnSize - 120.0f; // Positioned above bottom playback bar
            self.floatingButton = [[SpotifyReverbFloatingButton alloc] initWithFrame:CGRectMake(x, y, btnSize, btnSize)];

            __weak typeof(self) weakSelf = self;
            self.floatingButton.tapHandler = ^{
                [weakSelf toggleHUD];
            };
        }

        if (!self.floatingButton.superview) {
            [window addSubview:self.floatingButton];
            [window bringSubviewToFront:self.floatingButton];
        }

        // Two-finger double tap shortcut on window (does not block standard Spotify touches)
        static BOOL sGestureAdded = NO;
        if (!sGestureAdded) {
            UITapGestureRecognizer *twoFingerTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleHUD)];
            twoFingerTap.numberOfTouchesRequired = 2;
            twoFingerTap.numberOfTapsRequired = 2;
            twoFingerTap.cancelsTouchesInView = NO;
            [window addGestureRecognizer:twoFingerTap];
            sGestureAdded = YES;
        }
    });
}

- (void)toggleHUD {
    if (self.isHUDVisible) {
        [self hideHUD];
    } else {
        [self showHUD];
    }
}

- (void)showHUD {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.isHUDVisible) return;
        UIWindow *window = [self findKeyWindow];
        if (!window) return;

        CGRect winBounds = window.bounds;

        // Semi-transparent dimming background
        if (!self.dimBackgroundView) {
            self.dimBackgroundView = [[UIView alloc] initWithFrame:winBounds];
            self.dimBackgroundView.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.45f];
            self.dimBackgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

            UITapGestureRecognizer *tapDim = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideHUD)];
            [self.dimBackgroundView addGestureRecognizer:tapDim];
        } else {
            self.dimBackgroundView.frame = winBounds;
        }

        // HUD View sizing and centering
        CGFloat hudW = MIN(340.0f, winBounds.size.width - 32.0f);
        CGFloat hudH = 345.0f;
        CGFloat hudX = (winBounds.size.width - hudW) / 2.0f;
        CGFloat hudY = (winBounds.size.height - hudH) / 2.0f;

        if (!self.hudView) {
            self.hudView = [[SpotifyReverbHUDView alloc] initWithFrame:CGRectMake(hudX, hudY, hudW, hudH)];
            __weak typeof(self) weakSelf = self;
            self.hudView.closeHandler = ^{
                [weakSelf hideHUD];
            };
        } else {
            self.hudView.frame = CGRectMake(hudX, hudY, hudW, hudH);
            [self.hudView refreshValues];
        }

        [window addSubview:self.dimBackgroundView];
        [window addSubview:self.hudView];
        [window bringSubviewToFront:self.hudView];

        // Smooth spring animation
        self.dimBackgroundView.alpha = 0.0f;
        self.hudView.alpha = 0.0f;
        self.hudView.transform = CGAffineTransformMakeScale(0.85f, 0.85f);
        self.isHUDVisible = YES;

        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.85f initialSpringVelocity:0.5f options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.dimBackgroundView.alpha = 1.0f;
            self.hudView.alpha = 1.0f;
            self.hudView.transform = CGAffineTransformIdentity;
        } completion:nil];
    });
}

- (void)hideHUD {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.isHUDVisible) return;
        self.isHUDVisible = NO;

        [UIView animateWithDuration:0.2 animations:^{
            self.dimBackgroundView.alpha = 0.0f;
            self.hudView.alpha = 0.0f;
            self.hudView.transform = CGAffineTransformMakeScale(0.85f, 0.85f);
        } completion:^(BOOL finished) {
            [self.dimBackgroundView removeFromSuperview];
            [self.hudView removeFromSuperview];
        }];
    });
}

@end

// ============================================================================
// Auto-Register UI Overlay on App Launch
// ============================================================================
__attribute__((constructor))
static void SpotifyReverbUIInit(void) {
    // Listen for UIApplicationDidBecomeActiveNotification so UIKit has completed window setup
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        [[SpotifyReverbHUDManager sharedManager] startOverlay];
    }];
}
