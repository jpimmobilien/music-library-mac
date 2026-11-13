# Signatur der APK

Android installiert ein Update nur, wenn es mit **demselben Schlüssel** signiert ist wie die installierte Version.
Bisher gab es keine Release-Konfiguration und keinen Schlüssel (es war nie eine APK gebaut worden).

Seit ORBIT 0.4.0 liegt deshalb ein **Projektschlüssel** im Projekt: `app/signing/orbit-project.keystore`
(PKCS12, RSA 4096, gültig 100 Jahre, Alias `orbit`, Passwort `orbit-project`). `app/build.gradle.kts` signiert
Debug- **und** Release-Builds damit. Folge:

- Jede Version – aus dem automatischen Build oder aus Android Studio auf deinem Mac – ersetzt die vorherige ohne
  Deinstallation; Einstellungen und Papierkorb bleiben erhalten.
- Der Schlüssel ist **nicht geheim** (er liegt im Projekt und damit auch im öffentlichen Repository). Für eine privat
  installierte App ist das ausreichend; wer die APK sieht, kann damit keine Daten auf deinem Gerät lesen. Er erlaubt
  aber jedem, eine APK zu bauen, die Android als Update von ORBIT akzeptieren würde – installiere ORBIT-APKs deshalb
  nur aus deinem eigenen Build bzw. Ergebniszweig.
- **Für eine Veröffentlichung (Play Store o. Ä.) ungeeignet.** Dann einen eigenen, privaten Schlüssel erzeugen
  (Android Studio › Build › Generate Signed App Bundle/APK) und `signingConfigs` darauf umstellen. Achtung: Ein
  Wechsel des Schlüssels erfordert einmalig eine Deinstallation.

Zertifikat (SHA-256): `08:5C:C4:5C:DE:76:CB:F7:BE:1F:D3:82:73:7E:C2:E5:10:B3:DB:75:3A:CD:42:17:60:FC:D7:5F:6E:C0:58:DB`
– prüfbar mit `apksigner verify --print-certs ORBIT-0.4.0.apk`.
