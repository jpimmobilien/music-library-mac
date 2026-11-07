"""Minimal read-only HFS+/HFSX extractor (catalog B-tree, data forks incl. extents overflow, symlinks)."""
import sys, struct, os, uuid

def gpt_hfs_offset(img):
    img.seek(512)
    hdr = img.read(92)
    assert hdr[:8] == b'EFI PART'
    entries_lba, num, size = struct.unpack('<QII', hdr[72:88])
    img.seek(entries_lba * 512)
    for i in range(num):
        e = img.read(size)
        tguid = uuid.UUID(bytes_le=e[:16])
        first = struct.unpack('<Q', e[32:40])[0]
        if str(tguid).upper() == '48465300-0000-11AA-AA11-00306543ECAC':
            return first * 512
    raise SystemExit('no HFS partition')

class HFS:
    def __init__(self, path):
        self.f = open(path, 'rb')
        self.base = gpt_hfs_offset(self.f)
        self.f.seek(self.base + 1024)
        vh = self.f.read(512)
        sig = vh[:2]
        assert sig in (b'H+', b'HX'), sig
        self.case_sensitive = sig == b'HX'
        self.block = struct.unpack('>I', vh[40:44])[0]
        self.ext_fork = self.fork(vh[192:272])
        self.cat_fork = self.fork(vh[272:352])
        self.overflow = {}
        self.load_overflow()
        self.catalog = self.read_fork(self.cat_fork, 4, 0)

    @staticmethod
    def fork(b):
        size = struct.unpack('>Q', b[:8])[0]
        exts = [struct.unpack('>II', b[16 + 8 * i: 24 + 8 * i]) for i in range(8)]
        return size, [e for e in exts if e[1]]

    def read_fork(self, fork, cnid, ftype):
        size, exts = fork
        exts = list(exts)
        have = sum(c for _, c in exts)
        exts += self.overflow.get((cnid, ftype), [])
        out = bytearray()
        for start, count in exts:
            self.f.seek(self.base + start * self.block)
            out += self.f.read(count * self.block)
        return bytes(out[:size])

    def nodes(self, data):
        node_size = struct.unpack('>H', data[32:34])[0]
        first_leaf = struct.unpack('>I', data[24:28])[0]
        n = first_leaf
        while n:
            node = data[n * node_size:(n + 1) * node_size]
            flink = struct.unpack('>I', node[:4])[0]
            kind = struct.unpack('>b', node[8:9])[0]
            nrec = struct.unpack('>H', node[10:12])[0]
            offs = [struct.unpack('>H', node[node_size - 2 * (i + 1): node_size - 2 * i])[0] for i in range(nrec + 1)]
            for i in range(nrec):
                yield node[offs[i]:offs[i + 1]]
            n = flink

    def load_overflow(self):
        size, exts = self.ext_fork
        if not size:
            return
        out = bytearray()
        for start, count in exts:
            self.f.seek(self.base + start * self.block)
            out += self.f.read(count * self.block)
        data = bytes(out[:size])
        for rec in self.nodes(data):
            klen = struct.unpack('>H', rec[:2])[0]
            ftype = rec[2]
            cnid = struct.unpack('>I', rec[4:8])[0]
            body = rec[2 + klen:]
            exts = [struct.unpack('>II', body[8 * i:8 * i + 8]) for i in range(8)]
            self.overflow.setdefault((cnid, 0 if ftype == 0 else 0xFF), []).extend(e for e in exts if e[1])

    def walk(self):
        items = {}
        for rec in self.nodes(self.catalog):
            klen = struct.unpack('>H', rec[:2])[0]
            parent = struct.unpack('>I', rec[2:6])[0]
            nlen = struct.unpack('>H', rec[6:8])[0]
            name = rec[8:8 + 2 * nlen].decode('utf-16-be')
            body = rec[2 + klen:]
            rtype = struct.unpack('>h', body[:2])[0]
            if rtype == 1:  # folder
                cnid = struct.unpack('>I', body[8:12])[0]
                items[cnid] = ('d', parent, name, None, None)
            elif rtype == 2:  # file
                cnid = struct.unpack('>I', body[8:12])[0]
                mode = struct.unpack('>H', body[42 + 8 - 8 + 8 + 2: 42 + 8 - 8 + 8 + 4])[0] if False else struct.unpack('>H', body[0x2A + 0x0C - 0x0C + 0x0C - 0x0C + 0x0C - 0x0C + 6:0x2A + 8])[0]
                perms = body[32:48]
                fmode = struct.unpack('>H', perms[10:12])[0]
                data_fork = self.fork(body[88:168])
                items[cnid] = ('f', parent, name, data_fork, fmode)
        return items

    def extract(self, dst):
        items = self.walk()
        def path(cnid):
            parts = []
            while cnid in items and cnid != 2:
                k, parent, name, _, _ = items[cnid]
                parts.append(name)
                cnid = parent
            return os.path.join(*reversed(parts)) if parts else ''
        listing = []
        for cnid, (k, parent, name, fork, mode) in sorted(items.items()):
            if cnid == 1 or (k == 'd' and cnid == 2):
                continue
            p = path(cnid)
            if not p:
                continue
            full = os.path.join(dst, p.replace('\0', ''))
            if k == 'd':
                os.makedirs(full, exist_ok=True)
                listing.append((p + '/', 0))
            else:
                os.makedirs(os.path.dirname(full), exist_ok=True)
                content = self.read_fork(fork, cnid, 0)
                if mode is not None and (mode & 0o170000) == 0o120000:
                    listing.append((p + ' -> ' + content.decode('utf-8', 'replace'), len(content)))
                    with open(full + '.symlink', 'w') as fh:
                        fh.write(content.decode('utf-8', 'replace'))
                else:
                    with open(full, 'wb') as fh:
                        fh.write(content)
                    listing.append((p, len(content)))
        return listing

if __name__ == '__main__':
    h = HFS(sys.argv[1])
    for p, n in sorted(h.extract(sys.argv[2])):
        print(f'{n:>10}  {p}')
