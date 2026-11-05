#!/usr/bin/env python3
"""Build a Debian package without dpkg-deb (GNU ar format)."""
import os
import sys
import tarfile
import time


def ar_header(name, size, mode=0o100644):
    return b"%-16s%-12d%-6d%-6d%-8o%-10d`\n" % (
        name.encode(), int(time.time()), 0, 0, mode, size)


def make_ar(entries, out):
    with open(out, "wb") as f:
        f.write(b"!<arch>\n")
        for name, data in entries:
            f.write(ar_header(name, len(data)))
            f.write(data)
            if len(data) % 2:
                f.write(b"\n")


def main():
    pkg = sys.argv[1]
    out = sys.argv[2]
    tmp = os.path.join(os.path.dirname(out), "_deb")
    os.makedirs(tmp, exist_ok=True)

    data_path = os.path.join(tmp, "data.tar.gz")
    with tarfile.open(data_path, "w:gz") as tf:
        for d in ("Applications", "usr"):
            p = os.path.join(pkg, d)
            if os.path.exists(p):
                tf.add(p, arcname=d)

    ctrl_path = os.path.join(tmp, "control.tar.gz")
    with tarfile.open(ctrl_path, "w:gz") as tf:
        tf.add(os.path.join(pkg, "DEBIAN"), arcname="DEBIAN")

    entries = [
        ("debian-binary", b"2.0\n"),
        ("control.tar.gz", open(ctrl_path, "rb").read()),
        ("data.tar.gz", open(data_path, "rb").read()),
    ]
    make_ar(entries, out)
    print("built", out, os.path.getsize(out))


if __name__ == "__main__":
    main()
