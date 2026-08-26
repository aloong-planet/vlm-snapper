#include "VLMSnapperHotKeyShim.h"

#include <Carbon/Carbon.h>
#include <stdlib.h>

static const OSType VLMHotKeySignature = 0x564C4D53;

struct VLMHotKeyRegistration {
    EventHotKeyRef hotKey;
    struct VLMHotKeyRegistration *next;
};

struct VLMHotKeyRegistrar {
    EventHandlerRef eventHandler;
    VLMHotKeyCallback callback;
    void *context;
    struct VLMHotKeyRegistration *registrations;
};

static OSStatus VLMHotKeyHandleEvent(
    EventHandlerCallRef nextHandler,
    EventRef event,
    void *userData
) {
    (void)nextHandler;
    struct VLMHotKeyRegistrar *registrar = userData;
    if (registrar == NULL || registrar->callback == NULL) {
        return eventNotHandledErr;
    }

    EventHotKeyID hotKeyID = {0};
    OSStatus status = GetEventParameter(
        event,
        kEventParamDirectObject,
        typeEventHotKeyID,
        NULL,
        sizeof(hotKeyID),
        NULL,
        &hotKeyID
    );
    if (status != noErr || hotKeyID.signature != VLMHotKeySignature) {
        return eventNotHandledErr;
    }

    registrar->callback(hotKeyID.id, registrar->context);
    return noErr;
}

static UInt32 VLMCarbonModifiers(uint32_t modifierMask) {
    UInt32 modifiers = 0;
    if ((modifierMask & VLMHotKeyModifierCommand) != 0) {
        modifiers |= cmdKey;
    }
    if ((modifierMask & VLMHotKeyModifierOption) != 0) {
        modifiers |= optionKey;
    }
    if ((modifierMask & VLMHotKeyModifierControl) != 0) {
        modifiers |= controlKey;
    }
    if ((modifierMask & VLMHotKeyModifierShift) != 0) {
        modifiers |= shiftKey;
    }
    return modifiers;
}

VLMHotKeyRegistrarRef VLMHotKeyRegistrarCreate(
    VLMHotKeyCallback callback,
    void *context,
    int32_t *status
) {
    if (status != NULL) {
        *status = noErr;
    }
    if (callback == NULL) {
        if (status != NULL) {
            *status = paramErr;
        }
        return NULL;
    }

    struct VLMHotKeyRegistrar *registrar = calloc(1, sizeof(*registrar));
    if (registrar == NULL) {
        if (status != NULL) {
            *status = memFullErr;
        }
        return NULL;
    }
    registrar->callback = callback;
    registrar->context = context;

    EventTypeSpec eventType = {
        .eventClass = kEventClassKeyboard,
        .eventKind = kEventHotKeyPressed,
    };
    OSStatus installStatus = InstallEventHandler(
        GetApplicationEventTarget(),
        VLMHotKeyHandleEvent,
        1,
        &eventType,
        registrar,
        &registrar->eventHandler
    );
    if (installStatus != noErr) {
        free(registrar);
        if (status != NULL) {
            *status = installStatus;
        }
        return NULL;
    }
    return registrar;
}

void VLMHotKeyRegistrarDestroy(VLMHotKeyRegistrarRef registrar) {
    if (registrar == NULL) {
        return;
    }
    struct VLMHotKeyRegistration *registration = registrar->registrations;
    while (registration != NULL) {
        struct VLMHotKeyRegistration *next = registration->next;
        UnregisterEventHotKey(registration->hotKey);
        free(registration);
        registration = next;
    }
    if (registrar->eventHandler != NULL) {
        RemoveEventHandler(registrar->eventHandler);
    }
    free(registrar);
}

int32_t VLMHotKeyRegistrarRegister(
    VLMHotKeyRegistrarRef registrar,
    uint32_t keyCode,
    uint32_t modifierMask,
    uint32_t registrationID,
    VLMHotKeyRegistrationRef *registration
) {
    if (registrar == NULL || registration == NULL || registrationID == 0) {
        return paramErr;
    }

    EventHotKeyID hotKeyID = {
        .signature = VLMHotKeySignature,
        .id = registrationID,
    };
    EventHotKeyRef hotKey = NULL;
    OSStatus status = RegisterEventHotKey(
        keyCode,
        VLMCarbonModifiers(modifierMask),
        hotKeyID,
        GetApplicationEventTarget(),
        kEventHotKeyExclusive,
        &hotKey
    );
    if (status != noErr) {
        return status;
    }

    struct VLMHotKeyRegistration *node = malloc(sizeof(*node));
    if (node == NULL) {
        UnregisterEventHotKey(hotKey);
        return memFullErr;
    }
    node->hotKey = hotKey;
    node->next = registrar->registrations;
    registrar->registrations = node;
    *registration = node;
    return noErr;
}

int32_t VLMHotKeyRegistrarUnregister(
    VLMHotKeyRegistrarRef registrar,
    VLMHotKeyRegistrationRef registration
) {
    if (registrar == NULL || registration == NULL) {
        return paramErr;
    }

    struct VLMHotKeyRegistration **cursor = &registrar->registrations;
    while (*cursor != NULL && *cursor != registration) {
        cursor = &(*cursor)->next;
    }
    if (*cursor == NULL) {
        return eventHotKeyInvalidErr;
    }

    *cursor = registration->next;
    OSStatus status = UnregisterEventHotKey(registration->hotKey);
    free(registration);
    return status;
}

int32_t VLMHotKeyConflictStatus(void) {
    return eventHotKeyExistsErr;
}
