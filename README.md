# sync-exif

[![CI](https://github.com/jabou/sync-exif/actions/workflows/ci.yml/badge.svg)](https://github.com/jabou/sync-exif/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Apply camera metadata from XMP/XML sidecars to scanned film negatives — while
**preserving the scanner's own metadata as secondary EXIF**.

When you scan film, the scanner stamps the file with *its* identity (e.g.
`Nikon COOLSCAN V ED`) and scan settings. But the metadata you actually care
about, the camera, lens, aperture, shutter, ISO, film stock, GPS, lives in a
sidecar you produced separately. `sync-exif` merges the two so the **camera**
becomes the primary EXIF (visible in every photo app) and the **scanner** is
kept as a secondary record, all in a single file with no leftovers.

## What it does

For every TIFF or Nikon NEF raw in a folder it:

1. **Renames** numeric sidecars (e.g. `01.xmp`) to match the image whose
   filename contains the matching frame number (`..._01-...`).
2. **Copies** the camera metadata from the sidecar into the image's *real* EXIF
   (make, model, exposure, lens, GPS, `DateTimeOriginal`).
3. **Preserves the scanner** as secondary data — scanner model in
   `EXIF:Software`, scan date in `CreateDate`/`ModifyDate`, and the scanner's own
   scan-settings (e.g. the `NikonScan` block) and scan resolution left untouched.
4. **Strips** any embedded XMP block (the camera data now lives in EXIF).
5. **Deletes** each synced image's sidecar (use `--keep-xmp` to keep them).

The raw sensor data is never modified — only metadata blocks are rewritten.

### Before → after

| Field | Scanned file (before) | After `sync-exif` |
|-------|-----------------------|-------------------|
| `EXIF:Make` / `Model` | Nikon / **Nikon COOLSCAN V ED** *(scanner)* | Nikon / **L35AF** *(camera)* |
| `EXIF:DateTimeOriginal` | — | 2026:06:19 *(shot)* |
| `EXIF:FNumber`, `ISO`, `LensModel`, GPS… | — | from sidecar |
| `EXIF:UserComment` | — | Kodak ColorPlus 200 *(film)* |
| `EXIF:Software` | — | **Nikon COOLSCAN V ED** *(scanner)* |
| `EXIF:CreateDate` / `IFD0:ModifyDate` | 2026:07:16 *(scanned)* | 2026:07:16 *(scanned)* |
| `NikonScan` block, scan resolution | present | **kept** |
| embedded XMP | — | stripped |

`DateTimeOriginal` holds the capture date and `CreateDate` the digitization
(scan) date — the standard EXIF split — so photo managers that sort by capture
time order your photos by when they were *taken*, not when they were scanned.

## Install

### Homebrew (recommended)

```sh
brew tap jabou/tap
brew install sync-exif
```

### Manual

```sh
git clone https://github.com/jabou/sync-exif.git
ln -s "$PWD/sync-exif/bin/sync-exif" /usr/local/bin/sync-exif   # or anywhere on your PATH
```

### Requirements

- **bash** 4.0 or newer (macOS ships 3.2 — `brew install bash`)
- **[exiftool](https://exiftool.org/)** (`brew install exiftool`)

## Usage

```sh
sync-exif [options] [folder]
```

`folder` defaults to the current directory. Files are processed in parallel; on
a terminal a live list shows a spinner on in-flight files, ✓/✗ as they finish,
and a fill bar.

```
Options:
  -j, --jobs N      Process N files concurrently (default 4)
  -n, --dry-run     Show what would happen without modifying any files
      --keep-xmp    Do not delete sidecars after a successful sync
      --positives   Only run if the folder is named "Positives"
  -q, --quiet       Only print the final summary
  -V, --version     Print version and exit
  -h, --help        Show this help
```

### Examples

```sh
sync-exif ~/Scans/roll-42          # sync a folder
sync-exif --dry-run .              # preview, change nothing
sync-exif -j 8 --keep-xmp ~/Scans  # 8 at a time, keep sidecars
```

Sidecars of files that fail are always kept, so you can fix and re-run. A run
exits non-zero if any file failed.

## How sidecar matching works

For each image, `sync-exif` looks for a sidecar named after the image
(`shot.tiff` → `shot.xmp`/`shot.xml`, case-insensitive). Before that, any
**numeric** sidecar (`03.xmp`) is renamed to match the image whose filename
contains that frame number (`roll_03-frame.tiff`), comparing numerically so
`3.xmp`, `03.xmp`, and `_003-` all match.

## Development

```sh
brew install bats-core shellcheck exiftool   # test + lint tooling
bats test/sync-exif.bats                      # run the test suite
shellcheck bin/sync-exif                       # lint (config in .shellcheckrc)
```

Tests build tiny synthetic TIFF fixtures (`test/support/make_tiff.py`) stamped
with scanner-like EXIF plus hand-written XMP sidecars, so they need only bash,
python3 and exiftool — no sample images are committed. CI runs the suite on
Linux and macOS.

## License

[MIT](LICENSE) © Jasmin Abou Aldan
