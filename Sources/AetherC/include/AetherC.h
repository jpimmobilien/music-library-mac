// AetherC – kleine C-Hilfen für Schnittstellen, deren Speicherlayout exakt stimmen muss.
//
// SMC (System Management Controller): Temperaturen und Lüfter. Zugriff über die öffentlichen IOKit-Funktionen
// IOServiceOpen und IOConnectCallStructMethod; das Protokoll selbst ist nicht von Apple dokumentiert (siehe
// docs/KONZEPT.md, Risikoanalyse 8.3). AETHER LIEST AUSSCHLIESSLICH – es gibt keine Schreibfunktion.
#ifndef AETHER_C_H
#define AETHER_C_H

#include <stdbool.h>
#include <stdint.h>
#include <IOKit/IOKitLib.h>

typedef struct {
    char key[5];
    char type[5];
    uint32_t size;
    uint8_t bytes[32];
} AetherSMCValue;

/// Öffnet den AppleSMC-Dienst. 0 = nicht vorhanden (z. B. virtueller Mac) oder nicht zugänglich.
io_connect_t aether_smc_open(void);
void aether_smc_close(io_connect_t connection);
/// Anzahl der Schlüssel (#KEY) oder 0.
uint32_t aether_smc_key_count(io_connect_t connection);
/// Schlüssel an einer Position (nullterminiert in `key`). false bei Fehler.
bool aether_smc_key_at(io_connect_t connection, uint32_t index, char key[5]);
/// Liest einen Schlüssel (4 Zeichen). false bei Fehler.
bool aether_smc_read(io_connect_t connection, const char *key, AetherSMCValue *value);

#endif
