import Darwin
import IOKit
import Foundation

/// Kleine, sichere Hülle um `sysctlbyname`. Jede Abfrage kann fehlschlagen (Schlüssel fehlt auf dieser
/// Architektur oder macOS-Version) – dann `nil`, nie ein Ersatzwert.
public enum Sysctl {
    public static func int(_ name: String) -> Int? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return nil }
        switch size {
        case 4:
            var value: Int32 = 0
            var s = 4
            guard sysctlbyname(name, &value, &s, nil, 0) == 0 else { return nil }
            return Int(value)
        case 8:
            var value: Int64 = 0
            var s = 8
            guard sysctlbyname(name, &value, &s, nil, 0) == 0 else { return nil }
            return Int(value)
        default:
            return nil
        }
    }

    public static func uint64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        if size == 4 { return UInt64(UInt32(truncatingIfNeeded: value)) }
        return value
    }

    public static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size + 1)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let text = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Strukturwert (z. B. `xsw_usage`, `timeval`).
    public static func value<T>(_ name: String, initial: T) -> T? {
        var value = initial
        var size = MemoryLayout<T>.size
        let result = withUnsafeMutablePointer(to: &value) { pointer -> Int32 in
            sysctlbyname(name, UnsafeMutableRawPointer(pointer), &size, nil, 0)
        }
        guard result == 0, size == MemoryLayout<T>.size else { return nil }
        return value
    }
}

/// Hilfen für die IORegistry (öffentliche IOKit-Funktionen; die Schlüssel selbst sind teils undokumentiert und
/// werden deshalb immer auf Typ und Plausibilität geprüft).
public enum IORegistry {
    /// Alle Eigenschaften des ersten Dienstes einer Klasse.
    public static func properties(ofFirst className: String) -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(className))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return properties(of: service)
    }

    public static func properties(of entry: io_registry_entry_t) -> [String: Any]? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }
        return dictionary
    }

    /// Eine Eigenschaft aller Dienste einer Klasse (z. B. „Statistics“ aller IOBlockStorageDriver).
    public static func property(_ key: String, ofAll className: String) -> [Any] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var values: [Any] = []
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }
            if let value = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                values.append(value)
            }
            IOObjectRelease(entry)
        }
        return values
    }

    public static func int(_ dictionary: [String: Any], _ key: String) -> Int? {
        (dictionary[key] as? NSNumber)?.intValue
    }

    /// Vorzeichenbehaftet über das Bitmuster (IORegistry speichert negative Ströme teils als große vorzeichenlose Zahl).
    public static func int64(_ dictionary: [String: Any], _ key: String) -> Int64? {
        (dictionary[key] as? NSNumber)?.int64Value
    }

    public static func bool(_ dictionary: [String: Any], _ key: String) -> Bool? {
        (dictionary[key] as? NSNumber)?.boolValue
    }
}
