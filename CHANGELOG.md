# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-07-19

Initial standalone CLI release.

### Added
- Copy camera metadata from an XMP/XML sidecar into the image's real EXIF
  (make, model, exposure, lens, GPS, `DateTimeOriginal`) so every photo app,
  not just XMP-aware ones, shows it as the primary camera data.
- Preserve the scanner as secondary metadata: scanner model in `EXIF:Software`,
  scan date in `CreateDate`/`ModifyDate`, and the scanner's own scan-settings
  (e.g. the `NikonScan` block) and scan resolution left untouched.
- Rename numeric sidecars (e.g. `01.xmp`) to match the frame-numbered image
  (`..._01-...`), comparing frame numbers numerically (leading zeros ignored).
- Strip any embedded XMP block from the image after writing EXIF.
- Delete each synced image's sidecar on success (`--keep-xmp` to retain).
- Parallel processing (`-j`/`--jobs`) with a live terminal UI.
- `--dry-run`, `--quiet`, `--positives`, `--version`, `--help`.

[Unreleased]: https://github.com/jabou/sync-exif/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/jabou/sync-exif/releases/tag/v0.1.0
