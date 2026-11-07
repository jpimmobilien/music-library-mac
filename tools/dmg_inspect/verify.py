#!/usr/bin/env python3
"""Unabhängige Prüfung von AETHER-macOS-Universal.dmg ohne macOS (eigene Decoder für UDIF, HFS+ und Mach-O).

  python3 -I tools/dmg_inspect/verify.py AETHER-macOS-Universal.dmg [AETHER-macOS-Universal.dmg.sha256]

Prüft: Prüfsumme, UDIF-Struktur, HFS+-Inhalt (App, Link „Programme“, Hintergrund, Volume-Symbol), Info.plist,
Architekturen der Programmdatei (arm64 + x86_64), Mindest-macOS, Signatur, nur System-Bibliotheken.
"""
import hashlib
import importlib.util
import os
import pathlib
import plistlib
import struct
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent


def load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    dmg = pathlib.Path(sys.argv[1]).resolve()
    failures = []

    def check(ok, text):
        print(("✓ " if ok else "✗ ") + text)
        if not ok:
            failures.append(text)

    data = dmg.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    print(f"Datei: {dmg} ({len(data):,} Bytes)\nSHA-256: {digest}")
    if len(sys.argv) > 2:
        expected = pathlib.Path(sys.argv[2]).read_text().split()[0]
        check(expected == digest, "Prüfsumme stimmt mit der Build-Prüfsumme überein")
    check(data[-512:][:4] == b"koly", "UDIF-Trailer (koly) vorhanden")

    udif, hfsx, macho = load("udif"), load("hfsx"), load("macho")
    with tempfile.TemporaryDirectory() as tmp:
        raw = os.path.join(tmp, "disk.img")
        udif.main(str(dmg), raw)
        out = os.path.join(tmp, "fs")
        listing = hfsx.HFS(raw).extract(out)
        names = {p for p, _ in listing}
        top = sorted(p for p in names if p.count("/") == 0 or (p.endswith("/") and p.count("/") == 1))
        print("Inhalt (oberste Ebene):", ", ".join(top))
        check("AETHER.app/" in names, "AETHER.app enthalten")
        check(any(p.startswith("Programme -> /Applications") for p in names), "Verknüpfung „Programme“ → /Applications")
        check(any(p.startswith(".background") for p in names), "Hintergrundbild enthalten")
        check(".VolumeIcon.icns" in names, "Volume-Symbol enthalten")
        check(".DS_Store" in names, "Fensterlayout (.DS_Store) enthalten")

        app = pathlib.Path(out) / "AETHER.app" / "Contents"
        info = plistlib.loads((app / "Info.plist").read_bytes())
        print(f"Info.plist: {info.get('CFBundleIdentifier')} {info.get('CFBundleShortVersionString')} "
              f"({info.get('CFBundleVersion')}), macOS ab {info.get('LSMinimumSystemVersion')}, "
              f"Sprachen {info.get('CFBundleLocalizations')}")
        check(info.get("CFBundleExecutable") == "AETHER", "CFBundleExecutable = AETHER")
        check(info.get("LSMinimumSystemVersion") == "13.0", "LSMinimumSystemVersion = 13.0")
        for lang in ("en", "de"):
            check((app / "Resources" / f"{lang}.lproj" / "Localizable.strings").exists(), f"{lang}.lproj/Localizable.strings")
        check((app / "Resources" / "AppIcon.icns").exists(), "AppIcon.icns")
        check((app / "_CodeSignature" / "CodeResources").exists(), "Signatur-Siegel (_CodeSignature)")

        binary = (app / "MacOS" / "AETHER").read_bytes()
        magic = struct.unpack(">I", binary[:4])[0]
        check(magic == 0xCAFEBABE, "Universal Binary (fat)")
        archs = []
        if magic == 0xCAFEBABE:
            count = struct.unpack(">I", binary[4:8])[0]
            for i in range(count):
                _cpu, _sub, off, size, _align = struct.unpack(">iiIII", binary[8 + 20 * i: 28 + 20 * i])
                thin = macho.thin(binary, off, size)
                archs.append(thin["arch"])
                sig = thin["sig"] or {}
                print(f"  {thin['arch']}: Build {thin['build']}, Signatur {({k: v for k, v in sig.items() if k != 'entitlements'})}")
                foreign = [d for d in thin["dylibs"] if not (d.split(" ")[0].startswith("/System/Library/") or d.split(" ")[0].startswith("/usr/lib/"))]
                check(not foreign, f"{thin['arch']}: nur System-Bibliotheken" + (f" – fremd: {foreign}" if foreign else ""))
        check(sorted(archs) == ["arm64", "x86_64"], f"Architekturen: {', '.join(archs)}")

    print()
    print("ERGEBNIS:", "bestanden" if not failures else f"{len(failures)} Prüfung(en) fehlgeschlagen")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
