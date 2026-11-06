#import "ABLegacyUSB.h"
#import <IOKit/IOCFPlugIn.h>
#import <IOKit/usb/IOUSBLib.h>

typedef IOUSBInterfaceInterface300 ABInterface;

static NSError *ABError(IOReturn kr, NSString *what) {
    return [NSError errorWithDomain:@"IOKit" code:(NSInteger)(int32_t)kr
                           userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@ fehlgeschlagen", what]}];
}

@implementation ABLegacyUSBInterface {
    ABInterface **_intf;
    UInt8 _pipeIn;
    UInt8 _pipeOut;
    BOOL _open;
}

- (nullable instancetype)initWithService:(io_service_t)service error:(NSError **)error {
    self = [super init];
    if (!self) return nil;

    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    IOReturn kr = kIOReturnError;
    // Wie libusb: das Plug-in steht direkt nach dem Anstecken manchmal noch nicht bereit.
    for (int attempt = 0; attempt < 5; attempt++) {
        kr = IOCreatePlugInInterfaceForService(service, kIOUSBInterfaceUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
        if (kr == kIOReturnSuccess && plugin) break;
        usleep(150000);
    }
    if (kr != kIOReturnSuccess || !plugin) {
        if (error) *error = ABError(kr ?: kIOReturnError, @"Plug-in der USB-Schnittstelle");
        return nil;
    }
    HRESULT res = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300), (LPVOID *)&_intf);
    (*plugin)->Release(plugin);
    if (res != S_OK || !_intf) {
        if (error) *error = ABError(kIOReturnUnsupported, @"QueryInterface");
        return nil;
    }

    kr = (*_intf)->USBInterfaceOpen(_intf);
    if (kr != kIOReturnSuccess) {
        (*_intf)->Release(_intf);
        _intf = NULL;
        if (error) *error = ABError(kr, @"Öffnen der USB-Schnittstelle");
        return nil;
    }
    _open = YES;

    UInt8 number = 0;
    (*_intf)->GetInterfaceNumber(_intf, &number);
    _interfaceNumber = number;

    UInt8 count = 0;
    (*_intf)->GetNumEndpoints(_intf, &count);
    NSUInteger packet = 512;
    for (UInt8 pipe = 1; pipe <= count; pipe++) {
        UInt8 direction = 0, epNumber = 0, transferType = 0, interval = 0;
        UInt16 mps = 0;
        if ((*_intf)->GetPipeProperties(_intf, pipe, &direction, &epNumber, &transferType, &mps, &interval) != kIOReturnSuccess) continue;
        if (transferType != kUSBBulk) continue;
        if (direction == kUSBIn && _pipeIn == 0) { _pipeIn = pipe; packet = MAX(mps, 64); }
        else if (direction == kUSBOut && _pipeOut == 0) { _pipeOut = pipe; }
    }
    _maxPacketSize = packet;
    if (_pipeIn == 0 || _pipeOut == 0) {
        [self close];
        if (error) *error = ABError(kIOReturnNotFound, @"Suche der Bulk-Endpunkte");
        return nil;
    }
    return self;
}

- (BOOL)readInto:(void *)buffer length:(NSUInteger)length transferred:(NSUInteger *)transferred
       timeoutMs:(uint32_t)timeoutMs error:(NSError **)error {
    *transferred = 0;
    if (!_open) { if (error) *error = ABError(kIOReturnNoDevice, @"Lesen"); return NO; }
    UInt32 size = (UInt32)length;
    IOReturn kr = (*_intf)->ReadPipeTO(_intf, _pipeIn, buffer, &size, timeoutMs, timeoutMs);
    if (kr == kIOUSBPipeStalled) {
        (*_intf)->ClearPipeStallBothEnds(_intf, _pipeIn);
    }
    if (kr != kIOReturnSuccess) {
        if (error) *error = ABError(kr, @"Lesen");
        return NO;
    }
    *transferred = size;
    return YES;
}

- (BOOL)write:(const void *)buffer length:(NSUInteger)length timeoutMs:(uint32_t)timeoutMs error:(NSError **)error {
    if (!_open) { if (error) *error = ABError(kIOReturnNoDevice, @"Schreiben"); return NO; }
    IOReturn kr = (*_intf)->WritePipeTO(_intf, _pipeOut, (void *)buffer, (UInt32)length, timeoutMs, timeoutMs);
    if (kr == kIOUSBPipeStalled) {
        (*_intf)->ClearPipeStallBothEnds(_intf, _pipeOut);
    }
    if (kr != kIOReturnSuccess) {
        if (error) *error = ABError(kr, @"Schreiben");
        return NO;
    }
    return YES;
}

- (BOOL)controlRequestType:(uint8_t)requestType request:(uint8_t)request value:(uint16_t)value index:(uint16_t)index
                      data:(void *)data length:(uint16_t)length timeoutMs:(uint32_t)timeoutMs error:(NSError **)error {
    if (!_open) { if (error) *error = ABError(kIOReturnNoDevice, @"Steueranforderung"); return NO; }
    IOUSBDevRequestTO req;
    memset(&req, 0, sizeof(req));
    req.bmRequestType = requestType;
    req.bRequest = request;
    req.wValue = value;
    req.wIndex = index;
    req.wLength = length;
    req.pData = data;
    req.noDataTimeout = timeoutMs;
    req.completionTimeout = timeoutMs;
    IOReturn kr = (*_intf)->ControlRequestTO(_intf, 0, &req);
    if (kr != kIOReturnSuccess) {
        if (error) *error = ABError(kr, @"Steueranforderung");
        return NO;
    }
    return YES;
}

- (void)clearStallIn:(BOOL)inPipe {
    if (!_open) return;
    (*_intf)->ClearPipeStallBothEnds(_intf, inPipe ? _pipeIn : _pipeOut);
}

- (void)close {
    if (_intf) {
        if (_open) (*_intf)->USBInterfaceClose(_intf);
        (*_intf)->Release(_intf);
        _intf = NULL;
    }
    _open = NO;
}

- (void)dealloc {
    [self close];
}

@end
