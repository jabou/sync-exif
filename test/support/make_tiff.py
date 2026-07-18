#!/usr/bin/env python3
"""Write a minimal valid baseline TIFF (1x1, 8-bit grayscale).

Used only by the test suite to build fixtures without depending on an image
library — the pixels are irrelevant; the tests exercise metadata handling.

Usage: make_tiff.py <output-path>
"""
import struct
import sys

# 1x1, 8-bit grayscale, uncompressed. Header (8 bytes) + one padded pixel, then
# the IFD. SHORT values are inlined in the 4-byte value field; LONG offsets point
# into the file.
ENTRIES = [
    (256, 3, 1, 1),   # ImageWidth = 1
    (257, 3, 1, 1),   # ImageLength = 1
    (258, 3, 1, 8),   # BitsPerSample = 8
    (259, 3, 1, 1),   # Compression = none
    (262, 3, 1, 1),   # PhotometricInterpretation = BlackIsZero
    (273, 4, 1, 8),   # StripOffsets -> pixel byte at offset 8
    (277, 3, 1, 1),   # SamplesPerPixel = 1
    (278, 3, 1, 1),   # RowsPerStrip = 1
    (279, 4, 1, 1),   # StripByteCounts = 1
]


def build() -> bytes:
    ifd_offset = 10  # header (8) + one padded pixel (2)
    out = b"II" + struct.pack("<H", 42) + struct.pack("<I", ifd_offset)
    out += b"\x00\x00"  # the single pixel, padded to a word boundary
    ifd = struct.pack("<H", len(ENTRIES))
    for tag_id, typ, count, value in ENTRIES:
        if typ == 3:  # SHORT: value in the low half of the 4-byte field
            ifd += struct.pack("<HHIHH", tag_id, typ, count, value, 0)
        else:         # LONG
            ifd += struct.pack("<HHII", tag_id, typ, count, value)
    ifd += struct.pack("<I", 0)  # no next IFD
    return out + ifd


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: make_tiff.py <output-path>", file=sys.stderr)
        return 2
    with open(sys.argv[1], "wb") as handle:
        handle.write(build())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
