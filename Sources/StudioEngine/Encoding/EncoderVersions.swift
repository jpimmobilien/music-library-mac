import CFLAC
import CLame
import Foundation

/// Versionen der eingebundenen Encoder (für Tests und die Lizenzanzeige).
enum EncoderVersions {
    /// z. B. „LAME 3.100“
    static var lame: String { "LAME " + String(cString: get_lame_version()) }
    /// z. B. „libFLAC 1.5.0 (reference libFLAC 1.5.0 20250211)“
    static var flac: String { "libFLAC \(String(cString: FLAC__VERSION_STRING)) (\(String(cString: FLAC__VENDOR_STRING)))" }
}
