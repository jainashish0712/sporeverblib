// SpotifyReverbUI.m
// Clean, Floating Draggable HUD & Control Overlay for SpotifyReverb & Pitch
// Right-hand ergonomic layout, system volume integration, thread-safe

#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <MediaPlayer/MediaPlayer.h>
#import "SpotifyReverbUI.h"
#import "SpotifyReverb.h"

// Spotify Brand Accent Color: #1DB954
#define SPOTIFY_GREEN [UIColor colorWithRed:(29.0f/255.0f) green:(185.0f/255.0f) blue:(84.0f/255.0f) alpha:1.0f]

// ============================================================================
// Passthrough Overlay Window (Always Floats Above Now Playing & Modal Views)
// ============================================================================
@interface SpotifyReverbOverlayWindow : UIWindow
@end

@implementation SpotifyReverbOverlayWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self || hitView == self.rootViewController.view) {
        return nil; // Pass touches through to Spotify
    }
    return hitView;
}

@end

@interface SpotifyReverbOverlayViewController : UIViewController
@end

@implementation SpotifyReverbOverlayViewController

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)prefersStatusBarHidden {
    return NO;
}

@end

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
// Modal Reverb & Pitch HUD Control View (Compact & Right-Hand Ergonomic)
// ============================================================================
@interface SpotifyReverbHUDView : UIView

@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIView *contentContainer;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *closeBtn;
@property (nonatomic, strong) UISwitch *enableSwitch;
@property (nonatomic, strong) UIView *separator;
@property (nonatomic, strong) UISlider *pitchSlider;
@property (nonatomic, strong) UILabel *pitchLabel;
@property (nonatomic, strong) UISlider *mixSlider;
@property (nonatomic, strong) UILabel *mixLabel;
@property (nonatomic, strong) UISlider *roomSlider;
@property (nonatomic, strong) UILabel *roomLabel;
@property (nonatomic, strong) UILabel *volumeLabel;
@property (nonatomic, strong) MPVolumeView *volumeView;
@property (nonatomic, strong) UIButton *resetBtn;
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
        self.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.18f].CGColor;
        self.backgroundColor = [UIColor colorWithWhite:0.10f alpha:0.60f];

        // Half blur background effect
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        _blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
        _blurView.frame = self.bounds;
        _blurView.alpha = 0.5f;
        _blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _blurView.userInteractionEnabled = NO;
        [self addSubview:_blurView];

        _contentContainer = [[UIView alloc] initWithFrame:self.bounds];
        _contentContainer.backgroundColor = [UIColor clearColor];
        _contentContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_contentContainer];

        // Header: Title on left, Switch + Close on right
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.text = @"Reverb & Pitch";
        _titleLabel.font = [UIFont boldSystemFontOfSize:15.5f];
        _titleLabel.textColor = [UIColor whiteColor];
        [_contentContainer addSubview:_titleLabel];

        _enableSwitch = [[UISwitch alloc] init];
        _enableSwitch.onTintColor = SPOTIFY_GREEN;
        _enableSwitch.transform = CGAffineTransformMakeScale(0.80f, 0.80f);
        [_enableSwitch addTarget:self action:@selector(enableToggled:) forControlEvents:UIControlEventValueChanged];
        [_contentContainer addSubview:_enableSwitch];

        _closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        [_closeBtn setTitle:@"✕" forState:UIControlStateNormal];
        _closeBtn.titleLabel.font = [UIFont systemFontOfSize:17.0f weight:UIFontWeightMedium];
        [_closeBtn setTitleColor:[UIColor colorWithWhite:0.8f alpha:1.0f] forState:UIControlStateNormal];
        [_closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [_contentContainer addSubview:_closeBtn];

        // Separator
        _separator = [[UIView alloc] init];
        _separator.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.12f];
        [_contentContainer addSubview:_separator];

        // Pitch Shift Slider (-4.0 to +4.0 in 0.2 intervals)
        _pitchLabel = [[UILabel alloc] init];
        _pitchLabel.font = [UIFont systemFontOfSize:11.5f weight:UIFontWeightRegular];
        _pitchLabel.textColor = [UIColor colorWithWhite:0.85f alpha:1.0f];
        [_contentContainer addSubview:_pitchLabel];

        _pitchSlider = [[UISlider alloc] init];
        _pitchSlider.minimumValue = -4.0f;
        _pitchSlider.maximumValue = 4.0f;
        _pitchSlider.value = 0.0f;
        _pitchSlider.minimumTrackTintColor = SPOTIFY_GREEN;
        [_pitchSlider addTarget:self action:@selector(pitchChanged:) forControlEvents:UIControlEventValueChanged];
        [_contentContainer addSubview:_pitchSlider];

        // Wet/Dry Mix Slider (strictly 100% complementary sum)
        _mixLabel = [[UILabel alloc] init];
        _mixLabel.font = [UIFont systemFontOfSize:11.5f weight:UIFontWeightRegular];
        _mixLabel.textColor = [UIColor colorWithWhite:0.85f alpha:1.0f];
        [_contentContainer addSubview:_mixLabel];

        _mixSlider = [[UISlider alloc] init];
        _mixSlider.minimumValue = 0.0f;
        _mixSlider.maximumValue = 1.0f;
        _mixSlider.value = 0.35f;
        _mixSlider.minimumTrackTintColor = SPOTIFY_GREEN;
        [_mixSlider addTarget:self action:@selector(mixChanged:) forControlEvents:UIControlEventValueChanged];
        [_contentContainer addSubview:_mixSlider];

        // Room Size Slider
        _roomLabel = [[UILabel alloc] init];
        _roomLabel.font = [UIFont systemFontOfSize:11.5f weight:UIFontWeightRegular];
        _roomLabel.textColor = [UIColor colorWithWhite:0.85f alpha:1.0f];
        [_contentContainer addSubview:_roomLabel];

        _roomSlider = [[UISlider alloc] init];
        _roomSlider.minimumValue = 0.1f;
        _roomSlider.maximumValue = 0.98f;
        _roomSlider.value = 0.82f;
        _roomSlider.minimumTrackTintColor = SPOTIFY_GREEN;
        [_roomSlider addTarget:self action:@selector(roomChanged:) forControlEvents:UIControlEventValueChanged];
        [_contentContainer addSubview:_roomSlider];

        // System Volume Bar (MPVolumeView)
        _volumeLabel = [[UILabel alloc] init];
        _volumeLabel.text = @"System Volume";
        _volumeLabel.font = [UIFont systemFontOfSize:11.5f weight:UIFontWeightRegular];
        _volumeLabel.textColor = [UIColor colorWithWhite:0.85f alpha:1.0f];
        [_contentContainer addSubview:_volumeLabel];

        _volumeView = [[MPVolumeView alloc] init];
        _volumeView.showsRouteButton = NO; // Hide AirPlay icon, show volume bar only
        _volumeView.tintColor = SPOTIFY_GREEN;
        [_contentContainer addSubview:_volumeView];

        // Reset Defaults Button
        _resetBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [_resetBtn setTitle:@"Reset to Studio Defaults" forState:UIControlStateNormal];
        [_resetBtn setTitleColor:[UIColor colorWithWhite:0.75f alpha:1.0f] forState:UIControlStateNormal];
        _resetBtn.titleLabel.font = [UIFont systemFontOfSize:12.0f weight:UIFontWeightMedium];
        _resetBtn.backgroundColor = [UIColor colorWithWhite:1.0f alpha:0.07f];
        _resetBtn.layer.cornerRadius = 7.0f;
        [_resetBtn addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
        [_contentContainer addSubview:_resetBtn];

        [self refreshValues];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat pad = 16.0f;
    CGFloat w = self.bounds.size.width - (pad * 2.0f);

    // Header row: compact height 34pt
    _titleLabel.frame = CGRectMake(pad, 12.0f, w - 85.0f, 26.0f);
    _enableSwitch.frame = CGRectMake(self.bounds.size.width - pad - 74.0f, 9.0f, 44.0f, 26.0f);
    _closeBtn.frame = CGRectMake(self.bounds.size.width - pad - 26.0f, 9.0f, 26.0f, 26.0f);

    CGFloat y = 44.0f;
    _separator.frame = CGRectMake(pad, y, w, 1.0f);
    y += 8.0f;

    // Pitch
    _pitchLabel.frame = CGRectMake(pad, y, w, 14.0f);
    y += 15.0f;
    _pitchSlider.frame = CGRectMake(pad, y, w, 24.0f);
    y += 28.0f;

    // Reverb Mix
    _mixLabel.frame = CGRectMake(pad, y, w, 14.0f);
    y += 15.0f;
    _mixSlider.frame = CGRectMake(pad, y, w, 24.0f);
    y += 28.0f;

    // Room Size
    _roomLabel.frame = CGRectMake(pad, y, w, 14.0f);
    y += 15.0f;
    _roomSlider.frame = CGRectMake(pad, y, w, 24.0f);
    y += 28.0f;

    // System Volume
    _volumeLabel.frame = CGRectMake(pad, y, w, 14.0f);
    y += 15.0f;
    _volumeView.frame = CGRectMake(pad, y, w, 24.0f);
    y += 30.0f;

    // Reset Defaults Button
    _resetBtn.frame = CGRectMake(pad, y, w, 28.0f);
}

- (void)refreshValues {
    self.enableSwitch.on = SpotifyReverb_IsEnabled();

    // Pitch (-4.0 to +4.0 in 0.2 intervals)
    float pitch = SpotifyReverb_GetPitch();
    self.pitchSlider.value = pitch;
    if (fabsf(pitch) < 0.01f) {
        self.pitchLabel.text = @"Pitch: 0.0 st (Original)";
    } else {
        self.pitchLabel.text = [NSString stringWithFormat:@"Pitch: %+0.1f st", pitch];
    }

    // Wet / Dry (strictly 100% complementary: dry% + wet% = 100%)
    float wet = SpotifyReverb_GetWet();
    float dry = 1.0f - wet;
    self.mixSlider.value = wet;
    self.mixLabel.text = [NSString stringWithFormat:@"Reverb Mix: Dry %.0f%% / Wet %.0f%%", dry * 100.0f, wet * 100.0f];

    // Room Size
    float room = SpotifyReverb_GetRoomSize();
    self.roomSlider.value = room;
    self.roomLabel.text = [NSString stringWithFormat:@"Room Size (Decay): %.2f", room];
}

- (void)enableToggled:(UISwitch *)sender {
    SpotifyReverb_SetEnabled(sender.on);
}

- (void)pitchChanged:(UISlider *)sender {
    float step = 0.2f;
    float val = roundf(sender.value / step) * step;
    sender.value = val;
    SpotifyReverb_SetPitch(val);
    if (fabsf(val) < 0.01f) {
        self.pitchLabel.text = @"Pitch: 0.0 st (Original)";
    } else {
        self.pitchLabel.text = [NSString stringWithFormat:@"Pitch: %+0.1f st", val];
    }
}

- (void)mixChanged:(UISlider *)sender {
    float wet = sender.value;
    float dry = 1.0f - wet;
    SpotifyReverb_SetWetDry(wet, dry);
    self.mixLabel.text = [NSString stringWithFormat:@"Reverb Mix: Dry %.0f%% / Wet %.0f%%", dry * 100.0f, wet * 100.0f];
}

- (void)roomChanged:(UISlider *)sender {
    SpotifyReverb_SetRoomSize(sender.value);
    self.roomLabel.text = [NSString stringWithFormat:@"Room Size (Decay): %.2f", sender.value];
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
@property (nonatomic, strong) SpotifyReverbOverlayWindow *overlayWindow;
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

- (UIWindowScene *)findActiveWindowScene {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                return (UIWindowScene *)scene;
            }
        }
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                return (UIWindowScene *)scene;
            }
        }
    }
    return nil;
}

- (void)startOverlay {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindowScene *scene = [self findActiveWindowScene];
        CGRect screenBounds = [UIScreen mainScreen].bounds;

        if (!self.overlayWindow) {
            if (scene && @available(iOS 13.0, *)) {
                self.overlayWindow = [[SpotifyReverbOverlayWindow alloc] initWithWindowScene:scene];
            } else {
                self.overlayWindow = [[SpotifyReverbOverlayWindow alloc] initWithFrame:screenBounds];
            }
            self.overlayWindow.windowLevel = UIWindowLevelNormal + 1000.0f; // Above Now Playing & modals
            self.overlayWindow.backgroundColor = [UIColor clearColor];
            self.overlayWindow.rootViewController = [[SpotifyReverbOverlayViewController alloc] init];
            self.overlayWindow.hidden = NO;
        } else {
            if (@available(iOS 13.0, *)) {
                if (scene && self.overlayWindow.windowScene != scene) {
                    self.overlayWindow.windowScene = scene;
                }
            }
            self.overlayWindow.hidden = NO;
        }

        UIView *container = self.overlayWindow.rootViewController.view;
        if (!container) return;

        if (!self.floatingButton) {
            CGFloat btnSize = 52.0f;
            CGFloat x = container.bounds.size.width - btnSize - 16.0f;
            CGFloat y = container.bounds.size.height - btnSize - 120.0f; // Above playback bar
            self.floatingButton = [[SpotifyReverbFloatingButton alloc] initWithFrame:CGRectMake(x, y, btnSize, btnSize)];

            __weak typeof(self) weakSelf = self;
            self.floatingButton.tapHandler = ^{
                [weakSelf toggleHUD];
            };
        }

        if (!self.floatingButton.superview) {
            [container addSubview:self.floatingButton];
            [container bringSubviewToFront:self.floatingButton];
        }

        static BOOL sGestureAdded = NO;
        if (!sGestureAdded) {
            UITapGestureRecognizer *twoFingerTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleHUD)];
            twoFingerTap.numberOfTouchesRequired = 2;
            twoFingerTap.numberOfTapsRequired = 2;
            twoFingerTap.cancelsTouchesInView = NO;
            [self.overlayWindow addGestureRecognizer:twoFingerTap];
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
        if (!self.overlayWindow) [self startOverlay];

        UIView *container = self.overlayWindow.rootViewController.view;
        if (!container) return;

        CGRect winBounds = container.bounds;

        // Semi-transparent dimming background (reduced to 0.20 for half dimming)
        if (!self.dimBackgroundView) {
            self.dimBackgroundView = [[UIView alloc] initWithFrame:winBounds];
            self.dimBackgroundView.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.20f];
            self.dimBackgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

            UITapGestureRecognizer *tapDim = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideHUD)];
            [self.dimBackgroundView addGestureRecognizer:tapDim];
        } else {
            self.dimBackgroundView.frame = winBounds;
        }

        // Compact & Right-Hand Ergonomic Layout:
        // Positioned downward into the natural thumb sweep zone, right-hand aligned
        CGFloat screenW = winBounds.size.width;
        CGFloat screenH = winBounds.size.height;
        CGFloat rightMargin = 14.0f;
        CGFloat hudW = MIN(340.0f, screenW - 28.0f);
        CGFloat hudH = 270.0f; // Compact 270pt height (saves ~80pt vertically)
        CGFloat hudX = screenW - hudW - rightMargin; // Biased to right side for easy 1-handed thumb reach
        CGFloat hudY = screenH - hudH - 95.0f;       // Anchored low, comfortably above the mini-player

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

        [container addSubview:self.dimBackgroundView];
        [container addSubview:self.hudView];
        [container bringSubviewToFront:self.hudView];

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
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note) {
        [[SpotifyReverbHUDManager sharedManager] startOverlay];
    }];
}
