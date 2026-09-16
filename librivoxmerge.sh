#!/usr/bin/env bash
#
# Written by Joseph Cameron
# https://github.com/jfcameron/librivoxmerge
#
set -euo pipefail

DESCRIPTION="$(cat <<EOF
Usage:
 $(basename "$0") [options] mp3 <archive.zip> - single MP3
 $(basename "$0") [options] m4a <archive.zip> - single M4A with chapter markers

Options:
 -f, --force  Overwrite output file if it already exists
 -h, --help   Show this message

Merges librivox audiobook zip archives (https://librivox.org/) into a single audio file.

MP3: wide player support but no chapters. Much faster to generate than M4A.
M4A: chapter support but requires a compatible player. Much slower to generate than MP3.
 Since the MP3s within a librivox zip archive don't always represent chapters in the
 book, this script labels the contents of each mp3 "Part 1", "Part 2", etc.
 Once the M4A file has been generated, you can manually rename the parts to reflect 
 the book's actual naming structure, e.g: "chapter 2, part 3", or simply use as-is.
EOF
)"

# ===========================================================================
# Functions
# ===========================================================================
info() { echo -e "\033[1;33mInfo:\033[0m $*"; }

error() { echo -e "\033[1;31mError:\033[0m $*" >&2; exit 1; }

success() { echo -e "\033[1;32mSuccess:\033[0m $*" >&2; exit 0; }   

requires() {
    if ! command -v "$1" &>/dev/null; then
        error "'$1' is not installed or not in PATH."
    fi
}

# ===========================================================================
# Main
# ===========================================================================
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "$DESCRIPTION"
    exit 0
fi

FORCE=0
if [[ "${1:-}" == "-f" || "${1:-}" == "--force" ]]; then
    FORCE=1
    shift
fi

requires unzip
requires ffmpeg
requires ffprobe

FORMAT="${1:-}"
ARCHIVE="${2:-}"

if [[ -z "$FORMAT" || -z "$ARCHIVE" ]]; then
    error "Usage: $(basename "$0") <mp3|m4a> <archive.zip>"
fi

case "$FORMAT" in
    mp3|m4a) ;;
    *) error "Unsupported format '$FORMAT'. Use 'mp3' or 'm4a'." ;;
esac

if [[ ! -f "$ARCHIVE" ]]; then
    error "File not found: $ARCHIVE"
fi

OUTPUT="$(basename "$ARCHIVE")"
OUTPUT="${OUTPUT%.*}.$FORMAT"

if [[ -f "$OUTPUT" && "$FORCE" -eq 0 ]]; then
    error "Output file already exists: $OUTPUT"
fi

TMP_DIR="$(mktemp -d)"
trap '[[ -n "$TMP_DIR" ]] && rm -rf "$TMP_DIR"' EXIT

info "Extracting '$ARCHIVE' to '$TMP_DIR'..."
unzip -q "$ARCHIVE" -d "$TMP_DIR"

mapfile -d '' CHAPTERS < <(find "$TMP_DIR" -iname "*.mp3" -print0 | sort -zV)

if [[ ${#CHAPTERS[@]} -eq 0 ]]; then
    error "No MP3 files found inside the archive."
fi

info "Found ${#CHAPTERS[@]} MP3 file(s)."

CONCAT_LIST="$TMP_DIR/concat_list.txt"
for f in "${CHAPTERS[@]}"; do
    escaped="${f//\'/\'\\\'\'}"
    printf "file '%s'\n" "$escaped"
done > "$CONCAT_LIST"

if [[ "$FORMAT" == "mp3" ]]; then
    info "Merging into MP3..."
    _args=(
        -f concat
        -safe 0
        -i "$CONCAT_LIST"
        -c copy
        -y "$OUTPUT"
        -loglevel fatal
        -stats
    )
    ffmpeg "${_args[@]}"

    success "Output written to: $OUTPUT"
fi

info "Merging audio..."
MERGED_MP3="$TMP_DIR/merged.mp3"
_args=(
    -f concat
    -safe 0
    -i "$CONCAT_LIST"
    -c copy
    -y "$MERGED_MP3"
    -loglevel fatal
    -stats
)
ffmpeg "${_args[@]}"

info "Building chapter metadata..."
METADATA_FILE="$TMP_DIR/metadata.txt"
{
    echo ";FFMETADATA1"
    echo ""
    local_offset=0
    part_index=0
    for f in "${CHAPTERS[@]}"; do
        part_index=$(( part_index + 1 ))
        dur_s="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")"
        dur_ms="$(awk -v d="$dur_s" 'BEGIN {printf "%d", d * 1000}')"
        end_ms=$(( local_offset + dur_ms ))
        printf '[CHAPTER]\nTIMEBASE=1/1000\nSTART=%d\nEND=%d\ntitle=Part %d\n\n' \
            "$local_offset" "$end_ms" "$part_index"
        local_offset=$((end_ms))
    done
} > "$METADATA_FILE"

info "Remuxing into M4A..."
_args=(
    -i "$MERGED_MP3"
    -i "$METADATA_FILE"
    -map_metadata 1
    -map "0:a"
    -c:a aac
    -b:a 128k
    -y "$OUTPUT"
    -loglevel fatal
    -stats
)
ffmpeg "${_args[@]}"

success "Output written to: $OUTPUT"

