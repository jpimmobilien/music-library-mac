#!/bin/bash
# Signatur mit Developer ID und Notarisierung durch Apple – nur mit eigenem Apple-Developer-Konto.
# Ohne Zugangsdaten wird nichts vorgetäuscht: der Schritt meldet „übersprungen“, die App bleibt ad-hoc signiert.
#
# Zugangsdaten (GitHub-Secrets oder Umgebungsvariablen):
#   MACOS_CERT_P12_BASE64   Developer-ID-Application-Zertifikat samt privatem Schlüssel (.p12, Base64)
#   MACOS_CERT_PASSWORD     Passwort der .p12-Datei
#   NOTARY_APPLE_ID         Apple-ID des Developer-Kontos
#   NOTARY_TEAM_ID          Team-ID (10 Zeichen)
#   NOTARY_PASSWORD         app-spezifisches Passwort
#
#   scripts/notarize.sh keychain   → Zertifikat in temporären Schlüsselbund, gibt SIGN_IDENTITY für build_app.sh aus
#   scripts/notarize.sh dmg        → DMG signieren, einreichen, Ticket anheften, prüfen
set -euo pipefail
cd "$(dirname "$0")/.."
NAME="ORBIT-macOS-Universal.dmg"

have_credentials() {
    [ -n "${MACOS_CERT_P12_BASE64:-}" ] && [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ]
}

case "${1:-}" in
keychain)
    if ! have_credentials; then
        echo "Signatur/Notarisierung übersprungen: keine Developer-ID-Zugangsdaten hinterlegt (Build bleibt ad-hoc signiert)."
        exit 0
    fi
    KEYCHAIN="$RUNNER_TEMP/aether-signing.keychain-db"
    KEYCHAIN_PASSWORD="$(uuidgen)"
    echo "$MACOS_CERT_P12_BASE64" | base64 --decode > "$RUNNER_TEMP/cert.p12"
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security set-keychain-settings -lut 3600 "$KEYCHAIN"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security import "$RUNNER_TEMP/cert.p12" -P "${MACOS_CERT_PASSWORD:-}" -A -t cert -f pkcs12 -k "$KEYCHAIN"
    security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
    rm -f "$RUNNER_TEMP/cert.p12"
    IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.*)"/\1/')"
    test -n "$IDENTITY" || { echo "Kein „Developer ID Application“-Zertifikat in der .p12-Datei"; exit 1; }
    echo "SIGN_IDENTITY=$IDENTITY" >> "${GITHUB_ENV:-/dev/null}"
    echo "Signaturidentität: $IDENTITY"
    ;;
dmg)
    if ! have_credentials || [ -z "${SIGN_IDENTITY:-}" ]; then
        echo "Notarisierung übersprungen: keine Developer-ID-Zugangsdaten (DMG und App bleiben ad-hoc signiert)."
        exit 0
    fi
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "dist/$NAME"
    xcrun notarytool submit "dist/$NAME" --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" \
        --password "$NOTARY_PASSWORD" --wait --timeout 30m
    xcrun stapler staple "dist/$NAME"
    spctl --assess --type open --context context:primary-signature -v "dist/$NAME"
    cp "dist/$NAME" "$NAME"
    (cd dist && shasum -a 256 "$NAME" > "$NAME.sha256")
    ;;
*)
    echo "Aufruf: scripts/notarize.sh keychain|dmg"; exit 2 ;;
esac
