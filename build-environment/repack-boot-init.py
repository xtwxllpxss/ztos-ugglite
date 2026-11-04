#!/usr/bin/env python3
"""Repack the ugglite RAM boot image with a replacement /init.

Nothing but the ramdisk's ./init entry and the ramdisk_size field changes: the
kernel bytes, the DTB that the kernel carries, the header (page size, addresses,
cmdline) and the second stage are copied byte for byte. The cpio archive is rebuilt
entry by entry in its original order, so device nodes (mode/rdev), uid/gid, modes
and timestamps survive exactly -- bsdtar on macOS cannot write those nodes.
"""
import gzip, hashlib, io, os, struct, sys

if len(sys.argv) != 4:
    raise SystemExit("usage: repack-boot-init.py BASE_IMAGE INIT_SOURCE OUTPUT_IMAGE")
BASE, NEW_INIT, OUT = sys.argv[1:]


def parse_cpio(blob):
    entries, pos = [], 0
    while True:
        hdr = blob[pos:pos + 110]
        if len(hdr) < 110 or hdr[:6] != b"070701":
            raise SystemExit("not a newc cpio at %d: %r" % (pos, hdr[:6]))
        f = [int(hdr[6 + 8 * i: 14 + 8 * i], 16) for i in range(13)]
        (ino, mode, uid, gid, nlink, mtime, size, dmaj, dmin,
         rmaj, rmin, nsize, _chk) = f
        name = blob[pos + 110: pos + 110 + nsize - 1].decode()
        # newc: the *header+name* pair is padded to four bytes, not the name alone.
        pos = align(110 + nsize, 4) + pos
        data = blob[pos: pos + size]
        pos += (size + 3) & ~3
        if name == "TRAILER!!!":
            return entries
        entries.append(dict(ino=ino, mode=mode, uid=uid, gid=gid, nlink=nlink,
                            mtime=mtime, dmaj=dmaj, dmin=dmin, rmaj=rmaj, rmin=rmin,
                            name=name, data=data))


def emit_cpio(entries):
    out = io.BytesIO()
    for e in entries:
        name = e["name"].encode() + b"\0"
        hdr = b"070701" + b"".join(b"%08X" % v for v in (
            e["ino"], e["mode"], e["uid"], e["gid"], e["nlink"], e["mtime"],
            len(e["data"]), e["dmaj"], e["dmin"], e["rmaj"], e["rmin"], len(name), 0))
        out.write(hdr + name)
        out.write(b"\0" * ((-(110 + len(name))) % 4))  # header+name aligned to 4
        out.write(e["data"])
        out.write(b"\0" * ((-len(e["data"])) % 4))
    tr = b"TRAILER!!!\0"
    out.write(b"070701" + b"".join(b"%08X" % v for v in (
        0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, len(tr), 0)) + tr)
    out.write(b"\0" * ((-(110 + len(tr))) % 4))
    return out.getvalue()


def gz(data):
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb", compresslevel=9, mtime=0) as f:
        f.write(data)
    return buf.getvalue()


def align(n, a):
    return n + ((-n) % a)


def main():
    img = open(BASE, "rb").read()
    if img[:8] != b"ANDROID!":
        raise SystemExit("base image is not an ANDROID! boot image")
    ksz, kaddr = struct.unpack("<II", img[8:16])
    rsz, raddr = struct.unpack("<II", img[16:24])
    ssz, saddr = struct.unpack("<II", img[24:32])
    page = struct.unpack("<I", img[36:40])[0]
    hdr = bytearray(img[:page])

    koff = page
    roff = align(koff + ksz, page)
    soff = align(roff + rsz, page)
    kernel = img[koff:koff + ksz]
    ram = img[roff:roff + rsz]
    second = img[soff:soff + ssz]
    print("base: kernel=%d ramdisk=%d second=%d page=%d" % (ksz, rsz, ssz, page))

    cpio = gzip.decompress(ram)
    entries = parse_cpio(cpio)
    new_init = open(NEW_INIT, "rb").read()
    hits = [e for e in entries if os.path.normpath(e["name"]) == "init"]
    if len(hits) != 1:
        raise SystemExit("expected exactly one ./init in the ramdisk, found %d" % len(hits))
    e = hits[0]
    old_sha = hashlib.sha256(e["data"]).hexdigest()
    e["data"] = new_init
    e["mode"] = 0o100755
    e["nlink"] = 1
    print("init: %s %d bytes -> %d bytes (mode 0755, uid/gid %d/%d kept)"
          % (old_sha[:16], len(new_init), len(new_init), e["uid"], e["gid"]))

    new_cpio = emit_cpio(entries)
    # Round-trip proof: the rebuilt archive must parse and carry our bytes.
    again = parse_cpio(new_cpio)
    chk = [x for x in again if os.path.normpath(x["name"]) == "init"][0]
    assert chk["data"] == new_init and chk["mode"] == 0o100755
    assert len(again) == len(entries), "entry count changed"
    new_ram = gz(new_cpio)
    print("ramdisk: %d -> %d bytes, entries=%d" % (rsz, len(new_ram), len(again)))

    struct.pack_into("<I", hdr, 16, len(new_ram))
    out = bytearray()
    out += hdr
    out += kernel
    out += b"\0" * (align(len(out), page) - len(out))
    out += new_ram
    out += b"\0" * (align(len(out), page) - len(out))
    out += second
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "wb").write(out)
    print("wrote %s %d bytes sha256=%s" % (OUT, len(out), hashlib.sha256(out).hexdigest()))
    print("kernel_sha256_unchanged=%s" %
          (hashlib.sha256(kernel).hexdigest() ==
           hashlib.sha256(img[koff:koff + ksz]).hexdigest()))
    print("init_sha256=%s" % hashlib.sha256(new_init).hexdigest())


if __name__ == "__main__":
    main()
