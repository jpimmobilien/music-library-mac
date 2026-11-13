import AVFoundation
import CoreMedia

/// Format einer Audiospur so, wie sie dekodiert wird.
///
/// Bei HE-AAC (SBR) und HE-AAC v2 (zusätzlich Parametric Stereo) – üblich bei Instagram, Facebook, TikTok und vielen
/// Videos – nennt die Formatbeschreibung einer MP4-Spur nur den AAC-Grundlayer: halbe Abtastrate (z. B. 24 statt
/// 48 kHz) und bei v2 einen statt zwei Kanälen. Wer das übernimmt, gibt den Ton halb so schnell und eine (bei v2
/// zwei) Oktaven tiefer aus. Maßgeblich ist das reichhaltigste dekodierbare Format aus der Formatliste der Spur.
enum AudioTrackFormat {
    /// Abtastrate und Kanäle des dekodierten Tons (Formatkennung bleibt die der Spur).
    static func decoded(_ desc: CMAudioFormatDescription) -> AudioStreamBasicDescription? {
        let base = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee
        guard let richest = CMAudioFormatDescriptionGetRichestDecodableFormat(desc)?.pointee.mASBD,
              richest.mSampleRate > 0, richest.mChannelsPerFrame > 0 else { return base }
        guard var result = base else { return richest }
        result.mSampleRate = richest.mSampleRate
        result.mChannelsPerFrame = richest.mChannelsPerFrame
        return result
    }
}
