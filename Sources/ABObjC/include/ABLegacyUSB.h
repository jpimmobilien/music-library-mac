#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>

NS_ASSUME_NONNULL_BEGIN

/// Zugriff auf eine USB-Schnittstelle über die klassische IOKit-Schnittstelle (IOUSBLib, IOUSBInterfaceInterface).
/// Derselbe Weg, den libusb (und damit z. B. OpenMTP) und Android File Transfer verwenden – seit vielen
/// macOS-Versionen bewährt, im Benutzerraum, ohne Treiber.
@interface ABLegacyUSBInterface : NSObject

/// Öffnet die Schnittstelle exklusiv und sucht die Bulk-Endpunkte. Fehlercodes sind IOReturn-Werte
/// (Domäne „IOKit“), z. B. 0xE00002C5 = belegt.
- (nullable instancetype)initWithService:(io_service_t)service error:(NSError * _Nullable * _Nullable)error;

@property (nonatomic, readonly) NSUInteger maxPacketSize;
@property (nonatomic, readonly) uint8_t interfaceNumber;

/// Liest bis zu `length` Bytes (endet bei kurzem Paket). `timeoutMs` = Gesamtzeitlimit.
- (BOOL)readInto:(void *)buffer length:(NSUInteger)length transferred:(NSUInteger *)transferred
       timeoutMs:(uint32_t)timeoutMs error:(NSError * _Nullable * _Nullable)error;

/// Schreibt `length` Bytes als einen Transfer (0 = Nullpaket).
- (BOOL)write:(const void *)buffer length:(NSUInteger)length timeoutMs:(uint32_t)timeoutMs
        error:(NSError * _Nullable * _Nullable)error;

/// Klassenanforderung an die Schnittstelle (Steuerkanal).
- (BOOL)controlRequestType:(uint8_t)requestType request:(uint8_t)request value:(uint16_t)value index:(uint16_t)index
                      data:(nullable void *)data length:(uint16_t)length timeoutMs:(uint32_t)timeoutMs
                     error:(NSError * _Nullable * _Nullable)error;

/// Stillstand eines Endpunkts aufheben (beide Seiten), nur nach gemeldetem Stillstand verwenden.
- (void)clearStallIn:(BOOL)inPipe;

- (void)close;

@end

NS_ASSUME_NONNULL_END
