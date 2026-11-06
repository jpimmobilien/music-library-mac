import Foundation

/// PTP „DeviceInfo“-Datensatz.
public struct MTPDeviceInfo: Equatable, Sendable {
    public var standardVersion: UInt16
    public var vendorExtensionID: UInt32
    public var vendorExtensionVersion: UInt16
    public var vendorExtensionDescription: String
    public var functionalMode: UInt16
    public var operationsSupported: [UInt16]
    public var eventsSupported: [UInt16]
    public var devicePropertiesSupported: [UInt16]
    public var captureFormats: [UInt16]
    public var playbackFormats: [UInt16]
    public var manufacturer: String
    public var model: String
    public var deviceVersion: String
    public var serialNumber: String

    public func supports(_ op: PTPOperation) -> Bool { operationsSupported.contains(op.rawValue) }

    /// Ist es ein MTP-Gerät (Erweiterung „microsoft.com: 1.0“ bzw. MTP-Operationen vorhanden)?
    public var isMTP: Bool {
        vendorExtensionDescription.lowercased().contains("microsoft") || supports(.getObjectPropList) || supports(.getObjectPropValue)
    }

    public static func parse(_ data: Data) throws -> MTPDeviceInfo {
        var r = PTPReader(data)
        let std = try r.u16()
        let extID = try r.u32()
        let extVer = try r.u16()
        let extDesc = try r.string()
        let mode = try r.u16()
        let ops = try r.u16Array()
        let events = try r.u16Array()
        let props = try r.u16Array()
        let capture = try r.u16Array()
        let playback = try r.u16Array()
        let manufacturer = try r.string()
        let model = try r.string()
        let version = try r.string()
        let serial = (try? r.string()) ?? ""
        return MTPDeviceInfo(standardVersion: std, vendorExtensionID: extID, vendorExtensionVersion: extVer,
                             vendorExtensionDescription: extDesc, functionalMode: mode, operationsSupported: ops,
                             eventsSupported: events, devicePropertiesSupported: props, captureFormats: capture,
                             playbackFormats: playback, manufacturer: manufacturer, model: model,
                             deviceVersion: version, serialNumber: serial)
    }
}

/// PTP „StorageInfo“-Datensatz.
public struct MTPStorageInfo: Equatable, Sendable {
    public var storageType: UInt16
    public var filesystemType: UInt16
    public var accessCapability: UInt16
    public var maxCapacity: UInt64
    public var freeSpaceInBytes: UInt64
    public var freeSpaceInObjects: UInt32
    public var storageDescription: String
    public var volumeLabel: String

    /// 0 = Lesen/Schreiben, 1 = nur Lesen (ohne Löschen), 2 = nur Lesen (mit Löschen)
    public var isReadOnly: Bool { accessCapability != 0 }
    public var isRemovable: Bool {
        storageType == MTPStorageType.removableRAM.rawValue || storageType == MTPStorageType.removableROM.rawValue
    }

    public static func parse(_ data: Data) throws -> MTPStorageInfo {
        var r = PTPReader(data)
        let type = try r.u16()
        let fs = try r.u16()
        let access = try r.u16()
        let maxCap = try r.u64()
        let free = try r.u64()
        let freeObjects = try r.u32()
        let desc = try r.string()
        let label = (try? r.string()) ?? ""
        return MTPStorageInfo(storageType: type, filesystemType: fs, accessCapability: access, maxCapacity: maxCap,
                              freeSpaceInBytes: free, freeSpaceInObjects: freeObjects, storageDescription: desc,
                              volumeLabel: label)
    }
}

/// PTP „ObjectInfo“-Datensatz.
public struct MTPObjectInfo: Equatable, Sendable {
    public var storageID: UInt32
    public var objectFormat: UInt16
    public var protectionStatus: UInt16
    /// 32-Bit-Größe; 0xFFFFFFFF bedeutet „4 GB oder größer“ (echte Größe über Eigenschaft 0xDC04).
    public var compressedSize: UInt32
    public var thumbFormat: UInt16
    public var thumbCompressedSize: UInt32
    public var thumbPixWidth: UInt32
    public var thumbPixHeight: UInt32
    public var imagePixWidth: UInt32
    public var imagePixHeight: UInt32
    public var imageBitDepth: UInt32
    public var parentObject: UInt32
    public var associationType: UInt16
    public var associationDescription: UInt32
    public var sequenceNumber: UInt32
    public var filename: String
    public var captureDate: String
    public var modificationDate: String
    public var keywords: String

    public init(storageID: UInt32, objectFormat: UInt16, protectionStatus: UInt16 = 0, compressedSize: UInt32,
                thumbFormat: UInt16 = 0, thumbCompressedSize: UInt32 = 0, thumbPixWidth: UInt32 = 0,
                thumbPixHeight: UInt32 = 0, imagePixWidth: UInt32 = 0, imagePixHeight: UInt32 = 0,
                imageBitDepth: UInt32 = 0, parentObject: UInt32, associationType: UInt16 = 0,
                associationDescription: UInt32 = 0, sequenceNumber: UInt32 = 0, filename: String,
                captureDate: String = "", modificationDate: String = "", keywords: String = "") {
        self.storageID = storageID
        self.objectFormat = objectFormat
        self.protectionStatus = protectionStatus
        self.compressedSize = compressedSize
        self.thumbFormat = thumbFormat
        self.thumbCompressedSize = thumbCompressedSize
        self.thumbPixWidth = thumbPixWidth
        self.thumbPixHeight = thumbPixHeight
        self.imagePixWidth = imagePixWidth
        self.imagePixHeight = imagePixHeight
        self.imageBitDepth = imageBitDepth
        self.parentObject = parentObject
        self.associationType = associationType
        self.associationDescription = associationDescription
        self.sequenceNumber = sequenceNumber
        self.filename = filename
        self.captureDate = captureDate
        self.modificationDate = modificationDate
        self.keywords = keywords
    }

    public var isFolder: Bool { objectFormat == MTPFormat.association }
    public var sizeIsTruncated: Bool { compressedSize == 0xFFFF_FFFF }

    public static func parse(_ data: Data) throws -> MTPObjectInfo {
        var r = PTPReader(data)
        let storage = try r.u32()
        let format = try r.u16()
        let protection = try r.u16()
        let size = try r.u32()
        let thumbFormat = try r.u16()
        let thumbSize = try r.u32()
        let thumbW = try r.u32()
        let thumbH = try r.u32()
        let imgW = try r.u32()
        let imgH = try r.u32()
        let depth = try r.u32()
        let parent = try r.u32()
        let assocType = try r.u16()
        let assocDesc = try r.u32()
        let seq = try r.u32()
        let name = try r.string()
        let capture = (try? r.string()) ?? ""
        let modified = (try? r.string()) ?? ""
        let keywords = (try? r.string()) ?? ""
        return MTPObjectInfo(storageID: storage, objectFormat: format, protectionStatus: protection, compressedSize: size,
                             thumbFormat: thumbFormat, thumbCompressedSize: thumbSize, thumbPixWidth: thumbW,
                             thumbPixHeight: thumbH, imagePixWidth: imgW, imagePixHeight: imgH, imageBitDepth: depth,
                             parentObject: parent, associationType: assocType, associationDescription: assocDesc,
                             sequenceNumber: seq, filename: name, captureDate: capture, modificationDate: modified,
                             keywords: keywords)
    }

    public func encoded() -> Data {
        var w = PTPWriter()
        w.u32(storageID)
        w.u16(objectFormat)
        w.u16(protectionStatus)
        w.u32(compressedSize)
        w.u16(thumbFormat)
        w.u32(thumbCompressedSize)
        w.u32(thumbPixWidth)
        w.u32(thumbPixHeight)
        w.u32(imagePixWidth)
        w.u32(imagePixHeight)
        w.u32(imageBitDepth)
        w.u32(parentObject)
        w.u16(associationType)
        w.u32(associationDescription)
        w.u32(sequenceNumber)
        w.string(filename)
        w.string(captureDate)
        w.string(modificationDate)
        w.string(keywords)
        return w.data
    }

    /// Datensatz für eine neue Datei (Größen ab 4 GB werden als 0xFFFFFFFF gemeldet).
    public static func forUpload(name: String, size: UInt64, storageID: UInt32, parent: UInt32, modified: Date?) -> MTPObjectInfo {
        let compressed: UInt32 = size >= 0xFFFF_FFFF ? 0xFFFF_FFFF : UInt32(size)
        let date = modified.map { MTPDate.format($0) } ?? ""
        return MTPObjectInfo(storageID: storageID, objectFormat: MTPFormat.forFileName(name), compressedSize: compressed,
                             parentObject: parent, filename: name, captureDate: date, modificationDate: date)
    }

    /// Datensatz für einen neuen Ordner („Association“ vom Typ „Generic Folder“).
    public static func forFolder(name: String, storageID: UInt32, parent: UInt32) -> MTPObjectInfo {
        MTPObjectInfo(storageID: storageID, objectFormat: MTPFormat.association, compressedSize: 0,
                      parentObject: parent, associationType: 1, filename: name)
    }
}

/// Ein Eintrag aus „GetObjectPropList“.
public struct MTPPropertyEntry: Equatable, Sendable {
    public var handle: UInt32
    public var property: UInt16
    public var dataType: UInt16
    public var value: PTPValue
}

public enum MTPPropertyList {
    public static func parse(_ data: Data) throws -> [MTPPropertyEntry] {
        var r = PTPReader(data)
        let count = try r.u32()
        var out: [MTPPropertyEntry] = []
        out.reserveCapacity(Int(min(count, 1_000_000)))
        for _ in 0..<count {
            let handle = try r.u32()
            let prop = try r.u16()
            let type = try r.u16()
            let value = try r.value(ofType: type)
            out.append(MTPPropertyEntry(handle: handle, property: prop, dataType: type, value: value))
        }
        return out
    }

    /// Fasst eine Eigenschaftsliste zu Objekteinträgen zusammen (nur Objekte mit Dateinamen).
    public static func objects(from entries: [MTPPropertyEntry]) -> [UInt32: MTPObjectSummary] {
        var map: [UInt32: MTPObjectSummary] = [:]
        for e in entries {
            var s = map[e.handle] ?? MTPObjectSummary(handle: e.handle)
            switch e.property {
            case MTPProperty.storageID: s.storageID = e.value.integer.map { UInt32(truncatingIfNeeded: $0) }
            case MTPProperty.objectFormat: s.format = e.value.integer.map { UInt16(truncatingIfNeeded: $0) }
            case MTPProperty.objectSize: s.size = e.value.integer
            case MTPProperty.objectFileName: s.name = e.value.string
            case MTPProperty.parentObject: s.parent = e.value.integer.map { UInt32(truncatingIfNeeded: $0) }
            case MTPProperty.dateModified: s.modified = e.value.string.flatMap { MTPDate.parse($0) }
            case MTPProperty.dateCreated: s.created = e.value.string.flatMap { MTPDate.parse($0) }
            case MTPProperty.dateAdded: if s.created == nil { s.created = e.value.string.flatMap { MTPDate.parse($0) } }
            default: break
            }
            map[e.handle] = s
        }
        return map
    }
}

/// Zusammengefasste Objektdaten aus einer Eigenschaftsliste.
public struct MTPObjectSummary: Equatable, Sendable {
    public var handle: UInt32
    public var storageID: UInt32?
    public var parent: UInt32?
    public var format: UInt16?
    public var size: UInt64?
    public var name: String?
    public var modified: Date?
    public var created: Date?

    public init(handle: UInt32) { self.handle = handle }

    public var isComplete: Bool { name != nil && format != nil && size != nil }
}

/// MTP-Datumsformat „YYYYMMDDThhmmss[.s][Z|±hhmm]“.
public enum MTPDate {
    public static func parse(_ s: String) -> Date? {
        let chars = Array(s.trimmingCharacters(in: .whitespaces))
        guard chars.count >= 15, chars[8] == "T" else { return nil }
        func num(_ from: Int, _ len: Int) -> Int? { Int(String(chars[from..<(from + len)])) }
        guard let y = num(0, 4), let mo = num(4, 2), let d = num(6, 2),
              let h = num(9, 2), let mi = num(11, 2), let se = num(13, 2) else { return nil }
        guard y > 1970, (1...12).contains(mo), (1...31).contains(d), h < 24, mi < 60, se < 61 else { return nil }
        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d; comps.hour = h; comps.minute = mi; comps.second = se
        var tz = TimeZone.current
        var rest = String(chars[15...])
        if rest.hasPrefix(".") {
            rest.removeFirst()
            while let f = rest.first, f.isNumber { rest.removeFirst() }
        }
        if rest.hasPrefix("Z") {
            tz = TimeZone(secondsFromGMT: 0)!
        } else if let sign = rest.first, sign == "+" || sign == "-" {
            let digits = rest.dropFirst().filter { $0.isNumber }
            if digits.count >= 4, let hh = Int(digits.prefix(2)), let mm = Int(digits.dropFirst(2).prefix(2)) {
                let offset = (hh * 3600 + mm * 60) * (sign == "-" ? -1 : 1)
                tz = TimeZone(secondsFromGMT: offset) ?? tz
            }
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(from: comps)
    }

    public static func format(_ date: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02dT%02d%02d%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1,
                      c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}
