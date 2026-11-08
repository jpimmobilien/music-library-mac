// PTP/MTP-Konstanten (ISO 15740 / USB-IF „Media Transfer Protocol Rev. 1.1“).

public enum PTPContainerType: UInt16, Sendable {
    case command = 1
    case data = 2
    case response = 3
    case event = 4
}

public enum PTPOperation: UInt16, Sendable {
    case getDeviceInfo = 0x1001
    case openSession = 0x1002
    case closeSession = 0x1003
    case getStorageIDs = 0x1004
    case getStorageInfo = 0x1005
    case getNumObjects = 0x1006
    case getObjectHandles = 0x1007
    case getObjectInfo = 0x1008
    case getObject = 0x1009
    case getThumb = 0x100A
    case deleteObject = 0x100B
    case sendObjectInfo = 0x100C
    case sendObject = 0x100D
    case getDevicePropValue = 0x1015
    case getPartialObject = 0x101B
    // MTP-Erweiterungen
    case getObjectPropsSupported = 0x9801
    case getObjectPropDesc = 0x9802
    case getObjectPropValue = 0x9803
    case setObjectPropValue = 0x9804
    case getObjectPropList = 0x9805
    // Android-Erweiterungen
    case getPartialObject64 = 0x95C1
}

public enum PTPResponse: UInt16, Sendable {
    case ok = 0x2001
    case generalError = 0x2002
    case sessionNotOpen = 0x2003
    case invalidTransactionID = 0x2004
    case operationNotSupported = 0x2005
    case parameterNotSupported = 0x2006
    case incompleteTransfer = 0x2007
    case invalidStorageID = 0x2008
    case invalidObjectHandle = 0x2009
    case devicePropNotSupported = 0x200A
    case invalidObjectFormatCode = 0x200B
    case storeFull = 0x200C
    case objectWriteProtected = 0x200D
    case storeReadOnly = 0x200E
    case accessDenied = 0x200F
    case noThumbnailPresent = 0x2010
    case partialDeletion = 0x2012
    case storeNotAvailable = 0x2013
    case specificationByFormatUnsupported = 0x2014
    case noValidObjectInfo = 0x2015
    case deviceBusy = 0x2019
    case invalidParentObject = 0x201A
    case invalidParameter = 0x201D
    case sessionAlreadyOpen = 0x201E
    case transactionCancelled = 0x201F
    case invalidObjectPropCode = 0xA801
    case invalidObjectPropFormat = 0xA802
    case invalidObjectPropValue = 0xA803
    case invalidObjectReference = 0xA804
    case invalidDataset = 0xA806
    case specificationByGroupUnsupported = 0xA807
    case specificationByDepthUnsupported = 0xA808
    case objectTooLarge = 0xA809
    case objectPropNotSupported = 0xA80A
}

/// MTP-Objektformate (Auswahl).
public enum MTPFormat {
    public static let undefined: UInt16 = 0x3000
    public static let association: UInt16 = 0x3001
    public static let text: UInt16 = 0x3004
    public static let html: UInt16 = 0x3005
    public static let wav: UInt16 = 0x3008
    public static let mp3: UInt16 = 0x3009
    public static let avi: UInt16 = 0x300A
    public static let mpeg: UInt16 = 0x300B
    public static let quickTime: UInt16 = 0x300D
    public static let exifJPEG: UInt16 = 0x3801
    public static let bmp: UInt16 = 0x3804
    public static let gif: UInt16 = 0x3807
    public static let png: UInt16 = 0x380B
    public static let tiff: UInt16 = 0x380D
    public static let wma: UInt16 = 0xB901
    public static let ogg: UInt16 = 0xB902
    public static let aac: UInt16 = 0xB903
    public static let flac: UInt16 = 0xB906
    public static let wmv: UInt16 = 0xB981
    public static let mp4: UInt16 = 0xB982
    public static let threeGP: UInt16 = 0xB984

    /// Format für eine Datei anhand ihrer Endung (Android leitet den Typ ohnehin aus dem Namen ab;
    /// unbekannte Endungen werden als „undefiniert“ gesendet).
    public static func forFileName(_ name: String) -> UInt16 {
        switch FileKind.fileExtension(of: name) {
        case "jpg", "jpeg": return exifJPEG
        case "png": return png
        case "gif": return gif
        case "bmp": return bmp
        case "tif", "tiff": return tiff
        case "mp3": return mp3
        case "wav": return wav
        case "wma": return wma
        case "ogg", "oga": return ogg
        case "aac", "m4a": return aac
        case "flac": return flac
        case "mp4", "m4v": return mp4
        case "3gp": return threeGP
        case "avi": return avi
        case "mpg", "mpeg": return mpeg
        case "mov": return quickTime
        case "wmv": return wmv
        case "txt": return text
        case "htm", "html": return html
        default: return undefined
        }
    }
}

/// MTP-Objekteigenschaften (Auswahl).
public enum MTPProperty {
    public static let storageID: UInt16 = 0xDC01
    public static let objectFormat: UInt16 = 0xDC02
    public static let protectionStatus: UInt16 = 0xDC03
    public static let objectSize: UInt16 = 0xDC04
    public static let objectFileName: UInt16 = 0xDC07
    public static let dateCreated: UInt16 = 0xDC08
    public static let dateModified: UInt16 = 0xDC09
    public static let parentObject: UInt16 = 0xDC0B
    public static let persistentUID: UInt16 = 0xDC41
    public static let name: UInt16 = 0xDC44
    public static let dateAdded: UInt16 = 0xDC4E
}

/// PTP-Datentypen (für Eigenschaftslisten).
public enum PTPDataType {
    public static let int8: UInt16 = 0x0001
    public static let uint8: UInt16 = 0x0002
    public static let int16: UInt16 = 0x0003
    public static let uint16: UInt16 = 0x0004
    public static let int32: UInt16 = 0x0005
    public static let uint32: UInt16 = 0x0006
    public static let int64: UInt16 = 0x0007
    public static let uint64: UInt16 = 0x0008
    public static let int128: UInt16 = 0x0009
    public static let uint128: UInt16 = 0x000A
    public static let string: UInt16 = 0xFFFF
    /// Arrays: 0x4000 | Elementtyp
    public static let arrayFlag: UInt16 = 0x4000
}

public enum MTPStorageType: UInt16, Sendable {
    case undefined = 0
    case fixedROM = 1
    case removableROM = 2
    case fixedRAM = 3
    case removableRAM = 4
}

/// Besondere Objekt-Handles.
public enum MTPHandle {
    /// „Wurzel des Speichers“ als Elternobjekt bei GetObjectHandles/SendObjectInfo.
    public static let root: UInt32 = 0xFFFF_FFFF
    /// Alle Speicher bei GetObjectHandles.
    public static let allStorages: UInt32 = 0xFFFF_FFFF
}
