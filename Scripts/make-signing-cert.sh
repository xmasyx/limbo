#!/usr/bin/env bash
# Crea UNA VOLTA un'identità di firma stabile ("Limbo Dev") nel portachiavi di login.
#
# Perché serve, e non è un vezzo da distribuzione: la firma ad-hoc cambia identità
# **a ogni ricostruzione del bundle**, e macOS non riesce più a riconoscere l'app come
# la stessa di ieri. Con un'identità stabile il requisito designato smette di essere un
# `cdhash` che cambia e diventa il certificato, che resta lo stesso per dieci anni.
#
# Gemello utile: anche i permessi di sistema (TCC) seguono l'identità, quindi smettono
# di azzerarsi a ogni build.
#
# **Correzione del 2026-08-03.** Qui c'era scritto che la firma ad-hoc faceva tornare l'avviso
# «Attività app in background». Era falso: l'avviso veniva dal LaunchAgent scritto a mano, che
# macOS cataloga come *legacy agent*, e la prova è Kalamos — firmata allo stesso modo, senza Team
# ID, e muta. Curato passando a `SMAppService` (vedi `LoginItem`). Questo script resta utile per
# le due ragioni vere qui sopra.
#
# **Gotcha, pagato il 2026-08-03:** `-A -T /usr/bin/codesign` più sotto NON basta. macOS mette
# alla chiave una *partition list* a parte, e la prima firma apre comunque il dialogo del
# portachiavi — che dentro una build non interattiva è un blocco silenzioso a tempo
# indeterminato (successo oggi: dieci minuti fermi senza una riga di output). Si chiude una
# volta sola, dal Terminale:
#
#   security set-key-partition-list -S apple-tool:,apple:,codesign: \
#       -s -l "Limbo Dev" ~/Library/Keychains/login.keychain-db
#
# Chiede la password del portachiavi «login» e non stampa niente quando va bene.
#
# Si esegue una volta sola:  ./Scripts/make-signing-cert.sh
set -euo pipefail

IDENTITY="Limbo Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "✓ l'identità \"$IDENTITY\" c'è già, non tocco niente."
    exit 0
fi

# Un certificato rimasto da un tentativo fallito (importato ma non fidato) farebbe
# fallire l'import silenziosamente: si toglie, così rilanciare lo script è sempre pulito.
security delete-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1 || true

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/openssl.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions    = v3
prompt             = no
[dn]
CN = Limbo Dev
[v3]
basicConstraints   = critical, CA:false
keyUsage           = critical, digitalSignature
extendedKeyUsage   = critical, codeSigning
CNF

echo "▸ genero il certificato auto-firmato…"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf"

# `security import` rifiuta i p12 senza password («MAC verification failed») e non legge
# il MAC predefinito di OpenSSL 3: serve una password e `-legacy` dove esiste.
P12PASS="${P12_PASS:-$(openssl rand -hex 16)}"
LEGACY=""
if openssl pkcs12 -help 2>&1 | grep -q -- "-legacy"; then LEGACY="-legacy"; fi
openssl pkcs12 -export $LEGACY -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout "pass:$P12PASS" -name "$IDENTITY"

# Il .p12 e la SOLA copia della chiave privata: senza, un portachiavi ricreato da
# macOS porta via l identita per sempre (successo il 30/08/2026). Si copia fuori
# PRIMA che il trap cancelli $TMP, e mai dentro un repository.
BACKUP_DIR="${SIGNING_BACKUP_DIR:-$HOME/Library/Application Support/Limbo/signing}"
mkdir -p "$BACKUP_DIR"
cp "$TMP/id.p12" "$BACKUP_DIR/limbo.p12"
printf '%s\n' "$P12PASS" > "$BACKUP_DIR/limbo.password"
chmod 600 "$BACKUP_DIR/limbo.p12" "$BACKUP_DIR/limbo.password"
echo "- chiave privata conservata in $BACKUP_DIR/limbo.p12 (password in limbo.password)"

echo "▸ importo nel portachiavi di login (con accesso per codesign)…"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$P12PASS" -A -T /usr/bin/codesign

# Un certificato auto-firmato non è "valido" per codesign finché non è fidato.
# Qui può comparire una finestra del portachiavi che chiede la password di login.
echo "▸ lo rendo fidato per la firma del codice (approva la finestra del portachiavi)…"
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem" || true

if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "✓ identità \"$IDENTITY\" creata."
    echo "  Ora ricostruisci con ./Scripts/build-app.sh"
else
    echo "✗ identità non trovata dopo l'import. Rilancia lo script da un Terminale," >&2
    echo "  dove la finestra del portachiavi può comparire davvero." >&2
    exit 1
fi
