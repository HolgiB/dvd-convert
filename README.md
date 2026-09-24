# dvd-convert — BluRay/DivX-Rip ▶ DVD-Video (MPEG-2, 2-Pass, ohne Menü)

Konvertiert einen Rip (mkv/mp4/avi) in eine **DVD-kompatible VIDEO_TS-Struktur**
und erzeugt ein brennbares ISO — für Player, die nur echte DVD-Video können
(kein USB/DivX). Ohne Menü, mit **Dual-Pass**-MPEG-2 für bestmögliche Qualität.

## Voraussetzungen

    sudo apt install ffmpeg dvdauthor genisoimage
    # für --burn zusätzlich: wodim

## Benutzung

    ./dvd-convert.sh INPUT.mkv -o ausgabe_prefix [Optionen]

### Optionen

| Option | Bedeutung | Default |
|--------|-----------|---------|
| `-o PREFIX` | Ausgabe-Prefix (mpg/dvd/iso) | erforderlich |
| `--format auto\|dvd5\|dvd9` | Ziel-Medium | `auto` |
| `--pal` / `--ntsc` | Norm | `pal` |
| `--burn /dev/srX` | Direkt brennen nach ISO | aus |

### Beispiele

    # Automatisch (Bitrate aus Dauer, DVD-5/9 wählt selbst)
    ./dvd-convert.sh film.mkv -o film

    # Fest auf Dual-Layer, PAL
    ./dvd-convert.sh film.mkv -o film --format dvd9 --pal

    # NTSC + brennen
    ./dvd-convert.sh film.mkv -o film --format dvd5 --ntsc --burn /dev/sr0

## Ablauf (4 Schritte)

1. **Pass 1** — ffmpeg analysiert (MPEG-2, keine Ausgabe)
2. **Pass 2** — Video MPEG-2 bei berechneter Bitrate + **AC3 448k stereo**
3. **Authoring** — `dvdauthor` → `VIDEO_TS/` (kein Menü, direkt abspielbar)
4. **ISO** — `genisoimage -dvd-video` → brennbares `.iso`

## Ausgabedateien

    PREFIX.mpg     – der MPEG-2-Videostrom (Kontrolle)
    PREFIX.dvd/    – VIDEO_TS-Ordnerstruktur
    PREFIX.iso     – brennbar (genisoimage, DVD-Video-Dateisystem)

## Qualität / Einstellungen

- **Direkter Pass** mit konstanter Video-Bitrate aus Zielgröße + Laufzeit;
  Audio-Overhead (448 kbit/s) wird abgezogen, damit es wirklich passt.
- **Bitrate-Korridor:** 2500–8000 kbit/s (DVD-Hard-Limit ~9,8 Mbit total;
  8 Mbit Video bleibt sicher unter dem Limit).
- **GOP 15**, `-sc_threshold 1000000000` (keine schnellen Scene-Cut-Frames,
  wichtig für DVD-Spieler-Kompatibilität), `-bufsize` = 3× Bitrate.
- **AC3 48 kHz stereo** 448 k — der sicherste DVD-Audio-Codec.
- **16:9** fest (Rips sind i.d.R. 16:9).

## Wichtige Grenzen

| | Limit |
|---|---|
| Video-Codec | **MPEG-2** (Pflicht für DVD-Video) |
| Auflösung | PAL 720×576@25 / NTSC 720×480@29,97 (Skalierung durch `-target *_dvd`) |
| Max. Bitrate | ~9,8 Mbit/s total (hier: ≤8M Video + 448k Audio) |
| Max. Dauer/Lauf | DVD-5 ≈ 130-150 min @ 8Mbit; DVD-9 ≈ 240-270 min |
| Audio | AC3 (bevorzugt), LPCM, MP2 |
| GOP | ≤ 36 Frames (hier 15) |

## Bekannte Stolpersteine

- **`ERR: no video format specified for VMGM`** beim Authoring: dvdauthor
  0.7.2 (Ubuntu baut ohne kompiliertes `DEFAULT_VIDEO_FORMAT`) erzeugt das
  `VIDEO_TS.IFO`/`BUP` (Domain-Schlüssel) sonst nicht. Lösen: `<vmgm/>`-Element
  in der XML **und** die Umgebungsvariable `VIDEO_FORMAT=pal|ntsc` beim
  dvdauthor-Aufruf setzen (das Standard-Format). Ohne das ist das ISO nicht
  abspielbar (genisoimage meldet "invalid contents").
- **`writing data`-Abbruch** beim Authoring mit langem/leerzeichen-haltigem
  Pfad: die `title.mpg` und `batch.xml` werden in ein kurzes, sauberes
  Zwischenverzeichnis gelegt (dvdauthor löst `<vob file>` relativ zum
  Ausgabe-Ort auf).
- **`Fehlt: wodim`** → `sudo apt install wodim` (nur für `--burn`)
- **ISO zu groß** → niedrigere Bitrate wählen (`--format dvd9`)
- **Player spult nicht** → `-g 15`/GOP ist korrekt; prüfen ob PAL/NTSC stimmt

## Lizenz / Hinweis

Skript für private Medien-Konvertierung. Nehmen Sie nur Aufnahmen an, die Sie
besitzen/berechtigt sind weiterzugeben. BluRay → DVD ist verlustbehaftet
(2. Encodiergang); zur Archivierung ist der Original-Rip die Quelle.