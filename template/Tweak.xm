#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <substrate.h>
#include <mach-o/dyld.h>

// --- MOD MENÜ DEĞİŞKENLERİ ---
// Bu değişkenleri Mod Menü (UI) tarafındaki Slider'lara (Kaydırma Çubuğu) bağlayacağız.
bool isSpeedHackEnabled = false;
float speedMultiplier = 1.0f; // Slider değeri: 1.0 (Normal) ile 10.0 (Çok Hızlı) arası

bool isFlyingCarEnabled = false;
float jumpForce = 50000.0f; // Slider değeri: 0 ile 100000 arası

// Oyunun ana kütüphanesinin (UnityFramework) hafızadaki başlangıç adresini alıyoruz
uintptr_t GetUnityFrameworkBase() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *image_name = _dyld_get_image_name(i);
        if (strstr(image_name, "UnityFramework")) {
            return _dyld_get_image_vmaddr_slide(i);
        }
    }
    return 0;
}

// --- ORİJİNAL FONKSİYON POINTER'LARI ---
void (*old_set_timeScale)(float value);
void (*old_AddForce)(void* instance, float x, float y, float z, int mode);

// --- HİLELİ (HOOKED) FONKSİYONLAR ---

// 1. Hız Ayarı (Slider ile kontrol edilir)
void hooked_set_timeScale(float value) {
    if (isSpeedHackEnabled) {
        // Hız hilesi açıksa, Slider'dan gelen değeri kullan (Örn: 2.5x, 5.0x)
        old_set_timeScale(speedMultiplier);
    } else {
        // Kapalıysa oyunun normal hızını kullan
        old_set_timeScale(value);
    }
}

// 2. Uçan Araba / Zıplama Gücü (Slider ile kontrol edilir)
void hooked_AddForce(void* instance, float x, float y, float z, int mode) {
    if (isFlyingCarEnabled) {
        // Slider'dan gelen kuvveti arabanın Y (Yukarı) eksenine ekle
        y += jumpForce; 
    }
    old_AddForce(instance, x, y, z, mode);
}

// --- OYUN AÇILDIĞINDA ÇALIŞACAK KISIM (HOOKING) ---
%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        uintptr_t baseAddr = GetUnityFrameworkBase();
        if (baseAddr != 0) {
            // Hız Hilesi Hook (UnityEngine.Time.set_timeScale) RVA: 0x67523F8
            MSHookFunction((void *)(baseAddr + 0x67523F8), (void *)hooked_set_timeScale, (void **)&old_set_timeScale);
            
            // Uçan Araba Hook (UnityEngine.Rigidbody.AddForce) RVA: 0x6819C80
            MSHookFunction((void *)(baseAddr + 0x6819C80), (void *)hooked_AddForce, (void **)&old_AddForce);
        }
    });
}
