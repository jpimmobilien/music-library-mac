"""Mach-O / fat inspector: arches, build version (minos/sdk/tools), linked dylibs, code signature summary."""
import sys, struct
CPU = {0x01000007: 'x86_64', 0x0100000C: 'arm64'}
PLAT = {1: 'macOS'}
TOOLS = {1: 'clang', 2: 'swift', 3: 'ld', 4: 'lld'}
def ver(v):
    return f'{v >> 16}.{(v >> 8) & 0xff}.{v & 0xff}'

def thin(data, off, size):
    magic = struct.unpack('<I', data[off:off + 4])[0]
    assert magic == 0xFEEDFACF, hex(magic)
    cpu, sub, ftype, ncmds, sizecmds, flags = struct.unpack('<iiIIII', data[off + 4:off + 28])
    p = off + 32
    info = {'arch': CPU.get(cpu & 0xFFFFFFFF, hex(cpu)), 'dylibs': [], 'build': None, 'sig': None, 'rpaths': []}
    for _ in range(ncmds):
        cmd, csize = struct.unpack('<II', data[p:p + 8])
        if cmd in (0xC, 0x80000018, 0xD, 0x8000001F):  # LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, LC_ID_DYLIB, LC_REEXPORT
            name_off = struct.unpack('<I', data[p + 8:p + 12])[0]
            name = data[p + name_off:p + csize].split(b'\0')[0].decode()
            info['dylibs'].append(name + (' (weak)' if cmd == 0x80000018 else ''))
        elif cmd == 0x32:  # LC_BUILD_VERSION
            plat, minos, sdk, ntools = struct.unpack('<IIII', data[p + 8:p + 24])
            tools = [struct.unpack('<II', data[p + 24 + 8 * i:p + 32 + 8 * i]) for i in range(ntools)]
            info['build'] = (PLAT.get(plat, plat), ver(minos), ver(sdk), [(TOOLS.get(t, t), f'{v >> 16}.{(v >> 8) & 0xff}.{v & 0xff}') for t, v in tools])
        elif cmd == 0x1D:  # LC_CODE_SIGNATURE
            doff, dsize = struct.unpack('<II', data[p + 8:p + 16])
            info['sig'] = sig_summary(data, off + doff, dsize)
        elif cmd == 0x8000001C:  # LC_RPATH
            o = struct.unpack('<I', data[p + 8:p + 12])[0]
            info['rpaths'].append(data[p + o:p + csize].split(b'\0')[0].decode())
        p += csize
    return info

def sig_summary(data, off, size):
    blob = data[off:off + size]
    magic, length, count = struct.unpack('>III', blob[:12])
    res = {'blobs': []}
    for i in range(count):
        typ, boff = struct.unpack('>II', blob[12 + 8 * i:20 + 8 * i])
        bm = struct.unpack('>I', blob[boff:boff + 4])[0]
        res['blobs'].append(hex(typ))
        if bm == 0xFADE0C02:  # CodeDirectory
            version, flags = struct.unpack('>II', blob[boff + 8:boff + 16])
            ident_off = struct.unpack('>I', blob[boff + 20:boff + 24])[0]
            res['identifier'] = blob[boff + ident_off:boff + ident_off + 128].split(b'\0')[0].decode()
            res['flags'] = hex(flags)
            res['adhoc'] = bool(flags & 0x2)
            res['runtime'] = bool(flags & 0x10000)
            res['linker_signed'] = bool(flags & 0x20000)
            if version >= 0x20200:
                team_off = struct.unpack('>I', blob[boff + 48:boff + 52])[0]
                if team_off:
                    res['team'] = blob[boff + team_off:boff + team_off + 32].split(b'\0')[0].decode()
        elif bm == 0xFADE0B01:  # CMS signature wrapper
            res['cms_bytes'] = struct.unpack('>I', blob[boff + 4:boff + 8])[0]
        elif bm == 0xFADE7171:  # entitlements
            elen = struct.unpack('>I', blob[boff + 4:boff + 8])[0]
            res['entitlements'] = blob[boff + 8:boff + elen].decode(errors='replace')
    return res

def main(path):
    data = open(path, 'rb').read()
    magic = struct.unpack('>I', data[:4])[0]
    if magic == 0xCAFEBABE:
        n = struct.unpack('>I', data[4:8])[0]
        print('FAT binary with', n, 'architectures')
        for i in range(n):
            cpu, sub, off, size, align = struct.unpack('>iiIII', data[8 + 20 * i:28 + 20 * i])
            show(thin(data, off, size))
    else:
        show(thin(data, 0, len(data)))

def show(i):
    print('== arch', i['arch'])
    print('   build:', i['build'])
    print('   rpaths:', i['rpaths'])
    print('   signature:', {k: v for k, v in (i['sig'] or {}).items() if k != 'entitlements'})
    if i['sig'] and 'entitlements' in i['sig']:
        print('   entitlements:', i['sig']['entitlements'][:600])
    print('   dylibs:')
    for d in i['dylibs']:
        print('     ', d)

if __name__ == '__main__':
    main(sys.argv[1])
