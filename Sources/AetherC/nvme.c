// NVMe-SMART lesen (SSD-Gesundheit) und APFS-Klon-Hinweis – beides nur lesend, ohne Administratorrechte.
//
// SMART: öffentliche Plug-in-Schnittstelle aus dem SDK (IOKit/storage/nvme/NVMeSMARTLibExternal.h), so wie sie auch
// smartmontools verwendet. Gesucht wird ab jedem IOBlockStorageDevice aufwärts der Eintrag mit „NVMe SMART Capable“.
// Fehlt der Header beim Bauen, liefert aether_nvme_supported() false und es wird nichts gelesen.
//
// Das 512-Byte-Protokoll wird roh übergeben und in Swift (AetherCore, NVMeHealth.decode) nach der NVMe-Spezifikation
// dekodiert – so hängt nichts von Feldnamen der Header-Struktur ab.
#include "AetherC.h"
#include <string.h>
#include <sys/attr.h>
#include <unistd.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>

#if __has_include(<IOKit/storage/nvme/NVMeSMARTLibExternal.h>)
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/storage/nvme/NVMeSMARTLibExternal.h>
#define AETHER_HAS_NVME 1
#else
#define AETHER_HAS_NVME 0
#endif

bool aether_nvme_supported(void) {
    return AETHER_HAS_NVME ? true : false;
}

#if AETHER_HAS_NVME

static void aether_copy_string(CFTypeRef value, char *out, size_t size) {
    if (size == 0) return;
    out[0] = 0;
    if (value == NULL || CFGetTypeID(value) != CFStringGetTypeID()) return;
    if (!CFStringGetCString((CFStringRef)value, out, (CFIndex)size, kCFStringEncodingUTF8)) {
        out[0] = 0;
        return;
    }
    // Leerzeichen am Ende entfernen (Herstellerangaben sind oft aufgefüllt)
    size_t length = strlen(out);
    while (length > 0 && out[length - 1] == ' ') {
        out[--length] = 0;
    }
}

static bool aether_is_smart_capable(io_registry_entry_t entry) {
    CFTypeRef value = IORegistryEntryCreateCFProperty(entry, CFSTR(kIOPropertyNVMeSMARTCapableKey), kCFAllocatorDefault, 0);
    if (value == NULL) return false;
    bool capable = CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)value);
    CFRelease(value);
    return capable;
}

/// Ab `start` aufwärts (höchstens sechs Ebenen) den Eintrag mit „NVMe SMART Capable“ suchen. Rückgabe: gehalten (Aufrufer gibt frei) oder 0.
static io_registry_entry_t aether_find_capable(io_registry_entry_t start) {
    io_registry_entry_t entry = start;
    IOObjectRetain(entry);
    for (int depth = 0; depth < 6; depth++) {
        if (aether_is_smart_capable(entry)) return entry;
        io_registry_entry_t parent = 0;
        kern_return_t result = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent);
        IOObjectRelease(entry);
        if (result != KERN_SUCCESS || parent == 0) return 0;
        entry = parent;
    }
    IOObjectRelease(entry);
    return 0;
}

/// Modell und Firmware aus „Device Characteristics“ (IOStorageDeviceCharacteristics.h). Keine Seriennummer.
static void aether_read_characteristics(io_registry_entry_t entry, AetherNVMeDrive *drive) {
    CFTypeRef characteristics = IORegistryEntryCreateCFProperty(entry, CFSTR("Device Characteristics"), kCFAllocatorDefault, 0);
    if (characteristics == NULL) return;
    if (CFGetTypeID(characteristics) == CFDictionaryGetTypeID()) {
        CFDictionaryRef dictionary = (CFDictionaryRef)characteristics;
        aether_copy_string(CFDictionaryGetValue(dictionary, CFSTR("Product Name")), drive->model, sizeof(drive->model));
        aether_copy_string(CFDictionaryGetValue(dictionary, CFSTR("Product Revision Level")), drive->firmware, sizeof(drive->firmware));
    }
    CFRelease(characteristics);
}

static void aether_read_smart(io_registry_entry_t service, AetherNVMeDrive *drive) {
    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    kern_return_t result = IOCreatePlugInInterfaceForService(service, kIONVMeSMARTUserClientTypeID, kIOCFPlugInInterfaceID,
                                                             &plugin, &score);
    drive->ioReturn = (int32_t)result;
    if (result != KERN_SUCCESS || plugin == NULL) {
        drive->status = (result == kIOReturnNotPrivileged || result == kIOReturnNotPermitted)
            ? AETHER_NVME_NOT_PERMITTED : AETHER_NVME_PLUGIN_FAILED;
        return;
    }
    IONVMeSMARTInterface **smart = NULL;
    HRESULT queried = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID), (LPVOID *)&smart);
    if (queried != S_OK || smart == NULL) {
        drive->status = AETHER_NVME_INTERFACE_FAILED;
        IODestroyPlugInInterface(plugin);
        return;
    }
    union {
        NVMeSMARTData data;
        uint8_t bytes[512];
    } buffer;
    memset(&buffer, 0, sizeof(buffer));
    IOReturn readResult = (*smart)->SMARTReadData(smart, &buffer.data);
    drive->ioReturn = (int32_t)readResult;
    if (readResult == kIOReturnSuccess) {
        size_t count = sizeof(buffer) < sizeof(drive->raw) ? sizeof(buffer) : sizeof(drive->raw);
        memcpy(drive->raw, buffer.bytes, count);
        drive->status = AETHER_NVME_OK;
    } else {
        drive->status = (readResult == kIOReturnNotPrivileged || readResult == kIOReturnNotPermitted)
            ? AETHER_NVME_NOT_PERMITTED : AETHER_NVME_READ_FAILED;
    }
    (*smart)->Release(smart);
    IODestroyPlugInInterface(plugin);
}

int32_t aether_nvme_read_all(AetherNVMeDrive *drives, int32_t capacity) {
    if (drives == NULL || capacity <= 0) return 0;
    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDevice"), &iterator) != KERN_SUCCESS) {
        return 0;
    }
    int32_t count = 0;
    uint64_t seen[32];
    int seenCount = 0;
    io_object_t device;
    while (count < capacity && (device = IOIteratorNext(iterator)) != 0) {
        io_registry_entry_t capable = aether_find_capable(device);
        if (capable != 0) {
            uint64_t entryID = 0;
            IORegistryEntryGetRegistryEntryID(capable, &entryID);
            bool duplicate = false;
            for (int index = 0; index < seenCount; index++) {
                if (seen[index] == entryID) { duplicate = true; break; }
            }
            if (!duplicate && seenCount < 32) {
                seen[seenCount++] = entryID;
                AetherNVMeDrive *drive = &drives[count++];
                memset(drive, 0, sizeof(*drive));
                aether_read_characteristics(device, drive);
                if (drive->model[0] == 0) aether_read_characteristics(capable, drive);
                aether_read_smart(capable, drive);
            }
            IOObjectRelease(capable);
        }
        IOObjectRelease(device);
    }
    IOObjectRelease(iterator);
    return count;
}

#else

int32_t aether_nvme_read_all(AetherNVMeDrive *drives, int32_t capacity) {
    (void)drives;
    (void)capacity;
    return 0;
}

#endif

bool aether_file_may_share_blocks(const char *path, bool *mayShare) {
#if defined(ATTR_CMNEXT_EXT_FLAGS) && defined(EF_MAY_SHARE_BLOCKS) && defined(FSOPT_ATTR_CMN_EXTENDED)
    if (path == NULL || mayShare == NULL) return false;
    struct attrlist list;
    memset(&list, 0, sizeof(list));
    list.bitmapcount = ATTR_BIT_MAP_COUNT;
    list.commonattr = ATTR_CMN_RETURNED_ATTRS;
    list.forkattr = ATTR_CMNEXT_EXT_FLAGS;
    struct __attribute__((packed)) {
        uint32_t length;
        attribute_set_t returned;
        uint64_t flags;
    } buffer;
    memset(&buffer, 0, sizeof(buffer));
    if (getattrlist(path, &list, &buffer, sizeof(buffer), FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW) != 0) return false;
    if ((buffer.returned.forkattr & ATTR_CMNEXT_EXT_FLAGS) == 0) return false;
    *mayShare = (buffer.flags & EF_MAY_SHARE_BLOCKS) != 0;
    return true;
#else
    (void)path;
    (void)mayShare;
    return false;
#endif
}
