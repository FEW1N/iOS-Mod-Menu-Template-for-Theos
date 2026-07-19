#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <substrate.h>
#include <mach-o/dyld.h>
#include <string.h>
#include <dlfcn.h>
#include <math.h>

// ============================================================
//  v23.7 - FEW1N MOD MENU
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
typedef struct { float x, y, z; } Vec3;      // Unity Vector3

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
static void saveFloat(NSString* k, float v)   { [defs() setFloat:v forKey:k]; }
static float loadFloat(NSString* k, float def) { return [defs() objectForKey:k] ? [defs() floatForKey:k] : def; }
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
static bool isFlyEnabled = false;       // hover (dikey hizi 0 tut -> havada surus)
static bool isLowGravEnabled = false;   // dususu yavaslat (floaty)
static void* g_rb = NULL;               // arabanin Rigidbody'si (h_driveMove'da yakalanir)
static bool isAsciiAnimEnabled = false; // ASCII animasyon spam
static int  asciiAnimIndex = 0;         // hangi animasyon
static int  asciiFrameIdx = 0;          // mevcut kare
static bool isRoomSpamEnabled = false;  // fake oda spam
static char customRoomName[160] = "<b><color=#FF0000>FEW1N</color></b>";
static int  roomSpamPhase = 0;          // 0=kur, 1=cik
static int  roomSpamCount = 0;          // kurulan oda sayaci
static int  roomSpamMaxCount = 0;       // hedef (0 = sinirsiz)
static float roomSpamInterval = 1.5f;   // aralik (sn)
static int  roomSpamTTL = 300000;       // oda acik kalma (ms)
static bool roomSpamContinuous = true;  // surekli mod
static int  spamStyle = 0;              // 0=duz 1=cerceveli 2=sembol 3=renkli
static char customPlateText[64] = "FEW1N";
static char chatSpamText[128] = "FEW1N MOD MENU!";
static int  customMoneyAmount = 100000000;

static NSTimer *spamTimer = nil;
static NSTimer *tickTimer = nil;
static NSTimer *asciiTimer = nil;
static NSTimer *roomSpamTimer = nil;

// ASCII animasyon setleri (her set = kareler dizisi)
static NSArray* asciiAnims(void) {
    return @[
        @[@"[■□□□□]", @"[■■□□□]", @"[■■■□□]", @"[■■■■□]", @"[■■■■■] FEW1N!"],
        @[@"★☆☆☆☆", @"★★☆☆☆", @"★★★☆☆", @"★★★★☆", @"★★★★★ FEW1N"],
        @[@"FEW1N ▷", @"FEW1N ▷▷", @"FEW1N ▷▷▷", @"FEW1N ▷▷▷▷", @"FEW1N ▷▷▷▷▷"],
        @[@"🚗💨", @"·🚗💨", @"··🚗💨", @"···🚗💨", @"····🚗💨 FEW1N"],
        @[@"( •_•)", @"( •_•)>⌐■-■", @"(⌐■_■)", @"(⌐■_■) FEW1N"],
        @[@"◜", @"◝", @"◞", @"◟", @"◜ FEW1N"],
        // FEW1N HACK - duz yazi (renksiz, daktilo)
        @[@"F", @"FE", @"FEW", @"FEW1", @"FEW1N", @"FEW1N H", @"FEW1N HA", @"FEW1N HAC", @"FEW1N HACK", @"» FEW1N HACK «"],
        // FEW1N HACK - Rainbow (rich text acigi: TMP renk render eder)
        @[@"<color=#FF0000><b>FEW1N HACK</b></color>", @"<color=#FF7F00><b>FEW1N HACK</b></color>",
          @"<color=#FFFF00><b>FEW1N HACK</b></color>", @"<color=#00FF00><b>FEW1N HACK</b></color>",
          @"<color=#00FFFF><b>FEW1N HACK</b></color>", @"<color=#4466FF><b>FEW1N HACK</b></color>",
          @"<color=#FF00FF><b>FEW1N HACK</b></color>"],
        // FEW1N HACK - Daktilo (harf harf yazar)
        @[@"<color=#00FF88><b>F</b></color>", @"<color=#00FF88><b>FE</b></color>",
          @"<color=#00FF88><b>FEW</b></color>", @"<color=#00FF88><b>FEW1</b></color>",
          @"<color=#00FF88><b>FEW1N</b></color>", @"<color=#00FF88><b>FEW1N H</b></color>",
          @"<color=#00FF88><b>FEW1N HA</b></color>", @"<color=#00FF88><b>FEW1N HAC</b></color>",
          @"<color=#00FF88><b>FEW1N HACK</b></color>"],
        // FEW1N HACK - Buyuk/parlak (size + color)
        @[@"<size=150%><color=#00FFFF><b>⚡ FEW1N HACK ⚡</b></color></size>",
          @"<size=150%><color=#FF00FF><b>⚡ FEW1N HACK ⚡</b></color></size>",
          @"<size=150%><color=#FFFF00><b>⚡ FEW1N HACK ⚡</b></color></size>"],
        // Kutu cerceve (renksiz)
        @[@"╔══════════╗", @"║  FEW1N   ║", @"║   HACK   ║", @"╚══════════╝"],
        // Progress bar zengin
        @[@"▰▱▱▱▱▱▱▱▱▱", @"▰▰▰▱▱▱▱▱▱▱", @"▰▰▰▰▰▱▱▱▱▱", @"▰▰▰▰▰▰▰▱▱▱", @"▰▰▰▰▰▰▰▰▰▰ FEW1N"],
        // Suslu parantez
        @[@"《 F 》", @"《 FE 》", @"《 FEW 》", @"《 FEW1 》", @"《 FEW1N 》", @"『 FEW1N HACK 』"],
        // Pulse (buyuyup kuculen - renkli)
        @[@"<size=80%><color=#FF0000><b>FEW1N</b></color></size>",
          @"<size=110%><color=#FF6600><b>FEW1N</b></color></size>",
          @"<size=140%><color=#FFCC00><b>⚡ FEW1N HACK ⚡</b></color></size>",
          @"<size=110%><color=#FF6600><b>FEW1N</b></color></size>"],
        // Matrix (yesil)
        @[@"<color=#00FF00>01001 FEW1N 10110</color>",
          @"<color=#00FF00>10110 FEW1N 01001</color>",
          @"<color=#00FF00>█▓▒░ FEW1N ░▒▓█</color>"],
        // Neon yanip sonme
        @[@"<color=#00FFFF><b>『 FEW1N HACK 』</b></color>",
          @"<color=#FF00FF><b>『 FEW1N HACK 』</b></color>",
          @"<color=#FFFF00><b>『 FEW1N HACK 』</b></color>"],
        // Dalga efekti (renkli, harfler dalgalanir)
        @[@"<color=#FF0000>F</color><color=#FF8800>E</color><color=#FFFF00>W</color><color=#00FF00>1</color><color=#00FFFF>N</color>",
          @"<color=#00FFFF>F</color><color=#FF0000>E</color><color=#FF8800>W</color><color=#FFFF00>1</color><color=#00FF00>N</color>",
          @"<color=#00FF00>F</color><color=#00FFFF>E</color><color=#FF0000>W</color><color=#FF8800>1</color><color=#FFFF00>N</color>"],
        // Glitch efekti
        @[@"<color=#FF00FF>F̷E̷W̷1̷N̷</color>", @"<color=#00FFFF>F3W1N</color>", @"<color=#FF0000>FΞW1N HACK</color>", @"<b>FEW1N HACK</b>"],
        // Kayan yildizlar
        @[@"✦　　　FEW1N", @"　✦　　FEW1N", @"　　✦　FEW1N", @"　　　✦ FEW1N HACK"],
        // Ates efekti (kirmizi-turuncu-sari)
        @[@"<color=#FF0000>🔥 FEW1N 🔥</color>", @"<color=#FF6600>🔥 FEW1N 🔥</color>", @"<color=#FFCC00>🔥 FEW1N HACK 🔥</color>"],
        // Buz efekti (mavi tonlari)
        @[@"<color=#00CCFF>❄ FEW1N ❄</color>", @"<color=#66E0FF>❄ FEW1N ❄</color>", @"<color=#FFFFFF>❄ FEW1N HACK ❄</color>"],
        // Kalp atisi
        @[@"<size=90%><color=#FF0055>♥ FEW1N ♥</color></size>", @"<size=140%><color=#FF0055>♥ FEW1N ♥</color></size>", @"<size=90%><color=#FF0055>♥ FEW1N ♥</color></size>"],
        // Yukleniyor nokta
        @[@"FEW1N HACK.", @"FEW1N HACK..", @"FEW1N HACK...", @"FEW1N HACK ✓"],
        // Rainbow border
        @[@"<color=#FF0000>▐</color><color=#FFFF00> FEW1N HACK </color><color=#00FFFF>▌</color>",
          @"<color=#00FF00>▐</color><color=#FF00FF> FEW1N HACK </color><color=#FF8800>▌</color>"],
        // Kayan yazi (soldan saga akar)
        @[@"FEW1N HACK", @" FEW1N HACK", @"  FEW1N HACK", @"   FEW1N HACK", @"    FEW1N HACK", @"     FEW1N HACK", @"      FEW1N HACK"],
        // Kayan renkli ok
        @[@"<color=#00FFFF>»</color>FEW1N", @"<color=#00FFFF>»»</color>FEW1N", @"<color=#00FFFF>»»»</color>FEW1N HACK", @"<color=#00FF00>»»»»</color>FEW1N HACK"],
    ];
}

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
    if (gLog.count > 250) [gLog removeObjectAtIndex:0];
}

// ===== IL2CPP API (iGameGod tarzi - isimle bul, runtime_invoke ile cagir) =====
static void* (*i_domain_get)(void) = NULL;
static void** (*i_domain_get_assemblies)(void*, unsigned long*) = NULL;
static const void* (*i_assembly_get_image)(void*) = NULL;
static void* (*i_class_from_name)(const void*, const char*, const char*) = NULL;
static void* (*i_class_get_method_from_name)(void*, const char*, int) = NULL;
static void* (*i_runtime_invoke)(void*, void*, void**, void**) = NULL;
static void* (*i_thread_attach)(void*) = NULL;
static void* (*i_domain_get_ptr)(void) = NULL;
static void* g_mSetTS = NULL;   // set_timeScale MethodInfo*
static void* g_mGetTS = NULL;   // get_timeScale MethodInfo*
static void* g_mRbGetVel = NULL; // Rigidbody.get_linearVelocity MethodInfo*
static void* g_mRbSetVel = NULL; // Rigidbody.set_linearVelocity MethodInfo*
static void* g_mRbGetPos = NULL; // Rigidbody.get_position MethodInfo*  (isinlanma icin)
static void* g_mRbSetPos = NULL; // Rigidbody.set_position MethodInfo*
static void* g_mSetRichText = NULL; // TMP_Text.set_richText MethodInfo* (oda ismi rich text acigi)
static void* (*i_object_new)(void*) = NULL;   // il2cpp_object_new
static void* g_roomOptionsClass = NULL;       // Photon.Realtime.RoomOptions Il2CppClass*
static bool  g_il2cppReady = false;
// ==== ARAC DEGISTIRME (hooksuz, il2cpp singleton uzerinden) ====
// HR_MainMenuHandler: static field 'iiz' = singleton
// metodlar: SelectCar / PositiveCarIndex / NegativeCarIndex / BuyCar
static void* (*i_class_get_field_from_name)(void*, const char*) = NULL;
static void  (*i_field_static_get_value)(void*, void*) = NULL;
static void* g_mmhClass   = NULL;   // HR_MainMenuHandler Il2CppClass*
static void* g_mmhField   = NULL;   // 'iiz' static field
static void* g_mSelectCar = NULL;
static void* g_mNextCar   = NULL;
static void* g_mPrevCar   = NULL;
// ==== HOOKSUZ ARABA BULMA ====
// MSHookFunction bu oyunda calismiyor (0 OK / 17 FAIL) -> hook yerine
// UnityEngine.Object.FindObjectOfType(Type) ile arabayi her saniye ARIYORUZ.
static void* (*i_class_get_type)(void*) = NULL;
static void* (*i_type_get_object)(void*) = NULL;
static void* g_mFindObjectOfType = NULL;   // UnityEngine.Object.FindObjectOfType(Type)
static void* g_mFindObjInactive  = NULL;   // FindObjectOfType(Type, bool includeInactive)
static void* g_mFindAnyByType    = NULL;   // FindAnyObjectByType(Type)
static void* g_carDriveTypeObj   = NULL;   // typeof(CarDriveSystem)
static void* g_carInputTypeObj   = NULL;   // typeof(CarPlayerInput)

static void few1n_initIl2cpp(void) {
    i_domain_get                = (void*(*)(void))dlsym(RTLD_DEFAULT, "il2cpp_domain_get");
    i_domain_get_assemblies     = (void**(*)(void*,unsigned long*))dlsym(RTLD_DEFAULT, "il2cpp_domain_get_assemblies");
    i_assembly_get_image        = (const void*(*)(void*))dlsym(RTLD_DEFAULT, "il2cpp_assembly_get_image");
    i_class_from_name           = (void*(*)(const void*,const char*,const char*))dlsym(RTLD_DEFAULT, "il2cpp_class_from_name");
    i_class_get_method_from_name= (void*(*)(void*,const char*,int))dlsym(RTLD_DEFAULT, "il2cpp_class_get_method_from_name");
    i_runtime_invoke            = (void*(*)(void*,void*,void**,void**))dlsym(RTLD_DEFAULT, "il2cpp_runtime_invoke");
    i_thread_attach             = (void*(*)(void*))dlsym(RTLD_DEFAULT, "il2cpp_thread_attach");
    i_object_new                = (void*(*)(void*))dlsym(RTLD_DEFAULT, "il2cpp_object_new");
    i_class_get_field_from_name = (void*(*)(void*,const char*))dlsym(RTLD_DEFAULT, "il2cpp_class_get_field_from_name");
    i_field_static_get_value    = (void(*)(void*,void*))dlsym(RTLD_DEFAULT, "il2cpp_field_static_get_value");
    i_class_get_type            = (void*(*)(void*))dlsym(RTLD_DEFAULT, "il2cpp_class_get_type");
    i_type_get_object           = (void*(*)(void*))dlsym(RTLD_DEFAULT, "il2cpp_type_get_object");
    if (!i_domain_get || !i_domain_get_assemblies || !i_assembly_get_image ||
        !i_class_from_name || !i_class_get_method_from_name || !i_runtime_invoke) {
        FLog(@"il2cpp API bulunamadi!"); return;
    }
    void* domain = i_domain_get();
    if (i_thread_attach && domain) i_thread_attach(domain);   // bu thread'i il2cpp'e bagla
    unsigned long n = 0;
    void** asms = i_domain_get_assemblies(domain, &n);
    FLog([NSString stringWithFormat:@"il2cpp: %lu assembly taraniyor", n]);
    for (unsigned long i = 0; i < n; i++) {
        const void* img = i_assembly_get_image(asms[i]);
        if (!img) continue;
        if (!g_mSetTS) {
            void* timeClass = i_class_from_name(img, "UnityEngine", "Time");
            if (timeClass) {
                g_mSetTS = i_class_get_method_from_name(timeClass, "set_timeScale", 1);
                g_mGetTS = i_class_get_method_from_name(timeClass, "get_timeScale", 0);
                FLog([NSString stringWithFormat:@"Time bulundu! set=%p get=%p", g_mSetTS, g_mGetTS]);
            }
        }
        // UnityEngine.Object.FindObjectOfType(Type) - hooksuz arama icin
        if (!g_mFindObjectOfType) {
            void* oc = i_class_from_name(img, "UnityEngine", "Object");
            if (oc) {
                g_mFindObjectOfType = i_class_get_method_from_name(oc, "FindObjectOfType", 1);
                g_mFindObjInactive  = i_class_get_method_from_name(oc, "FindObjectOfType", 2);
                g_mFindAnyByType    = i_class_get_method_from_name(oc, "FindAnyObjectByType", 1);
                FLog([NSString stringWithFormat:@"Bulucular: tek=%p ikili=%p any=%p",
                      g_mFindObjectOfType, g_mFindObjInactive, g_mFindAnyByType]);
            }
        }
        // typeof(CarDriveSystem) ve typeof(CarPlayerInput)
        if (!g_carDriveTypeObj && i_class_get_type && i_type_get_object) {
            void* c = i_class_from_name(img, "TurnTheGameOn.IKAvatarDriver", "CarDriveSystem");
            if (c) {
                void* t = i_class_get_type(c);
                if (t) g_carDriveTypeObj = i_type_get_object(t);
                FLog([NSString stringWithFormat:@"CarDriveSystem tipi: %p", g_carDriveTypeObj]);
            }
        }
        if (!g_carInputTypeObj && i_class_get_type && i_type_get_object) {
            void* c = i_class_from_name(img, "TurnTheGameOn.IKAvatarDriver", "CarPlayerInput");
            if (c) {
                void* t = i_class_get_type(c);
                if (t) g_carInputTypeObj = i_type_get_object(t);
                FLog([NSString stringWithFormat:@"CarPlayerInput tipi: %p", g_carInputTypeObj]);
            }
        }
        if (!g_mmhClass) {
            void* c = i_class_from_name(img, "", "HR_MainMenuHandler");
            if (c) {
                g_mmhClass   = c;
                g_mSelectCar = i_class_get_method_from_name(c, "SelectCar", 0);
                g_mNextCar   = i_class_get_method_from_name(c, "PositiveCarIndex", 0);
                g_mPrevCar   = i_class_get_method_from_name(c, "NegativeCarIndex", 0);
                if (i_class_get_field_from_name) g_mmhField = i_class_get_field_from_name(c, "iiz");
                FLog([NSString stringWithFormat:@"MainMenuHandler bulundu! sec=%p ileri=%p geri=%p singleton=%p",
                      g_mSelectCar, g_mNextCar, g_mPrevCar, g_mmhField]);
            }
        }
        if (!g_mRbSetVel) {
            void* rbClass = i_class_from_name(img, "UnityEngine", "Rigidbody");
            if (rbClass) {
                // Unity6: linearVelocity (yeni). Eski velocity de denenir.
                g_mRbGetVel = i_class_get_method_from_name(rbClass, "get_linearVelocity", 0);
                g_mRbSetVel = i_class_get_method_from_name(rbClass, "set_linearVelocity", 1);
                if (!g_mRbSetVel) {
                    g_mRbGetVel = i_class_get_method_from_name(rbClass, "get_velocity", 0);
                    g_mRbSetVel = i_class_get_method_from_name(rbClass, "set_velocity", 1);
                }
                g_mRbGetPos = i_class_get_method_from_name(rbClass, "get_position", 0);
                g_mRbSetPos = i_class_get_method_from_name(rbClass, "set_position", 1);
                FLog([NSString stringWithFormat:@"Rigidbody bulundu! get=%p set=%p", g_mRbGetVel, g_mRbSetVel]);
            }
        }
        if (!g_mSetRichText) {
            void* tmpClass = i_class_from_name(img, "TMPro", "TMP_Text");
            if (tmpClass) {
                g_mSetRichText = i_class_get_method_from_name(tmpClass, "set_richText", 1);
                FLog([NSString stringWithFormat:@"TMP_Text bulundu! set_richText=%p", g_mSetRichText]);
            }
        }
        if (!g_roomOptionsClass) {
            void* roc = i_class_from_name(img, "Photon.Realtime", "RoomOptions");
            if (roc) { g_roomOptionsClass = roc; FLog([NSString stringWithFormat:@"RoomOptions bulundu! %p", roc]); }
        }
        if (g_mSetTS && g_mRbSetVel && g_mSetRichText && g_roomOptionsClass) break;
    }
    g_il2cppReady = (g_mSetTS != NULL);
    if (!g_il2cppReady) FLog(@"UnityEngine.Time bulunamadi");
}

// TMP_Text.richText = true  (Unity rich text acigini geri ac)
static void setRichTextIl(void* tmp, bool on) {
    if (!i_runtime_invoke || !g_mSetRichText || !tmp) return;
    bool val = on;
    void* params[1] = { &val };
    i_runtime_invoke(g_mSetRichText, tmp, params, NULL);
}

// Rigidbody ham Injected pointer'lari (rbGetVelIl/rbSetVelIl yedegi olarak kullanilir)
static void (*rb_getVel)(void* self, Vec3* out) = NULL;   // get_linearVelocity_Injected
static void (*rb_setVel)(void* self, Vec3* val) = NULL;   // set_linearVelocity_Injected
static void (*rb_getPos)(void* self, Vec3* out) = NULL;   // get_position_Injected
static void (*rb_setPos)(void* self, Vec3* val) = NULL;   // set_position_Injected

// Rigidbody linearVelocity - il2cpp runtime_invoke ile (ham offset degil)
static void rbGetVelIl(void* rb, Vec3* out) {
    out->x = out->y = out->z = 0;
    if (!rb) return;
    if (i_runtime_invoke && g_mRbGetVel) {
        void* box = i_runtime_invoke(g_mRbGetVel, rb, NULL, NULL);   // boxed Vector3
        if (box) { *out = *(Vec3*)((uintptr_t)box + 0x10); return; }
    }
    if (rb_getVel) rb_getVel(rb, out);   // yedek: ham Injected
}
static void rbSetVelIl(void* rb, Vec3* v) {
    if (!rb) return;
    if (i_runtime_invoke && g_mRbSetVel) {
        void* params[1] = { v };
        i_runtime_invoke(g_mRbSetVel, rb, params, NULL);
        return;
    }
    if (rb_setVel) rb_setVel(rb, v);     // yedek: ham Injected
}

// Rigidbody position - il2cpp runtime_invoke (ham cagri yedek)
static void rbGetPosIl(void* rb, Vec3* out) {
    out->x = out->y = out->z = 0;
    if (!rb) return;
    if (i_runtime_invoke && g_mRbGetPos) {
        void* box = i_runtime_invoke(g_mRbGetPos, rb, NULL, NULL);   // boxed Vector3
        if (box) { *out = *(Vec3*)((uintptr_t)box + 0x10); return; }
    }
    if (rb_getPos) rb_getPos(rb, out);
}
static void rbSetPosIl(void* rb, Vec3* v) {
    if (!rb) return;
    if (i_runtime_invoke && g_mRbSetPos) {
        void* params[1] = { v };
        i_runtime_invoke(g_mRbSetPos, rb, params, NULL);
        return;
    }
    if (rb_setPos) rb_setPos(rb, v);
}

static void setTimeScaleVal(float v) {
    if (!i_runtime_invoke || !g_mSetTS) return;
    float val = v;
    void* params[1] = { &val };
    i_runtime_invoke(g_mSetTS, NULL, params, NULL);
}
static float getTimeScaleVal(void) {
    if (!i_runtime_invoke || !g_mGetTS) return -1.0f;
    void* box = i_runtime_invoke(g_mGetTS, NULL, NULL, NULL);   // boxed float
    if (!box) return -1.0f;
    return *(float*)((uintptr_t)box + 0x10);                    // unbox
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
// Substrate calisiyor mu? Bagli sembol bos stub olabilir -> dlsym ile gercegini ara.
typedef void (*MSHookFn)(void*, void*, void**);
static MSHookFn g_msHook = NULL;
static bool g_msHookChecked = false;
static void few1n_probeSubstrate(void) {
    if (g_msHookChecked) return;
    g_msHookChecked = true;
    // Substrate / ElleKit / libhooker isimlerini sirayla dene
    g_msHook = (MSHookFn)dlsym(RTLD_DEFAULT, "MSHookFunction");
    if (g_msHook) { FLog([NSString stringWithFormat:@"Substrate VAR: MSHookFunction=%p", (void*)g_msHook]); return; }
    g_msHook = (MSHookFn)dlsym(RTLD_DEFAULT, "LHHookFunctions");   // libhooker
    if (g_msHook) { FLog(@"libhooker bulundu (LHHookFunctions)"); return; }
    void* ek = dlopen("/var/jb/usr/lib/libellekit.dylib", RTLD_LAZY);
    if (!ek) ek = dlopen("/usr/lib/libsubstrate.dylib", RTLD_LAZY);
    if (ek) {
        g_msHook = (MSHookFn)dlsym(ek, "MSHookFunction");
        FLog(g_msHook ? @"ElleKit/Substrate dylib ile yuklendi" : @"dylib acildi ama MSHookFunction yok");
        return;
    }
    FLog(@"SUBSTRATE YOK! Hicbir hook motoru bulunamadi -> il2cpp yolu kullaniliyor");
}

static void safeHook(void* target, void* replacement, void** original, const char* name) {
    NSString* nm = [NSString stringWithUTF8String:name];
    if (!target) { FLog([@"SKIP (NULL) " stringByAppendingString:nm]); hookFailCount++; return; }
    if (original) *original = NULL;
    few1n_probeSubstrate();
    if (g_msHook) g_msHook(target, replacement, original);   // dlsym ile bulunan gercek motor
    else MSHookFunction(target, replacement, original);      // bagli sembol (stub olabilir)
    // GERCEK dogrulama: MSHookFunction basarili olursa *original orijinal koda isaret eder.
    // Sideload'da (Substrate yok) MSHookFunction sessizce hicbir sey yapmaz -> *original NULL kalir.
    if (original && *original == NULL) {
        FLog([NSString stringWithFormat:@"FAIL (hook yazilamadi) %@", nm]);
        hookFailCount++;
        return;
    }
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
static void* (*tmp_get_text)(void* self) = NULL;   // TMP_InputField.get_text
static void* (*rinfo_getName)(void* self) = NULL;  // RoomInfo.get_Name (ham oda ismi)
static void  (*pn_setNickName)(void* name) = NULL;
static void* (*lobbyGetInst)(void) = NULL;
static void* (*playerManagerGetInst)(void) = NULL;
static void  (*pm_updateNicknameInternal)(void* self, void* newName) = NULL;
static int   (*pm_getMoney)(void* self) = NULL;
static void  (*pm_syncWithServer)(void* self) = NULL;
static void  (*pm_addMoney)(void* self, int amount) = NULL;
static void  (*lobby_createRoom)(void* self) = NULL;   // HR_PhotonLobbyManager.CreateRoomButton
static void  (*lobby_leaveRoom)(void* self) = NULL;    // HR_PhotonLobbyManager.LeaveRoom
static bool  (*pn_createRoom)(void* name, void* opts, void* lobby, void* users) = NULL; // PhotonNetwork.CreateRoom
// ==== ODADAKI OYUNCULAR (script.json dogrulandi) ====
static void* (*pn_getPlayerList)(void) = NULL;      // PhotonNetwork.get_PlayerList -> Player[]  0x59339D0
static void* (*ply_getNickName)(void*) = NULL;      // Player.get_NickName          0x5924574
static int   (*ply_getActorNumber)(void*) = NULL;   // Player.get_ActorNumber       0x592455C
static bool  (*ply_getIsMaster)(void*) = NULL;      // Player.get_IsMasterClient    0x5924640
static void* (*ply_getUserId)(void*) = NULL;        // Player.get_UserId            0x5924630
// HR_PhotonLobbyManager.EnableCarSelectionMenu() - oyun ici arac degistirme  0x54ABFD4
static void  (*lobby_carSelectMenu)(void*) = NULL;
// ==== ARAC KONTROL PANELI (CarDriveSystem field offsetleri, il2cpp.h dogrulandi) ====
//  +0x60 overrideBrake(bool)  +0x61 overrideAcceleration(bool)  +0x62 overrideSteering(bool)
//  +0x64 overrideSteeringPower  +0x68 overrideBrakePower  +0x6C overrideAccelerationPower
//  +0x98 topSpeed  +0x9C currentSpeed
static bool  isCarPanelEnabled = false;
static float carAccelPower  = 3.0f;
static float carSteerPower  = 1.0f;
static float carTopSpeed    = 300.0f;
// UserId -> isim gecmisi. ActorNumber odadan cikinca degisir, UserId hesaba bagli kalir.
static NSMutableDictionary *g_playerDB = nil;
static void loadPlayerDB(void) {
    if (g_playerDB) return;
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] objectForKey:@"few1n_playerDB"];
    g_playerDB = d ? [d mutableCopy] : [NSMutableDictionary dictionary];
}
static void savePlayerDB(void) {
    if (g_playerDB) {
        [[NSUserDefaults standardUserDefaults] setObject:g_playerDB forKey:@"few1n_playerDB"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

// ===== HIZ TESHIS / YARDIMCILAR =====
static float (*ts_get)(void) = NULL;     // Time.get_timeScale
static Vec3 g_savedPos = {0,0,0};
static bool g_hasSavedPos = false;
static void* diagDrive = NULL;
static float diagCurSpd = 0, diagTopSpd = 0, diagVel = 0;
static long  fNitro = 0, fDrive = 0, fPlate = 0, fRoomLine = 0, fRccp = 0, fSmRCC = 0, fSmPUN = 0;  // hook tetiklenme sayaclari
static long  fTS = 0, fChat = 0, fCreateBtn = 0, fConn = 0;  // araba-disi hook sayaclari (base testi)
static long  fInput = 0;  // CarPlayerInput.FixedUpdate - GERCEK araba hooku
static float diagNitroVal = 0;
static float g_origTop = 0;

// ===== TIME SCALE =====
static void (*o_setTimeScale)(float) = NULL;
static inline float targetScale(void) {
    if (speedMode == 2) return 2.0f;
    if (speedMode == 3) return 3.0f;
    if (speedMode == 5) return 5.0f;
    return 1.0f;
}
static inline void enforceScale(void) {
    // iGameGod yontemi: il2cpp runtime_invoke ile set_timeScale (ham offset degil!)
    if (speedMode > 1) {
        if (g_il2cppReady) setTimeScaleVal(targetScale());
        else if (o_setTimeScale) o_setTimeScale(targetScale());  // yedek
    }
}
static void h_setTimeScale(float v) {
    fTS++;
    // Oyun timeScale'i 1'e resetlemeye calisirsa bizim degeri zorla
    if (speedMode > 1) v = targetScale();
    if (o_setTimeScale) o_setTimeScale(v);
}

// ===== ANTI-KICK =====
static bool (*o_closeConnection)(void*) = NULL;
static bool h_closeConnection(void* kickPlayer) { fConn++; return false; }

// ===== INFINITE NITRO =====
static float (*o_getNitro)(void*) = NULL;
static float h_getNitro(void* self) {
    // CarNitro -> driveSystem(0x28) -> rigidbody(0x48) : arabanin Rigidbody'sini yakala
    fNitro++;
    if (self) {
        @try {
            void* ds = *(void**)((uintptr_t)self + 0x28);
            if (ds) { void* rb = *(void**)((uintptr_t)ds + 0x48); if (rb) g_rb = rb; }
            diagNitroVal = *(float*)((uintptr_t)self + 0x34);
            if (isInfiniteNitroEnabled) *(float*)((uintptr_t)self + 0x34) = 1.0f;  // nitroAmount backing field'i de doldur
        } @catch (...) {}
    }
    if (isInfiniteNitroEnabled) return 1.0f;
    return o_getNitro ? o_getNitro(self) : 0.0f;
}
static void (*o_setNitro)(void*, float) = NULL;
static void h_setNitro(void* self, float value) {
    if (isInfiniteNitroEnabled) value = 1.0f;
    if (o_setNitro) o_setNitro(self, value);
}

// ===== CarDriveSystem.Move : hiz hilesi (tam gaz + topSpeed) + teshis =====
// a=steering, b=accel(0..1), c=footbrake, d=handbrake
// topSpeed@0x98, currentSpeed@0x9C  (public, isimleri korundu)
static void (*o_driveMove)(void*, float, float, float, float) = NULL;
static void h_driveMove(void* self, float a, float b, float c, float d) {
    fDrive++;
    enforceScale();
    if (self && speedMode > 1) {
        // TAM GAZ (fren yoksa) - kuvvet yok, araba kalkmaz
        if (c <= 0.0f && d <= 0.0f) b = 1.0f;
    }
    if (o_driveMove) o_driveMove(self, a, b, c, d);   // once oyunun fizigi calissin

    if (self) {
        @try {
            diagDrive  = self;
            diagCurSpd = *(float*)((uintptr_t)self + 0x9C);   // currentSpeed
            diagTopSpd = *(float*)((uintptr_t)self + 0x98);   // topSpeed
            // topSpeed cap'ini de yukselt (bazi oyunlar hizi buna clamp eder)
            if (speedMode > 1) {
                if (g_origTop <= 0.0f && diagTopSpd > 0.0f && diagTopSpd < 1000.0f) g_origTop = diagTopSpd;
                float base = (g_origTop > 0.0f) ? g_origTop : 200.0f;
                *(float*)((uintptr_t)self + 0x98) = base * 3.0f;
            } else if (g_origTop > 0.0f) {
                *(float*)((uintptr_t)self + 0x98) = g_origTop; g_origTop = 0.0f;
            }
            // ASIL HIZ: Rigidbody linearVelocity'yi dogrudan olcekle (en kesin yontem)
            void* rb = *(void**)((uintptr_t)self + 0x48);     // CarDriveSystem._rigidbody
            g_rb = rb;                                        // fly/zipla/lowgrav icin sakla
            if (rb && rb_getVel && rb_setVel) {
                Vec3 v = {0,0,0};
                rb_getVel(rb, &v);
                float horiz = sqrtf(v.x*v.x + v.z*v.z);       // yatay hiz (y=dikey, dokunmuyoruz -> ucmaz)
                diagVel = horiz;
                if (speedMode > 1 && horiz > 0.5f) {
                    float cap = (speedMode == 2) ? 90.0f : (speedMode == 3) ? 140.0f : 230.0f;
                    float ns = horiz * 1.06f; if (ns > cap) ns = cap;
                    float k = ns / horiz;
                    v.x *= k; v.z *= k;                        // sadece yatayi buyut
                    rb_setVel(rb, &v);
                }
            }
        } @catch (...) {}
    }
}

// ===== HOOKSUZ ARABA ARAMA (MSHookFunction calismadigi icin tek yol) =====
// Her poll'da FindObjectOfType(CarDriveSystem) cagirip Rigidbody'yi +0x48'den okur.
// Ayrica arac paneli degerlerini de burada yazar.
static long fFind = 0;      // basarili arama sayisi
static void* g_carDrive = NULL;
static void* g_carNitro = NULL;
// Bir tipi 3 farkli Unity API'siyle aramayi dener (aktif olmayanlar dahil)
static void* few1n_findByType(void* typeObj) {
    if (!typeObj || !i_runtime_invoke) return NULL;
    void* r = NULL;
    // Yol 1 - FindObjectOfType Type,true : pasif nesneleri de bulur
    if (g_mFindObjInactive) {
        bool inc = true;
        void* a[2]; a[0] = typeObj; a[1] = &inc;
        @try { r = i_runtime_invoke(g_mFindObjInactive, NULL, a, NULL); } @catch (...) {}
        if (r) return r;
    }
    // Yol 2 - FindObjectOfType Type
    if (g_mFindObjectOfType) {
        void* a[1]; a[0] = typeObj;
        @try { r = i_runtime_invoke(g_mFindObjectOfType, NULL, a, NULL); } @catch (...) {}
        if (r) return r;
    }
    // Yol 3 - FindAnyObjectByType Type : Unity 6 yeni API
    if (g_mFindAnyByType) {
        void* a[1]; a[0] = typeObj;
        @try { r = i_runtime_invoke(g_mFindAnyByType, NULL, a, NULL); } @catch (...) {}
        if (r) return r;
    }
    return NULL;
}

static void few1n_findCar(void) {
    if (!i_runtime_invoke) return;
    @try {
        // Adim 1 - CarDriveSystem'i bul
        if (g_carDriveTypeObj) {
            void* found = few1n_findByType(g_carDriveTypeObj);
            if (found) {
                g_carDrive = found;
                fFind++;
                void* rb = *(void**)((uintptr_t)found + 0x48);   // _jfu_k__BackingField
                if (rb) g_rb = rb;
            } else {
                g_carDrive = NULL;   // arabadan indiyse temizle
            }
        }
        // Adim 2 - CarPlayerInput'u bul, nitro icin
        if (g_carInputTypeObj) {
            void* inp = few1n_findByType(g_carInputTypeObj);
            if (inp) {
                void* nos = *(void**)((uintptr_t)inp + 0x28);    // jhs -> CarNitro
                if (nos) g_carNitro = nos;
            }
        }
        // SONSUZ NITRO - hooksuz: CarNitro._jhq_k__BackingField (+0x34) surekli doldur
        if (isInfiniteNitroEnabled && g_carNitro) {
            *(float*)((uintptr_t)g_carNitro + 0x34) = 1.0f;
        }
        // HIZ HILESI - eski h_driveMove hookundan tasindi (hooklar calismiyor)
        if (g_carDrive) {
            uintptr_t d = (uintptr_t)g_carDrive;
            diagDrive  = g_carDrive;
            diagCurSpd = *(float*)(d + 0x9C);   // currentSpeed
            diagTopSpd = *(float*)(d + 0x98);   // topSpeed
            if (speedMode > 1) {
                if (g_origTop <= 0.0f && diagTopSpd > 0.0f && diagTopSpd < 1000.0f) g_origTop = diagTopSpd;
                float base = (g_origTop > 0.0f) ? g_origTop : 200.0f;
                *(float*)(d + 0x98) = base * 3.0f;      // topSpeed cap'ini yukselt
            } else if (g_origTop > 0.0f && !isCarPanelEnabled) {
                *(float*)(d + 0x98) = g_origTop; g_origTop = 0.0f;   // eski degere don
            }
            // ASIL HIZ: linearVelocity'nin yatay bileseni buyutulur (y'ye dokunulmaz -> ucmaz)
            if (g_rb && speedMode > 1) {
                Vec3 v = {0,0,0};
                rbGetVelIl(g_rb, &v);
                float horiz = sqrtf(v.x*v.x + v.z*v.z);
                diagVel = horiz;
                if (horiz > 0.5f) {
                    float cap = (speedMode == 2) ? 90.0f : (speedMode == 3) ? 140.0f : 230.0f;
                    float ns = horiz * 1.06f; if (ns > cap) ns = cap;
                    float k = ns / horiz;
                    v.x *= k; v.z *= k;
                    rbSetVelIl(g_rb, &v);
                }
            }
        }
        // Adim 3 - Arac kontrol paneli degerlerini yaz
        if (isCarPanelEnabled && g_carDrive) {
            uintptr_t d = (uintptr_t)g_carDrive;
            *(unsigned char*)(d + 0x61) = 1;              // overrideAcceleration
            *(float*)(d + 0x6C) = carAccelPower;          // overrideAccelerationPower
            *(unsigned char*)(d + 0x62) = 1;              // overrideSteering
            *(float*)(d + 0x64) = carSteerPower;          // overrideSteeringPower
            *(float*)(d + 0x98) = carTopSpeed;            // topSpeed
        }
    } @catch (...) {}
}

// ===== GERCEK COZUM: CarPlayerInput.FixedUpdate (SADECE YEREL OYUNCU) =====
// script.json + il2cpp.h ile dogrulandi:
//   CarPlayerInput$$FixedUpdate = RVA 0x54D0BC0  (88935360)
//   CarPlayerInput_Fields: +0x20 jhr=CarDriveSystem*, +0x28 jhs=CarNitro*
//   CarDriveSystem_Fields: +0x48 _jfu_k__BackingField = UnityEngine.Rigidbody*
// NOT: CarDriveSystem'de Update/FixedUpdate YOK -> eski hooklar bu yuzden hic tetiklenmedi.
static void (*o_playerInputFixed)(void*) = NULL;
static void h_playerInputFixed(void* self) {
    fInput++;
    if (self) {
        @try {
            void* drive = *(void**)((uintptr_t)self + 0x20);   // jhr -> CarDriveSystem
            if (drive) {
                g_carDrive = drive;
                void* rb = *(void**)((uintptr_t)drive + 0x48); // Rigidbody backing field
                if (rb) g_rb = rb;
            }
            void* nos = *(void**)((uintptr_t)self + 0x28);     // jhs -> CarNitro
            if (nos) g_carNitro = nos;
            // ---- ARAC KONTROL PANELI: oyunun kendi override alanlarini kullan ----
            // timeScale'e dokunmaz -> sadece bu arac etkilenir, digerleri fark etmez
            if (isCarPanelEnabled && g_carDrive) {
                uintptr_t d = (uintptr_t)g_carDrive;
                *(unsigned char*)(d + 0x61) = 1;              // overrideAcceleration
                *(float*)(d + 0x6C) = carAccelPower;          // overrideAccelerationPower
                *(unsigned char*)(d + 0x62) = 1;              // overrideSteering
                *(float*)(d + 0x64) = carSteerPower;          // overrideSteeringPower
                *(float*)(d + 0x98) = carTopSpeed;            // topSpeed
            }
        } @catch (...) {}
    }
    if (o_playerInputFixed) o_playerInputFixed(self);
}

// ===== RCCP araba (oyuncu bunu kullaniyor) - Rigidbody yakala =====
// RCCP_MainComponent Rigidbody @ self+0x48
static void (*o_rccpUpdate)(void*) = NULL;
static void h_rccpUpdate(void* self) {
    fRccp++;
    if (self) {
        @try {
            void* rb = *(void**)((uintptr_t)self + 0x48);   // RCCP Rigidbody
            if (rb) g_rb = rb;
        } @catch (...) {}
    }
    if (o_rccpUpdate) o_rccpUpdate(self);
}

// ===== SmoothSync (AGDAKI TUM ARABALAR - oyuncu dahil) : Rigidbody yakala =====
// SmoothSyncRCC.rb @ 0xF8 (Rigidbody), carController @ 0xF0
static void (*o_smRCC)(void*) = NULL;
static void h_smRCC(void* self) {
    fSmRCC++;
    if (self) {
        @try {
            void* rb = *(void**)((uintptr_t)self + 0xF8);   // SmoothSyncRCC.rb
            if (rb) g_rb = rb;
        } @catch (...) {}
    }
    if (o_smRCC) o_smRCC(self);
}
static void (*o_smPUN)(void*) = NULL;
static void h_smPUN(void* self) {
    fSmPUN++;
    if (o_smPUN) o_smPUN(self);
}

// ===== CUSTOM PLATE =====
static void (*o_plateChange)(void*, struct PlateHolder) = NULL;
static void h_plateChange(void* self, struct PlateHolder holder) {
    fPlate++;
    if (isCustomPlateEnabled && customPlateText[0] != '\0') {
        void* r = mkStr([NSString stringWithUTF8String:customPlateText]);
        if (r) holder.t = r;
    }
    if (o_plateChange) o_plateChange(self, holder);
}

// ===== CHAT =====
static void (*o_chatSend)(void*, void*) = NULL;
static void h_chatSend(void* self, void* msg) {
    fChat++;
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

// ===== ODA ISMI RICH TEXT ACIGI =====
// HR_UI_RoomListLine.elw(roomName,map,pc,pc,pwd,roomInfo) : oda satiri kurulunca
// RoomNameText'in richText'ini zorla ac (oyun guncellemede kapatmis)
static void (*o_roomLineSetup)(void*, void*, void*, unsigned char, unsigned char, void*, void*) = NULL;
static void h_roomLineSetup(void* self, void* a, void* b, unsigned char c, unsigned char d, void* e, void* f) {
    fRoomLine++;
    if (o_roomLineSetup) o_roomLineSetup(self, a, b, c, d, e, f);   // once oyun ismi set etsin (buyuk harfe cevirir)
    if (self) {
        @try {
            void* nameText = *(void**)((uintptr_t)self + 0x20);    // RoomNameText (TMP_Text)
            if (nameText) {
                if (g_mSetRichText) setRichTextIl(nameText, true); // richText ac
                // HAM ismi RoomInfo'dan al (buyuk harfe cevrilmemis, kucuk harf tag'ler) -> etiketler render olur
                void* rawName = (f && rinfo_getName) ? rinfo_getName(f) : a;
                if (rawName && tmp_set_text) tmp_set_text(nameText, rawName);
            }
            void* mapText = *(void**)((uintptr_t)self + 0x28);     // MapNameText
            if (mapText && g_mSetRichText) setRichTextIl(mapText, true);
        } @catch (...) {}
    }
}

// ===== ODA KURMA HATASI TESHIS =====
// OnCreateRoomFailed/OnJoinRoomFailed -> neden reddedildigini loga yaz
static void (*o_onCreateFail)(void*, short, void*) = NULL;
static void h_onCreateFail(void* self, short code, void* msg) {
    @try { FLog([NSString stringWithFormat:@"ODA KURMA HATASI: kod=%d mesaj=%@", (int)code, readStr(msg)]); } @catch (...) {}
    if (o_onCreateFail) o_onCreateFail(self, code, msg);
}
static void (*o_onJoinFail)(void*, short, void*) = NULL;
static void h_onJoinFail(void* self, short code, void* msg) {
    @try { FLog([NSString stringWithFormat:@"ODA GIRIS HATASI: kod=%d mesaj=%@", (int)code, readStr(msg)]); } @catch (...) {}
    if (o_onJoinFail) o_onJoinFail(self, code, msg);
}

// ===== "ODA OLUSTUR" butonu: yazdigin rich text ismi DOGRUDAN pn_createRoom ile kur =====
// Oyunun kendi CreateRoomButton'u rich text ismi reddediyordu; biz dogrulamayi atliyoruz.
static void (*o_createRoomBtn)(void*) = NULL;
static void h_createRoomBtn(void* self) {
    fCreateBtn++;
    @try {
        void* nameInput = *(void**)((uintptr_t)self + 0x48);   // roomNameInput
        NSString *typed = (nameInput && tmp_get_text) ? readStr(tmp_get_text(nameInput)) : @"";
        // SADECE rich text isimlerde bypass yap (normal odalar oyunun akisini kullansin -> harita korunur)
        BOOL isRich = ([typed rangeOfString:@"<"].location != NSNotFound);
        if (isRich && typed.length > 0 && pn_createRoom && i_object_new && g_roomOptionsClass) {
            static int gc = 0; gc++;
            NSString *zwsp = [NSString stringWithFormat:@"%C", (unichar)0x200B];
            NSMutableString *uniq = [NSMutableString stringWithString:typed];
            int reps = (gc % 400) + 1;
            for (int i = 0; i < reps; i++) [uniq appendString:zwsp];
            void* ns = mkStr(uniq);
            void* opts = i_object_new(g_roomOptionsClass);
            if (ns && opts) {
                *(bool*)((uintptr_t)opts + 0x10) = true;
                *(bool*)((uintptr_t)opts + 0x11) = true;
                *(int*) ((uintptr_t)opts + 0x14) = 8;
                *(int*) ((uintptr_t)opts + 0x1C) = roomSpamTTL;
                pn_createRoom(ns, opts, NULL, NULL);
                FLog(@"Oda kuruldu (direkt pn_createRoom, dogrulama atlandi)");
                return;   // orijinali CAGIRMA -> reddi atla
            }
        }
    } @catch (...) {}
    if (o_createRoomBtn) o_createRoomBtn(self);   // yedek: normal akis
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
// ==== BEYAZ / BUZ MAVISI NEON TEMA ====
#define C_BG     [UIColor colorWithRed:0.03 green:0.07 blue:0.11 alpha:0.72]
#define C_CARD   [UIColor colorWithRed:0.60 green:0.90 blue:1.0 alpha:0.09]
#define C_ON     [UIColor colorWithRed:0.45 green:0.93 blue:1.0 alpha:1.0]   // buz mavisi neon
#define C_OFF    [UIColor colorWithRed:0.18 green:0.26 blue:0.33 alpha:1.0]
#define C_RED    [UIColor colorWithRed:1.0 green:0.35 blue:0.55 alpha:1.0]
#define C_ACCENT [UIColor colorWithRed:0.70 green:0.95 blue:1.0 alpha:1.0]   // beyaza calan buz
#define C_GOLD   [UIColor colorWithRed:0.85 green:0.97 blue:1.0 alpha:1.0]   // parlak buz beyazi
#define C_CYAN   [UIColor colorWithRed:0.30 green:0.85 blue:1.0 alpha:1.0]
#define C_TEXT   [UIColor colorWithRed:0.94 green:0.99 blue:1.0 alpha:1.0]
#define C_SUB    [UIColor colorWithRed:0.65 green:0.85 blue:0.95 alpha:0.62]

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
@property (nonatomic, strong) CADisplayLink *dl;
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
    CAGradientLayer *hgrad = [CAGradientLayer layer];
    hgrad.frame = CGRectMake(0,0,pw,60);
    hgrad.colors = @[(id)[UIColor colorWithRed:0.0 green:0.55 blue:0.75 alpha:0.35].CGColor,
                     (id)[UIColor colorWithRed:0.35 green:0.15 blue:0.75 alpha:0.30].CGColor];
    hgrad.startPoint = CGPointMake(0,0); hgrad.endPoint = CGPointMake(1,1);
    [header.layer insertSublayer:hgrad atIndex:0];
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16,10,pw-80,26)];
    title.text = @"FEW1N MOD MENU"; title.textColor = [UIColor whiteColor];
    title.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBlack];
    [header addSubview:title];
    UILabel *ver = [[UILabel alloc] initWithFrame:CGRectMake(16,34,pw-80,16)];
    ver.text = [NSString stringWithFormat:@"v25.5 Unity6 | Base:0x%lX | H:%d", (unsigned long)global_base, hookSuccessCount];
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
    y = [self actionRow:@"\U0001F504  Araci Degistir (oyun ici)" color:C_GOLD atY:y action:@selector(openCarSelect)];
    y = [self toggle:@"⚙️  Arac Kontrol Paneli" sub:@"Motor/direksiyon/maks hiz - timeScale'siz" key:@"carpanel" atY:y action:@selector(tapCarPanel)];
    y = [self actionRow:@"✏️  Arac Ayarlarini Duzenle" color:C_CYAN atY:y action:@selector(editCarPanel)];
    y = [self toggle:@"\U0001F4A8  Sonsuz Nitro" sub:@"Nitro hic bitmez" key:@"nitro" atY:y action:@selector(tapNitro)];
    y = [self toggle:@"\U0001F681  Ucus (Hover)"  sub:@"Havada asili kal, surerek uc" key:@"fly" atY:y action:@selector(tapFly)];
    y = [self toggle:@"\U0001FAB6  Dusuk Yercekimi" sub:@"Dusus yavas, floaty" key:@"lowgrav" atY:y action:@selector(tapLowGrav)];
    y = [self actionRow:@"\U0001F53C  ZIPLA (bas)" color:C_ON atY:y action:@selector(jumpTap)];
    y = [self actionRow:@"\U0001F53C  Yukari Isinlan (takildinca)" color:C_CYAN atY:y action:@selector(teleportUp)];
    y = [self actionRow:@"➡️  Ileri Isinlan (+50)" color:C_CYAN atY:y action:@selector(teleportForward)];
    y = [self actionRow:@"\U0001F4CD  Konum Kaydet" color:C_GOLD atY:y action:@selector(saveTeleportPos)];
    y = [self actionRow:@"\U0001F680  Kayitli Konuma Isinlan" color:C_GOLD atY:y action:@selector(teleportSaved)];

    y = [self header:@"\U0001F4AC  CHAT" atY:y];
    y = [self toggle:@"\U0001F3A8  Renkli Chat" sub:@"[FEW1N] prefix + cyan" key:@"colorchat" atY:y action:@selector(tapColorChat)];
    y = [self toggle:@"\U0001F4E2  Chat Spam" sub:@"50ms araligla mesaj" key:@"chatspam" atY:y action:@selector(tapChatSpam)];
    y = [self actionRow:@"✏️  Spam Yazisini Duzenle" color:C_CYAN atY:y action:@selector(editSpam)];
    y = [self actionRow:@"\U0001F9EA  Rich Text Test (chate gonder)" color:C_ACCENT atY:y action:@selector(richTextTest)];
    {
        UIView *ssrow = [[UIView alloc] initWithFrame:CGRectMake(12,y,pw-24,44)];
        ssrow.backgroundColor = C_CARD; ssrow.layer.cornerRadius = 12;
        UIButton *ssb = [UIButton buttonWithType:UIButtonTypeSystem];
        ssb.frame = CGRectMake(0,0,pw-24,44);
        NSArray *nm = @[@"Duz", @"Cerceveli", @"Semboller", @"Renkli"];
        [ssb setTitle:[NSString stringWithFormat:@"\U0001F3AD Spam Stili: %@", nm[spamStyle % 4]] forState:UIControlStateNormal];
        [ssb setTitleColor:C_ACCENT forState:UIControlStateNormal];
        ssb.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        [ssb addTarget:self action:@selector(pickSpamStyle:) forControlEvents:UIControlEventTouchUpInside];
        [ssrow addSubview:ssb];
        [self.contentView addSubview:ssrow];
        y += 52;
    }
    y = [self toggle:@"\U0001F3AC  ASCII Animasyon Spam" sub:@"Kare kare animasyon chate" key:@"asciianim" atY:y action:@selector(tapAsciiAnim)];
    {
        UIView *arow = [[UIView alloc] initWithFrame:CGRectMake(12,y,pw-24,44)];
        arow.backgroundColor = C_CARD; arow.layer.cornerRadius = 12;
        UIButton *ab = [UIButton buttonWithType:UIButtonTypeSystem];
        ab.frame = CGRectMake(0,0,pw-24,44);
        [ab setTitle:[NSString stringWithFormat:@"\U0001F3AC Animasyon Sec (%d/%d)", asciiAnimIndex + 1, (int)asciiAnims().count] forState:UIControlStateNormal];
        [ab setTitleColor:C_ACCENT forState:UIControlStateNormal];
        ab.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        [ab addTarget:self action:@selector(pickAsciiAnim:) forControlEvents:UIControlEventTouchUpInside];
        [arow addSubview:ab];
        [self.contentView addSubview:arow];
        y += 52;
    }

    y = [self header:@"\U0001F522  PLAKA" atY:y];
    self.plateBtn = [self actionButtonRow:&y];
    [self.plateBtn addTarget:self action:@selector(editPlate) forControlEvents:UIControlEventTouchUpInside];

    y = [self header:@"\U0001F4DB  OYUNCU" atY:y];
    self.nameBtn = [self actionButtonRow:&y];
    [self.nameBtn setTitle:@"\U0001F4DB  Isim Degistir" forState:UIControlStateNormal];
    [self.nameBtn setTitleColor:C_CYAN forState:UIControlStateNormal];
    [self.nameBtn addTarget:self action:@selector(changeName) forControlEvents:UIControlEventTouchUpInside];
    y = [self actionRow:@"\U0001F308  Rainbow Isim (Rich Text)" color:C_ACCENT atY:y action:@selector(rainbowName)];
    y = [self actionRow:@"\U0001F3A8  Gradient Isim (Kirmizi-Mavi)" color:C_ACCENT atY:y action:@selector(gradientName)];

    y = [self header:@"\U0001F511  ODA" atY:y];
    y = [self toggle:@"\U0001F513  Sifre Kirici" sub:@"Sifreli odalara gir" key:@"bypass" atY:y action:@selector(tapBypass)];
    y = [self actionRow:@"\U0001F465  Odadaki Oyuncular (isim kopyala)" color:C_CYAN atY:y action:@selector(showPlayers)];
    y = [self actionRow:@"\U0001F3A8  Renkli Oda Ac (rich text)" color:C_ON atY:y action:@selector(createColoredRoom)];
    y = [self actionRow:@"\U0001F3E0  Ozel Isimli Oda Kur" color:C_GOLD atY:y action:@selector(createOneRoom)];
    y = [self toggle:@"\U0001F4E5  Fake Oda Spam" sub:@"Kalici odalar birikir" key:@"roomspam" atY:y action:@selector(tapRoomSpam)];
    y = [self toggle:@"\U0001F504  Surekli Mod" sub:@"Kapatana kadar spam" key:@"roomcont" atY:y action:@selector(tapRoomContinuous)];
    y = [self actionRow:@"✏️  Oda Ismini Ayarla" color:C_CYAN atY:y action:@selector(editRoomName)];
    y = [self actionRow:@"\U0001F4CA  Oda Sayisi (0=sinirsiz)" color:C_CYAN atY:y action:@selector(editRoomSpamCount)];
    y = [self actionRow:@"⏱️  Oda Acik Kalma Suresi" color:C_CYAN atY:y action:@selector(editRoomTTL)];
    y = [self actionRow:@"⏰  Spam Araligi" color:C_CYAN atY:y action:@selector(editRoomSpamInterval)];

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
    // iGameGod gibi: timeScale'i HER FRAME zorla (oyun resetlese bile tutar)
    if (self.dl) { [self.dl invalidate]; self.dl = nil; }
    self.dl = [CADisplayLink displayLinkWithTarget:self selector:@selector(frameTick)];
    [self.dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    if (isSpamEnabled && !spamTimer)
        spamTimer = [NSTimer scheduledTimerWithTimeInterval:0.05 target:self selector:@selector(fireSpam) userInfo:nil repeats:YES];
    if (isAsciiAnimEnabled && !asciiTimer)
        asciiTimer = [NSTimer scheduledTimerWithTimeInterval:0.4 target:self selector:@selector(fireAscii) userInfo:nil repeats:YES];
}

- (CGFloat)header:(NSString*)text atY:(CGFloat)y {
    CGFloat pw = self.panel.bounds.size.width;
    // sol aksан cubugu (neon)
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(12, y+2, 4, 16)];
    bar.backgroundColor = C_CYAN; bar.layer.cornerRadius = 2;
    bar.layer.shadowColor = C_CYAN.CGColor; bar.layer.shadowRadius = 4;
    bar.layer.shadowOpacity = 0.8; bar.layer.shadowOffset = CGSizeMake(0,0);
    [self.contentView addSubview:bar];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(24,y,pw-40,20)];
    l.text = [text uppercaseString]; l.textColor = C_TEXT;
    l.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBlack];
    [self.contentView addSubview:l];
    // ince gradient ayirici cizgi
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(12, y+22, pw-24, 1)];
    CAGradientLayer *lg = [CAGradientLayer layer];
    lg.frame = CGRectMake(0,0,pw-24,1);
    lg.colors = @[(id)C_CYAN.CGColor, (id)[UIColor clearColor].CGColor];
    lg.startPoint = CGPointMake(0,0.5); lg.endPoint = CGPointMake(1,0.5);
    [line.layer addSublayer:lg];
    [self.contentView addSubview:line];
    return y + 30;
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
    [self setToggle:@"fly"       on:isFlyEnabled];
    [self setToggle:@"lowgrav"   on:isLowGravEnabled];
    [self setToggle:@"colorchat" on:isColorChatEnabled];
    [self setToggle:@"chatspam"  on:isSpamEnabled];
    [self setToggle:@"asciianim" on:isAsciiAnimEnabled];
    [self setToggle:@"bypass"    on:isBypassPasswordEnabled];
    [self setToggle:@"roomspam"  on:isRoomSpamEnabled];
    [self setToggle:@"roomcont"  on:roomSpamContinuous];
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

- (void)frameTick {
    enforceScale();   // her ekran frame'inde timeScale'i zorla
    // Ucus (hover) ve dusuk yercekimi - Rigidbody dikey hizini ayarla
    if ((isFlyEnabled || isLowGravEnabled) && g_rb) {
        @try {
            Vec3 v = {0,0,0};
            rbGetVelIl(g_rb, &v);
            if (isFlyEnabled) {
                v.y = 0.0f;                       // havada asili kal (dusme yok)
            } else if (isLowGravEnabled && v.y < 0.0f) {
                v.y *= 0.25f;                     // dususu yavaslat (floaty)
            }
            rbSetVelIl(g_rb, &v);
        } @catch (...) {}
    }
}

- (void)jumpTap {
    FLog(g_rb ? @"ZIPLA basildi: rb VAR, uygulaniyor" : @"ZIPLA basildi: rb YOK! (once arabaya bin+sur)");
    if (g_rb) {
        @try {
            Vec3 v = {0,0,0};
            rbGetVelIl(g_rb, &v);
            v.y = 14.0f;                          // yukari itme (zipla)
            rbSetVelIl(g_rb, &v);
        } @catch (NSException *e) { FLog([@"ZIPLA hata: " stringByAppendingString:e.reason ?: @"?"]); }
    }
}

// ===== ISINLANMA (kendi araban - Rigidbody.position) =====
- (void)saveTeleportPos {
    if (g_rb) {
        @try {
            rbGetPosIl(g_rb, &g_savedPos);
            g_hasSavedPos = true;
            FLog([NSString stringWithFormat:@"Konum kaydedildi: %.1f, %.1f, %.1f", g_savedPos.x, g_savedPos.y, g_savedPos.z]);
        } @catch (...) {}
    }
}
- (void)teleportSaved {
    if (g_rb && g_hasSavedPos) {
        @try {
            Vec3 p = g_savedPos;
            rbSetPosIl(g_rb, &p);
            Vec3 z = {0,0,0}; rbSetVelIl(g_rb, &z);   // hizi sifirla
        } @catch (...) {}
    }
}
- (void)teleportForward {
    if (g_rb) {
        @try {
            Vec3 p = {0,0,0};
            rbGetPosIl(g_rb, &p);
            p.z += 50.0f;   // 50 birim ileri (harita eksenine gore)
            p.y += 3.0f;
            rbSetPosIl(g_rb, &p);
        } @catch (...) {}
    }
}
- (void)teleportUp {
    if (g_rb) {
        @try {
            Vec3 p = {0,0,0};
            rbGetPosIl(g_rb, &p);
            p.y += 30.0f;   // 30 birim yukari (takildiginda kurtul)
            rbSetPosIl(g_rb, &p);
        } @catch (...) {}
    }
}

- (void)tick {
    enforceScale();
    few1n_findCar();   // hooksuz araba arama + arac paneli uygulamasi
    // her ~2 sn'de bir canli hiz teshisini loga yaz
    static int tc = 0;
    if (++tc >= 7) {
        tc = 0;
        float ts = g_il2cppReady ? getTimeScaleVal() : (ts_get ? ts_get() : -1.0f);
        FLog([NSString stringWithFormat:@"[DIAG] ARAMA=%ld carDrive=%@ | bulucu=%@ tip=%@",
              fFind, g_carDrive ? @"VAR" : @"YOK",
              (g_mFindObjInactive || g_mFindObjectOfType || g_mFindAnyByType) ? @"VAR" : @"YOK",
              g_carDriveTypeObj ? @"VAR" : @"YOK"]);
        FLog([NSString stringWithFormat:@"[DIAG] nitro=%ld drive=%ld plate=%ld RCCP=%ld smRCC=%ld smPUN=%ld",
              fNitro, fDrive, fPlate, fRccp, fSmRCC, fSmPUN]);
        FLog([NSString stringWithFormat:@"[DIAG] rb=%@ rbMethod=%@ nitroDeg=%.2f il2cpp=%@",
              g_rb ? @"VAR" : @"YOK", g_mRbSetVel ? @"VAR" : @"YOK", diagNitroVal, g_il2cppReady ? @"OK" : @"YOK"]);
    }
}

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
- (void)tapFly       { isFlyEnabled            = !isFlyEnabled;            saveBool(@"fly", isFlyEnabled);                  [self refreshUI]; }
- (void)tapLowGrav   { isLowGravEnabled        = !isLowGravEnabled;        saveBool(@"lowgrav", isLowGravEnabled);          [self refreshUI]; }
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
        NSString *base = [NSString stringWithUTF8String:chatSpamText];
        NSString *msg;
        if (spamStyle == 1)      msg = [NSString stringWithFormat:@"═══ %@ ═══", base];
        else if (spamStyle == 2) msg = [NSString stringWithFormat:@"★彡 %@ 彡★", base];
        else if (spamStyle == 3) msg = [NSString stringWithFormat:@"<color=#00FFFF><b>★ %@ ★</b></color>", base];
        else                     msg = base;
        void* s = mkStr(msg);
        if (s) chatSend(mgr, s);
    } @catch (...) {}
}

- (void)pickSpamStyle:(UIButton*)b {
    spamStyle = (spamStyle + 1) % 4;
    saveInt(@"spamStyle", spamStyle);
    NSArray *names = @[@"Duz", @"Cerceveli", @"Semboller", @"Renkli"];
    [b setTitle:[NSString stringWithFormat:@"\U0001F3AD Spam Stili: %@", names[spamStyle]] forState:UIControlStateNormal];
}

- (void)fireAscii {
    if (!chatGetInst || !chatSend) return;
    @try {
        NSArray *anims = asciiAnims();
        if (anims.count == 0) return;
        if (asciiAnimIndex < 0 || asciiAnimIndex >= (int)anims.count) asciiAnimIndex = 0;
        NSArray *frames = anims[asciiAnimIndex];
        if (frames.count == 0) return;
        if (asciiFrameIdx < 0 || asciiFrameIdx >= (int)frames.count) asciiFrameIdx = 0;
        NSString *frame = frames[asciiFrameIdx];
        asciiFrameIdx++;
        void* mgr = chatGetInst();
        if (!mgr) return;
        void* s = mkStr(frame);
        if (s) chatSend(mgr, s);
    } @catch (...) {}
}

- (void)tapAsciiAnim {
    isAsciiAnimEnabled = !isAsciiAnimEnabled;
    saveBool(@"asciianim", isAsciiAnimEnabled);
    if (asciiTimer) { [asciiTimer invalidate]; asciiTimer = nil; }
    if (isAsciiAnimEnabled) {
        asciiFrameIdx = 0;
        asciiTimer = [NSTimer scheduledTimerWithTimeInterval:0.4 target:self selector:@selector(fireAscii) userInfo:nil repeats:YES];
    }
    [self refreshUI];
}

- (void)pickAsciiAnim:(UIButton*)b {
    asciiAnimIndex = (asciiAnimIndex + 1) % (int)asciiAnims().count;
    asciiFrameIdx = 0;
    saveInt(@"asciiIdx", asciiAnimIndex);
    [b setTitle:[NSString stringWithFormat:@"\U0001F3AC Animasyon Sec (%d/%d)", asciiAnimIndex + 1, (int)asciiAnims().count] forState:UIControlStateNormal];
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

// Her harfe rainbow renk verir (Unity TMP rich text acigi)
- (void)rainbowName {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"\U0001F308 Rainbow Isim"
                                                               message:@"Isim yaz - her harf rainbow olur:" preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf){ tf.text = @"FEW1N"; tf.clearButtonMode = UITextFieldViewModeAlways; }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Uygula" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        NSString *src = ac.textFields.firstObject.text;
        if (src.length == 0 || !pn_setNickName) return;
        NSArray *cols = @[@"#FF0000",@"#FF7F00",@"#FFFF00",@"#00FF00",@"#00FFFF",@"#4466FF",@"#FF00FF"];
        NSMutableString *rich = [NSMutableString string];
        for (NSUInteger i = 0; i < src.length; i++) {
            NSString *ch = [src substringWithRange:NSMakeRange(i,1)];
            [rich appendFormat:@"<color=%@><b>%@</b></color>", cols[i % cols.count], ch];
        }
        void* ns = mkStr(rich);
        if (ns) {
            pn_setNickName(ns);
            if (playerManagerGetInst && pm_updateNicknameInternal) {
                @try { void* pm = playerManagerGetInst(); if (pm) pm_updateNicknameInternal(pm, ns); } @catch (...) {}
            }
            [self.nameBtn setTitle:@"\U0001F308 Rainbow isim aktif ✅" forState:UIControlStateNormal];
            [self.nameBtn setTitleColor:C_ON forState:UIControlStateNormal];
        }
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Iptal" style:UIAlertActionStyleCancel handler:nil]];
    [self present:ac];
}

// ===== FAKE ODA SPAM =====
- (void)createOneRoom {
    @try {
        // BENZERSIZ isim: Photon oda isimleri UNIQUE olmali. Gorunmez zero-width space (​)
        // ekle -> her oda benzersiz, ekranda GORUNMEZ ve buyuk harfe cevrilse bile kalir.
        static int g_roomCounter = 0;
        g_roomCounter++;
        NSMutableString *uniqName = [NSMutableString stringWithUTF8String:customRoomName];
        int reps = (g_roomCounter % 400) + 1;
        for (int i = 0; i < reps; i++) [uniqName appendString:@"​"];
        void* nameStr = mkStr(uniqName);
        if (!nameStr) return;
        // KALICI oda: RoomOptions.EmptyRoomTtl ver -> sen cikinca oda silinmez, listede kalir
        if (pn_createRoom && i_object_new && g_roomOptionsClass) {
            void* opts = i_object_new(g_roomOptionsClass);
            if (opts) {
                *(bool*)((uintptr_t)opts + 0x10) = true;     // isVisible
                *(bool*)((uintptr_t)opts + 0x11) = true;     // isOpen
                *(int*) ((uintptr_t)opts + 0x14) = 8;        // MaxPlayers
                *(int*) ((uintptr_t)opts + 0x1C) = roomSpamTTL;   // EmptyRoomTtl (ayarlanabilir)
                pn_createRoom(nameStr, opts, NULL, NULL);
                return;
            }
        }
        // yedek: oyunun kendi butonu (oda kalici olmayabilir)
        if (lobbyGetInst && lobby_createRoom) {
            void* lobby = lobbyGetInst();
            if (!lobby) return;
            if (tmp_set_text) {
                void* nameInput = *(void**)((uintptr_t)lobby + 0x48);   // roomNameInput
                if (nameInput) tmp_set_text(nameInput, nameStr);
            }
            lobby_createRoom(lobby);
        }
    } @catch (...) {}
}

// Ayri buton: rich text ismi sor + direkt renkli oda ac
- (void)createColoredRoom {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"\U0001F3A8 Renkli Oda Ac"
                                                               message:@"Oda ismi (rich text destekli):" preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf){
        tf.text = [NSString stringWithUTF8String:customRoomName];
        tf.clearButtonMode = UITextFieldViewModeAlways;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"\U0001F3E0 Oda Ac" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        NSString *t = ac.textFields.firstObject.text;
        if (t.length > 0) {
            strncpy(customRoomName, t.UTF8String, sizeof(customRoomName)-1);
            customRoomName[sizeof(customRoomName)-1]='\0';
            saveStr(@"roomName", t);
        }
        [self createOneRoom];   // direkt kur (pn_createRoom, dogrulama atlanir)
    }]];
    // hazir renk sablonlari
    [ac addAction:[UIAlertAction actionWithTitle:@"\U0001F308 Gokkusagi Sablonu" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        strncpy(customRoomName, "<b><color=#FF0000>F</color><color=#FF7F00>E</color><color=#FFFF00>W</color><color=#00FF00>1</color><color=#00FFFF>N</color></b>", sizeof(customRoomName)-1);
        customRoomName[sizeof(customRoomName)-1]='\0';
        saveStr(@"roomName", [NSString stringWithUTF8String:customRoomName]);
        [self createOneRoom];
    }]];
    // ==== UNICODE SABLONLARI (richText GEREKTIRMEZ - garanti gorunur) ====
    // Bunlar tag degil gercek karakter: oyun strip edemez, ToUpper bozamaz, richText kapali olsa da cikar
    void (^uni)(NSString*, const char*) = ^(NSString *title, const char *val){
        [ac addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            strncpy(customRoomName, val, sizeof(customRoomName)-1);
            customRoomName[sizeof(customRoomName)-1]='\0';
            saveStr(@"roomName", [NSString stringWithUTF8String:customRoomName]);
            FLog(@"Unicode oda ismi secildi (richText gerekmez)");
            [self createOneRoom];
        }]];
    };
    uni(@"✨ Unicode: Kalin + Yildiz",  "【★ \U0001D5D9\U0001D5D8\U0001D5E7\U0001D7ED\U0001D5ED ★】");
    uni(@"✨ Unicode: Genis Harf",      "▄▀▄ ＦＥＷ１Ｎ ▄▀▄");
    uni(@"✨ Unicode: Gotik Suslu",     "꧁༺ \U0001D571\U0001D570\U0001D582\U0001D7CF\U0001D573 ༻꧂");
    [ac addAction:[UIAlertAction actionWithTitle:@"Iptal" style:UIAlertActionStyleCancel handler:nil]];
    [self present:ac];
}

// ===== OYUN ICI ARAC DEGISTIRME =====
// HR_MainMenuHandler singleton'ini il2cpp static field uzerinden al
static void* few1n_getMainMenu(void) {
    if (!g_mmhField || !i_field_static_get_value) return NULL;
    void* inst = NULL;
    @try { i_field_static_get_value(g_mmhField, &inst); } @catch (...) { return NULL; }
    return inst;
}
// Parametresiz bir MethodInfo'yu il2cpp uzerinden cagir
static bool few1n_invoke0(void* method, void* obj, const char* label) {
    if (!method || !i_runtime_invoke) { FLog([NSString stringWithFormat:@"%s: metod yok", label]); return false; }
    if (!obj) { FLog([NSString stringWithFormat:@"%s: nesne yok", label]); return false; }
    @try { i_runtime_invoke(method, obj, NULL, NULL); FLog([NSString stringWithFormat:@"%s: calisti", label]); return true; }
    @catch (...) { FLog([NSString stringWithFormat:@"%s: cagri hatasi", label]); return false; }
}

- (void)openCarSelect {
    // Her adim loglanir ki "tepki yok" durumunda nerede takildigi gorulsun
    FLog(@"--- Arac degistirme denemesi ---");
    // Adim 1 - Lobi yolu: HR_PhotonLobbyManager.EnableCarSelectionMenu
    if (!lobbyGetInst)         FLog(@"Adim1:lobbyGetInst pointeri YOK");
    else if (!lobby_carSelectMenu) FLog(@"Adim1:EnableCarSelectionMenu pointeri YOK");
    else {
        void* lobby = NULL;
        @try { lobby = lobbyGetInst(); } @catch (...) {}
        if (!lobby) FLog(@"Adim1:Lobi nesnesi YOK (yaris sahnesinde lobi olmayabilir)");
        else {
            @try { lobby_carSelectMenu(lobby); FLog(@"Adim1:Lobi yoluyla acildi"); return; }
            @catch (...) { FLog(@"Adim1:Lobi cagrisi hata verdi"); }
        }
    }
    // Adim 2 - Ana menu yolu: HR_MainMenuHandler singleton + il2cpp
    void* mm = few1n_getMainMenu();
    if (!mm) { FLog(@"Adim2:MainMenuHandler bulunamadi - bu sahnede arac degistirilemiyor"); return; }
    FLog(@"Adim2:MainMenuHandler bulundu, arac menusu kullanilabilir");
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"\U0001F504 Arac Degistir"
                                                               message:@"Araclar arasinda gez, sonra sec"
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"➡️ Sonraki Arac" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        few1n_invoke0(g_mNextCar, few1n_getMainMenu(), "Sonraki arac");
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"⬅️ Onceki Arac" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        few1n_invoke0(g_mPrevCar, few1n_getMainMenu(), "Onceki arac");
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"✅ Bu Araci Sec" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        few1n_invoke0(g_mSelectCar, few1n_getMainMenu(), "Arac secildi");
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Kapat" style:UIAlertActionStyleCancel handler:nil]];
    [self present:ac];
}

// ===== ARAC KONTROL PANELI =====
- (void)tapCarPanel {
    isCarPanelEnabled = !isCarPanelEnabled;
    saveBool(@"carpanel", isCarPanelEnabled);
    if (!isCarPanelEnabled && g_carDrive) {
        @try {   // kapatinca oyunun kendi kontroluna geri birak
            uintptr_t d = (uintptr_t)g_carDrive;
            *(unsigned char*)(d + 0x61) = 0;
            *(unsigned char*)(d + 0x62) = 0;
        } @catch (...) {}
    }
    FLog([NSString stringWithFormat:@"Arac paneli: %@", isCarPanelEnabled ? @"ACIK" : @"KAPALI"]);
    [self refreshUI];
}

- (void)editCarPanel {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"\U0001F3CE Arac Ayarlari"
                                                               message:@"Motor gucu / direksiyon / maks hiz"
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf){
        tf.placeholder = @"Motor gucu (normal 1.0)";
        tf.text = [NSString stringWithFormat:@"%.1f", carAccelPower];
        tf.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf){
        tf.placeholder = @"Direksiyon (normal 1.0)";
        tf.text = [NSString stringWithFormat:@"%.1f", carSteerPower];
        tf.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf){
        tf.placeholder = @"Maks hiz";
        tf.text = [NSString stringWithFormat:@"%.0f", carTopSpeed];
        tf.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Kaydet" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        float v1 = [ac.textFields[0].text floatValue];
        float v2 = [ac.textFields[1].text floatValue];
        float v3 = [ac.textFields[2].text floatValue];
        if (v1 > 0.1f && v1 <= 50.0f)   carAccelPower = v1;
        if (v2 > 0.1f && v2 <= 20.0f)   carSteerPower = v2;
        if (v3 > 10.0f && v3 <= 2000.0f) carTopSpeed  = v3;
        saveFloat(@"caraccel", carAccelPower);
        saveFloat(@"carsteer", carSteerPower);
        saveFloat(@"cartop",   carTopSpeed);
        FLog([NSString stringWithFormat:@"Arac ayari: guc=%.1f direksiyon=%.1f maksHiz=%.0f", carAccelPower, carSteerPower, carTopSpeed]);
        [self refreshUI];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Varsayilana Don" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){
        carAccelPower = 1.0f; carSteerPower = 1.0f; carTopSpeed = 150.0f;
        saveFloat(@"caraccel", carAccelPower);
        saveFloat(@"carsteer", carSteerPower);
        saveFloat(@"cartop",   carTopSpeed);
        FLog(@"Arac ayarlari sifirlandi");
        [self refreshUI];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Iptal" style:UIAlertActionStyleCancel handler:nil]];
    [self present:ac];
}

// ===== ODADAKI OYUNCULARI LISTELE + ISIM KOPYALA =====
// il2cpp dizi yerlesimi: +0x18 = eleman sayisi, +0x20 = ilk eleman
- (void)showPlayers {
    if (!pn_getPlayerList) { FLog(@"Oyuncu listesi pointeri yok"); return; }
    loadPlayerDB();
    NSMutableArray<NSDictionary*> *rows = [NSMutableArray array];   // her satir: nick/uid/etiket/gecmis
    int changedCount = 0;
    @try {
        void* arr = pn_getPlayerList();
        if (!arr) { FLog(@"Odada degilsin (PlayerList bos)"); return; }
        int cnt = (int)(*(uintptr_t*)((uintptr_t)arr + 0x18));
        if (cnt < 0 || cnt > 64) { FLog([NSString stringWithFormat:@"Oyuncu sayisi anormal: %d", cnt]); return; }
        void** elems = (void**)((uintptr_t)arr + 0x20);
        for (int i = 0; i < cnt; i++) {
            void* p = elems[i];
            if (!p) continue;
            NSString *nick = (ply_getNickName) ? readStr(ply_getNickName(p)) : @"";
            if (nick.length == 0) nick = @"(isimsiz)";
            NSString *uid  = (ply_getUserId) ? readStr(ply_getUserId(p)) : @"";
            int actor = (ply_getActorNumber) ? ply_getActorNumber(p) : 0;
            BOOL master = (ply_getIsMaster) ? ply_getIsMaster(p) : NO;

            // ---- UserId ile isim degisikligi tespiti ----
            NSString *flag = @"";
            NSArray *hist = @[];
            if (uid.length > 0) {
                NSDictionary *rec = g_playerDB[uid];
                NSString *last = rec[@"last"];
                NSMutableArray *all = rec[@"all"] ? [rec[@"all"] mutableCopy] : [NSMutableArray array];
                if (last && ![last isEqualToString:nick]) {
                    flag = @"  ⚠️";
                    changedCount++;
                    FLog([NSString stringWithFormat:@"ISIM DEGISTI: %@ -> %@ (uid %@)", last, nick, uid]);
                }
                if (![all containsObject:nick]) [all addObject:nick];
                g_playerDB[uid] = @{@"last": nick, @"all": all};
                hist = all;
            }
            [rows addObject:@{@"title": [NSString stringWithFormat:@"%@%@  #%d%@", master ? @"\U0001F451 " : @"", nick, actor, flag],
                              @"nick": nick, @"uid": uid, @"hist": hist}];
        }
        savePlayerDB();
    } @catch (...) { FLog(@"Oyuncu listesi okunamadi"); return; }

    if (rows.count == 0) { FLog(@"Odada oyuncu bulunamadi"); return; }
    FLog([NSString stringWithFormat:@"Odada %lu oyuncu, %d isim degisikligi", (unsigned long)rows.count, changedCount]);

    NSString *msg = (changedCount > 0)
        ? [NSString stringWithFormat:@"%lu kisi - ⚠️ %d kisi ismini degistirmis", (unsigned long)rows.count, changedCount]
        : [NSString stringWithFormat:@"%lu kisi - detay icin sec", (unsigned long)rows.count];
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"\U0001F465 Odadaki Oyuncular"
                                                               message:msg preferredStyle:UIAlertControllerStyleAlert];
    for (NSDictionary *r in rows) {
        [ac addAction:[UIAlertAction actionWithTitle:r[@"title"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            [self showPlayerDetail:r];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Kapat" style:UIAlertActionStyleCancel handler:nil]];
    [self present:ac];
}

// Secilen oyuncunun kimligi + bu UserId ile gorulmus tum isimler
- (void)showPlayerDetail:(NSDictionary*)r {
    NSString *nick = r[@"nick"];
    NSString *uid  = r[@"uid"];
    NSArray  *hist = r[@"hist"];

    NSMutableString *m = [NSMutableString string];
    [m appendFormat:@"Su anki isim: %@\n", nick];
    if (uid.length > 0) {
        [m appendFormat:@"UserId: %@\n", uid];
        if (hist.count > 1) {
            [m appendFormat:@"\n⚠️ Bu kisi %lu farkli isim kullanmis:\n", (unsigned long)hist.count];
            for (NSString *n in hist) [m appendFormat:@"  • %@\n", n];
        } else {
            [m appendString:@"\nBu kisi hep ayni ismi kullanmis."];
        }
    } else {
        [m appendString:@"UserId bos - oyun kimlik dogrulama kullanmiyor,\nbu kisi isim degisikligi icin takip edilemez."];
    }

    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"\U0001F50D Oyuncu Detayi"
                                                               message:m preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"\U0001F4CB Ismi Kopyala" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        [UIPasteboard generalPasteboard].string = nick;
        FLog([NSString stringWithFormat:@"Isim kopyalandi: %@", nick]);
    }]];
    if (uid.length > 0) {
        [ac addAction:[UIAlertAction actionWithTitle:@"\U0001F511 UserId Kopyala" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
            [UIPasteboard generalPasteboard].string = uid;
            FLog([NSString stringWithFormat:@"UserId kopyalandi: %@", uid]);
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Kapat" style:UIAlertActionStyleCancel handler:nil]];
    [self present:ac];
}

- (void)fireRoomSpam {
    if (!isRoomSpamEnabled || !lobbyGetInst) return;
    @try {
        // Hedef sayiya ulasildiysa ve surekli mod kapaliysa dur
        if (!roomSpamContinuous && roomSpamMaxCount > 0 && roomSpamCount >= roomSpamMaxCount) {
            isRoomSpamEnabled = false;
            if (roomSpamTimer) { [roomSpamTimer invalidate]; roomSpamTimer = nil; }
            [self refreshUI];
            return;
        }
        void* lobby = lobbyGetInst();
        if (!lobby) return;
        if (roomSpamPhase == 0) { [self createOneRoom]; roomSpamCount++; roomSpamPhase = 1; }
        else { if (lobby_leaveRoom) lobby_leaveRoom(lobby); roomSpamPhase = 0; }
        [self refreshUI];   // durum etiketini guncelle
    } @catch (...) {}
}

- (void)tapRoomSpam {
    isRoomSpamEnabled = !isRoomSpamEnabled;
    saveBool(@"roomspam", isRoomSpamEnabled);
    if (roomSpamTimer) { [roomSpamTimer invalidate]; roomSpamTimer = nil; }
    if (isRoomSpamEnabled) {
        roomSpamPhase = 0;
        roomSpamCount = 0;   // sayaci sifirla
        float iv = roomSpamInterval >= 0.1f ? roomSpamInterval : 1.5f;
        roomSpamTimer = [NSTimer scheduledTimerWithTimeInterval:iv target:self selector:@selector(fireRoomSpam) userInfo:nil repeats:YES];
    }
    [self refreshUI];
}

- (void)editRoomSpamCount {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"\U0001F4CA Oda Sayisi" message:@"Kac oda? (0 = sinirsiz)" preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf){ tf.keyboardType = UIKeyboardTypeNumberPad; tf.text = [NSString stringWithFormat:@"%d", roomSpamMaxCount]; }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Kaydet" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        int v = [ac.textFields.firstObject.text intValue];
        if (v >= 0) { roomSpamMaxCount = v; roomSpamContinuous = (v == 0); saveInt(@"roomMax", v); [self refreshUI]; }
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Iptal" style:UIAlertActionStyleCancel handler:nil]];
    [self present:ac];
}

- (void)editRoomTTL {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"⏱️ Oda Acik Kalma" message:@"Kac saniye acik kalsin?" preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf){ tf.keyboardType = UIKeyboardTypeNumberPad; tf.text = [NSString stringWithFormat:@"%d", roomSpamTTL/1000]; }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Kaydet" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        int sec = [ac.textFields.firstObject.text intValue];
        if (sec > 0) { if (sec > 300) sec = 300; roomSpamTTL = sec * 1000; saveInt(@"roomTTL", roomSpamTTL); }
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Iptal" style:UIAlertActionStyleCancel handler:nil]];
    [self present:ac];
}

- (void)editRoomSpamInterval {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"⏰ Spam Araligi" message:@"Kac saniyede bir? (0.1 = cok hizli, 5 = yavas)" preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf){ tf.keyboardType = UIKeyboardTypeDecimalPad; tf.text = [NSString stringWithFormat:@"%.1f", roomSpamInterval]; }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Kaydet" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        float v = [ac.textFields.firstObject.text floatValue];
        if (v >= 0.1f && v <= 5.0f) { roomSpamInterval = v; saveInt(@"roomIv", (int)(v*100)); }
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Iptal" style:UIAlertActionStyleCancel handler:nil]];
    [self present:ac];
}

- (void)tapRoomContinuous {
    roomSpamContinuous = !roomSpamContinuous;
    saveBool(@"roomcont", roomSpamContinuous);
    [self refreshUI];
}

- (void)editRoomName {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"\U0001F3E0 Oda Ismi (Rich Text)"
                                                               message:@"Rich text kodu da girebilirsin:" preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf){ tf.text = [NSString stringWithUTF8String:customRoomName]; tf.clearButtonMode = UITextFieldViewModeAlways; }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Kaydet" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        NSString *t = ac.textFields.firstObject.text;
        if (t.length > 0) { strncpy(customRoomName, t.UTF8String, sizeof(customRoomName)-1); customRoomName[sizeof(customRoomName)-1]='\0'; saveStr(@"roomName", t); }
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Iptal" style:UIAlertActionStyleCancel handler:nil]];
    [self present:ac];
}

// Gradient isim: 2 renk arasi gecis (kirmizi->mavi)
- (void)gradientName {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"\U0001F3A8 Gradient Isim"
                                                               message:@"Isim yaz - kirmizidan maviye:" preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf){ tf.text = @"FEW1N"; tf.clearButtonMode = UITextFieldViewModeAlways; }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Uygula" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a){
        NSString *src = ac.textFields.firstObject.text;
        if (src.length == 0 || !pn_setNickName) return;
        NSUInteger n = src.length;
        NSMutableString *rich = [NSMutableString string];
        for (NSUInteger i = 0; i < n; i++) {
            float t = (n > 1) ? (float)i/(n-1) : 0.0f;
            int r = (int)(255*(1-t)), g = 0, bl = (int)(255*t);
            NSString *ch = [src substringWithRange:NSMakeRange(i,1)];
            [rich appendFormat:@"<color=#%02X%02X%02X><b>%@</b></color>", r, g, bl, ch];
        }
        void* ns = mkStr(rich);
        if (ns) {
            pn_setNickName(ns);
            if (playerManagerGetInst && pm_updateNicknameInternal) {
                @try { void* pm = playerManagerGetInst(); if (pm) pm_updateNicknameInternal(pm, ns); } @catch (...) {}
            }
            [self.nameBtn setTitle:@"\U0001F3A8 Gradient isim aktif ✅" forState:UIControlStateNormal];
            [self.nameBtn setTitleColor:C_ON forState:UIControlStateNormal];
        }
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Iptal" style:UIAlertActionStyleCancel handler:nil]];
    [self present:ac];
}

// Rich text test: cesitli etiketleri chate gonder, hangileri render oluyor gor
- (void)richTextTest {
    if (!chatGetInst || !chatSend) return;
    NSArray *tests = @[
        @"<i>italik</i> <u>alti-cizili</u> <s>ustu-cizili</s>",
        @"<mark=#FFFF0044>vurgu</mark> <sup>ust</sup><sub>alt</sub>",
        @"<size=200%>DEV</size> normal <size=50%>kucuk</size>",
        @"gizli:<alpha=#00>gizliyazi</alpha><alpha=#FF>-son",
        @"<voffset=1em>yukari</voffset> <cspace=10>aralikli</cspace>"
    ];
    __block int i = 0;
    for (NSString *t in tests) {
        double delay = (i++) * 0.6;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            @try { void* mgr = chatGetInst(); void* s = mkStr(t); if (mgr && s) chatSend(mgr, s); } @catch (...) {}
        });
    }
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
    CGFloat ow = MIN(640.0, W - 20), oh = MIN(440.0, H - 20);
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
    // === KAPSAMLI DURUM OZETI ===
    NSMutableString *st = [NSMutableString string];
    [st appendString:@"══════ FEW1N DURUM ══════\n"];
    [st appendFormat:@"Base: 0x%lX | il2cpp: %@\n", (unsigned long)global_base, g_il2cppReady ? @"OK" : @"YOK"];
    [st appendFormat:@"Hook: %d OK / %d FAIL\n", hookSuccessCount, hookFailCount];
    [st appendString:@"── il2cpp metodlari ──\n"];
    [st appendFormat:@"Time:%@ RB-vel:%@ RB-pos:%@\n", g_mSetTS?@"✓":@"✗", g_mRbSetVel?@"✓":@"✗", rb_setPos?@"✓":@"✗"];
    [st appendFormat:@"TMP-rich:%@ RoomOpt:%@ CreateRoom:%@ RoomName:%@\n", g_mSetRichText?@"✓":@"✗", g_roomOptionsClass?@"✓":@"✗", pn_createRoom?@"✓":@"✗", rinfo_getName?@"✓":@"✗"];
    [st appendString:@"── araba hook tetiklenme ──\n"];
    [st appendFormat:@"*ANA* CarPlayerInput.FixedUpdate: %ld\n", fInput];
    [st appendFormat:@"CarDriveSystem:%@ CarNitro:%@\n", g_carDrive?@"✓":@"✗", g_carNitro?@"✓":@"✗"];
    [st appendFormat:@"AracPanel:%@ guc=%.1f dir=%.1f maks=%.0f\n", isCarPanelEnabled?@"A":@"K", carAccelPower, carSteerPower, carTopSpeed];
    [st appendFormat:@"nitro:%ld drive:%ld plate:%ld\nRCCP:%ld smRCC:%ld smPUN:%ld\n", fNitro, fDrive, fPlate, fRccp, fSmRCC, fSmPUN];
    [st appendFormat:@"Rigidbody(g_rb): %@  %@\n", g_rb?@"YAKALANDI ✓":@"YOK ✗", g_rb?@"(zipla/ucus/isinla calisir)":@"(arabaya bin+sur)"];
    [st appendString:@"── BASE TESTI (araba disi hook) ──\n"];
    [st appendFormat:@"timeScale:%ld chat:%ld odaSatir:%ld odaKurBtn:%ld baglanti:%ld\n", fTS, fChat, fRoomLine, fCreateBtn, fConn];
    long nonCar = fTS + fChat + fRoomLine + fCreateBtn + fConn;
    [st appendFormat:@"SONUC: %@\n", nonCar > 0 ? @"HOOKLAR CALISIYOR -> sorun araba sinifi" : @"HICBIR HOOK CALISMIYOR -> OFFSET/BASE OLU"];
    [st appendString:@"── ozellik durumlari ──\n"];
    [st appendFormat:@"Hiz:%dx Nitro:%@ Ucus:%@ DusukG:%@\n", speedMode, isInfiniteNitroEnabled?@"A":@"K", isFlyEnabled?@"A":@"K", isLowGravEnabled?@"A":@"K"];
    [st appendFormat:@"RenkliChat:%@ Spam:%@ ASCII:%@ Sifre:%@\n", isColorChatEnabled?@"A":@"K", isSpamEnabled?@"A":@"K", isAsciiAnimEnabled?@"A":@"K", isBypassPasswordEnabled?@"A":@"K"];
    [st appendFormat:@"OdaSpam:%@ (kurulan:%d) SurekliMod:%@\n", isRoomSpamEnabled?@"A":@"K", roomSpamCount, roomSpamContinuous?@"A":@"K"];
    [st appendString:@"════════════════════════\n\n"];
    NSString *joined = gLog.count ? [gLog componentsJoinedByString:@"\n"] : @"(log yok - henuz calismadi)";
    self.logText.text = [st stringByAppendingString:joined];
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
    // ekrandaki her seyi kopyala (durum ozeti + loglar)
    NSString *full = self.logText.text ?: @"";
    [UIPasteboard generalPasteboard].string = full;
    self.logText.text = [full stringByAppendingString:@"\n\n>>> PANOYA KOPYALANDI <<<"];
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
    isCarPanelEnabled      = loadBool(@"carpanel", false);
    carAccelPower          = loadFloat(@"caraccel", 3.0f);
    carSteerPower          = loadFloat(@"carsteer", 1.0f);
    carTopSpeed            = loadFloat(@"cartop",   300.0f);
    isColorChatEnabled     = loadBool(@"colorchat", false);
    isSpamEnabled          = loadBool(@"chatspam", false);
    isBypassPasswordEnabled= loadBool(@"bypass", true);
    isFlyEnabled           = loadBool(@"fly", false);
    isLowGravEnabled       = loadBool(@"lowgrav", false);
    isAsciiAnimEnabled     = loadBool(@"asciianim", false);
    asciiAnimIndex         = loadInt(@"asciiIdx", 0);
    isRoomSpamEnabled      = false;   // spam her acilista kapali baslasin (guvenlik)
    roomSpamMaxCount       = loadInt(@"roomMax", 0);
    roomSpamTTL            = loadInt(@"roomTTL", 300000);
    roomSpamInterval       = loadInt(@"roomIv", 150) / 100.0f;
    roomSpamContinuous     = loadBool(@"roomcont", true);
    spamStyle              = loadInt(@"spamStyle", 0);
    NSString* rn = loadStr(@"roomName", @"<b><color=#FF0000>FEW1N</color></b>");
    strncpy(customRoomName, rn.UTF8String, sizeof(customRoomName)-1); customRoomName[sizeof(customRoomName)-1]='\0';
    isCustomPlateEnabled   = loadBool(@"plateEnabled", false);
    isAutoMoneyEnabled     = loadBool(@"automoney", false);
    customMoneyAmount      = loadInt(@"moneyAmount", 100000000);
    NSString* pt = loadStr(@"plateText", @"FEW1N");
    strncpy(customPlateText, pt.UTF8String, sizeof(customPlateText)-1); customPlateText[sizeof(customPlateText)-1]='\0';
    NSString* stx = loadStr(@"spamText", @"FEW1N MOD MENU!");
    strncpy(chatSpamText, stx.UTF8String, sizeof(chatSpamText)-1); chatSpamText[sizeof(chatSpamText)-1]='\0';
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
    few1n_initIl2cpp();

    chatGetInst               = (void*(*)(void))(b + 0x31A6168);
    chatSend                  = (void(*)(void*,void*))(b + 0x31A626C);
    tmp_set_text              = (void(*)(void*,void*))(b + 0x65F4CC8);
    tmp_get_text              = (void*(*)(void*))(b + 0x65F4CC0);
    rinfo_getName             = (void*(*)(void*))(b + 0x59293A4);   // RoomInfo.get_Name
    pn_setNickName            = (void(*)(void*))(b + 0x5933940);
    lobbyGetInst              = (void*(*)(void))(b + 0x54A8098);
    playerManagerGetInst      = (void*(*)(void))(b + 0x5A2DE20);
    pm_updateNicknameInternal = (void(*)(void*,void*))(b + 0x5A3DDD4);
    pm_getMoney               = (int(*)(void*))(b + 0x5A4346C);
    pm_syncWithServer         = (void(*)(void*))(b + 0x5A2DF80);
    pm_addMoney               = (void(*)(void*,int))(b + 0x5A43A2C);
    ts_get                    = (float(*)(void))(b + 0x67718D8);
    rb_getVel                 = (void(*)(void*,Vec3*))(b + 0x6837B7C);
    rb_setVel                 = (void(*)(void*,Vec3*))(b + 0x6837C88);
    rb_getPos                 = (void(*)(void*,Vec3*))(b + 0x6838E24);   // get_position_Injected
    rb_setPos                 = (void(*)(void*,Vec3*))(b + 0x6838F30);   // set_position_Injected
    lobby_createRoom          = (void(*)(void*))(b + 0x54A94A4);
    lobby_leaveRoom           = (void(*)(void*))(b + 0x54A9F1C);
    pn_createRoom             = (bool(*)(void*,void*,void*,void*))(b + 0x5939B4C);
    pn_getPlayerList          = (void*(*)(void))(b + 0x59339D0);
    ply_getNickName           = (void*(*)(void*))(b + 0x5924574);
    ply_getActorNumber        = (int(*)(void*))(b + 0x592455C);
    ply_getIsMaster           = (bool(*)(void*))(b + 0x5924640);
    ply_getUserId             = (void*(*)(void*))(b + 0x5924630);
    lobby_carSelectMenu       = (void(*)(void*))(b + 0x54ABFD4);

    safeHook((void*)(b + 0x6771918), (void*)h_setTimeScale,  (void**)&o_setTimeScale,     "set_timeScale");
    safeHook((void*)(b + 0x5938844), (void*)h_closeConnection,(void**)&o_closeConnection, "CloseConnection");
    safeHook((void*)(b + 0x54CFE14), (void*)h_getNitro,       (void**)&o_getNitro,        "get_nitroAmount");
    safeHook((void*)(b + 0x54CFE1C), (void*)h_setNitro,       (void**)&o_setNitro,        "set_nitroAmount");
    safeHook((void*)(b + 0x54CCAA0), (void*)h_driveMove,      (void**)&o_driveMove,       "CarDriveSystem.Move");
    safeHook((void*)(b + 0x54D0BC0), (void*)h_playerInputFixed,(void**)&o_playerInputFixed,"CarPlayerInput.FixedUpdate *ANA*");
    safeHook((void*)(b + 0x59C4BCC), (void*)h_rccpUpdate,     (void**)&o_rccpUpdate,      "RCCP.Update(rb yakala)");
    safeHook((void*)(b + 0x5A57390), (void*)h_smRCC,          (void**)&o_smRCC,           "SmoothSyncRCC.Update(rb!)");
    safeHook((void*)(b + 0x5A4F72C), (void*)h_smPUN,          (void**)&o_smPUN,           "SmoothSyncPUN2.Update");
    safeHook((void*)(b + 0x54EA1FC), (void*)h_plateChange,    (void**)&o_plateChange,     "PlateVariant.Change");
    safeHook((void*)(b + 0x31A626C), (void*)h_chatSend,       (void**)&o_chatSend,        "ChatManager.Send");
    safeHook((void*)(b + 0x54B32F4), (void*)h_roomConnect,    (void**)&o_roomConnect,     "RoomListLine.Connect");
    safeHook((void*)(b + 0x54B33E0), (void*)h_roomLineSetup,  (void**)&o_roomLineSetup,   "RoomListLine.Setup(richtext)");
    safeHook((void*)(b + 0x54A9A30), (void*)h_onCreateFail,   (void**)&o_onCreateFail,    "OnCreateRoomFailed(teshis)");
    safeHook((void*)(b + 0x54A9498), (void*)h_onJoinFail,     (void**)&o_onJoinFail,      "OnJoinRoomFailed(teshis)");
    safeHook((void*)(b + 0x54A94A4), (void*)h_createRoomBtn,  (void**)&o_createRoomBtn,   "CreateRoomButton(richtext)");
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
    FLog(@"v25.5 basladi, UnityFramework araniyor...");
    restoreSettings();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ few1n_poll(); });
}