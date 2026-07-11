#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <substrate.h>
#include <mach-o/dyld.h>

// Oyunun ana kütüphanesinin (UnityFramework) hafızadaki başlangıç adresini alıyoruz (ASLR bypass)
uintptr_t GetUnityFrameworkBase() {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *image_name = _dyld_get_image_name(i);
        if (strstr(image_name, "UnityFramework")) {
            return _dyld_get_image_vmaddr_slide(i);
        }
    }
    return 0;
}

// Global Değişkenler (Mod Menü'deki Switch'lere bağlanacak)
bool isSpeedHackEnabled = false;
bool isFlyingCarEnabled = false;

// Orijinal Fonksiyonlar için Pointer'lar
void (*old_set_timeScale)(float value);
void (*old_AddForce)(void* instance, float x, float y, float z, int mode);

// Hooked Fonksiyonlar
void hooked_set_timeScale(float value) {
    if (isSpeedHackEnabled) {
        // Hız hilesi açıksa oyunu 5 kat hızlandır
        old_set_timeScale(5.0f);
    } else {
        old_set_timeScale(value);
    }
}

void hooked_AddForce(void* instance, float x, float y, float z, int mode) {
    if (isFlyingCarEnabled) {
        // Uçan araba açıksa arabanın Y (yukarı) eksenindeki kuvvetini artır
        y += 50000.0f; // Yukarı doğru devasa bir güç!
    }
    old_AddForce(instance, x, y, z, mode);
}

// Oyun açıldığında hilelerin belleğe yerleşmesi (Hooking)
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
