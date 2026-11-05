#!/usr/bin/env python3
"""rawtool – byte-level helpers for the MLTags test fixtures.

  rawtool.py dsf <out>                     minimal DSD64 mono DSF file (silence pattern)
  rawtool.py dff <out>                     minimal DSD64 mono DSDIFF file
  rawtool.py riffchunk <wav> <id> <text>   append an unknown chunk to a RIFF/WAVE file
  rawtool.py aiffchunk <aiff> <id> <text>  append an unknown chunk to a FORM/AIFF file
  rawtool.py flacapp <flac> <text>         insert an APPLICATION block after STREAMINFO
"""
import struct
import sys

RATE = 2822400
BLOCK = 4096


def dsf(out):
    blocks = 5
    data = bytes([0x69]) * (BLOCK * blocks)
    samples = 141120  # 0.05 s
    fmt = b"fmt " + struct.pack("<QIIIIIIQII", 52, 1, 0, 1, 1, RATE, 1, samples, BLOCK, 0)
    datachunk = b"data" + struct.pack("<Q", 12 + len(data)) + data
    total = 28 + len(fmt) + len(datachunk)
    head = b"DSD " + struct.pack("<QQQ", 28, total, 0)
    with open(out, "wb") as f:
        f.write(head + fmt + datachunk)


def chunk_be(ident, payload):
    pad = b"\0" if len(payload) % 2 else b""
    return ident + struct.pack(">Q", len(payload)) + payload + pad


def dff(out):
    data = bytes([0x69]) * 17640  # 0.05 s mono DSD64
    fver = chunk_be(b"FVER", struct.pack(">I", 0x01050000))
    fs = chunk_be(b"FS  ", struct.pack(">I", RATE))
    chnl = chunk_be(b"CHNL", struct.pack(">H", 1) + b"C   ")
    name = b"not compressed"
    cmpr = chunk_be(b"CMPR", b"DSD " + bytes([len(name)]) + name)
    prop = chunk_be(b"PROP", b"SND " + fs + chnl + cmpr)
    dsd = chunk_be(b"DSD ", data)
    body = b"DSD " + fver + prop + dsd
    with open(out, "wb") as f:
        f.write(b"FRM8" + struct.pack(">Q", len(body)) + body)


def riffchunk(path, ident, text):
    payload = text.encode()
    with open(path, "rb") as f:
        b = bytearray(f.read())
    assert b[:4] == b"RIFF"
    b += ident.encode().ljust(4)[:4] + struct.pack("<I", len(payload)) + payload
    if len(payload) % 2:
        b += b"\0"
    struct.pack_into("<I", b, 4, len(b) - 8)
    with open(path, "wb") as f:
        f.write(b)


def aiffchunk(path, ident, text):
    payload = text.encode()
    with open(path, "rb") as f:
        b = bytearray(f.read())
    assert b[:4] == b"FORM"
    b += ident.encode().ljust(4)[:4] + struct.pack(">I", len(payload)) + payload
    if len(payload) % 2:
        b += b"\0"
    struct.pack_into(">I", b, 4, len(b) - 8)
    with open(path, "wb") as f:
        f.write(b)


def flacapp(path, text):
    with open(path, "rb") as f:
        b = bytearray(f.read())
    pos = b.find(b"fLaC")
    assert pos >= 0
    hdr = pos + 4
    flags = b[hdr]
    length = int.from_bytes(b[hdr + 1:hdr + 4], "big")
    assert flags & 0x7F == 0, "first block must be STREAMINFO"
    was_last = flags & 0x80
    b[hdr] = flags & 0x7F
    payload = b"MLTS" + text.encode()
    block = bytes([(0x80 if was_last else 0) | 2]) + len(payload).to_bytes(3, "big") + payload
    insert_at = hdr + 4 + length
    b[insert_at:insert_at] = block
    with open(path, "wb") as f:
        f.write(b)


if __name__ == "__main__":
    cmd, args = sys.argv[1], sys.argv[2:]
    {"dsf": dsf, "dff": dff, "riffchunk": riffchunk, "aiffchunk": aiffchunk, "flacapp": flacapp}[cmd](*args)
