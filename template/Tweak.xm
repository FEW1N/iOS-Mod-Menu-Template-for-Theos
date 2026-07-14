#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <substrate.h>
#include <mach-o/dyld.h>
#include <string.h>
#include <dlfcn.h>

// ============================================================
//  v19.0 STABLE - FEW1N MOD MENU
//  DreamRoadMultiplayer (1.4.1)  |  Il2Cpp / UnityFramework
// ============================================================
//  OFFSET TABLE  (ALL VERIFIED against dump.cs)
// ============================================================
// Time.set_timeScale(float)                [STATIC]   -> 0x6771BDC
// PhotonNetwork.set_NickName(string)       [STATIC]   -> 0x5933C4C
// PhotonNetwork.CloseConnection(Player)    [STATIC]   -> 0x5938B50
// PhotonNetwork.set_SendRate(int)          [STATIC]   -> 0x59348E8
// PhotonNetwork.set_SerializationRate(int) [STATIC]   -> 0x5934A48
// ChatManager.get_Instance()               [STATIC]   -> 0x31A6234
// ChatManager.Send(string)                 [INSTANCE] -> 0x31A6338
// HR_UI_RoomListLine.Connect()             [INSTANCE] -> 0x54B3430   (password @ self+0x50)
// HR_PhotonLobbyManager.get_Instance()     [STATIC]   -> 0x54A81D4   (passwordInput @ +0x50, passwordOnConnectInput @ +0x60)
// TMP_InputField.set_text(string)          [INSTANCE] -> 0x65F4F8C
// RCCP_CarController.Update()              [INSTANCE] -> 0x59C4ED8   (_engine @ self+0x58, maximumSpeed @ self+0x138)
// RCCP_Engine: maxTorqueAtRPM@0x5C, maximumTorqueAsNM@0x94, useCuveForMaxTorque@0x98
// CarNitro.get_nitroAmount()               [INSTANCE] -> 0x54CFF50
// CarNitro.set_nitroAmount(float)          [INSTANCE] -> 0x54CFF58
// CarDriveSystem.Move(f,f,f,f)             [INSTANCE] -> 0x54CCBDC   (overrideAcceleration@0x61, overrideAccelerationPower@0x6C, topSpeed@0x98, speedMultiplier@0xA0)
// PlateVariant.Change(PlateHolder)         [INSTANCE] -> 0x54EA338
// PlayerManager.get_Instance()             [STATIC]   -> 0x5A2E138
// PlayerManager.get_Money()                [INSTANCE] -> 0x5A43784
// PlayerManager.AddMoney(int)              [INSTANCE] -> 0x5A43D44
// PlayerManager.UpdateNicknameInternal(str)[INSTANCE] -> 0x5A3E0EC
// ============================================================

// ===== STRUCTS =====
struct PlateHolder {          // dump.cs: c@0x0 (string), t@0x8 (string)
    void* c;
    void* t;
};

// ===== PERSISTED SETTINGS =====
#define DEF_SUITE @"com.few1n.dreamroadmod"
static NSUserDefaults* defs(void) {
    static NSUserDefaults* d = nil;
    if (!d) d = [[NSUserDefaults alloc] initWithSuiteName:DEF_SUITE] ?: [NSUserDefaults standardUserDefaults];
    return d;
}
static void saveBool(NSString* k, bool v)   { [defs() setBool:v forKey:k]; }
static bool loadBool(NSString* k, bool def)  { return [defs() objectForKey:k] ? [defs() boolForKey:k] : def; }
static void saveInt(NSString* k, int v)      { [defs() setInteger:v forKey:k]; }
static int  loadInt(NSString* k, int def)    { return [defs() objectForKey:k] ? (int)[defs() integerForKey:k] : def; }
static void saveStr(NSString* k, NSString* v){ if (v) [defs() setObject:v forKey:k]; }
static NSString* loadStr(NSString* k, NSString* def){ NSString* s=[defs() stringForKey:k]; return s?:def; }

// ===== GLOBAL STATE =====
static int  speedMode = 1;
static bool isCustomPlateEnabled = false;
static char customPlateText[64] = "FEW1N";
static bool isColorChatEnabled = false;
static bool isSpamEnabled = false;
static char chatSpamText[128] = "FEW1N MOD MENU!";
static NSTimer *spamTimer = nil;
static NSTimer *speedEnforceTimer = nil;
static bool isBypassPasswordEnabled = true;
static bool isEnginePowerEnabled = false;
static bool isMaxSpeedEnabled = false;
static bool isInfiniteNitroEnabled = false;
static bool isAddMoneyEnabled = false;
static bool isSuperAccelEnabled = false;   // NEW: CarDriveSystem full-throttle / super speed
static int  customMoneyAmount = 100000000; // NEW: user-configurable money amount

// ===== IL2CPP HELPERS =====
static void* (*cached_il2cpp_string_new)(const char*) = NULL;
static uintptr_t global_base = 0;
static int hookSuccessCount = 0;
static int hookFailCount = 0;

static void* mkStr(NSString* s) {
    if (!cached_il2cpp_string_new) {
        cached_il2cpp_string_new = (void*(*)(const char*))dlsym(RTLD_DEFAULT, "il2cpp_string_new");
    }
    if (!cached_il2cpp_string_new || !s) return NULL;
    return cached_il2cpp_string_new(s.UTF8String);
}

static NSString* readStr(void* il2s) {
    if (!il2s) return @"";
    @try {
        int32_t len = *(int32_t*)((uintptr_t)il2s + 0x10);
        if (len <= 0 || len > 4096) return @"";
        return [NSString stringWithCharacters:(unichar*)((uintptr_t)il2s + 0x14) length:len];
    } @catch (...) {
        return @"";
    }
}

// ===== SAFE HOOK WRAPPER =====
static void safeHook(void* target, void* replacement, void** original, const char* name) {
    if (!target) {
        NSLog(@"[FEW1N] SKIP hook %s: target address is NULL", name);
        hookFailCount++;
        return;
    }
    MSHookFunction(target, replacement, original);
    if (original && *original) {
        NSLog(@"[FEW1N] OK hook %s at %p -> orig %p", name, target, *original);
        hookSuccessCount++;
    } else {
        NSLog(@"[FEW1N] WARN hook %s at %p: original is NULL (may still work)", name, target);
        hookSuccessCount++;
    }
}

// ===== WINDOW HELPER (iOS 13+ Scene-based) =====
static UIWindow* getKeyWindow(void) {
    if (@available(iOS 15.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) return window;
                }
                if (windowScene.windows.count > 0) return windowScene.windows.firstObject;
            }
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
    if (w) return w;
    NSArray<UIWindow *> *windows = [UIApplication sharedApplication].windows;
    for (UIWindow *win in windows) {
        if (win.isKeyWindow) return win;
    }
    return windows.firstObject;
}

// ===== FUNCTION POINTERS (il2cpp direct calls) =====
static void* (*chatGetInst)(void) = NULL;
static void  (*chatSend)(void* self, void* msg) = NULL;
static void  (*tmp_set_text)(void* self, void* msg) = NULL;
static void  (*pn_setNickName)(void* name) = NULL;
static void* (*lobbyGetInst)(void) = NULL;
static void* (*playerManagerGetInst)(void) = NULL;
static void  (*pm_updateNicknameInternal)(void* self, void* newName) = NULL;
static int   (*pm_getMoney)(void* self) = NULL;          // NEW
static void  (*pn_setSendRate)(int value) = NULL;
static void  (*pn_setSerializationRate)(int value) = NULL;
static void  (*pm_addMoney)(void* self, int amount) = NULL;

// ================================================================
//  HOOK 1: Time.set_timeScale  [STATIC]
// ================================================================
static void (*o_setTimeScale)(float) = NULL;
static void h_setTimeScale(float v) {
    if (speedMode == 2)       v = 2.5f;
    else if (speedMode == 5)  v = 5.0f;
    else if (speedMode == 10) v = 10.0f;
    if (o_setTimeScale) o_setTimeScale(v);

    @try {
        if (pn_setSendRate && pn_setSerializationRate) {
            if (speedMode > 1) { pn_setSendRate(5);  pn_setSerializationRate(3); }
            else               { pn_setSendRate(20); pn_setSerializationRate(10); }
        }
    } @catch (...) {}
}

// ================================================================
//  HOOK 2: PhotonNetwork.CloseConnection  [STATIC]  (anti-kick)
// ================================================================
static bool (*o_closeConnection)(void*) = NULL;
static bool h_closeConnection(void* kickPlayer) {
    return false; // swallow local kick requests
}

// ================================================================
//  HOOK 3: RCCP_CarController.Update  [INSTANCE]
//  _engine @ self+0x58 (RCCP_Engine*), maximumSpeed @ self+0x138
// ================================================================
static void (*o_rccp)(void*) = NULL;
static void h_rccp(void* self) {
    if (o_rccp) o_rccp(self);
    if (!self) return;
    @try {
        if (isEnginePowerEnabled) {
            void* engine = *(void**)((uintptr_t)self + 0x58);   // RCCP_MainComponent._engine
            if (engine) {
                *(float*)((uintptr_t)engine + 0x5C) = 9999.0f;  // maxTorqueAtRPM
                *(float*)((uintptr_t)engine + 0x94) = 9999.0f;  // maximumTorqueAsNM
                *(bool*) ((uintptr_t)engine + 0x98) = false;    // useCuveForMaxTorque -> use raw max torque
            }
        }
        if (isMaxSpeedEnabled) {
            *(float*)((uintptr_t)self + 0x138) = 999.0f;        // maximumSpeed
        }
    } @catch (...) {}
}

// ================================================================
//  HOOK 4: CarNitro.get_nitroAmount  [INSTANCE]
// ================================================================
static float (*o_getNitro)(void*) = NULL;
static float h_getNitro(void* self) {
    if (isInfiniteNitroEnabled) return 1.0f;
    return o_getNitro ? o_getNitro(self) : 0.0f;
}

// ================================================================
//  HOOK 5: CarNitro.set_nitroAmount  [INSTANCE]
// ================================================================
static void (*o_setNitro)(void*, float) = NULL;
static void h_setNitro(void* self, float value) {
    if (isInfiniteNitroEnabled) value = 1.0f;
    if (o_setNitro) o_setNitro(self, value);
}

// ================================================================
//  HOOK 6: CarDriveSystem.Move  [INSTANCE]  (NEW - actual player car)
//  overrideAcceleration@0x61, overrideAccelerationPower@0x6C,
//  topSpeed@0x98, speedMultiplier@0xA0
// ================================================================
static void (*o_driveMove)(void*, float, float, float, float) = NULL;
static void h_driveMove(void* self, float steering, float accel, float footbrake, float handbrake) {
    if (self) {
        @try {
            if (isSuperAccelEnabled) {
                *(bool*) ((uintptr_t)self + 0x61) = true;      // overrideAcceleration
                *(float*)((uintptr_t)self + 0x6C) = 5000.0f;   // overrideAccelerationPower
                if (*(float*)((uintptr_t)self + 0x98) < 500.0f)
                    *(float*)((uintptr_t)self + 0x98) = 500.0f; // topSpeed
                *(float*)((uintptr_t)self + 0xA0) = 3.0f;      // speedMultiplier
                if (footbrake <= 0.0f && handbrake <= 0.0f) accel = 1.0f; // full throttle
            } else {
                // revert ONLY if override is currently set, so we never fight the game when off
                if (*(bool*)((uintptr_t)self + 0x61)) {
                    *(bool*)((uintptr_t)self + 0x61) = false; // overrideAcceleration
                    *(float*)((uintptr_t)self + 0xA0) = 1.0f; // speedMultiplier back to normal
                }
            }
        } @catch (...) {}
    }
    if (o_driveMove) o_driveMove(self, steering, accel, footbrake, handbrake);
}

// ================================================================
//  HOOK 7: PlateVariant.Change  [INSTANCE]
// ================================================================
static void (*o_plateVariantChange)(void*, struct PlateHolder) = NULL;
static void h_plateVariantChange(void* self, struct PlateHolder holder) {
    if (isCustomPlateEnabled && customPlateText[0] != '\0') {
        void* r = mkStr([NSString stringWithUTF8String:customPlateText]);
        if (r) holder.t = r;
    }
    if (o_plateVariantChange) o_plateVariantChange(self, holder);
}

// ================================================================
//  HOOK 8: ChatManager.Send  [INSTANCE]
// ================================================================
static void (*o_chatSendHook)(void*, void*) = NULL;
static void h_chatSendHook(void* self, void* msg) {
    if (isColorChatEnabled && msg) {
        NSString *orig = readStr(msg);
        if (orig.length > 0) {
            void* colored = mkStr([NSString stringWithFormat:@"<color=cyan><b>[FEW1N]</b></color> %@", orig]);
            if (colored) { if (o_chatSendHook) o_chatSendHook(self, colored); return; }
        }
    }
    if (o_chatSendHook) o_chatSendHook(self, msg);
}

// ================================================================
//  HOOK 9: HR_UI_RoomListLine.Connect  [INSTANCE]
//  password @ self+0x50 ; lobby passwordInput@+0x50, passwordOnConnectInput@+0x60
// ================================================================
static void (*o_roomConnect)(void*) = NULL;
static void h_roomConnect(void* self) {
    if (isBypassPasswordEnabled && self) {
        @try {
            void* roomPwd = *(void**)((uintptr_t)self + 0x50);
            if (lobbyGetInst && roomPwd) {
                void* lobbyMgr = lobbyGetInst();
                if (lobbyMgr && tmp_set_text) {
                    void* pwdOnConnect = *(void**)((uintptr_t)lobbyMgr + 0x60);
                    if (pwdOnConnect) tmp_set_text(pwdOnConnect, roomPwd);
                    void* pwdInput = *(void**)((uintptr_t)lobbyMgr + 0x50);
                    if (pwdInput) tmp_set_text(pwdInput, roomPwd);
                }
            }
        } @catch (...) {}
    }
    if (o_roomConnect) o_roomConnect(self);
}

// ================================================================
//  HOOK 10: PlayerManager.AddMoney  [INSTANCE]
// ================================================================
static void (*o_addMoney)(void*, int) = NULL;
static void h_addMoney(void* self, int amount) {
    if (isAddMoneyEnabled && amount > 0) amount = customMoneyAmount;
    if (o_addMoney) o_addMoney(self, amount);
}

// =============================================================
//  CYBER-GLASS PREMIUM MOD MENU UI
// =============================================================
#define C_BG     [UIColor colorWithRed:0.04 green:0.06 blue:0.10 alpha:0.65]
#define C_CARD   [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.06]
#define C_ON     [UIColor colorWithRed:0.0 green:1.0 blue:0.53 alpha:1.0]
#define C_OFF    [UIColor colorWithRed:0.22 green:0.25 blue:0.32 alpha:1.0]
#define C_RED    [UIColor colorWithRed:1.0 green:0.22 blue:0.38 alpha:1.0]
#define C_ACCENT [UIColor colorWithRed:0.52 green:0.22 blue:1.0 alpha:1.0]
#define C_GOLD   [UIColor colorWithRed:1.0 green:0.73 blue:0.15 alpha:1.0]
#define C_CYAN   [UIColor colorWithRed:0.0 green:0.90 blue:1.0 alpha:1.0]
#define C_TEXT   [UIColor colorWithWhite:1.0 alpha:0.95]
#define C_SUB    [UIColor colorWithWhite:1.0 alpha:0.50]

@interface FEW1NMenu : NSObject
@property (nonatomic, strong) UIButton *fab;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) NSMutableDictionary *toggleViews;
@property (nonatomic, strong) NSMutableDictionary *speedBtns;
@property (nonatomic, strong) UIButton *plateBtn;
@property (nonatomic, strong) UIButton *nameBtn;
@property (nonatomic, strong) UIButton *moneyBtn;
+ (instancetype)shared;
- (void)build;
- (void)forceApplySpeed;
@end

@implementation FEW1NMenu

+ (instancetype)shared {
    static FEW1NMenu *inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ inst = [[self alloc] init]; });
    return inst;
}

- (void)build {
    UIWindow *w = getKeyWindow();
    if (!w) {
        NSLog(@"[FEW1N] ERROR: No key window found for menu UI");
        // retry shortly - window may not be ready yet
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (!self.panel) [self build];
        });
        return;
    }
    if (self.panel) return; // already built
    self.toggleViews = [NSMutableDictionary new];
    self.speedBtns = [NSMutableDictionary new];

    // ===== FAB BUTTON =====
    self.fab = [UIButton buttonWithType:UIButtonTypeCustom];
    self.fab.frame = CGRectMake(16, 100, 56, 56);
    self.fab.layer.cornerRadius = 28;
    self.fab.clipsToBounds = NO;

    UIView *pulseRing = [[UIView alloc] initWithFrame:self.fab.bounds];
    pulseRing.layer.cornerRadius = 28;
    pulseRing.backgroundColor = C_CYAN;
    pulseRing.alpha = 0.4;
    pulseRing.userInteractionEnabled = NO;
    [self.fab addSubview:pulseRing];
    [UIView animateWithDuration:1.8 delay:0
                        options:UIViewAnimationOptionRepeat | UIViewAnimationOptionCurveEaseOut
                     animations:^{
        pulseRing.transform = CGAffineTransformMakeScale(1.6, 1.6);
        pulseRing.alpha = 0.0;
    } completion:nil];

    CAGradientLayer *fabGrad = [CAGradientLayer layer];
    fabGrad.frame = self.fab.bounds;
    fabGrad.cornerRadius = 28;
    fabGrad.colors = @[(id)C_CYAN.CGColor, (id)C_ACCENT.CGColor];
    fabGrad.startPoint = CGPointMake(0, 0);
    fabGrad.endPoint = CGPointMake(1, 1);
    [self.fab.layer insertSublayer:fabGrad atIndex:0];
    self.fab.layer.shadowColor = C_CYAN.CGColor;
    self.fab.layer.shadowOffset = CGSizeMake(0, 0);
    self.fab.layer.shadowRadius = 15;
    self.fab.layer.shadowOpacity = 0.8;

    UILabel *fabLbl = [[UILabel alloc] initWithFrame:self.fab.bounds];
    fabLbl.text = @"F1";
    fabLbl.textColor = [UIColor whiteColor];
    fabLbl.textAlignment = NSTextAlignmentCenter;
    fabLbl.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBlack];
    [self.fab addSubview:fabLbl];
    [self.fab addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pg1 = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
    [self.fab addGestureRecognizer:pg1];
    [w addSubview:self.fab];

    // ===== PANEL =====
    CGFloat pw = 310, ph = 640;
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(
        (w.bounds.size.width - pw) / 2,
        (w.bounds.size.height - ph) / 2,
        pw, ph)];
    self.panel.backgroundColor = C_BG;
    self.panel.layer.cornerRadius = 28;
    self.panel.layer.borderWidth = 1.5;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
    self.panel.layer.shadowColor = C_CYAN.CGColor;
    self.panel.layer.shadowOffset = CGSizeMake(0, 0);
    self.panel.layer.shadowRadius = 25;
    self.panel.layer.shadowOpacity = 0.4;
    self.panel.clipsToBounds = YES;
    self.panel.hidden = YES;
    self.panel.alpha = 0;
    self.panel.transform = CGAffineTransformMakeScale(0.85, 0.85);

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *blurV = [[UIVisualEffectView alloc] initWithEffect:blur];
    blurV.frame = self.panel.bounds;
    blurV.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.panel insertSubview:blurV atIndex:0];

    UIPanGestureRecognizer *pg2 = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
    [self.panel addGestureRecognizer:pg2];

    // ===== HEADER =====
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, pw, 60)];
    header.backgroundColor = [UIColor colorWithWhite:0 alpha:0.2];

    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, pw - 80, 26)];
    titleLbl.text = @"FEW1N MOD MENU";
    titleLbl.textColor = [UIColor whiteColor];
    titleLbl.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBlack];
    [header addSubview:titleLbl];

    UILabel *verLbl = [[UILabel alloc] initWithFrame:CGRectMake(16, 34, pw - 80, 16)];
    verLbl.text = [NSString stringWithFormat:@"v19.0 | Base: 0x%lX | H:%d F:%d",
                   (unsigned long)global_base, hookSuccessCount, hookFailCount];
    verLbl.textColor = C_CYAN;
    verLbl.font = [UIFont fontWithName:@"Menlo-Bold" size:8]
                  ?: [UIFont systemFontOfSize:8 weight:UIFontWeightBold];
    [header addSubview:verLbl];

    UIView *neonLine = [[UIView alloc] initWithFrame:CGRectMake(0, 58, pw, 2)];
    CAGradientLayer *lineGrad = [CAGradientLayer layer];
    lineGrad.frame = neonLine.bounds;
    lineGrad.colors = @[(id)C_CYAN.CGColor, (id)C_ACCENT.CGColor];
    lineGrad.startPoint = CGPointMake(0, 0.5);
    lineGrad.endPoint = CGPointMake(1, 0.5);
    [neonLine.layer addSublayer:lineGrad];
    [header addSubview:neonLine];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(pw - 46, 10, 36, 36);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor colorWithWhite:1 alpha:0.6] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightLight];
    [closeBtn addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:closeBtn];
    [self.panel addSubview:header];

    // ===== SCROLL VIEW =====
    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 60, pw, ph - 60)];
    self.scrollView.showsVerticalScrollIndicator = NO;
    [self.panel addSubview:self.scrollView];
    self.contentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, pw, 0)];
    [self.scrollView addSubview:self.contentView];

    CGFloat y = 12;

    // ======= HIZ KONTROLU =======
    y = [self addSectionHeader:@"⚡  HIZ KONTROLU" atY:y];
    UIView *speedRow = [[UIView alloc] initWithFrame:CGRectMake(12, y, pw - 24, 44)];
    speedRow.backgroundColor = C_CARD;
    speedRow.layer.cornerRadius = 12;
    speedRow.layer.borderWidth = 1;
    speedRow.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.04].CGColor;
    NSArray *speeds = @[@"1x", @"2.5x", @"5x", @"10x"];
    NSArray *speedVals = @[@1, @2, @5, @10];
    CGFloat bw = (pw - 24 - 10 * 3 - 16) / 4;
    for (int i = 0; i < 4; i++) {
        UIButton *sb = [UIButton buttonWithType:UIButtonTypeSystem];
        sb.frame = CGRectMake(8 + i * (bw + 10), 6, bw, 32);
        sb.layer.cornerRadius = 10;
        [sb setTitle:speeds[i] forState:UIControlStateNormal];
        sb.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
        sb.tag = [speedVals[i] intValue];
        [sb addTarget:self action:@selector(speedTap:) forControlEvents:UIControlEventTouchUpInside];
        [speedRow addSubview:sb];
        self.speedBtns[speedVals[i]] = sb;
    }
    [self.contentView addSubview:speedRow];
    y += 56;

    // ======= ARAC HILELERI =======
    y = [self addSectionHeader:@"\U0001F3CE  ARAC HILELERI" atY:y];
    y = [self addToggleCard:@"⚡  Super Hiz / Tam Gaz" sub:@"Oyuncu arabasi - tam ivme + hiz"  key:@"superaccel" atY:y action:@selector(tapSuperAccel)];
    y = [self addToggleCard:@"\U0001F527  Motor Gucu"       sub:@"RCCP tork 9999 - maks guc"        key:@"engine" atY:y action:@selector(tapEngine)];
    y = [self addToggleCard:@"\U0001F680  Maks Hiz"         sub:@"RCCP hiz limiti 999'a cikar"      key:@"maxspd" atY:y action:@selector(tapMaxSpeed)];
    y = [self addToggleCard:@"\U0001F4A8  Sonsuz Nitro"     sub:@"Nitro hic bitmesin"               key:@"nitro"  atY:y action:@selector(tapNitro)];

    // ======= PARA HILELERI =======
    y = [self addSectionHeader:@"\U0001F4B5  PARA HILELERI" atY:y];
    y = [self addToggleCard:@"\U0001F4B0  Otomatik Para Carpani" sub:@"Kazanci ozel miktara yukselt" key:@"moneytgl" atY:y action:@selector(tapAddMoney)];

    UIView *moneyCard = [[UIView alloc] initWithFrame:CGRectMake(12, y, pw - 24, 48)];
    moneyCard.backgroundColor = C_CARD;
    moneyCard.layer.cornerRadius = 12;
    moneyCard.layer.borderWidth = 1;
    moneyCard.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.04].CGColor;
    self.moneyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.moneyBtn.frame = CGRectMake(0, 0, pw - 24, 48);
    [self.moneyBtn setTitleColor:C_GOLD forState:UIControlStateNormal];
    self.moneyBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [self.moneyBtn addTarget:self action:@selector(addMoneyTap) forControlEvents:UIControlEventTouchUpInside];
    [moneyCard addSubview:self.moneyBtn];
    [self.contentView addSubview:moneyCard];
    y += 60;

    UIView *setAmtRow = [[UIView alloc] initWithFrame:CGRectMake(12, y, pw - 24, 44)];
    setAmtRow.backgroundColor = C_CARD;
    setAmtRow.layer.cornerRadius = 12;
    setAmtRow.layer.borderWidth = 1;
    setAmtRow.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.04].CGColor;
    UIButton *setAmt = [UIButton buttonWithType:UIButtonTypeSystem];
    setAmt.frame = CGRectMake(0, 0, pw - 24, 44);
    [setAmt setTitle:@"✏️  Para Miktarini Ayarla" forState:UIControlStateNormal];
    [setAmt setTitleColor:C_CYAN forState:UIControlStateNormal];
    setAmt.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [setAmt addTarget:self action:@selector(editMoneyAmount) forControlEvents:UIControlEventTouchUpInside];
    [setAmtRow addSubview:setAmt];
    [self.contentView addSubview:setAmtRow];
    y += 52;

    // ======= CHAT =======
    y = [self addSectionHeader:@"\U0001F4AC  CHAT" atY:y];
    y = [self addToggleCard:@"\U0001F3A8  Renkli Chat"  sub:@"[FEW1N] prefix + cyan"  key:@"colorchat" atY:y action:@selector(tapColorChat)];
    y = [self addToggleCard:@"\U0001F4E2  Chat Spam"    sub:@"50ms aralikla mesaj"     key:@"chatspam"  atY:y action:@selector(tapChatSpam)];

    UIView *spamRow = [[UIView alloc] initWithFrame:CGRectMake(12, y, pw - 24, 44)];
    spamRow.backgroundColor = C_CARD;
    spamRow.layer.cornerRadius = 12;
    spamRow.layer.borderWidth = 1;
    spamRow.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.04].CGColor;
    UIButton *editSpam = [UIButton buttonWithType:UIButtonTypeSystem];
    editSpam.frame = CGRectMake(0, 0, pw - 24, 44);
    [editSpam setTitle:@"✏️  Spam Yazisini Duzenle" forState:UIControlStateNormal];
    [editSpam setTitleColor:C_CYAN forState:UIControlStateNormal];
    editSpam.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [editSpam addTarget:self action:@selector(editSpam) forControlEvents:UIControlEventTouchUpInside];
    [spamRow addSubview:editSpam];
    [self.contentView addSubview:spamRow];
    y += 52;

    // ======= PLAKA =======
    y = [self addSectionHeader:@"\U0001F522  PLAKA" atY:y];
    UIView *plateCard = [[UIView alloc] initWithFrame:CGRectMake(12, y, pw - 24, 48)];
    plateCard.backgroundColor = C_CARD;
    plateCard.layer.cornerRadius = 12;
    plateCard.layer.borderWidth = 1;
    plateCard.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.04].CGColor;
    self.plateBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.plateBtn.frame = CGRectMake(0, 0, pw - 24, 48);
    [self.plateBtn setTitleColor:C_GOLD forState:UIControlStateNormal];
    self.plateBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [self.plateBtn addTarget:self action:@selector(editPlate) forControlEvents:UIControlEventTouchUpInside];
    [plateCard addSubview:self.plateBtn];
    [self.contentView addSubview:plateCard];
    y += 60;

    // ======= OYUNCU =======
    y = [self addSectionHeader:@"\U0001F4DB  OYUNCU" atY:y];
    UIView *nameCard = [[UIView alloc] initWithFrame:CGRectMake(12, y, pw - 24, 48)];
    nameCard.backgroundColor = C_CARD;
    nameCard.layer.cornerRadius = 12;
    nameCard.layer.borderWidth = 1;
    nameCard.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.04].CGColor;
    self.nameBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.nameBtn.frame = CGRectMake(0, 0, pw - 24, 48);
    [self.nameBtn setTitle:@"\U0001F4DB  Isim Degistir" forState:UIControlStateNormal];
    [self.nameBtn setTitleColor:C_CYAN forState:UIControlStateNormal];
    self.nameBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [self.nameBtn addTarget:self action:@selector(changeName) forControlEvents:UIControlEventTouchUpInside];
    [nameCard addSubview:self.nameBtn];
    [self.contentView addSubview:nameCard];
    y += 60;

    // ======= ODA =======
    y = [self addSectionHeader:@"\U0001F511  ODA" atY:y];
    y = [self addToggleCard:@"\U0001F513  Sifre Kirici" sub:@"Sifreli odalara gir" key:@"bypass" atY:y action:@selector(tapBypass)];

    // ===== STATUS BAR =====
    UIView *statusCard = [[UIView alloc] initWithFrame:CGRectMake(12, y, pw - 24, 36)];
    UILabel *statusLbl = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, pw - 24, 36)];
    if (global_base != 0) {
        statusCard.backgroundColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.53 alpha:0.08];
        statusCard.layer.borderColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.53 alpha:0.2].CGColor;
        statusLbl.text = [NSString stringWithFormat:@"✅ Hooklar aktif (%d/%d)",
                          hookSuccessCount, hookSuccessCount + hookFailCount];
        statusLbl.textColor = C_ON;
    } else {
        statusCard.backgroundColor = [UIColor colorWithRed:1.0 green:0.22 blue:0.38 alpha:0.08];
        statusCard.layer.borderColor = [UIColor colorWithRed:1.0 green:0.22 blue:0.38 alpha:0.2].CGColor;
        statusLbl.text = @"❌ Framework bulunamadi";
        statusLbl.textColor = C_RED;
    }
    statusCard.layer.cornerRadius = 10;
    statusCard.layer.borderWidth = 1;
    statusLbl.textAlignment = NSTextAlignmentCenter;
    statusLbl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    [statusCard addSubview:statusLbl];
    [self.contentView addSubview:statusCard];
    y += 44;

    UILabel *foot = [[UILabel alloc] initWithFrame:CGRectMake(0, y + 4, pw, 24)];
    foot.text = @"made by few1n \U0001F5A4";
    foot.textColor = [UIColor colorWithWhite:0.3 alpha:1];
    foot.textAlignment = NSTextAlignmentCenter;
    foot.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    [self.contentView addSubview:foot];
    y += 36;

    self.contentView.frame = CGRectMake(0, 0, pw, y);
    self.scrollView.contentSize = CGSizeMake(pw, y);
    [w addSubview:self.panel];
    [self refreshUI];

    if (speedEnforceTimer) { [speedEnforceTimer invalidate]; speedEnforceTimer = nil; }
    speedEnforceTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                         target:self
                                                       selector:@selector(forceApplySpeed)
                                                       userInfo:nil
                                                        repeats:YES];

    // Restart chat spam timer if it was persisted ON
    if (isSpamEnabled && !spamTimer) {
        spamTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 target:self
                                                   selector:@selector(fireSpam) userInfo:nil repeats:YES];
    }
}

// ===== UI HELPERS =====
- (CGFloat)addSectionHeader:(NSString*)text atY:(CGFloat)y {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 270, 20)];
    l.text = text;
    l.textColor = C_CYAN;
    l.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBlack];
    [self.contentView addSubview:l];
    return y + 26;
}

- (CGFloat)addToggleCard:(NSString*)title sub:(NSString*)sub key:(NSString*)key atY:(CGFloat)y action:(SEL)action {
    CGFloat pw = self.panel.bounds.size.width;
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(12, y, pw - 24, 56)];
    card.backgroundColor = C_CARD;
    card.layer.cornerRadius = 14;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.04].CGColor;

    UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, pw - 100, 22)];
    tl.text = title;
    tl.textColor = C_TEXT;
    tl.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [card addSubview:tl];

    UILabel *sl = [[UILabel alloc] initWithFrame:CGRectMake(16, 30, pw - 100, 16)];
    sl.text = sub;
    sl.textColor = C_SUB;
    sl.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    [card addSubview:sl];

    UIView *pill = [[UIView alloc] initWithFrame:CGRectMake(pw - 24 - 60, 15, 44, 24)];
    pill.backgroundColor = C_OFF;
    pill.layer.cornerRadius = 12;
    pill.tag = 100;

    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(2, 2, 20, 20)];
    dot.backgroundColor = [UIColor whiteColor];
    dot.layer.cornerRadius = 10;
    dot.tag = 101;
    dot.layer.shadowColor = [UIColor blackColor].CGColor;
    dot.layer.shadowOffset = CGSizeMake(0, 1);
    dot.layer.shadowRadius = 2;
    dot.layer.shadowOpacity = 0.3;
    [pill addSubview:dot];
    [card addSubview:pill];

    UIButton *tapBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    tapBtn.frame = card.bounds;
    [tapBtn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:tapBtn];

    [self.contentView addSubview:card];
    self.toggleViews[key] = pill;
    return y + 64;
}

- (void)setToggle:(NSString*)key on:(BOOL)on {
    UIView *pill = self.toggleViews[key];
    if (!pill) return;
    UIView *dot = [pill viewWithTag:101];
    if (!dot) return;
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.6
          initialSpringVelocity:0.5 options:0 animations:^{
        pill.backgroundColor = on ? C_ON : C_OFF;
        dot.frame = on ? CGRectMake(22, 2, 20, 20) : CGRectMake(2, 2, 20, 20);
        if (on) {
            pill.layer.shadowColor = C_ON.CGColor;
            pill.layer.shadowOffset = CGSizeMake(0, 0);
            pill.layer.shadowRadius = 8;
            pill.layer.shadowOpacity = 0.6;
        } else {
            pill.layer.shadowOpacity = 0.0;
        }
    } completion:nil];
}

- (NSString*)moneyLabel {
    // read live money if available
    if (playerManagerGetInst && pm_getMoney) {
        @try {
            void* pm = playerManagerGetInst();
            if (pm) {
                int m = pm_getMoney(pm);
                return [NSString stringWithFormat:@"\U0001F4B5  Para Ekle (%@) | Bakiye: %d",
                        [self shortNum:customMoneyAmount], m];
            }
        } @catch (...) {}
    }
    return [NSString stringWithFormat:@"\U0001F4B5  Tek Tikla %@ Para Ekle", [self shortNum:customMoneyAmount]];
}

- (NSString*)shortNum:(long)n {
    if (n >= 1000000000) return [NSString stringWithFormat:@"%.1fB", n / 1000000000.0];
    if (n >= 1000000)    return [NSString stringWithFormat:@"%ldM", n / 1000000];
    if (n >= 1000)       return [NSString stringWithFormat:@"%ldK", n / 1000];
    return [NSString stringWithFormat:@"%ld", n];
}

- (void)refreshUI {
    for (NSNumber *val in self.speedBtns) {
        UIButton *b = self.speedBtns[val];
        BOOL active = (speedMode == val.intValue);
        b.backgroundColor = active ? C_ON : [UIColor colorWithWhite:0.18 alpha:1];
        [b setTitleColor:active ? [UIColor blackColor] : C_TEXT forState:UIControlStateNormal];
        if (active) {
            b.layer.shadowColor = C_ON.CGColor;
            b.layer.shadowRadius = 6;
            b.layer.shadowOpacity = 0.5;
            b.layer.shadowOffset = CGSizeMake(0, 0);
        } else {
            b.layer.shadowOpacity = 0;
        }
    }
    [self setToggle:@"superaccel" on:isSuperAccelEnabled];
    [self setToggle:@"engine"     on:isEnginePowerEnabled];
    [self setToggle:@"maxspd"     on:isMaxSpeedEnabled];
    [self setToggle:@"nitro"      on:isInfiniteNitroEnabled];
    [self setToggle:@"colorchat"  on:isColorChatEnabled];
    [self setToggle:@"chatspam"   on:isSpamEnabled];
    [self setToggle:@"bypass"     on:isBypassPasswordEnabled];
    [self setToggle:@"moneytgl"   on:isAddMoneyEnabled];

    [self.moneyBtn setTitle:[self moneyLabel] forState:UIControlStateNormal];
    [self.moneyBtn setTitleColor:C_GOLD forState:UIControlStateNormal];

    if (isCustomPlateEnabled) {
        [self.plateBtn setTitle:[NSString stringWithFormat:@"\U0001F4DD  Plaka: %s ✅", customPlateText]
                       forState:UIControlStateNormal];
        [self.plateBtn setTitleColor:C_ON forState:UIControlStateNormal];
    } else {
        [self.plateBtn setTitle:@"\U0001F4DD  Ozel Plaka Ayarla" forState:UIControlStateNormal];
        [self.plateBtn setTitleColor:C_GOLD forState:UIControlStateNormal];
    }
}

// ===== ACTIONS =====
- (void)toggle {
    BOOL showing = self.panel.hidden;
    if (showing) {
        [self refreshUI]; // refresh live balance each open
        self.panel.hidden = NO;
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.8
              initialSpringVelocity:0.5 options:0 animations:^{
            self.panel.alpha = 1;
            self.panel.transform = CGAffineTransformIdentity;
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.2 animations:^{
            self.panel.alpha = 0;
            self.panel.transform = CGAffineTransformMakeScale(0.9, 0.9);
        } completion:^(BOOL finished) {
            self.panel.hidden = YES;
        }];
    }
}

- (void)drag:(UIPanGestureRecognizer*)g {
    UIView *v = g.view;
    if (!v) return;
    CGPoint t = [g translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [g setTranslation:CGPointZero inView:v.superview];
}

- (void)forceApplySpeed {
    if (!o_setTimeScale) return;
    float v = 1.0f;
    if (speedMode == 2)       v = 2.5f;
    else if (speedMode == 5)  v = 5.0f;
    else if (speedMode == 10) v = 10.0f;
    o_setTimeScale(v);
}

- (void)speedTap:(UIButton*)s {
    speedMode = (int)s.tag;
    saveInt(@"speedMode", speedMode);
    [self refreshUI];
    [self forceApplySpeed];
}

- (void)tapSuperAccel { isSuperAccelEnabled     = !isSuperAccelEnabled;     saveBool(@"superaccel", isSuperAccelEnabled); [self refreshUI]; }
- (void)tapEngine     { isEnginePowerEnabled    = !isEnginePowerEnabled;    saveBool(@"engine", isEnginePowerEnabled);    [self refreshUI]; }
- (void)tapMaxSpeed   { isMaxSpeedEnabled       = !isMaxSpeedEnabled;       saveBool(@"maxspd", isMaxSpeedEnabled);       [self refreshUI]; }
- (void)tapNitro      { isInfiniteNitroEnabled  = !isInfiniteNitroEnabled;  saveBool(@"nitro", isInfiniteNitroEnabled);   [self refreshUI]; }
- (void)tapColorChat  { isColorChatEnabled      = !isColorChatEnabled;      saveBool(@"colorchat", isColorChatEnabled);   [self refreshUI]; }
- (void)tapBypass     { isBypassPasswordEnabled = !isBypassPasswordEnabled; saveBool(@"bypass", isBypassPasswordEnabled); [self refreshUI]; }
- (void)tapAddMoney   { isAddMoneyEnabled       = !isAddMoneyEnabled;       saveBool(@"moneytgl", isAddMoneyEnabled);     [self refreshUI]; }

- (void)tapChatSpam {
    isSpamEnabled = !isSpamEnabled;
    saveBool(@"chatspam", isSpamEnabled);
    if (spamTimer) { [spamTimer invalidate]; spamTimer = nil; }
    if (isSpamEnabled) {
        spamTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 target:self
                                                   selector:@selector(fireSpam) userInfo:nil repeats:YES];
    }
    [self refreshUI];
}

- (void)addMoneyTap {
    if (playerManagerGetInst && pm_addMoney) {
        @try {
            void* pm = playerManagerGetInst();
            if (pm) {
                pm_addMoney(pm, customMoneyAmount);
                [self.moneyBtn setTitle:[NSString stringWithFormat:@"\U0001F4B5 %@ Eklendi! ✅", [self shortNum:customMoneyAmount]]
                               forState:UIControlStateNormal];
                [self.moneyBtn setTitleColor:C_ON forState:UIControlStateNormal];
            } else {
                [self.moneyBtn setTitle:@"\U0001F4B5 Oyuna Giris Yapin!" forState:UIControlStateNormal];
                [self.moneyBtn setTitleColor:C_RED forState:UIControlStateNormal];
            }
        } @catch (...) {
            [self.moneyBtn setTitle:@"\U0001F4B5 Hata olustu!" forState:UIControlStateNormal];
            [self.moneyBtn setTitleColor:C_RED forState:UIControlStateNormal];
        }
    } else {
        [self.moneyBtn setTitle:@"\U0001F4B5 Hata: RVA bulunamadi" forState:UIControlStateNormal];
        [self.moneyBtn setTitleColor:C_RED forState:UIControlStateNormal];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self refreshUI];
    });
}

- (void)fireSpam {
    if (!chatGetInst || !chatSend) return;
    @try {
        void* mgr = chatGetInst();
        if (!mgr) return;
        void* s = mkStr([NSString stringWithUTF8String:chatSpamText]);
        if (s) chatSend(mgr, s);
    } @catch (...) {}
}

- (void)changeName {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"\U0001F4DB Isim Degistir"
                                                               message:@"Yeni ismin:"
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"FEW1N";
        tf.clearButtonMode = UITextFieldViewModeAlways;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Degistir" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *name = ac.textFields.firstObject.text;
        if (name.length > 0 && pn_setNickName) {
            void* nameStr = mkStr(name);
            if (nameStr) {
                pn_setNickName(nameStr);
                if (playerManagerGetInst && pm_updateNicknameInternal) {
                    @try {
                        void* pm = playerManagerGetInst();
                        if (pm) pm_updateNicknameInternal(pm, nameStr);
                    } @catch (...) {}
                }
                [self.nameBtn setTitle:[NSString stringWithFormat:@"\U0001F4DB  Isim: %@ ✅", name]
                              forState:UIControlStateNormal];
                [self.nameBtn setTitleColor:C_ON forState:UIControlStateNormal];
            }
        }
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Iptal" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:ac];
}

- (void)editMoneyAmount {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"\U0001F4B5 Para Miktari"
                                                               message:@"Eklenecek para miktari:"
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.text = [NSString stringWithFormat:@"%d", customMoneyAmount];
        tf.clearButtonMode = UITextFieldViewModeAlways;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Kaydet" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *t = ac.textFields.firstObject.text;
        long long v = [t longLongValue];
        if (v > 0) {
            if (v > 2000000000LL) v = 2000000000LL; // clamp to int32 range
            customMoneyAmount = (int)v;
            saveInt(@"moneyAmount", customMoneyAmount);
            [self refreshUI];
        }
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Iptal" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:ac];
}

- (void)editSpam {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"\U0001F4AC Spam Yazisi"
                                                               message:nil
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = [NSString stringWithUTF8String:chatSpamText];
        tf.clearButtonMode = UITextFieldViewModeAlways;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Kaydet" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *t = ac.textFields.firstObject.text;
        if (t.length > 0) {
            strncpy(chatSpamText, t.UTF8String, sizeof(chatSpamText) - 1);
            chatSpamText[sizeof(chatSpamText) - 1] = '\0';
            saveStr(@"spamText", t);
        }
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Iptal" style:UIAlertActionStyleCancel handler:nil]];
    [self presentAlert:ac];
}

- (void)editPlate {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"\U0001F522 Ozel Plaka"
                                                               message:@"Plakada gorunecek yazi:"
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"FEW1N";
        if (isCustomPlateEnabled) tf.text = [NSString stringWithUTF8String:customPlateText];
        tf.clearButtonMode = UITextFieldViewModeAlways;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Uygula" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *t = ac.textFields.firstObject.text;
        if (t.length > 0) {
            strncpy(customPlateText, t.UTF8String, sizeof(customPlateText) - 1);
            customPlateText[sizeof(customPlateText) - 1] = '\0';
            isCustomPlateEnabled = true;
            saveStr(@"plateText", t);
            saveBool(@"plateEnabled", true);
            [self refreshUI];
        }
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Kapat" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
        isCustomPlateEnabled = false;
        saveBool(@"plateEnabled", false);
        [self refreshUI];
    }]];
    [self presentAlert:ac];
}

- (void)presentAlert:(UIAlertController*)ac {
    UIWindow *w = getKeyWindow();
    if (!w) return;
    UIViewController *vc = w.rootViewController;
    if (!vc) return;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if (vc.isBeingDismissed || vc.isBeingPresented) return;
    [vc presentViewController:ac animated:YES completion:nil];
}

@end

// =============================================================
//  Restore persisted settings into globals
// =============================================================
static void restoreSettings(void) {
    speedMode               = loadInt(@"speedMode", 1);
    isSuperAccelEnabled     = loadBool(@"superaccel", false);
    isEnginePowerEnabled    = loadBool(@"engine", false);
    isMaxSpeedEnabled       = loadBool(@"maxspd", false);
    isInfiniteNitroEnabled  = loadBool(@"nitro", false);
    isColorChatEnabled      = loadBool(@"colorchat", false);
    isSpamEnabled           = loadBool(@"chatspam", false);
    isBypassPasswordEnabled = loadBool(@"bypass", true);
    isAddMoneyEnabled       = loadBool(@"moneytgl", false);
    isCustomPlateEnabled    = loadBool(@"plateEnabled", false);
    customMoneyAmount       = loadInt(@"moneyAmount", 100000000);

    NSString* pt = loadStr(@"plateText", @"FEW1N");
    strncpy(customPlateText, pt.UTF8String, sizeof(customPlateText) - 1);
    customPlateText[sizeof(customPlateText) - 1] = '\0';

    NSString* st = loadStr(@"spamText", @"FEW1N MOD MENU!");
    strncpy(chatSpamText, st.UTF8String, sizeof(chatSpamText) - 1);
    chatSpamText[sizeof(chatSpamText) - 1] = '\0';
}

// =============================================================
//  ASLR Base Address Extraction
// =============================================================
static uintptr_t GetUnityFrameworkBase(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *image_name = _dyld_get_image_name(i);
        if (!image_name) continue;
        if (strstr(image_name, "UnityFramework")) {
            return _dyld_get_image_vmaddr_slide(i);
        }
    }
    // Fallback: main executable (sideload with embedded UF)
    for (uint32_t i = 0; i < count; i++) {
        const char *image_name = _dyld_get_image_name(i);
        if (!image_name) continue;
        if (strstr(image_name, "DreamRoadMultiplayer.app/DreamRoadMultiplayer")) {
            return _dyld_get_image_vmaddr_slide(i);
        }
    }
    return 0;
}

// =============================================================
//  Install all hooks + resolve pointers  (runs once, on main queue)
// =============================================================
static void InstallEverything(uintptr_t b) {
    global_base = b;
    NSLog(@"[FEW1N] Base address: 0x%lX", (unsigned long)b);

    // Resolve function pointers
    chatGetInst               = (void*(*)(void))(b + 0x31A6234);
    chatSend                  = (void(*)(void*, void*))(b + 0x31A6338);
    tmp_set_text              = (void(*)(void*, void*))(b + 0x65F4F8C);
    pn_setNickName            = (void(*)(void*))(b + 0x5933C4C);
    lobbyGetInst              = (void*(*)(void))(b + 0x54A81D4);
    playerManagerGetInst      = (void*(*)(void))(b + 0x5A2E138);
    pm_updateNicknameInternal = (void(*)(void*, void*))(b + 0x5A3E0EC);
    pm_getMoney               = (int(*)(void*))(b + 0x5A43784);
    pn_setSendRate            = (void(*)(int))(b + 0x59348E8);
    pn_setSerializationRate   = (void(*)(int))(b + 0x5934A48);
    pm_addMoney               = (void(*)(void*, int))(b + 0x5A43D44);

    NSLog(@"[FEW1N] Function pointers resolved. Installing hooks...");

    safeHook((void*)(b + 0x6771BDC), (void*)h_setTimeScale,       (void**)&o_setTimeScale,       "Time.set_timeScale");
    safeHook((void*)(b + 0x5938B50), (void*)h_closeConnection,    (void**)&o_closeConnection,    "PhotonNetwork.CloseConnection");
    safeHook((void*)(b + 0x59C4ED8), (void*)h_rccp,               (void**)&o_rccp,               "RCCP_CarController.Update");
    safeHook((void*)(b + 0x54CFF50), (void*)h_getNitro,           (void**)&o_getNitro,           "CarNitro.get_nitroAmount");
    safeHook((void*)(b + 0x54CFF58), (void*)h_setNitro,           (void**)&o_setNitro,           "CarNitro.set_nitroAmount");
    safeHook((void*)(b + 0x54CCBDC), (void*)h_driveMove,          (void**)&o_driveMove,          "CarDriveSystem.Move");
    safeHook((void*)(b + 0x54EA338), (void*)h_plateVariantChange, (void**)&o_plateVariantChange, "PlateVariant.Change");
    safeHook((void*)(b + 0x31A6338), (void*)h_chatSendHook,       (void**)&o_chatSendHook,       "ChatManager.Send");
    safeHook((void*)(b + 0x54B3430), (void*)h_roomConnect,        (void**)&o_roomConnect,        "HR_UI_RoomListLine.Connect");
    safeHook((void*)(b + 0x5A43D44), (void*)h_addMoney,           (void**)&o_addMoney,           "PlayerManager.AddMoney");

    NSLog(@"[FEW1N] Hook installation complete: %d OK, %d FAILED", hookSuccessCount, hookFailCount);

    [[FEW1NMenu shared] build];
    NSLog(@"[FEW1N] Menu UI built successfully.");
}

// =============================================================
//  CONSTRUCTOR  -  robust polling for UnityFramework
// =============================================================
%ctor {
    NSLog(@"[FEW1N] v19.0 constructor triggered at %@", [NSDate date]);
    restoreSettings();

    __block int attempts = 0;
    __block void (^poll)(void) = nil;
    poll = ^{
        attempts++;
        uintptr_t b = GetUnityFrameworkBase();
        if (b != 0) {
            NSLog(@"[FEW1N] UnityFramework found on attempt %d.", attempts);
            InstallEverything(b);
            poll = nil;
            return;
        }
        if (attempts >= 80) { // ~40s worth of 0.5s polls
            NSLog(@"[FEW1N] FATAL: UnityFramework not found after %d attempts. Showing menu without hooks.", attempts);
            [[FEW1NMenu shared] build];
            poll = nil;
            return;
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), poll);
    };
    // give the app a moment to start loading UnityFramework, then begin polling
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), poll);
}
