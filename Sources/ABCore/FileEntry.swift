import Foundation

/// Ein Objekt auf dem Android-Gerät (Datei oder Ordner).
public struct DeviceEntry: Identifiable, Hashable, Codable, Sendable {
    /// Eindeutig je Gerät und Sitzung: Speicher + Handle.
    public var id: String { "\(storageID):\(handle)" }
    public var handle: UInt32
    public var storageID: UInt32
    public var parent: UInt32
    public var name: String
    public var isFolder: Bool
    public var size: UInt64
    public var format: UInt16
    public var modified: Date?
    public var created: Date?
    public var imageWidth: UInt32
    public var imageHeight: UInt32

    public init(handle: UInt32, storageID: UInt32, parent: UInt32, name: String, isFolder: Bool, size: UInt64,
                format: UInt16, modified: Date? = nil, created: Date? = nil, imageWidth: UInt32 = 0, imageHeight: UInt32 = 0) {
        self.handle = handle
        self.storageID = storageID
        self.parent = parent
        self.name = name
        self.isFolder = isFolder
        self.size = size
        self.format = format
        self.modified = modified
        self.created = created
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }

    public var kind: FileKind { FileKind.of(name: name, isFolder: isFolder) }
    public var isHidden: Bool { name.hasPrefix(".") }
    /// Bestes verfügbares Datum (Änderung, sonst Erstellung).
    public var bestDate: Date? { modified ?? created }

    public init(handle: UInt32, info: MTPObjectInfo, fullSize: UInt64? = nil) {
        self.init(handle: handle, storageID: info.storageID, parent: info.parentObject, name: info.filename,
                  isFolder: info.isFolder, size: fullSize ?? UInt64(info.compressedSize), format: info.objectFormat,
                  modified: MTPDate.parse(info.modificationDate), created: MTPDate.parse(info.captureDate),
                  imageWidth: info.imagePixWidth, imageHeight: info.imagePixHeight)
    }

    public init?(summary s: MTPObjectSummary) {
        guard let name = s.name, let format = s.format else { return nil }
        self.init(handle: s.handle, storageID: s.storageID ?? 0, parent: s.parent ?? 0, name: name,
                  isFolder: format == MTPFormat.association, size: s.size ?? 0, format: format,
                  modified: s.modified, created: s.created)
    }
}

/// Speicher eines Android-Geräts (interner Speicher, SD-Karte …).
public struct DeviceStorage: Identifiable, Hashable, Codable, Sendable {
    public var id: UInt32
    public var description: String
    public var volumeLabel: String
    public var capacity: UInt64
    public var free: UInt64
    public var isRemovable: Bool
    public var isReadOnly: Bool

    public init(id: UInt32, description: String, volumeLabel: String, capacity: UInt64, free: UInt64, isRemovable: Bool, isReadOnly: Bool) {
        self.id = id
        self.description = description
        self.volumeLabel = volumeLabel
        self.capacity = capacity
        self.free = free
        self.isRemovable = isRemovable
        self.isReadOnly = isReadOnly
    }

    public init(id: UInt32, info: MTPStorageInfo) {
        self.init(id: id, description: info.storageDescription, volumeLabel: info.volumeLabel,
                  capacity: info.maxCapacity, free: info.freeSpaceInBytes, isRemovable: info.isRemovable,
                  isReadOnly: info.isReadOnly)
    }

    public var used: UInt64 { capacity > free ? capacity - free : 0 }
    public var usedFraction: Double { capacity > 0 ? Double(used) / Double(capacity) : 0 }

    /// Anzeigename: Beschreibung des Geräts, sonst sinnvoller Standard.
    public var displayName: String {
        let d = description.trimmingCharacters(in: .whitespaces)
        if !d.isEmpty { return d }
        let l = volumeLabel.trimmingCharacters(in: .whitespaces)
        if !l.isEmpty { return l }
        return isRemovable ? "SD-Karte" : "Interner Speicher"
    }

    public var typeName: String { isRemovable ? "Wechselspeicher" : "Interner Speicher" }
    public var symbolName: String { isRemovable ? "sdcard" : "internaldrive" }
}
