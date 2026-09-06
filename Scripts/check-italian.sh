#!/bin/bash
# Fa passare TUTTO il testo che si legge da un cancello di stile italiano
# (MacAppRules §5: NoSleep è uscita in traduttese perché il cancello copriva i
# documenti e non le stringhe dell'interfaccia).
#
# Gira dentro build-app.sh. Il cancello è esterno e opzionale: si indica con
# ITALIAN_GATE, e senza quella variabile lo script salta senza bloccare — un
# controllo di stile che impedisce a un estraneo di compilare sarebbe un
# difetto peggiore del traduttese che previene.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STRINGS="$ROOT/Sources/Limbo/Strings.swift"
GATE="${ITALIAN_GATE:-}"
TMP="$(mktemp -t limbo-strings).md"

if [[ -z "$GATE" || ! -f "$GATE" ]]; then
    echo "▸ nessun cancello di italiano configurato (ITALIAN_GATE), salto"
    exit 0
fi

python3 - "$STRINGS" "$TMP" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
righe = []
for m in re.finditer(r'"((?:[^"\\]|\\.)*)"', src):
    t = m.group(1)
    # Le stringhe corte sono etichette, non prosa.
    if len(t) > 12 and not t.startswith('\\('):
        righe.append('- ' + re.sub(r'\\\([a-zA-Z]+\)', 'valore', t))
testo = '# Testo di Limbo\n\n' + '\n'.join(dict.fromkeys(righe)) + '\n'
open(sys.argv[2], 'w').write(testo)
PY

bun "$GATE" "$TMP"
