"""Minimal UDIF (.dmg) decoder: writes the raw disk image. Supports raw, zero, zlib, bzip2 chunks."""
import sys, struct, plistlib, zlib, bz2, lzma

def main(src, dst):
    data = open(src, 'rb').read()
    koly = data[-512:]
    assert koly[:4] == b'koly', 'no koly trailer'
    xml_off, xml_len = struct.unpack('>QQ', koly[0xD8:0xE8])
    pl = plistlib.loads(data[xml_off:xml_off + xml_len])
    blkx = pl['resource-fork']['blkx']
    out = open(dst, 'wb')
    for part in blkx:
        mish = part['Data']
        assert mish[:4] == b'mish'
        first_sector = struct.unpack('>Q', mish[8:16])[0]
        data_start = struct.unpack('>Q', mish[24:32])[0]
        n = struct.unpack('>I', mish[200:204])[0]
        print('partition', part.get('Name'), 'chunks', n, file=sys.stderr)
        for i in range(n):
            e = mish[204 + 40 * i: 244 + 40 * i]
            typ, _c, sec, cnt, coff, clen = struct.unpack('>IIQQQQ', e)
            if typ == 0xFFFFFFFF:
                break
            if typ == 0x7FFFFFFE:
                continue
            pos = (first_sector + sec) * 512
            out.seek(pos)
            raw = data[data_start + coff: data_start + coff + clen]
            if typ == 0x80000005:
                buf = zlib.decompress(raw)
            elif typ == 0x80000006:
                buf = bz2.decompress(raw)
            elif typ == 0x80000008:
                buf = lzma.decompress(raw)
            elif typ == 1:
                buf = raw
            elif typ in (0, 2):
                buf = b'\0' * (cnt * 512)
            else:
                raise SystemExit('unsupported chunk type %x' % typ)
            out.write(buf)
    out.close()

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
