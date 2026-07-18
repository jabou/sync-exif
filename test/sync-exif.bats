#!/usr/bin/env bats
#
# Test suite for sync-exif. Fixtures are tiny synthetic TIFFs (see
# support/make_tiff.py) stamped with scanner-like EXIF, paired with hand-written
# XMP camera sidecars — so the tests need only bash, python3 and exiftool.

setup() {
  SYNC_EXIF="${BATS_TEST_DIRNAME}/../bin/sync-exif"
  SUPPORT="${BATS_TEST_DIRNAME}/support"
  WORK="$(mktemp -d "${BATS_TMPDIR}/sync-exif.XXXXXX")"
  EXIFTOOL="$(command -v exiftool)"
}

teardown() {
  [ -n "${WORK:-}" ] && rm -rf "$WORK"
}

# ── Helpers ───────────────────────────────────────────────────────────────────

# make_scan <filename> — a TIFF stamped with the scanner's identity + scan date.
make_scan() {
  python3 "${SUPPORT}/make_tiff.py" "${WORK}/$1"
  "$EXIFTOOL" -q -overwrite_original \
    -IFD0:Make=Nikon -IFD0:Model="Nikon COOLSCAN V ED" \
    -IFD0:ModifyDate="2026:07:16 21:22:06" \
    -XResolution=4000 -YResolution=4000 -ResolutionUnit=inches \
    "${WORK}/$1"
}

# make_sidecar <filename> — a camera XMP sidecar with make/model/date/etc.
make_sidecar() {
  cat > "${WORK}/$1" <<'XMP'
<?xml version="1.0" encoding="UTF-8"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
   xmlns:tiff="http://ns.adobe.com/tiff/1.0/"
   xmlns:exif="http://ns.adobe.com/exif/1.0/"
   tiff:Make="Nikon"
   tiff:Model="L35AF"
   exif:DateTimeOriginal="2026-06-19T20:46:36+02:00"
   exif:FNumber="28/10"
   exif:UserComment="Kodak ColorPlus 200"/>
 </rdf:RDF>
</x:xmpmeta>
XMP
}

# tag <tagname> <file> — print a single tag value (empty if absent).
tag() {
  "$EXIFTOOL" -s3 -f "-$1" "${WORK}/$2" 2>/dev/null | sed 's/^-$//'
}

# ── CLI surface ───────────────────────────────────────────────────────────────

@test "--version prints program and version" {
  run "$SYNC_EXIF" --version
  [ "$status" -eq 0 ]
  [[ "$output" == "sync-exif "* ]]
}

@test "--help shows usage and exits 0" {
  run "$SYNC_EXIF" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--keep-xmp"* ]]
}

@test "unknown option exits 2" {
  run "$SYNC_EXIF" --frobnicate
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "invalid --jobs exits 2" {
  run "$SYNC_EXIF" --jobs 0 "$WORK"
  [ "$status" -eq 2 ]
  run "$SYNC_EXIF" --jobs abc "$WORK"
  [ "$status" -eq 2 ]
}

@test "missing directory exits 1" {
  run "$SYNC_EXIF" /no/such/dir/here
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a directory"* ]]
}

@test "empty folder is a no-op, exit 0" {
  run "$SYNC_EXIF" "$WORK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no TIFF/NEF files found"* ]]
}

# ── Core sync behaviour ───────────────────────────────────────────────────────

@test "camera metadata is written into real EXIF" {
  make_scan "shot.tiff"
  make_sidecar "shot.xmp"
  run "$SYNC_EXIF" -q "$WORK"
  [ "$status" -eq 0 ]
  [ "$(tag EXIF:Make shot.tiff)" = "Nikon" ]
  [ "$(tag EXIF:Model shot.tiff)" = "L35AF" ]
  [ "$(tag EXIF:DateTimeOriginal shot.tiff)" = "2026:06:19 20:46:36" ]
  [ "$(tag EXIF:FNumber shot.tiff)" = "2.8" ]
  [ "$(tag EXIF:UserComment shot.tiff)" = "Kodak ColorPlus 200" ]
}

@test "scanner model is preserved in EXIF:Software" {
  make_scan "shot.tiff"
  make_sidecar "shot.xmp"
  run "$SYNC_EXIF" -q "$WORK"
  [ "$(tag EXIF:Software shot.tiff)" = "Nikon COOLSCAN V ED" ]
}

@test "scan date goes to CreateDate and ModifyDate; capture date stays in DateTimeOriginal" {
  make_scan "shot.tiff"
  make_sidecar "shot.xmp"
  run "$SYNC_EXIF" -q "$WORK"
  [ "$(tag EXIF:CreateDate shot.tiff)" = "2026:07:16 21:22:06" ]
  [ "$(tag IFD0:ModifyDate shot.tiff)" = "2026:07:16 21:22:06" ]
  [ "$(tag EXIF:DateTimeOriginal shot.tiff)" = "2026:06:19 20:46:36" ]
}

@test "scan resolution is retained" {
  make_scan "shot.tiff"
  make_sidecar "shot.xmp"
  run "$SYNC_EXIF" -q "$WORK"
  [ "$(tag IFD0:XResolution shot.tiff)" = "4000" ]
}

@test "embedded XMP is stripped from the image" {
  make_scan "shot.tiff"
  make_sidecar "shot.xmp"
  run "$SYNC_EXIF" -q "$WORK"
  run "$EXIFTOOL" -XMP:all "${WORK}/shot.tiff"
  [ -z "$output" ]
}

@test "sidecar is deleted on success" {
  make_scan "shot.tiff"
  make_sidecar "shot.xmp"
  run "$SYNC_EXIF" -q "$WORK"
  [ ! -f "${WORK}/shot.xmp" ]
  [ -f "${WORK}/shot.tiff" ]
}

# ── Flags ─────────────────────────────────────────────────────────────────────

@test "--keep-xmp retains the sidecar" {
  make_scan "shot.tiff"
  make_sidecar "shot.xmp"
  run "$SYNC_EXIF" -q --keep-xmp "$WORK"
  [ "$status" -eq 0 ]
  [ -f "${WORK}/shot.xmp" ]
}

@test "--dry-run modifies nothing" {
  make_scan "shot.tiff"
  make_sidecar "shot.xmp"
  before="$(tag IFD0:Model shot.tiff)"
  run "$SYNC_EXIF" --dry-run "$WORK"
  [ "$status" -eq 0 ]
  [ -f "${WORK}/shot.xmp" ]                         # sidecar untouched
  [ "$(tag IFD0:Model shot.tiff)" = "$before" ]     # still the scanner model
  [[ "$output" == *"[dry run]"* ]]
}

@test "image without a sidecar is skipped and left untouched" {
  make_scan "orphan.tiff"
  run "$SYNC_EXIF" -q "$WORK"
  [ "$status" -eq 0 ]
  [ "$(tag IFD0:Model orphan.tiff)" = "Nikon COOLSCAN V ED" ]  # unchanged
}

# ── Phase 1: numeric sidecar renaming ─────────────────────────────────────────

@test "numeric sidecar is renamed to match the frame-numbered image, then synced" {
  make_scan "roll_03-frame.tiff"
  make_sidecar "03.xmp"                              # numeric → must be renamed
  run "$SYNC_EXIF" -q "$WORK"
  [ "$status" -eq 0 ]
  [ ! -f "${WORK}/03.xmp" ]                          # renamed then deleted
  [ "$(tag EXIF:Model roll_03-frame.tiff)" = "L35AF" ]
}

@test "leading zeros in frame numbers are compared numerically" {
  make_scan "roll_007-frame.tiff"
  make_sidecar "7.xmp"                               # 7 matches _007-
  run "$SYNC_EXIF" -q "$WORK"
  [ "$status" -eq 0 ]
  [ "$(tag EXIF:Model roll_007-frame.tiff)" = "L35AF" ]
}

# ── --positives guard ─────────────────────────────────────────────────────────

@test "--positives skips a folder not named Positives" {
  make_scan "shot.tiff"
  make_sidecar "shot.xmp"
  run "$SYNC_EXIF" --positives "$WORK"
  [ "$status" -eq 0 ]
  [ -f "${WORK}/shot.xmp" ]                          # nothing happened
  [[ "$output" == *"not named 'Positives'"* ]]
}

@test "--positives runs in a folder named Positives" {
  mkdir -p "${WORK}/Positives"
  python3 "${SUPPORT}/make_tiff.py" "${WORK}/Positives/shot.tiff"
  "$EXIFTOOL" -q -overwrite_original -IFD0:Make=Nikon -IFD0:Model="Nikon COOLSCAN V ED" "${WORK}/Positives/shot.tiff"
  cat > "${WORK}/Positives/shot.xmp" <<'XMP'
<?xml version="1.0" encoding="UTF-8"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
<rdf:Description rdf:about="" xmlns:tiff="http://ns.adobe.com/tiff/1.0/" tiff:Make="Nikon" tiff:Model="L35AF"/>
</rdf:RDF></x:xmpmeta>
XMP
  run "$SYNC_EXIF" -q --positives "${WORK}/Positives"
  [ "$status" -eq 0 ]
  [ ! -f "${WORK}/Positives/shot.xmp" ]
  [ "$("$EXIFTOOL" -s3 -EXIF:Model "${WORK}/Positives/shot.tiff")" = "L35AF" ]
}

# ── Data-safety regressions (from code review) ────────────────────────────────

@test "sidecar with no mappable camera data is kept, not deleted, and reported failed" {
  make_scan "shot.tiff"
  # A syntactically valid .xml that carries no mappable camera metadata.
  cat > "${WORK}/shot.xml" <<'XML'
<?xml version="1.0"?><note><to>nobody</to><body>not a sidecar</body></note>
XML
  run "$SYNC_EXIF" -q "$WORK"
  [ "$status" -eq 1 ]                                            # failure
  [ -f "${WORK}/shot.xml" ]                                      # sidecar preserved
  [ "$(tag IFD0:Model shot.tiff)" = "Nikon COOLSCAN V ED" ]     # image untouched
}

@test "a stray numeric sidecar never clobbers an already-correct sidecar" {
  make_scan "roll_03-frame.tiff"
  make_sidecar "roll_03-frame.xmp"     # the correct sidecar (real camera data)
  cat > "${WORK}/03.xmp" <<'XML'
<?xml version="1.0"?><x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" xmlns:tiff="http://ns.adobe.com/tiff/1.0/" tiff:Make="STRAY" tiff:Model="STRAY"/></rdf:RDF></x:xmpmeta>
XML
  run "$SYNC_EXIF" -q "$WORK"
  [ "$status" -eq 0 ]
  [ -f "${WORK}/03.xmp" ]                                        # stray left in place
  [ "$(tag EXIF:Model roll_03-frame.tiff)" = "L35AF" ]          # correct sidecar won
}

@test "ambiguous frame number across two images is skipped, not misapplied" {
  make_scan "rollA_03-x.tiff"
  make_scan "rollB_03-y.tiff"
  make_sidecar "03.xmp"
  run "$SYNC_EXIF" "$WORK"
  [ "$status" -eq 0 ]
  [ -f "${WORK}/03.xmp" ]                                        # not consumed
  [ "$(tag IFD0:Model rollA_03-x.tiff)" = "Nikon COOLSCAN V ED" ]
  [ "$(tag IFD0:Model rollB_03-y.tiff)" = "Nikon COOLSCAN V ED" ]
  [[ "$output" == *"matches multiple images"* ]]
}

@test "too many folder arguments exits 2" {
  run "$SYNC_EXIF" "$WORK" "$WORK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"too many arguments"* ]]
}

@test "mixed-case sidecar extension is matched" {
  make_scan "shot.tiff"
  make_sidecar "shot.XmP"
  run "$SYNC_EXIF" -q "$WORK"
  [ "$status" -eq 0 ]
  [ "$(tag EXIF:Model shot.tiff)" = "L35AF" ]
}
