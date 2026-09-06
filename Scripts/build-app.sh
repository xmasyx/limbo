#!/bin/bash
# Costruisce Limbo.app e la installa in /Applications.
#
# «Compilato» non vuol dire «consegnato» (MacAppRules §1): la copia che si apre
# è quella installata. Il bundle di lavorazione vive in una cartella
# temporanea, mai in dist/ — due icone identiche in Spotlight sono un difetto.
#
#   LIMBO_SKIP_INSTALL=1 Scripts/build-app.sh   → costruisce senza installare

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:-${TMPDIR:-/tmp}/Limbo-build}"
APP="$DEST/Limbo.app"
# La versione la può dettare chi costruisce: sul runner è il TAG a essere la
# verità (`LIMBO_VERSION=0.6.0`), così il bundle non può dire un numero diverso
# da quello della release che lo contiene.
VERSION="${LIMBO_VERSION:-0.6.0}"

cd "$ROOT"

# Un file di codice che nessun compilatore guarda va comunque fatto guardare da
# qualcosa (MacAppRules §6: uno script rotto ha superato la firma ed è fallito
# in faccia dopo la password di amministratore).
echo "▸ controllo la sintassi degli script…"
for s in "$ROOT"/Scripts/*.sh; do
    bash -n "$s" || { echo "✗ sintassi rotta in $s" >&2; exit 5; }
done

echo "▸ controllo l'italiano del testo che si legge…"
bash "$ROOT/Scripts/check-italian.sh"

echo "▸ compilo (release)…"
swift build -c release --product Limbo

BIN="$ROOT/.build/release/Limbo"

echo "▸ banco delle stringhe…"
"$BIN" --selftest-stringhe

echo "▸ banco della geometria…"
"$BIN" --selftest-geometria

echo "▸ banco del movimento…"
"$BIN" --selftest-movimento

echo "▸ banco del deposito…"
"$BIN" --selftest-deposito

echo "▸ banco della scheda Chat…"
"$BIN" --selftest-chat

echo "▸ banco della grazia del puntatore…"
"$BIN" --selftest-grazia

echo "▸ banco dell'aggiornamento…"
"$BIN" --selftest-aggiornamenti

echo "▸ banco di quello che è arrivato il 19/08…"
"$BIN" --selftest-nuove

# Il banco della fluidita': misura il costo di un fotogramma del pannello,
# fermo e a meta' apertura. Nasce il 18/08 dall'impasto che lui ha visto, ed e'
# la sonda che dice se qualcuno rimette del lavoro pesante sul thread che
# disegna.
echo "▸ banco della fluidità…"
"$BIN" --banco-fluidita

echo "▸ icona…"
# L'icona vera vive in Assets/ ed è nel repo: una fotografia ritagliata dentro
# la piastrella, col notch nero appeso in cima (sua scelta del 6/09, «falene»
# con il notch a 0,095 del lato). `MakeIcon.swift` resta come ripiego se un
# giorno l'asset sparisse: disegna in codice la vecchia icona geometrica.
if [[ -f "$ROOT/Assets/icon-1024.png" ]]; then
    cp "$ROOT/Assets/icon-1024.png" "$ROOT/.build/icon-1024.png"
elif [[ ! -f "$ROOT/.build/icon-1024.png" ]]; then
    swift "$ROOT/Scripts/MakeIcon.swift" "$ROOT/.build/icon-1024.png" >/dev/null
fi
rm -rf "$ROOT/.build/icon.iconset"
mkdir -p "$ROOT/.build/icon.iconset"
for size in 16 32 64 128 256 512; do
    sips -z $size $size "$ROOT/.build/icon-1024.png" \
        --out "$ROOT/.build/icon.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$ROOT/.build/icon-1024.png" \
        --out "$ROOT/.build/icon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ROOT/.build/icon.iconset" -o "$ROOT/.build/Limbo.icns"

echo "▸ assemblo il bundle…"
mkdir -p "$DEST"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Limbo"
cp "$ROOT/.build/Limbo.icns" "$APP/Contents/Resources/Limbo.icns"

# L'eseguibile del bundle è byte per byte quello compilato (lezione NoSleep: su
# APFS senza distinzione di maiuscole una cp può sovrascrivere quella
# sbagliata).
if ! cmp -s "$BIN" "$APP/Contents/MacOS/Limbo"; then
    echo "✗ l'eseguibile del bundle NON è quello compilato — build interrotta" >&2
    exit 4
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Limbo</string>
    <key>CFBundleDisplayName</key><string>Limbo</string>
    <key>CFBundleExecutable</key><string>Limbo</string>
    <key>CFBundleIdentifier</key><string>app.limbo.mac</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>Limbo</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <!-- Vive nel notch: niente Dock e (dal 19/08) niente barra dei menu. -->
    <key>LSUIElement</key><true/>
    <!-- La scheda Chat: il clic su una riga porta iTerm2 alla sessione giusta.
         Senza questa dicitura macOS nega l'Automazione senza nemmeno chiedere. -->
    <key>NSAppleEventsUsageDescription</key><string>Un clic su una riga della scheda Chat apre iTerm2 sulla sessione giusta.</string>
    <key>NSHumanReadableCopyright</key><string>Locale. Niente rete, niente telemetria: quello che copi non esce dal Mac.</string>
</dict>
</plist>
PLIST

# Si firma con l'IMPRONTA, non col nome: `codesign -s "Limbo Dev"` esce
# `ambiguous` quando nel portachiavi restano certificati omonimi, e in più il
# nome non prova niente — un altro autofirmato con lo stesso nome comune lo
# supererebbe, e macOS azzererebbe i permessi già concessi.
IDENTITY="Limbo Dev"
IMPRONTA="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "$IDENTITY" | head -1 | awk '{print $2}')"
if [[ -n "$IMPRONTA" ]]; then
    echo "▸ firma con identità stabile «${IDENTITY}» (${IMPRONTA})…"
    # `xattr -cr` prima della firma: codesign rifiuta un bundle con «resource
    # fork, Finder information, or similar detritus not allowed».
    xattr -cr "$APP" 2>/dev/null || true
    codesign --force --deep --sign "$IMPRONTA" --timestamp=none "$APP"
elif [[ "${LIMBO_RELEASE:-0}" == "1" ]]; then
    # Un artefatto pubblicato firmato ad-hoc cambia identità a ogni build, e
    # con essa i permessi concessi: qui la firma è un requisito, non un extra.
    echo "✗ manca l'identità «${IDENTITY}» e LIMBO_RELEASE=1: non firmo ad-hoc" >&2
    exit 6
else
    echo "▸ firma ad-hoc…"
    codesign --force --deep --sign - --timestamp=none "$APP" >/dev/null 2>&1 \
        || echo "  (firma saltata: non blocca l'avvio in locale)"
fi

INSTALLED="/Applications/Limbo.app"
if [[ "${LIMBO_SKIP_INSTALL:-0}" == "1" ]]; then
    echo "▸ installazione saltata (LIMBO_SKIP_INSTALL=1)"
elif pgrep -f "^$INSTALLED/Contents/MacOS/Limbo( |\$)" >/dev/null; then
    echo "⚠︎ Limbo è in esecuzione da $INSTALLED — esci dall'app e rilancia questo script"
    echo "  (il bundle nuovo resta pronto in $APP)"
else
    echo "▸ installo in ${INSTALLED}…"
    rm -rf "$INSTALLED"
    ditto "$APP" "$INSTALLED"
fi

echo "✓ pronto: $APP"
echo "  installata: $INSTALLED"
echo "  apri con:   open \"$INSTALLED\""
echo "  archivio:   ~/Library/Application Support/Limbo/"
