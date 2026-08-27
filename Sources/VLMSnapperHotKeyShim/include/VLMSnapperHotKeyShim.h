#ifndef VLMSNAPPER_HOT_KEY_SHIM_H
#define VLMSNAPPER_HOT_KEY_SHIM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct VLMHotKeyRegistrar *VLMHotKeyRegistrarRef;
typedef struct VLMHotKeyRegistration *VLMHotKeyRegistrationRef;
typedef void (*VLMHotKeyCallback)(uint32_t registrationID, void *context);

enum VLMHotKeyModifierMask {
    VLMHotKeyModifierCommand = 1u << 0,
    VLMHotKeyModifierOption = 1u << 1,
    VLMHotKeyModifierControl = 1u << 2,
    VLMHotKeyModifierShift = 1u << 3,
};

VLMHotKeyRegistrarRef VLMHotKeyRegistrarCreate(
    VLMHotKeyCallback callback,
    void *context,
    int32_t *status
);

void VLMHotKeyRegistrarDestroy(VLMHotKeyRegistrarRef registrar);

int32_t VLMHotKeyRegistrarRegister(
    VLMHotKeyRegistrarRef registrar,
    uint32_t keyCode,
    uint32_t modifierMask,
    uint32_t registrationID,
    VLMHotKeyRegistrationRef *registration
);

int32_t VLMHotKeyRegistrarUnregister(
    VLMHotKeyRegistrarRef registrar,
    VLMHotKeyRegistrationRef registration
);

int32_t VLMHotKeyConflictStatus(void);

#ifdef __cplusplus
}
#endif

#endif
