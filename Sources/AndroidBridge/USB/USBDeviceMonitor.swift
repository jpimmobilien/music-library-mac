import Foundation
import IOKit
import IOKit.usb
import ABCore

/// Ein angeschlossenes USB-Gerät (Momentaufnahme aus der IORegistry).
final class USBDeviceRecord: Identifiable {
    let id: UInt64
    let service: io_service_t
    var vendorID: Int
    var productID: Int
    var vendorName: String?
    var productName: String?
    var serialNumber: String?
    var locationID: Int
    var interfaces: [USBInterfaceDescriptor]
    var speedDescription: String?

    init(id: UInt64, service: io_service_t, vendorID: Int, productID: Int, vendorName: String?, productName: String?,
         serialNumber: String?, locationID: Int, interfaces: [USBInterfaceDescriptor], speedDescription: String?) {
        self.id = id
        self.service = service
        self.vendorID = vendorID
        self.productID = productID
        self.vendorName = vendorName
        self.productName = productName
        self.serialNumber = serialNumber
        self.locationID = locationID
        self.interfaces = interfaces
        self.speedDescription = speedDescription
        IOObjectRetain(service)
    }

    deinit { IOObjectRelease(service) }

    var mode: USBDeviceMode { USBDeviceClassifier.classify(vendorID: vendorID, interfaces: interfaces, productName: productName) }

    var idString: String { String(format: "%04X:%04X", vendorID, productID) }

    /// Prozesse, die die Schnittstelle gerade geöffnet halten (laut IORegistry: „IOUserClientCreator“ = „pid N, Name“).
    func interfaceHolders(number: Int) -> [InterfaceHolder] {
        guard let iface = copyInterfaceService(number: number) else { return [] }
        defer { IOObjectRelease(iface) }
        var holders: [InterfaceHolder] = []
        func scan(_ entry: io_registry_entry_t, depth: Int) {
            IORegistryKit.forEachChild(of: entry) { child in
                if let creator: String = IORegistryKit.property(child, "IOUserClientCreator"),
                   let holder = InterfaceHolder(creator: creator), !holders.contains(holder) {
                    holders.append(holder)
                }
                if depth < 3 { scan(child, depth: depth + 1) }
            }
        }
        scan(iface, depth: 0)
        return holders
    }

    /// Sucht den IOService der Schnittstelle mit der angegebenen Nummer (vom Aufrufer freizugeben).
    func copyInterfaceService(number: Int) -> io_service_t? {
        var found: io_service_t?
        IORegistryKit.forEachChild(of: service) { child in
            guard found == nil, IOObjectConformsTo(child, "IOUSBHostInterface") != 0 else { return }
            if let n: Int = IORegistryKit.property(child, "bInterfaceNumber"), n == number {
                IOObjectRetain(child)
                found = child
            }
        }
        return found
    }
}

/// Kleine Helfer für die IORegistry.
enum IORegistryKit {
    static func property<T>(_ entry: io_registry_entry_t, _ key: String) -> T? {
        guard let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return nil
        }
        return value as? T
    }

    static func name(_ entry: io_registry_entry_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 128)
        guard IORegistryEntryGetName(entry, &buffer) == KERN_SUCCESS else { return nil }
        let s = String(cString: buffer)
        return s.isEmpty ? nil : s
    }

    static func registryID(_ entry: io_registry_entry_t) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(entry, &id)
        return id
    }

    /// Ruft `body` für jedes direkte Kind im IOService-Baum auf (Objekte werden danach freigegeben).
    static func forEachChild(of entry: io_registry_entry_t, _ body: (io_registry_entry_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while case let child = IOIteratorNext(iterator), child != 0 {
            body(child)
            IOObjectRelease(child)
        }
    }

    static func parentDevice(of interface: io_registry_entry_t) -> io_registry_entry_t? {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(interface, kIOServicePlane, &parent) == KERN_SUCCESS, parent != 0 else { return nil }
        return parent
    }
}

/// Beobachtet das An- und Abstecken von USB-Geräten (IOKit-Benachrichtigungen, kein Abfragen im Takt).
final class USBDeviceMonitor {
    var onChange: ((USBDeviceRecord) -> Void)?
    var onRemoval: ((UInt64) -> Void)?
    private(set) var isRunning = false
    private(set) var startError: String?

    private var port: IONotificationPortRef?
    private var deviceAddedIterator: io_iterator_t = 0
    private var deviceRemovedIterator: io_iterator_t = 0
    private var interfaceAddedIterator: io_iterator_t = 0

    func start() {
        guard !isRunning else { return }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            startError = "IONotificationPortCreate fehlgeschlagen"
            return
        }
        self.port = port
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        let context = Unmanaged.passUnretained(self).toOpaque()

        let deviceAdded: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            Unmanaged<USBDeviceMonitor>.fromOpaque(refcon).takeUnretainedValue().handleDevices(iterator)
        }
        let deviceRemoved: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            Unmanaged<USBDeviceMonitor>.fromOpaque(refcon).takeUnretainedValue().handleRemoved(iterator)
        }
        let interfaceAdded: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            Unmanaged<USBDeviceMonitor>.fromOpaque(refcon).takeUnretainedValue().handleInterfaces(iterator)
        }

        var kr = IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching("IOUSBHostDevice"),
                                                  deviceAdded, context, &deviceAddedIterator)
        if kr != KERN_SUCCESS { startError = "Gerätebenachrichtigung: \(kr)" }
        kr = IOServiceAddMatchingNotification(port, kIOTerminatedNotification, IOServiceMatching("IOUSBHostDevice"),
                                              deviceRemoved, context, &deviceRemovedIterator)
        if kr != KERN_SUCCESS { startError = "Trennbenachrichtigung: \(kr)" }
        kr = IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, IOServiceMatching("IOUSBHostInterface"),
                                              interfaceAdded, context, &interfaceAddedIterator)
        if kr != KERN_SUCCESS { startError = "Schnittstellenbenachrichtigung: \(kr)" }

        isRunning = true
        // Iteratoren leeren: liefert die bereits angeschlossenen Geräte und „scharf schalten“ der Benachrichtigung.
        handleDevices(deviceAddedIterator)
        handleRemoved(deviceRemovedIterator)
        handleInterfaces(interfaceAddedIterator)
        Diagnostics.shared.log(.usb, "USB-Überwachung gestartet\(startError.map { " (Hinweis: \($0))" } ?? "")")
    }

    func stop() {
        for it in [deviceAddedIterator, deviceRemovedIterator, interfaceAddedIterator] where it != 0 { IOObjectRelease(it) }
        deviceAddedIterator = 0
        deviceRemovedIterator = 0
        interfaceAddedIterator = 0
        if let port { IONotificationPortDestroy(port) }
        port = nil
        isRunning = false
    }

    deinit { stop() }

    /// Liest ein Gerät neu ein (z. B. nachdem seine Schnittstellen erschienen sind).
    func rescan(_ service: io_service_t) {
        if let record = Self.makeRecord(service) { onChange?(record) }
    }

    private func handleDevices(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let record = Self.makeRecord(service) { onChange?(record) }
            IOObjectRelease(service)
        }
    }

    private func handleRemoved(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            onRemoval?(IORegistryKit.registryID(service))
            IOObjectRelease(service)
        }
    }

    private func handleInterfaces(_ iterator: io_iterator_t) {
        var parents: [io_registry_entry_t] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let parent = IORegistryKit.parentDevice(of: service) {
                if IOObjectConformsTo(parent, "IOUSBHostDevice") != 0 { parents.append(parent) } else { IOObjectRelease(parent) }
            }
            IOObjectRelease(service)
        }
        var seen = Set<UInt64>()
        for parent in parents {
            let id = IORegistryKit.registryID(parent)
            if seen.insert(id).inserted, let record = Self.makeRecord(parent) { onChange?(record) }
            IOObjectRelease(parent)
        }
    }

    static func makeRecord(_ service: io_service_t) -> USBDeviceRecord? {
        guard let vendor: Int = IORegistryKit.property(service, "idVendor"),
              let product: Int = IORegistryKit.property(service, "idProduct") else { return nil }
        var interfaces: [USBInterfaceDescriptor] = []
        IORegistryKit.forEachChild(of: service) { child in
            guard IOObjectConformsTo(child, "IOUSBHostInterface") != 0 else { return }
            let number: Int = IORegistryKit.property(child, "bInterfaceNumber") ?? interfaces.count
            let cls: Int = IORegistryKit.property(child, "bInterfaceClass") ?? -1
            let sub: Int = IORegistryKit.property(child, "bInterfaceSubClass") ?? -1
            let proto: Int = IORegistryKit.property(child, "bInterfaceProtocol") ?? -1
            var name: String? = IORegistryKit.property(child, "kUSBString")
                ?? IORegistryKit.property(child, "USB Interface Name")
            if name == nil, let regName = IORegistryKit.name(child), regName != "IOUSBHostInterface" {
                name = regName
            }
            interfaces.append(USBInterfaceDescriptor(number: number, interfaceClass: cls, subClass: sub, interfaceProtocol: proto, name: name))
        }
        interfaces.sort { $0.number < $1.number }
        let speed: Int? = IORegistryKit.property(service, "USBSpeed") ?? IORegistryKit.property(service, "Device Speed")
        let speedText: String?
        switch speed {
        case 1?: speedText = "USB 1.1 (12 Mbit/s)"
        case 2?: speedText = "USB 2.0 (480 Mbit/s)"
        case 3?: speedText = "USB 3.x (5 Gbit/s)"
        case 4?: speedText = "USB 3.x (10 Gbit/s)"
        case 5?: speedText = "USB 3.x (20 Gbit/s)"
        default: speedText = nil
        }
        return USBDeviceRecord(
            id: IORegistryKit.registryID(service),
            service: service,
            vendorID: vendor,
            productID: product,
            vendorName: IORegistryKit.property(service, "USB Vendor Name") ?? IORegistryKit.property(service, "kUSBVendorString"),
            productName: IORegistryKit.property(service, "USB Product Name") ?? IORegistryKit.property(service, "kUSBProductString"),
            serialNumber: IORegistryKit.property(service, "USB Serial Number") ?? IORegistryKit.property(service, "kUSBSerialNumberString"),
            locationID: IORegistryKit.property(service, "locationID") ?? 0,
            interfaces: interfaces,
            speedDescription: speedText
        )
    }
}

/// Ein Prozess, der eine USB-Schnittstelle geöffnet hat.
struct InterfaceHolder: Hashable {
    let pid: pid_t
    let processName: String

    /// „pid 412, ptpcamerad“
    init?(creator: String) {
        let parts = creator.components(separatedBy: ",")
        guard let first = parts.first, first.hasPrefix("pid "), let pid = Int32(first.dropFirst(4).trimmingCharacters(in: .whitespaces)) else { return nil }
        self.pid = pid
        self.processName = parts.dropFirst().joined(separator: ",").trimmingCharacters(in: .whitespaces)
    }

    var isSelf: Bool { pid == getpid() }

    var displayName: String {
        let lower = processName.lowercased()
        if lower.contains("ptpcamerad") { return "macOS-Fotodienst (ptpcamerad)" }
        if lower.contains("icdd") || lower.contains("imagecapture") { return "macOS-Digitale-Bilder-Dienst (\(processName))" }
        if lower.contains("mtpagent") || lower.contains("android file transfer") { return "Android File Transfer Agent" }
        return processName.isEmpty ? "Prozess \(pid)" : processName
    }
}
