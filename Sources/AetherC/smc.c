// SMC lesen – nur lesend. Struktur und Befehlsnummern des AppleSMC-Benutzerclients (seit Jahren unverändert,
// u. a. von smcFanControl und iStat genutzt). Es werden ausschließlich die Befehle „Schlüsselinfo“, „Schlüssel lesen“
// und „Schlüssel an Position“ verwendet.
#include "AetherC.h"
#include <mach/mach.h>
#include <string.h>

enum {
    kAetherSMCHandleYPCEvent = 2,
    kAetherSMCReadKey = 5,
    kAetherSMCGetKeyFromIndex = 8,
    kAetherSMCGetKeyInfo = 9,
};

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} AetherSMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} AetherSMCPLimit;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} AetherSMCKeyInfo;

typedef struct {
    uint32_t key;
    AetherSMCVersion version;
    AetherSMCPLimit pLimitData;
    AetherSMCKeyInfo keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} AetherSMCParam;

_Static_assert(sizeof(AetherSMCParam) == 80, "SMC-Struktur muss 80 Bytes groß sein");

static uint32_t aether_fourcc(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16) | ((uint32_t)(uint8_t)s[2] << 8) |
           (uint32_t)(uint8_t)s[3];
}

static void aether_from_fourcc(uint32_t value, char out[5]) {
    out[0] = (char)((value >> 24) & 0xFF);
    out[1] = (char)((value >> 16) & 0xFF);
    out[2] = (char)((value >> 8) & 0xFF);
    out[3] = (char)(value & 0xFF);
    out[4] = 0;
}

static kern_return_t aether_smc_call(io_connect_t connection, AetherSMCParam *input, AetherSMCParam *output) {
    size_t outputSize = sizeof(AetherSMCParam);
    return IOConnectCallStructMethod(connection, kAetherSMCHandleYPCEvent, input, sizeof(AetherSMCParam), output,
                                     &outputSize);
}

io_connect_t aether_smc_open(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == 0) {
        return 0;
    }
    io_connect_t connection = 0;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    return result == KERN_SUCCESS ? connection : 0;
}

void aether_smc_close(io_connect_t connection) {
    if (connection != 0) {
        IOServiceClose(connection);
    }
}

static bool aether_smc_key_info(io_connect_t connection, uint32_t key, AetherSMCKeyInfo *info) {
    AetherSMCParam input;
    AetherSMCParam output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key;
    input.data8 = kAetherSMCGetKeyInfo;
    if (aether_smc_call(connection, &input, &output) != KERN_SUCCESS || output.result != 0) {
        return false;
    }
    *info = output.keyInfo;
    return true;
}

bool aether_smc_read(io_connect_t connection, const char *key, AetherSMCValue *value) {
    if (connection == 0 || key == NULL || strlen(key) < 4 || value == NULL) {
        return false;
    }
    uint32_t code = aether_fourcc(key);
    AetherSMCKeyInfo info;
    if (!aether_smc_key_info(connection, code, &info)) {
        return false;
    }
    AetherSMCParam input;
    AetherSMCParam output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = code;
    input.keyInfo.dataSize = info.dataSize;
    input.data8 = kAetherSMCReadKey;
    if (aether_smc_call(connection, &input, &output) != KERN_SUCCESS || output.result != 0) {
        return false;
    }
    memset(value, 0, sizeof(*value));
    memcpy(value->key, key, 4);
    aether_from_fourcc(info.dataType, value->type);
    value->size = info.dataSize > 32 ? 32 : info.dataSize;
    memcpy(value->bytes, output.bytes, value->size);
    return true;
}

uint32_t aether_smc_key_count(io_connect_t connection) {
    AetherSMCValue value;
    if (!aether_smc_read(connection, "#KEY", &value) || value.size < 4) {
        return 0;
    }
    return ((uint32_t)value.bytes[0] << 24) | ((uint32_t)value.bytes[1] << 16) | ((uint32_t)value.bytes[2] << 8) |
           (uint32_t)value.bytes[3];
}

bool aether_smc_key_at(io_connect_t connection, uint32_t index, char key[5]) {
    if (connection == 0) {
        return false;
    }
    AetherSMCParam input;
    AetherSMCParam output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.data8 = kAetherSMCGetKeyFromIndex;
    input.data32 = index;
    if (aether_smc_call(connection, &input, &output) != KERN_SUCCESS || output.result != 0) {
        return false;
    }
    aether_from_fourcc(output.key, key);
    return true;
}
