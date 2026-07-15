#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <substrate.h>
#include <mach-o/dyld.h>
#include <string.h>
#include <dlfcn.h>

// ============================================================
//  v21.0 - FEW1N MOD MENU
//  DreamRoadMultiplayer | Unity 6 (6000.3.0b1) | Metadata v39
// ------------------------------------------------------------
//  ONEMLI: Oyun Unity 6'ya guncellendi + isim obfuscation eklendi.
//  Tum offsetler YENI dump.cs'ten (metadata v39) cikarilip, uye
//  isimleri karisik oldugu icin YAPIYA/imzaya gore eslendi.
// ============================================================
//  OFFSET TABLE (yeni Unity6 dump, dogrulandi)
// ------------------------------------------------------------
// Time.set_timeScale(float)                -> 0x6771918
// PhotonNetwork.CloseConnection(Player)    -> 0x5938844
// PhotonNetwork.set_NickName(string)       -> 0x5933940
// ChatManager.get_Instance()               -> 0x31A6168
// ChatManager.Send(string)                 -> 0x31A626C
// CarNitro.get_nitroAmount() [obf: fda]    -> 0x54CFE14
// CarNitro.set_nitroAmount(float)[obf: fdb]-> 0x54CFE1C
// CarDriveSystem.Move(f,f,f,f) [obf: fca]  -> 0x54CCAA0
// PlateVariant.Change(PlateHolder)[obf:gal]-> 0x54EA1FC   (c@0x0, t@0x8)
// HR_UI_RoomListLine.Connect() [obf: elv]  -> 0x54B32F4   (password @ self+0x50)
// HR_PhotonLobbyManager.get_Instance()[eke]-> 0x54A8098   (passwordInput@+0x50, passwordOnConnectInput@+0x60)
// TMP_InputField.set_text(string)          -> 0x65F4CC8
// PlayerManager.get_Instance() [obf: ggn]  -> 0x5A2DE20
// PlayerManager.get_Money()    [obf: ggx]  -> 0x5A4346C
// PlayerManager.AddMoney(int)  [obf: ghm]  -> 0x5A43A2C
// PlayerManager.SyncWithServer()[obf: ghj] -> 0x5A2DF80
// PlayerManager.UpdateNicknameInternal(str)[ghn] -> 0x5A3DDD4
// ============================================================

struct PlateHolder { void* c; void* t; };   // c@0x0, t@0x8

// ===== PERSIST =====
#define DEF_SUITE @"com.few1n.dreamroadmod"
static NSUserDefaults* defs(void) {
    static NSUserDefaults* d = nil;
    if (!d) d = [[NSUserDefaults alloc] initWithSuiteName:DEF_SUITE] ?: [NSUserDefaults standardUserDefaults];
    return d;
}
static void saveBool(NSString* k, bool v)    { [defs() setBool:v forKey:k]; }
static bool loadBool(NSString* k, bool def)   { return [defs() objectForKey:k] ? [defs() boolForKey:k] : def; }
static void saveInt(NSString* k, int v)       { [defs() setInteger:v forKey:k]; }
static int  loadInt(NSString* k, int def)     { return [defs() objectForKey:k] ? (int)[defs() integerForKey:k] : def; }
static void saveStr(NSString* k, NSString* v) { if (v) [defs() setObject:v forKey:k]; }
static NSString* loadStr(NSString* k, NSString* def) { NSString* s=[defs() stringForKey:k]; return s?:def; }

// ===== STATE =====
static int  speedMode = 1;
static bool isInfiniteNitroEnabled = false;
static bool isColorChatEnabled = false;
static bool isSpamEnabled = false;
static bool isBypassPasswordEnabled = true;
static bool isCustomPlateEnabled = false;
static bool isAutoMoneyEnabled = false;
static char customPlateText[64] = "FEW1N";
static char chatSpamText[128] = "FEW1N MOD MENU!";
static int  customMoneyAmount = 100000000;

static NSTimer *spamTimer = nil;
static NSTimer *tickTimer = nil;

// ===== IL2CPP HELPERS =====
static void* (*cached_il2cpp_string_new)(const char*) = NULL;
static uintptr_t global_base = 0;
static int hookSuccessCount = 0;
static int hookFailCount = 0;

// ===== EKRAN LOGU (menude gosterilir) =====
static NSMutableArray<NSString*>* gLog = nil;
static void FLog(NSString* line) {
    if (!line) return;
    NSLog(@"[FEW1N] %@", line);
    if (!gLog) gLog = [NSMutableArray new];
    [gLog addObject:line];
    if (gLog.count > 100) [gLog removeObjectAtIndex:0];
}

static void* mkStr(NSString* s) {
    if (!cached_il2cpp_string_new)
        cached_il2cpp_string_new = (void*(*)(const char*))dlsym(RTLD_DEFAULT, "il2cpp_string_new");
    if (!cached_il2cpp_string_new || !s) return NULL;
    return cached_il2cpp_string_new(s.UTF8String);
}
static NSString* readStr(void* il2s) {
    if (!il2s) return @"";
    @try {
        int32_t len = *(int32_t*)((uintptr_t)il2s + 0x10);
        if (len <= 0 || len > 4096) return @"";
        return [NSString stringWithCharacters:(unichar*)((uintptr_t)il2s + 0x14) length:len];
    } @catch (...) { return @""; }
}
static void safeHook(void* target, void* replacement, void** original, const char* name) {
    NSString* nm = [NSString stringWithUTF8String:name];
    if (!target) { FLog([@"SKIP (NULL) " stringByAppendingString:nm]); hookFailCount++; return; }
    MSHookFunction(target, replacement, original);
    FLog([NSString stringWithFormat:@"OK  %@", nm]);
    hookSuccessCount++;
}
static UIWindow* getKeyWindow(void) {
    if (@available(iOS 15.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *ws = (UIWindowScene *)scene;
                for (UIWindow *win in ws.windows) if (win.isKeyWindow) return win;
                if (ws.windows.count > 0) return ws.windows.firstObject;
            }
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIWindow *w = [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
    if (w) return w;
    NSArray<UIWindow *> *wins = [UIApplication sharedApplication].windows;
    for (UIWindow *win in wins) if (win.isKeyWindow) return win;
    return wins.firstObject;
}

// ===== FUNCTION POINTERS =====
static void* (*chatGetInst)(void) = NULL;
static void  (*chatSend)(void* self, void* msg) = NULL;
static void  (*tmp_set_text)(void* self, void* msg) = NULL;
static void  (*pn_setNickName)(void* name) = NULL;
static void* (*lobbyGetInst)(void) = NULL;
static void* (*playerManagerGetInst)(void) = NULL;
static void  (*pm_updateNicknameInternal)(void* self, void* newName) = NULL;
static int   (*pm_getMoney)(void* self) = NULL;
static void  (*pm_syncWithServer)(void* self) = NULL;
static void  (*pm_addMoney)(void* self, int amount) = NULL;

// ===== TIME SCALE =====
static void (*o_setTimeScale)(float) = NULL;
static inline float targetScale(void) {
    if (speedMode == 2) return 2.0f;
    if (speedMode == 3) return 3.0f;
    if (speedMode == 5) return 5.0f;
    return 1.0f;
}
static inline void enforceScale(void) {
    if (o_setTimeScale && speedMode > 1) o_setTimeScale(targetScale());
}
static void h_setTimeScale(float v) {
    if (speedMode > 1) v = targetScale();
    if (o_setTimeScale) o_setTimeScale(v);
}

// ===== ANTI-KICK =====
static bool (*o_closeConnection)(void*) = NULL;
static bool h_closeConnection(void* kickPlayer) { return false; }

// ===== INFINITE NITRO =====
static float (*o_getNitro)(void*) = NULL;
static float h_getNitro(void* self) {
    if (isInfiniteNitroEnabled) return 1.0f;
    return o_getNitro ? o_getNitro(self) : 0.0f;
}
static void (*o_setNitro)(void*, float) = NULL;
static void h_setNitro(void* self, float value) {
    if (isInfiniteNitroEnabled) value = 1.0f;
    if (o_setNitro) o_setNitro(self, value);
}

// ===== CarDriveSystem.Move : per-frame timeScale zorlama =====
static void (*o_driveMove)(void*, float, float, float, float) = NULL;
static void h_driveMove(void* self, float a, float b, float c, float d) {
    enforceScale();
    if (o_driveMove) o_driveMove(self, a, b, c, d);
}

// ===== CUSTOM PLATE =====
static void (*o_plateChange)(void*, struct PlateHolder) = NULL;
static void h_plateChange(void* self, struct PlateHolder holder) {
    if (isCustomPlateEnabled && customPlateText[0] != '\0') {
        void* r = mkStr([NSString stringWithUTF8String:customPlateText]);
        if (r) holder.t = r;
    }
    if (o_plateChange) o_plateChange(self, holder);
}

// ===== CHAT =====
static void (*o_chatSend)(void*, void*) = NULL;
static void h_chatSend(void* self, void* msg) {
    if (isColorChatEnabled && msg) {
        NSString *orig = readStr(msg);
        if (orig.length > 0) {
            void* colored = mkStr([NSString stringWithFormat:@"<color=cyan><b>[FEW1N]</b></color> %@", orig]);
            if (colored) { if (o_chatSend) o_chatSend(self, colored); return; }
        }
    }
    if (o_chatSend) o_chatSend(self, msg);
}

// ===== PASSWORD BYPASS =====
static void (*o_roomConnect)(void*) = NULL;
static void h_roomConnect(void* self) {
    if (isBypassPasswordEnabled && self) {
        @try {
            void* roomPwd = *(void**)((uintptr_t)self + 0x50);   // RoomListLine.password
            if (lobbyGetInst && roomPwd) {
                void* lobby = lobbyGetInst();
                if (lobby && tmp_set_text) {
                    void* pOnConnect = *(void**)((uintptr_t)lobby + 0x60);
                    if (pOnConnect) tmp_set_text(pOnConnect, roomPwd);
                    void* pInput = *(void**)((uintptr_t)lobby + 0x50);
                    if (pInput) tmp_set_text(pInput, roomPwd);
                }
            }
        } @catch (...) {}
    }
    if (o_roomConnect) o_roomConnect(self);
}

// ===== MONEY =====
static void (*o_addMoney)(void*, int) = NULL;
static void h_addMoney(void* self, int amount) {
    if (isAutoMoneyEnabled && amount > 0) amount = customMoneyAmount;
    if (o_addMoney) o_addMoney(self, amount);
}

// =============================================================
//  UI
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
@property (nonatomic, strong) UIView *logOverlay;
@property (nonatomic, strong) UITextView *logText;
+ (instancetype)shared;
- (void)build;
@end

@implementation FEW1NMenu

+ (instancetype)shared {
    static FEW1NMenu *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[self alloc] init]; });
    return inst;
}

- (void)build {
    UIWindow *w = getKeyWindow();
    if (!w) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (!self.panel) [self build];
        });
        return;
    }
    if (self.panel) return;
    self.toggleViews = [NSMutableDictionary new];
    self.speedBtns = [NSMutableDictionary new];

    // FAB
    self.fab = [UIButton buttonWithType:UIButtonTypeCustom];
    self.fab.frame = CGRectMake(16, 100, 56, 56);
    self.fab.layer.cornerRadius = 28;
    self.fab.clipsToBounds = NO;
    UIView *pulse = [[UIView alloc] initWithFrame:self.fab.bounds];
    pulse.layer.cornerRadius = 28; pulse.backgroundColor = C_CYAN;
    pulse.alpha = 0.4; pulse.userInteractionEnabled = NO;
    [self.fab addSubview:pulse];
    [UIView animateWithDuration:1.8 delay:0 options:UIViewAnimationOptionRepeat|UIViewAnimationOptionCurveEaseOut animations:^{
        pulse.transform = CGAffineTransformMakeScale(1.6,1.6); pulse.alpha = 0.0;
    } completion:nil];
    CAGradientLayer *fg = [CAGradientLayer layer];
    fg.frame = self.fab.bounds; fg.cornerRadius = 28;
    fg.colors = @[(id)C_CYAN.CGColor, (id)C_ACCENT.CGColor];
    fg.startPoint = CGPointMake(0,0); fg.endPoint = CGPointMake(1,1);
    [self.fab.layer insertSublayer:fg atIndex:0];
    self.fab.layer.shadowColor = C_CYAN.CGColor;
    self.fab.layer.shadowRadius = 15; self.fab.layer.shadowOpacity = 0.8;
    self.fab.layer.shadowOffset = CGSizeMake(0,0);
    UILabel *fl = [[UILabel alloc] initWithFrame:self.fab.bounds];
    fl.text = @"F1"; fl.textColor = [UIColor whiteColor];
    fl.textAlignment = NSTextAlignmentCenter;
    fl.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBlack];
    [self.fab addSubview:fl];
    [self.fab addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [self.fab addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];
    [w addSubview:self.fab];

    // PANEL - ekrana sigacak sekilde dinamik yukseklik (landscape'te tasmasin)
    CGFloat pw = 310;
    CGFloat ph = MIN(600.0, w.bounds.size.height - 30.0);
    if (ph < 260) ph = 260;
    self.panel = [[UIView alloc] initWithFrame:CGRectMake((w.bounds.size.width-pw)/2, (w.bounds.size.height-ph)/2, pw, ph)];
    self.panel.backgroundColor = C_BG;
    self.panel.layer.cornerRadius = 28;
    self.panel.layer.borderWidth = 1.5;
    self.panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
    self.panel.layer.shadowColor = C_CYAN.CGColor;
    self.panel.layer.shadowRadius = 25; self.panel.layer.shadowOpacity = 0.4;
    self.panel.layer.shadowOffset = CGSizeMake(0,0);
    self.panel.clipsToBounds = YES;
    self.panel.hidden = YES; self.panel.alpha = 0;
    self.panel.transform = CGAffineTransformMakeScale(0.85, 0.85);
    UIVisualEffectView *blurV = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark]];
    blurV.frame = self.panel.bounds;
    blurV.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.panel insertSubview:blurV atIndex:0];
    [self.panel addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)]];

    // HEADER
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0,0,pw,60)];
    header.backgroundColor = [UIColor colorWithWhite:0 alpha:0.2];
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16,10,pw-80,26)];
    title.text = @"FEW1N MOD MENU"; title.textColor = [UIColor whiteColor];
    title.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBlack];
    [header addSubview:title];
    UILabel *ver = [[UILabel alloc] initWithFrame:CGRectMake(16,34,pw-80,16)];
    ver.text = [NSString stringWithFormat:@"v21.1 Unity6 | Base:0x%lX | H:%d", (unsigned long)global_base, hookSuccessCount];
    ver.textColor = C_CYAN;
    ver.font = [UIFont fontWithName:@"Menlo-Bold" size:8] ?: [UIFont systemFontOfSize:8 weight:UIFontWeightBold];
    [header addSubview:ver];
    UIButton *cls = [UIButton buttonWithType:UIButtonTypeSystem];
    cls.frame = CGRectMake(pw-46,10,36,36);
    [cls setTitle:@"✕" forState:UIControlStateNormal];
    [cls setTitleColor:[UIColor colorWithWhite:1 alpha:0.6] forState:UIControlStateNormal];
    cls.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightLight];
    [cls addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:cls];
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0,58,pw,2)];
    CAGradientLayer *lg = [CAGradientLayer layer];
    lg.frame = line.bounds; lg.colors = @[(id)C_CYAN.CGColor, (id)C_ACCENT.CGColor];
    lg.startPoint = CGPointMake(0,0.5); lg.endPoint = CGPointMake(1,0.5);
    [line.layer addSublayer:lg];
    [header addSubview:line];
    [self.panel addSubview:header];

    // SCROLL
    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0,60,pw,ph-60)];
    self.scrollView.showsVerticalScrollIndicator = NO;
    [self.panel addSubview:self.scrollView];
    self.contentView = [[UIView alloc] initWithFrame:CGRectMake(0,0,pw,0)];
    [self.scrollView addSubview:self.contentView];

    CGFloat y = 12;

    y = [self header:@"⚡  HIZ (timeScale)" atY:y];
    UIView *sr = [[UIView alloc] initWithFrame:CGRectMake(12,y,pw-24,44)];
    sr.backgroundColor = C_CARD; sr.layer.cornerRadius = 12;
    NSArray *labels = @[@"1x", @"2x", @"3x", @"5x"];
    NSArray *vals   = @[@1, @2, @3, @5];
    CGFloat bw = (pw-24-10*3-16)/4;
    for (int i=0;i<4;i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(8+i*(bw+10),6,bw,32);
        b.layer.cornerRadius = 10;
        [b setTitle:labels[i] forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
        b.tag = [vals[i] intValue];
        [b addTarget:self action:@selector(speedTap:) forControlEvents:UIControlEventTouchUpInside];
        [sr addSubview:b];
        self.speedBtns[vals[i]] = b;
    }
    [self.contentView addSubview:sr];
    y += 52;
    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(16,y,pw-32,16)];
    hint.text = @"Online icin 2x onerilir";
    hint.textColor = C_SUB; hint.font = [UIFont systemFontOfSize:9];
    [self.contentView addSubview:hint];
    y += 22;

    y = [self header:@"\U0001F3CE  ARAC" atY:y];
    y = [self toggle:@"\U0001F4A8  Sonsuz Nitro" sub:@"Nitro hic bitmez" key:@"nitro" atY:y action:@selector(tapNitro)];

    y = [self header:@"\U0001F4AC  CHAT" atY:y];
    y = [self toggle:@"\U0001F3A8  Renkli Chat" sub:@"[FEW1N] prefix + cyan" key:@"colorchat" atY:y action:@selector(tapColorChat)];
    y = [self toggle:@"\U0001F4E2  Chat Spam" sub:@"50ms araligla mesaj" key:@"chatspam" atY:y action:@selector(tapChatSpam)];
    y = [self actionRow:@"✏️  Spam Yazisini Duzenle" color:C_CYAN atY:y action:@selector(editSpam)];

    y = [self header:@"\U0001F522  PLAKA" atY:y];
    self.plateBtn = [self actionButtonRow:&y];
    [self.plateBtn addTarget:self action:@selector(editPlate) forControlEvents:UIControlEventTouchUpInside];

    y = [self header:@"\U0001F4DB  OYUNCU" atY:y];
    self.nameBtn = [self actionButtonRow:&y];
    [self.nameBtn setTitle:@"\U0001F4DB  Isim Degistir" forState:UIControlStateNormal];
    [self.nameBtn setTitleColor:C_CYAN forState:UIControlStateNormal];
    [self.nameBtn addTarget:self action:@selector(changeName) forControlEvents:UIControlEventTouchUpInside];

    y = [self header:@"\U0001F511  ODA" atY:y];
    y = [self toggle:@"\U0001F513  Sifre Kirici" sub:@"Sifreli odalara gir" key:@"bypass" atY:y action:@selector(tapBypass)];

    y = [self header:@"\U0001F4B5  PARA (gecici - server kilitli)" atY:y];
    y = [self toggle:@"\U0001F4B0  Yaris Odulunu Buyut" sub:@"Kazandikca sunucuya yazmayi dener" key:@"automoney" atY:y action:@selector(tapAutoMoney)];
    self.moneyBtn = [self actionButtonRow:&y];
    [self.moneyBtn addTarget:self action:@selector(addMoneyTap) forControlEvents:UIControlEventTouchUpInside];
    y = [self actionRow:@"✏️  Para Miktarini Ayarla" color:C_CYAN atY:y action:@selector(editMoneyAmount)];

    UIView *sc = [[UIView alloc] initWithFrame:CGRectMake(12,y,pw-24,36)];
    UILabel *sl = [[UILabel alloc] initWithFrame:CGRectMake(0,0,pw-24,36)];
    if (global_base != 0) {
        sc.backgroundColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.53 alpha:0.08];
        sl.text = [NSString stringWithFormat:@"✅ Hooklar aktif (%d)", hookSuccessCount];
        sl.textColor = C_ON;
    } else {
        sc.backgroundColor = [UIColor colorWithRed:1.0 green:0.22 blue:0.38 alpha:0.08];
        sl.text = @"❌ Framework bulunamadi";
        sl.textColor = C_RED;
    }
    sc.layer.cornerRadius = 10;
    sl.textAlignment = NSTextAlignmentCenter;
    sl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    [sc addSubview:sl];
    [self.contentView addSubview:sc];
    y += 44;

    y = [self actionRow:@"\U0001F4CB  Loglari Goster (hata teshisi)" color:C_CYAN atY:y action:@selector(showLog)];

    UILabel *foot = [[UILabel alloc] initWithFrame:CGRectMake(0,y+4,pw,24)];
    foot.text = @"made by few1n \U0001F5A4";
    foot.textColor = [UIColor colorWithWhite:0.3 alpha:1];
    foot.textAlignment = NSTextAlignmentCenter;
    foot.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    [self.contentView addSubview:foot];
    y += 36;

    self.contentView.frame = CGRectMake(0,0,pw,y);
    self.scrollView.contentSize = CGSizeMake(pw,y);
    [w addSubview:self.panel];
    [self refreshUI];

    if (tickTimer) { [tickTimer invalidate]; tickTimer = nil; }
    tickTimer = [NSTimer scheduledTimerWithTimeInterval:0.3 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    if (isSpamEnabled && !spamTimer)
        spamTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(fireSpam) userInfo:nil repeats:YES];
}

- (CGFloat)header:(NSString*)text atY:(CGFloat)y {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(20,y,270,20)];
    l.text = text; l.textColor = C_CYAN;
    l.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBlack];
    [self.contentView addSubview:l];
    return y + 26;
}

- (CGFloat)toggle:(NSString*)tl sub:(NSString*)sub key:(NSString*)key atY:(CGFloat)y action:(SEL)action {
    CGFloat pw = self.panel.bounds.size.width;
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(12,y,pw-24,56)];
    card.backgroundColor = C_CARD; card.layer.cornerRadius = 14;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.04].CGColor;
    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(16,8,pw-100,22)];
    t.text = tl; t.textColor = C_TEXT;
    t.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [card addSubview:t];
    UILabel *s = [[UILabel alloc] initWithFrame:CGRectMake(16,30,pw-100,16)];
    s.text = sub; s.textColor = C_SUB;
    s.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    [card addSubview:s];
    UIView *pill = [[UIView alloc] initWithFrame:CGRectMake(pw-24-60,15,44,24)];
    pill.backgroundColor = C_OFF; pill.layer.cornerRadius = 12;
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(2,2,20,20)];
    dot.backgroundColor = [UIColor whiteColor]; dot.layer.cornerRadius = 10; dot.tag = 101;
    [pill addSubview:dot];
    [card addSubview:pill];
    UIButton *tap = [UIButton buttonWithType:UIButtonTypeCustom];
    tap.frame = card.bounds;
    [tap addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:tap];
    [self.contentView addSubview:card];
    self.toggleViews[key] = pill;
    return y + 64;
}

- (CGFloat)actionRow:(NSString*)text color:(UIColor*)color atY:(CGFloat)y action:(SEL)action {
    CGFloat pw = self.panel.bounds.size.width;
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(12,y,pw-24,44)];
    row.backgroundColor = C_CARD; row.layer.cornerRadius = 12;
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(0,0,pw-24,44);
    [b setTitle:text forState:UIControlStateNormal];
    [b setTitleColor:color forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:b];
    [self.contentView addSubview:row];
    return y + 52;
}

- (UIButton*)actionButtonRow:(CGFloat*)y {
    CGFloat pw = self.panel.bounds.size.width;
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(12,*y,pw-24,48)];
    card.backgroundColor = C_CARD; card.layer.cornerRadius = 12;
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(0,0,pw-24,48);
    [b setTitleColor:C_GOLD forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [card addSubview:b];
    [self.contentView addSubview:card];
    *y += 60;
    return b;
}

- (void)setToggle:(NSString*)key on:(BOOL)on {
    UIView *pill = self.toggleViews[key];
    if (!pill) return;
    UIView *dot = [pill viewWithTag:101];
    if (!dot) return;
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.5 options:0 animations:^{
        pill.backgroundColor = on ? C_ON : C_OFF;
        dot.frame = on ? CGRectMake(22,2,20,20) : CGRectMake(2,2,20,20);
        pill.layer.shadowColor = C_ON.CGColor;
        pill.layer.shadowOffset = CGSizeMake(0,0);
        pill.layer.shadowRadius = on ? 8 : 0;
        pill.layer.shadowOpacity = on ? 0.7 : 0.0;
    } completion:nil];
}

- (NSString*)shortNum:(long)n {
    if (n >= 1000000000) return [NSString stringWithFormat:@"%.1fB", n/1000000000.0];
    if (n >= 1000000)    return [NSString stringWithFormat:@"%ldM", n/1000000];
    if (n >= 1000)       return [NSString stringWithFormat:@"%ldK", n/1000];
    return [NSString stringWithFormat:@"%ld", n];
}

- (void)refreshUI {
    for (NSNumber *v in self.speedBtns) {
        UIButton *b = self.speedBtns[v];
        BOOL on = (speedMode == v.intValue);
        b.backgroundColor = on ? C_ON : [UIColor colorWithWhite:0.18 alpha:1];
        [b setTitleColor:on ? [UIColor blackColor] : C_TEXT forState:UIControlStateNormal];
        b.layer.shadowColor = C_ON.CGColor;
        b.layer.shadowOffset = CGSizeMake(0,0);
        b.layer.shadowRadius = on ? 6 : 0;
        b.layer.shadowOpacity = on ? 0.5 : 0.0;
    }
    [self setToggle:@"nitro"     on:isInfiniteNitroEnabled];
    [self setToggle:@"colorchat" on:isColorChatEnabled];
    [self setToggle:@"chatspam"  on:isSpamEnabled];
    [self setToggle:@"bypass"    on:isBypassPasswordEnabled];
    [self setToggle:@"automoney" on:isAutoMoneyEnabled];

    long m = -1;
    if (playerManagerGetInst && pm_getMoney) {
        @try { void* pm = playerManagerGetInst(); if (pm) m = pm_getMoney(pm); } @catch (...) {}
    }
    if (m >= 0)
        [self.moneyBtn setTitle:[NSString stringWithFormat:@"\U0001F4B5 %@ Ekle | Bakiye:%ld", [self shortNum:customMoneyAmount], m] forState:UIControlStateNormal];
    else
        [self.moneyBtn setTitle:[NSString stringWithFormat:@"\U0001F4B5 %@ Para Ekle", [self shortNum:customMoneyAmount]] forState:UIControlStateNormal];
    [self.moneyBtn setTitleColor:C_GOLD forState:UIControlStateNormal];

    if (isCustomPlateEnabled)
        [self.plateBtn setTitle:[NSString stringWithFormat:@"\U0001F4DD Plaka: %s ✅", customPlateText] forState:UIControlStateNormal];
    else
        [self.plateBtn setTitle:@"\U0001F4DD Ozel Plaka Ayarla" forState:UIControlStateNormal];
    [self.plateBtn setTitleColor:isCustomPlateEnabled ? C_ON : C_GOLD forState:UIControlStateNormal];
}

- (void)tick { enforceScale(); }

- (void)toggle {
    if (self.panel.hidden) {
        [self refreshUI];
        self.panel.hidden = NO;
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
            self.panel.alpha = 1; self.panel.transform = CGAffineTransformIdentity;
        } completion:nil];
    } else {
        [UIView animateWithDuration:0.2 animations:^{
            self.panel.alpha = 0; self.panel.transform = CGAffineTransformMakeScale(0.9,0.9);
        } completion:^(BOOL f){ self.panel.hidden = YES; }];
    }
}

- (void)drag:(UIPanGestureRecognizer*)g {
    UIView *v = g.view; if (!v) return;
    CGPoint t = [g translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [g setTranslation:CGPointZero inView:v.superview];
}

- (void)speedTap:(UIButton*)s {
    speedMode = (int)s.tag;
    saveInt(@"speedMode", speedMode);
    [self refreshUI];
    enforceScale();
}

- (void)tapNitro     { isInfiniteNitroEnabled  = !isInfiniteNitroEnabled;  saveBool(@"nitro", isInfiniteNitroEnabled);      [self refreshUI]; }
- (void)tapColorChat { isColorChatEnabled       = !isColorChatEnabled;      saveBool(@"colorchat", isColorChatEnabled);      [self refreshUI]; }
- (void)tapBypass    { isBypassPasswordEnabled  = !isBypassPasswordEnabled; saveBool(@"bypass", isBypassPasswordEnabled);    [self refreshUI]; }
- (void)tapAutoMoney { isAutoMoneyEnabled        = !isAutoMoneyEnabled;      saveBool(@"automoney", isAutoMoneyEnabled);      [self refreshUI]; }

- (void)tapChatSpam {
    isSpamEnabled = !isSpamEnabled;
    saveBool(@"chatspam", isSpamEnabled);
    if (spamTimer) { [spamTimer invalidate]; spamTimer = nil; }
    if (isSpamEnabled)
        spamTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(fireSpam) userInfo:nil repeats:YES];
    [self refreshUI];
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

- (void)addMoneyTap {
    if (playerManagerGetInst && pm_addMoney) {
        @try {
            void* pm = playerManagerGetInst();
            if (pm) {
                pm_addMoney(pm, customMoneyAmount);
                if (pm_syncWithServer) { @try { pm_syncWithServer(pm); } @catch (...) {} }
                [self.moneyBtn setTitle:[NSString stringWithFormat:@"\U0001F4B5 %@ Eklendi ✅", [self shortNum:customMoneyAmount]] forState:UIControlStateNormal];
                [self.moneyBtn setTitleColor:C_ON forState:UIControlStateNormal];
            } else {
                [self.moneyBtn setTitle:@"\U0001F4B5 Oyuna gir!" forState:UIControlStateNormal];
                [self.moneyBtn setTitleColor:C_RED forState:UIControlStateNormal];
            }
        } @catch (...) {}
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self refreshUI]; });
}

- (void)changeName {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"\U0001F4DB Isim Degistir" message:@"Yeni ismin:" preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf){ tf.placeholder = @"FEW1N"; tf.clearButtonMode = UITextFieldViewModeAlways; }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Degistir" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        NSString *name = ac.textFields.firstObject.text;
        if (name.length > 0 && pn_setNickName) {
            void* ns = mkStr(name);
            if (ns) {
                pn_setNickName(ns);
                if (playerManagerGetInst && pm_updateNicknameInternal) {
                    @try { void* pm = playerManagerGetInst(); if (pm) pm_updateNicknameInternal(pm, ns); } @catch (...) {}
                }
                [self.nameBtn setTitle:[NSString stringWithFormat:@"\U0001F4DB Isim: %@ ✅", name] forState:UIControlStateNormal];
                [self.nameBtn setTitleColor:C_ON forState:UIControlStateNormal];
            }
        }
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Iptal" style:UIAlertActionStyleCancel handler:nil]];
    [self present:ac];
}

- (void)editSpam {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"\U0001F4AC Spam Yazisi" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf){ tf.text = [NSString stringWithUTF8String:chatSpamText]; tf.clearButtonMode = UITextFieldViewModeAlways; }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Kaydet" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        NSString *t = ac.textFields.firstObject.text;
        if (t.length > 0) { strncpy(chatSpamText, t.UTF8String, sizeof(chatSpamText)-1); chatSpamText[sizeof(chatSpamText)-1]='\0'; saveStr(@"spamText", t); }
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Iptal" style:UIAlertActionStyleCancel handler:nil]];
    [self present:ac];
}

- (void)editMoneyAmount {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"\U0001F4B5 Para Miktari" message:@"Eklenecek miktar:" preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf){ tf.keyboardType = UIKeyboardTypeNumberPad; tf.text = [NSString stringWithFormat:@"%d", customMoneyAmount]; tf.clearButtonMode = UITextFieldViewModeAlways; }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Kaydet" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        long long v = [ac.textFields.firstObject.text longLongValue];
        if (v > 0) { if (v > 2000000000LL) v = 2000000000LL; customMoneyAmount = (int)v; saveInt(@"moneyAmount", customMoneyAmount); [self refreshUI]; }
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Iptal" style:UIAlertActionStyleCancel handler:nil]];
    [self present:ac];
}

- (void)editPlate {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"\U0001F522 Ozel Plaka" message:@"Plakada gorunecek yazi:" preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf){ tf.placeholder = @"FEW1N"; if (isCustomPlateEnabled) tf.text = [NSString stringWithUTF8String:customPlateText]; tf.clearButtonMode = UITextFieldViewModeAlways; }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Uygula" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        NSString *t = ac.textFields.firstObject.text;
        if (t.length > 0) { strncpy(customPlateText, t.UTF8String, sizeof(customPlateText)-1); customPlateText[sizeof(customPlateText)-1]='\0'; isCustomPlateEnabled = true; saveStr(@"plateText", t); saveBool(@"plateEnabled", true); [self refreshUI]; }
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Kapat" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a){ isCustomPlateEnabled = false; saveBool(@"plateEnabled", false); [self refreshUI]; }]];
    [self present:ac];
}

- (void)showLog {
    UIWindow *w = getKeyWindow(); if (!w) return;
    if (self.logOverlay) { [self.logOverlay removeFromSuperview]; self.logOverlay = nil; }

    CGFloat W = w.bounds.size.width, H = w.bounds.size.height;
    CGFloat ow = MIN(520.0, W - 40), oh = MIN(360.0, H - 40);
    self.logOverlay = [[UIView alloc] initWithFrame:CGRectMake((W-ow)/2, (H-oh)/2, ow, oh)];
    self.logOverlay.backgroundColor = [UIColor colorWithRed:0.03 green:0.04 blue:0.07 alpha:0.97];
    self.logOverlay.layer.cornerRadius = 16;
    self.logOverlay.layer.borderWidth = 1.5;
    self.logOverlay.layer.borderColor = C_CYAN.CGColor;

    UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(14,10,ow-28,20)];
    tl.text = @"FEW1N LOG"; tl.textColor = C_CYAN;
    tl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    [self.logOverlay addSubview:tl];

    self.logText = [[UITextView alloc] initWithFrame:CGRectMake(10,36,ow-20,oh-86)];
    self.logText.backgroundColor = [UIColor colorWithWhite:1 alpha:0.04];
    self.logText.textColor = [UIColor colorWithRed:0.6 green:1.0 blue:0.7 alpha:1.0];
    self.logText.font = [UIFont fontWithName:@"Menlo" size:9] ?: [UIFont systemFontOfSize:9];
    self.logText.editable = NO;
    self.logText.layer.cornerRadius = 8;
    NSString *joined = gLog.count ? [gLog componentsJoinedByString:@"\n"] : @"(log yok - henuz calismadi)";
    self.logText.text = joined;
    [self.logOverlay addSubview:self.logText];

    UIButton *copyB = [UIButton buttonWithType:UIButtonTypeSystem];
    copyB.frame = CGRectMake(10, oh-42, (ow-30)/2, 32);
    copyB.backgroundColor = C_CARD; copyB.layer.cornerRadius = 8;
    [copyB setTitle:@"\U0001F4CB Panoya Kopyala" forState:UIControlStateNormal];
    [copyB setTitleColor:C_CYAN forState:UIControlStateNormal];
    copyB.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [copyB addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    [self.logOverlay addSubview:copyB];

    UIButton *closeB = [UIButton buttonWithType:UIButtonTypeSystem];
    closeB.frame = CGRectMake(20+(ow-30)/2, oh-42, (ow-30)/2, 32);
    closeB.backgroundColor = C_CARD; closeB.layer.cornerRadius = 8;
    [closeB setTitle:@"Kapat" forState:UIControlStateNormal];
    [closeB setTitleColor:C_RED forState:UIControlStateNormal];
    closeB.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [closeB addTarget:self action:@selector(closeLog) forControlEvents:UIControlEventTouchUpInside];
    [self.logOverlay addSubview:closeB];

    [w addSubview:self.logOverlay];
}

- (void)copyLog {
    NSString *joined = gLog.count ? [gLog componentsJoinedByString:@"\n"] : @"(log yok)";
    [UIPasteboard generalPasteboard].string = joined;
    self.logText.text = [joined stringByAppendingString:@"\n\n>>> PANOYA KOPYALANDI <<<"];
}

- (void)closeLog {
    if (self.logOverlay) { [self.logOverlay removeFromSuperview]; self.logOverlay = nil; }
}

- (void)present:(UIAlertController*)ac {
    UIWindow *w = getKeyWindow(); if (!w) return;
    UIViewController *vc = w.rootViewController; if (!vc) return;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if (vc.isBeingDismissed || vc.isBeingPresented) return;
    [vc presentViewController:ac animated:YES completion:nil];
}

@end

static void restoreSettings(void) {
    speedMode              = loadInt(@"speedMode", 1);
    isInfiniteNitroEnabled = loadBool(@"nitro", false);
    isColorChatEnabled     = loadBool(@"colorchat", false);
    isSpamEnabled          = loadBool(@"chatspam", false);
    isBypassPasswordEnabled= loadBool(@"bypass", true);
    isCustomPlateEnabled   = loadBool(@"plateEnabled", false);
    isAutoMoneyEnabled     = loadBool(@"automoney", false);
    customMoneyAmount      = loadInt(@"moneyAmount", 100000000);
    NSString* pt = loadStr(@"plateText", @"FEW1N");
    strncpy(customPlateText, pt.UTF8String, sizeof(customPlateText)-1); customPlateText[sizeof(customPlateText)-1]='\0';
    NSString* st = loadStr(@"spamText", @"FEW1N MOD MENU!");
    strncpy(chatSpamText, st.UTF8String, sizeof(chatSpamText)-1); chatSpamText[sizeof(chatSpamText)-1]='\0';
}

static uintptr_t GetUnityFrameworkBase(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i=0;i<count;i++) {
        const char *n = _dyld_get_image_name(i);
        if (n && strstr(n, "UnityFramework")) return _dyld_get_image_vmaddr_slide(i);
    }
    for (uint32_t i=0;i<count;i++) {
        const char *n = _dyld_get_image_name(i);
        if (n && strstr(n, "DreamRoadMultiplayer.app/DreamRoadMultiplayer")) return _dyld_get_image_vmaddr_slide(i);
    }
    return 0;
}

static void InstallEverything(uintptr_t b) {
    global_base = b;
    FLog([NSString stringWithFormat:@"Base bulundu: 0x%lX", (unsigned long)b]);

    chatGetInst               = (void*(*)(void))(b + 0x31A6168);
    chatSend                  = (void(*)(void*,void*))(b + 0x31A626C);
    tmp_set_text              = (void(*)(void*,void*))(b + 0x65F4CC8);
    pn_setNickName            = (void(*)(void*))(b + 0x5933940);
    lobbyGetInst              = (void*(*)(void))(b + 0x54A8098);
    playerManagerGetInst      = (void*(*)(void))(b + 0x5A2DE20);
    pm_updateNicknameInternal = (void(*)(void*,void*))(b + 0x5A3DDD4);
    pm_getMoney               = (int(*)(void*))(b + 0x5A4346C);
    pm_syncWithServer         = (void(*)(void*))(b + 0x5A2DF80);
    pm_addMoney               = (void(*)(void*,int))(b + 0x5A43A2C);

    safeHook((void*)(b + 0x6771918), (void*)h_setTimeScale,  (void**)&o_setTimeScale,     "set_timeScale");
    safeHook((void*)(b + 0x5938844), (void*)h_closeConnection,(void**)&o_closeConnection, "CloseConnection");
    safeHook((void*)(b + 0x54CFE14), (void*)h_getNitro,       (void**)&o_getNitro,        "get_nitroAmount");
    safeHook((void*)(b + 0x54CFE1C), (void*)h_setNitro,       (void**)&o_setNitro,        "set_nitroAmount");
    safeHook((void*)(b + 0x54CCAA0), (void*)h_driveMove,      (void**)&o_driveMove,       "CarDriveSystem.Move");
    safeHook((void*)(b + 0x54EA1FC), (void*)h_plateChange,    (void**)&o_plateChange,     "PlateVariant.Change");
    safeHook((void*)(b + 0x31A626C), (void*)h_chatSend,       (void**)&o_chatSend,        "ChatManager.Send");
    safeHook((void*)(b + 0x54B32F4), (void*)h_roomConnect,    (void**)&o_roomConnect,     "RoomListLine.Connect");
    safeHook((void*)(b + 0x5A43A2C), (void*)h_addMoney,       (void**)&o_addMoney,        "PlayerManager.AddMoney");

    FLog([NSString stringWithFormat:@"Bitti: %d hook OK, %d fail", hookSuccessCount, hookFailCount]);
    [[FEW1NMenu shared] build];
}

static int few1n_attempts = 0;
static void few1n_poll(void) {
    few1n_attempts++;
    uintptr_t b = GetUnityFrameworkBase();
    if (b != 0) { InstallEverything(b); return; }
    if (few1n_attempts >= 80) { FLog(@"UnityFramework BULUNAMADI (80 deneme)"); [[FEW1NMenu shared] build]; return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ few1n_poll(); });
}

%ctor {
    FLog(@"v21.1 basladi, UnityFramework araniyor...");
    restoreSettings();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ few1n_poll(); });
}
