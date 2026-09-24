#!/usr/bin/env bash
# DVD-Convert: BluRay/DivX-Rip -> DVD-Video (MPEG-2, ohne Menü), 2-Pass.
# Ziel: DVD-R (4,7GB) oder DVD-R Dual Layer (8,5GB), PAL oder NTSC.
#
# Benutzung:
#   ./dvd-convert.sh INPUT.mkv -o OUT_PREFIX [--format auto|dvd5|dvd9] [--pal|--ntsc]
#     --format auto : Bitrate aus der Zielgröße automatisch berechnen (empfohlen)
#     --pal (default) / --ntsc
#
# Ausgabe: OUT_PREFIX.mpg (MPEG-2), OUT_PREFIX.vob / VIDEO_TS-Ordner, OUT_PREFIX.iso
# Ohne --burn erzeugt es nur das ISO; mit --burn /dev/sr0 direkt brennen.
#
# Abhängigkeiten: ffmpeg, dvdauthor, genisoimage (ggf. wodim für --burn)

set -euo pipefail

# ---------- Parameter ----------
INPUT="" OUTPUT="" FORMAT="auto" STD="pal" BURN=""
SRC_BIN="/dev/sr0"

usage() {
  echo "Benutzung: $0 INPUT -o PREFIX [--format dvd5|dvd9|auto] [--pal|--ntsc] [--burn /dev/srX]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) OUTPUT="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    --pal) STD="pal"; shift ;;
    --ntsc) STD="ntsc"; shift ;;
    --burn) BURN="${2:-$SRC_BIN}"; shift 2 ;;
    *) INPUT="$1"; shift ;;
  esac
done

[[ -z "$INPUT" || -z "$OUTPUT" ]] && usage
[[ -f "$INPUT" ]] || { echo "Eingabe fehlt: $INPUT"; exit 1; }

for t in ffmpeg ffprobe dvdauthor genisoimage; do
  command -v "$t" >/dev/null || { echo "Fehlt: $t"; exit 1; }
done

# ---------- Zielgröße ----------
# DVD-5 = 4,7 GB, DVD-9 (Dual Layer) = 8,5 GB. Praktisch nutzbar ~ 12% weniger.
DVD5_BYTES=$(( 4700000000 / 100 * 85 ))   # ~3,8 GB
DVD9_BYTES=$(( 8500000000 / 100 * 88 ))   # ~7,3 GB (DL-Fehlerreserve)

dur=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT")
[[ -z "$dur" || "$dur" == "N/A" ]] && { echo "Dauer nicht lesbar"; exit 1; }
dur=${dur%.*}

auto_dvd9() { [[ -n "$1" ]] && (( $1 > 11700 )); }

case "$FORMAT" in
  dvd5) TARGET_BYTES="$DVD5_BYTES" ;;
  dvd9) TARGET_BYTES="$DVD9_BYTES" ;;
  auto)
    if auto_dvd9 "$dur"; then
      echo "Lange Dauer (${dur}s) -> Dual-Layer-Ziel (dvd9)"
      TARGET_BYTES="$DVD9_BYTES"
    else
      TARGET_BYTES="$DVD5_BYTES"
    fi
    ;;
esac

# Video-Budget = Ziel minus Audio (448 kbit/s) minus Overhead; daraus Bitrate.
video_budget=$(( TARGET_BYTES * 8 - 448000 * dur ))
target_br=$(( video_budget / dur / 1000 ))
# MPI-Engine-Grenzen: 2500..8000 kbit/s (DVD-Max ~9,8k total; 8k Video ist sicher)
(( target_br > 8000 )) && target_br=8000
(( target_br < 2500 )) && target_br=2500
echo "Ziel: dvd=$FORMAT Nutzbar=$((TARGET_BYTES/1000000))MB Dauer=${dur}s Video-Bitrate=${target_br}k"

# ---------- PAL/NTSC (für ffmpeg-Ziel) ----------
if [[ "$STD" == "pal" ]]; then
  TARGET="-target pal-dvd"
else
  TARGET="-target ntsc-dvd"
fi

echo "======================================"
echo " Quell: $INPUT"
echo " Ausg.: $OUTPUT.mp4 (2-Pass MPEG-2)"
echo " Ziel : $FORMAT (${TARGET_BYTES:+Budget benutzt})"
echo " Pass : 2-Pass, Video-Bitrate ${target_br}k + AC3 448k"
echo "======================================"

# ---------- Pass 1 (nur Analyse) ----------
echo "[1/4] DVD-Authoring-Vorbereitung (Pass 1)..."
ffmpeg -y -loglevel error -stats \
  -i "$INPUT" \
  $TARGET \
  -an \
  -c:v mpeg2video \
  -b:v "${target_br}k" -minrate "${target_br}k" -maxrate "${target_br}k" \
  -bufsize "$(( target_br * 3 ))k" \
  -g 15 -sc_threshold 1000000000 \
  -aspect 16:9 \
  -pass 1 -passlogfile "$OUTPUT" \
  -f mpeg2video /dev/null

# ---------- Pass 2 (Video + AC3) ----------
echo "[2/4] Encoding (Pass 2, Video+Audio)..."
ffmpeg -y -loglevel error -stats \
  -i "$INPUT" \
  $TARGET \
  -c:v mpeg2video \
  -b:v "${target_br}k" -minrate "${target_br}k" -maxrate "${target_br}k" \
  -bufsize "$(( target_br * 3 ))k" \
  -g 15 -sc_threshold 1000000000 \
  -aspect 16:9 \
  -c:a ac3 -b:a 448k -ac 2 \
  -pass 2 -passlogfile "$OUTPUT" \
  "$OUTPUT.mpg"

# ---------- DVD-Authoring (VIDEO_TS, ohne Menü) ----------
# Fix (findet den Bug seit dvdauthor 0.7.2/Ubuntu ohne kompiliertes Default):
#   * <vmgm/>-Element sorgt dafür, dass VIDEO_TS.IFO/BUP (Domain-Schlüssel) erzeugt wird.
#   * dvdauthor 0.7.2 (Ubuntu) braucht das Videoformat GLOBAL über die
#     UMGEBUNGSVARIABLE VIDEO_FORMAT=pal|ntsc -- sonst: "no video format for VMGM".
#   * dvdauthor löst <vob file> relativ zum AUSGABE-Ort auf; title.mpg direkt in
#     $OUTPUT.dvd stellen (kurzer, leer-raum-freier Pfad -> keine "writing data"-Abbrüche).
echo "[3/4] DVD-Authoring (VIDEO_TS)..."
rm -rf "$OUTPUT.dvd" && mkdir -p "$OUTPUT.dvd"
cp "$OUTPUT.mpg" "$OUTPUT.dvd/title.mpg"
cat > "$OUTPUT.dvd/batch.xml" <<EOF
<?xml version="1.0"?>
<dvdauthor>
  <vmgm/>
  <titleset>
    <titles>
      <pgc>
        <vob file="title.mpg"/>
      </pgc>
    </titles>
  </titleset>
</dvdauthor>
EOF
( cd "$OUTPUT.dvd" && VIDEO_FORMAT="$STD" dvdauthor -o . -x batch.xml )
rv=$?
rm -f "$OUTPUT.dvd/batch.xml" "$OUTPUT.dvd/title.mpg"
if [[ $rv -ne 0 ]]; then
  echo "FEHLER: dvdauthor schlug fehl (Code $rv). Abbruch." >&2
  exit $rv
fi

# ---------- ISO ----------
echo "[4/4] ISO bauen..."
genisoimage -dvd-video -o "$OUTPUT.iso" "$OUTPUT.dvd"

echo "======================================"
echo "FERTIG:"
echo "  Video-Strom : $OUTPUT.mpg"
echo "  VIDEO_TS    : $OUTPUT.dvd/"
echo "  ISO (brennbar): $OUTPUT.iso ($(du -h "$OUTPUT.iso" | cut -f1))"
if [[ -n "$BURN" ]]; then
  echo "Brenne auf $BURN ..."
  wodim -v -dao dev="$BURN" "$OUTPUT.iso"
  echo "Gebrannt."
fi
echo "======================================"