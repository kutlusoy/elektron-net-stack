#!/usr/bin/env bash
#
# Elektron Net -- one-shot install script (node + ppool + ppool-ui + faucet + Caddy)
#
# Usage:
#   1. Copy this file (and, if you have one, elektron-stack.conf) onto the
#      Hetzner server (Hetzner console / scp).
#   2. chmod +x install-elektron-stack.sh
#   3. ./install-elektron-stack.sh
#
# Three ways to supply the server-specific settings (domains, IPs, GitHub
# user, hCaptcha keys, ...) -- pick whichever is easiest, or mix them:
#
#   a) Interactive: just run the script from a terminal. It prompts for
#      every setting, showing the built-in default in brackets -- press
#      Enter to keep it. This is what happens by default when stdin is a
#      terminal.
#   b) Config file upload: copy elektron-stack.conf.example to
#      elektron-stack.conf, fill in your values (locally, or with an
#      editor directly on the server), place it next to this script (or
#      pass --config /path/to/file). Anything left blank there falls back
#      to the built-in default / an interactive prompt.
#   c) Fully unattended: combine (b) with --yes to skip every prompt, e.g.
#      for scripted/CI installs.
#
# All secrets (JWT_SECRET, DB passwords, wallet passphrase, faucet admin
# password, RPC password) are auto-generated when left blank -- you never
# have to invent or type those yourself.
#
# Safe to re-run: existing clones/wallets are detected and skipped instead
# of being recreated or overwritten.

set -euo pipefail

log()  { printf '\n\033[1;32m==>\033[0m %s\n' "$1"; }
warn() { printf '\n\033[1;33m!!\033[0m %s\n' "$1"; }
die()  { printf '\n\033[1;31mERROR:\033[0m %s\n' "$1"; exit 1; }

# ============================================================================
# CONFIG DEFAULTS -- overridden by elektron-stack.conf (see --config below)
# and/or the interactive prompts further down. Only edit these directly if
# you'd rather not use a config file or prompts at all.
# ============================================================================

# --- General ---
STACK_DIR="/opt/elektron-net-stack"           # where everything gets installed
GITHUB_USER="kutlusoy"                        # github.com/<user>/elektron-net...
# false = never touch already-cloned repos (today's default, 100% predictable).
# true = on every run, git fetch each already-cloned repo and fast-forward
# it to its upstream tracking branch if there are new commits (never force,
# never rebase -- a diverged local branch is left alone and just warned
# about). Asked interactively below unless --yes is given.
AUTO_UPDATE_REPOS="false"
SERVER_IP="46.225.163.85"                     # only used for the DNS sanity check
# Fallback-Wert, falls die automatische Erkennung weiter unten (ip -6 addr)
# nichts findet. Das Hetzner-Panel zeigt im Networking-Tab nur das geroutete
# /64-Subnetz (z.B. 2a01:4f8:1c18:ea01::/64), NICHT die exakt konfigurierte
# Host-Adresse -- die wird gleich live auf diesem Server ausgelesen.
SERVER_IPV6="2a01:4f8:1c18:ea01::1"

# --- Domains (must already point to SERVER_IP in DNS, see README) ---
NODE_DOMAIN="node1.elektron-net.org"          # P2P seed only, no HTTP/Caddy block
POOL_DOMAIN="pplns.elektron-net.org"
FAUCET_DOMAIN="faucet.elektron-net.org"
CADDY_EMAIL=""                                # optional, for Let's Encrypt notices

# --- Node / RPC ---
RPC_USER="elektron_svc"                       # rpcauth username (password is auto-generated)

# --- Firewall ---
FIREWALL_AUTO_CONFIGURE=true                  # true = run ufw commands automatically

# --- Pool (elektron-net-ppool) ---
POOL_WALLET_NAME="pool"                       # wallet name on the node for pool payouts
# leave empty to auto-generate a strong passphrase (printed at the end -- save it!):
# The pool wallet gets encrypted with this just like the faucet wallet --
# ppool unlocks it automatically for WALLET_UNLOCK_SECONDS on every payout
# run, then re-locks it immediately (see wallet-rpc.service.ts).
POOL_WALLET_PASSPHRASE=""
WALLET_UNLOCK_SECONDS="60"
POOL_IDENTIFIER="Elektron-PPLNS-Pool"
POOL_FEE_PERCENT="1.0"
PPLNS_WINDOW_MINUTES="90"
MIN_PAYOUT_THRESHOLD_SATS="100000"
PAYOUT_INTERVAL_MINUTES="60"
PAYOUT_CONFIRMATIONS_REQUIRED="1"
PAYOUT_DRY_RUN="true"                         # keep true until you've verified payouts!
STRATUM_PORT="3333"
API_PORT="3334"
# leave empty to auto-generate a random 32-byte hex secret:
JWT_SECRET=""

# Optional -- Telegram bot for miner payout notifications (/subscribe
# <address>). Leave both empty to disable; TELEGRAM_BOT_USERNAME is purely
# cosmetic (shown as a link), has no effect on which bot receives traffic.
TELEGRAM_BOT_TOKEN=""
TELEGRAM_BOT_USERNAME=""
# Optional -- Discord bot. All four must be set together, otherwise the
# integration stays disabled (see discord.service.ts).
DISCORD_BOT_TOKEN=""
DISCORD_BOT_CLIENTID=""
DISCORD_BOT_GUILD_ID=""
DISCORD_BOT_CHANNEL_ID=""

# --- Faucet (elektron-net-faucet) ---
FAUCET_WALLET_NAME="faucet"                   # wallet name on the node for faucet payouts
# leave empty to auto-generate a strong passphrase (printed at the end -- save it!):
FAUCET_WALLET_PASSPHRASE=""
FAUCET_DB_NAME="elek_faucet"
FAUCET_DB_USER="elek_faucet"
# leave empty to auto-generate:
FAUCET_DB_PASS=""
FAUCET_DB_ROOT_PASS=""
FAUCET_ADMIN_USER="admin"
# leave empty to auto-generate (min 10 chars required by the faucet):
FAUCET_ADMIN_PASS=""
FAUCET_HCAPTCHA_SITE=""                       # from hcaptcha.com -- strongly recommended
FAUCET_HCAPTCHA_SECRET=""
FAUCET_TITLE="Elektron Net Faucet"
FAUCET_MESSAGE="Claim some free ELEK!"
FAUCET_AMOUNT_ELEK="0.001"
FAUCET_DAILY_BUDGET="1"
FAUCET_HOURLY_BUDGET="0.1"
FAUCET_PER_ADDR_COOLDOWN_H="24"
FAUCET_PER_IP_COOLDOWN_H="1"
FAUCET_DEFAULT_LANG="de"
FAUCET_EXPLORER_URL=""                        # optional, shown as a link after a successful claim

# Every variable a config file / prompt round is allowed to touch -- keep in
# sync with the block above. Doubles as the whitelist for config-file keys
# (so an uploaded file can only ever set plain values, never run code).
CONFIG_VARS="STACK_DIR GITHUB_USER AUTO_UPDATE_REPOS SERVER_IP SERVER_IPV6 NODE_DOMAIN POOL_DOMAIN
FAUCET_DOMAIN CADDY_EMAIL RPC_USER FIREWALL_AUTO_CONFIGURE POOL_WALLET_NAME
POOL_WALLET_PASSPHRASE WALLET_UNLOCK_SECONDS
POOL_IDENTIFIER POOL_FEE_PERCENT PPLNS_WINDOW_MINUTES MIN_PAYOUT_THRESHOLD_SATS
PAYOUT_INTERVAL_MINUTES PAYOUT_CONFIRMATIONS_REQUIRED PAYOUT_DRY_RUN STRATUM_PORT
API_PORT JWT_SECRET TELEGRAM_BOT_TOKEN TELEGRAM_BOT_USERNAME DISCORD_BOT_TOKEN
DISCORD_BOT_CLIENTID DISCORD_BOT_GUILD_ID DISCORD_BOT_CHANNEL_ID
FAUCET_WALLET_NAME FAUCET_WALLET_PASSPHRASE FAUCET_DB_NAME
FAUCET_DB_USER FAUCET_DB_PASS FAUCET_DB_ROOT_PASS FAUCET_ADMIN_USER FAUCET_ADMIN_PASS
FAUCET_HCAPTCHA_SITE FAUCET_HCAPTCHA_SECRET FAUCET_TITLE FAUCET_MESSAGE FAUCET_AMOUNT_ELEK
FAUCET_DAILY_BUDGET FAUCET_HOURLY_BUDGET FAUCET_PER_ADDR_COOLDOWN_H FAUCET_PER_IP_COOLDOWN_H
FAUCET_DEFAULT_LANG FAUCET_EXPLORER_URL"

# ============================================================================
# CLI args: --config FILE, --yes/-y (skip prompts), --help/-h
# ============================================================================
CONFIG_FILE=""
ASSUME_YES=false

usage() {
  cat <<'USAGE_EOF'
Usage: install-elektron-stack.sh [--config FILE] [--yes] [--help]

  --config FILE   Load settings from FILE (KEY=VALUE per line, see
                  elektron-stack.conf.example). Values found there override
                  the built-in defaults; anything still unset afterwards is
                  asked interactively unless --yes is given.
  --yes, -y       Never prompt -- use defaults / config-file values as-is.
                  Use this for unattended/CI runs.
  --help, -h      Show this help text and exit.

If no --config is given, a file named elektron-stack.conf next to this
script is used automatically if present.
USAGE_EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONFIG_FILE="${2:-}"; shift 2 ;;
    --config=*) CONFIG_FILE="${1#*=}"; shift ;;
    -y|--yes) ASSUME_YES=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unbekannte Option: $1 (siehe --help)" ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$CONFIG_FILE" ] && [ -f "${SCRIPT_DIR}/elektron-stack.conf" ]; then
  CONFIG_FILE="${SCRIPT_DIR}/elektron-stack.conf"
  log "Gefundene Config-Datei wird automatisch verwendet: ${CONFIG_FILE}"
fi

is_config_var() {
  local name="$1" v
  for v in $CONFIG_VARS; do [ "$v" = "$name" ] && return 0; done
  return 1
}

# Deliberately simple KEY=VALUE parser (NOT `source`) so an uploaded config
# file can only ever set plain values from the whitelist above -- it can
# never execute shell code, even if it came from somewhere untrusted.
if [ -n "$CONFIG_FILE" ]; then
  [ -f "$CONFIG_FILE" ] || die "Config-Datei nicht gefunden: $CONFIG_FILE"
  log "Lade Konfiguration aus ${CONFIG_FILE} ..."
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -z "$line" ] && continue
    case "$line" in
      *=*) ;;
      *) warn "Zeile ohne '=' in ${CONFIG_FILE} ignoriert: $line"; continue ;;
    esac
    key="$(printf '%s' "${line%%=*}" | sed -e 's/[[:space:]]*$//')"
    val="$(printf '%s' "${line#*=}" | sed -e 's/^[[:space:]]*//')"
    val="$(printf '%s' "$val" | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/")"
    if is_config_var "$key"; then
      printf -v "$key" '%s' "$val"
    else
      warn "Unbekannter Schlüssel in ${CONFIG_FILE} ignoriert: $key"
    fi
  done < "$CONFIG_FILE"
fi

# ============================================================================
# Interactive prompts -- only for the handful of settings that need a human
# decision (domains, IPs, GitHub user, optional hCaptcha/Let's Encrypt
# mail). All secrets keep auto-generating silently if left blank, see below.
# ============================================================================
ask() {
  local var_name="$1" prompt_text="$2" current input
  current="${!var_name}"
  read -rp "$prompt_text [${current:-leer}]: " input
  if [ -n "$input" ]; then
    printf -v "$var_name" '%s' "$input"
  fi
}

# Strict j/n prompt for boolean settings -- anything that isn't a clear
# yes/no answer keeps the current default rather than guessing.
ask_yes_no() {
  local var_name="$1" prompt_text="$2" current input default_label
  current="${!var_name}"
  [ "$current" = "true" ] && default_label="J/n" || default_label="j/N"
  read -rp "$prompt_text [$default_label]: " input
  case "$input" in
    [jJyY]*) printf -v "$var_name" 'true' ;;
    [nN]*) printf -v "$var_name" 'false' ;;
    "") : ;;
    *) warn "Unklare Eingabe ('$input') -- behalte den bisherigen Wert ($current)." ;;
  esac
}

if [ "$ASSUME_YES" = false ] && [ -t 0 ]; then
  log "Interaktive Konfiguration -- Enter übernimmt den Default-/Config-Wert. Mit --yes überspringen."
  ask_yes_no AUTO_UPDATE_REPOS "Vor dem Bauen nach Updates in den geklonten Repos suchen und per 'git pull --ff-only' einspielen?"
  ask GITHUB_USER   "GitHub-Benutzername (github.com/<user>/elektron-net...)"
  ask SERVER_IP     "Öffentliche IPv4-Adresse dieses Servers"
  ask SERVER_IPV6   "Öffentliche IPv6-Adresse (wird unten zusätzlich automatisch erkannt)"
  ask NODE_DOMAIN   "Domain für den P2P-Seed-Node"
  ask POOL_DOMAIN   "Domain für das Pool-Dashboard"
  ask FAUCET_DOMAIN "Domain für den Faucet"
  ask CADDY_EMAIL   "E-Mail für Let's Encrypt (optional, Enter zum Überspringen)"
  ask FAUCET_HCAPTCHA_SITE   "hCaptcha Site-Key von hcaptcha.com (optional, aber empfohlen)"
  ask FAUCET_HCAPTCHA_SECRET "hCaptcha Secret-Key (optional)"
  log "Alle Passwörter/Secrets (JWT_SECRET, DB-Passwörter, Wallet-Passphrase, RPC-Passwort,"
  log "Faucet-Admin-Passwort) werden gleich automatisch generiert, sofern nicht per Config-Datei vorgegeben."
else
  log "Nicht-interaktiver Modus (--yes oder kein Terminal) -- verwende Defaults/Config-Datei ohne Rückfrage."
fi

# ============================================================================
# END CONFIG -- nothing below this line needs editing for a normal install
# ============================================================================

rand_hex()    { openssl rand -hex "$1"; }
rand_base64() { openssl rand -base64 "$1" | tr -d '=+/\n' | cut -c1-"$1"; }

# ----------------------------------------------------------------------------
# Re-running this script (e.g. after editing elektron-stack.conf to change
# one setting) must NOT silently rotate secrets, RPC passwords or wallet
# addresses that are already in use -- that would break already-running
# containers (DB auth, RPC auth, faucet wallet unlock) or orphan funds sent
# to a previously issued address. So before anything gets (re)written, snap-
# shot whatever is already deployed from a previous run and prefer that over
# generating something new.
# ----------------------------------------------------------------------------
existing_value() {
  # existing_value <file> <KEY> -- prints KEY's current value from a
  # KEY=VALUE file, or nothing if the file/key doesn't exist yet.
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  grep "^${key}=" "$file" 2>/dev/null | tail -n1 | cut -d= -f2-
}

PPOOL_ENV_PATH="${STACK_DIR}/elektron-net-ppool/.env"
FAUCET_ENV_PATH="${STACK_DIR}/elektron-net-faucet/.env"
BITCOIN_CONF_PATH="${STACK_DIR}/elektron-net/bitcoin.conf"

# Auto-generate any secret left blank in the CONFIG block above -- but only
# if it wasn't already generated by an earlier run of this script. Track
# which ones were freshly generated vs. reused vs. supplied by you, so the
# final summary can say so explicitly.
GENERATED_SECRETS=""
REUSED_SECRETS=""

reuse_or_generate() {
  # reuse_or_generate <var_name> <source_file> <key> <generator_expr...>
  local var_name="$1" src_file="$2" key="$3"; shift 3
  [ -n "${!var_name}" ] && return 0  # explicitly set via config/prompt -- leave it alone
  local existing
  existing="$(existing_value "$src_file" "$key")"
  if [ -n "$existing" ]; then
    printf -v "$var_name" '%s' "$existing"
    REUSED_SECRETS="${REUSED_SECRETS}${var_name} "
  else
    printf -v "$var_name" '%s' "$("$@")"
    GENERATED_SECRETS="${GENERATED_SECRETS}${var_name} "
  fi
}

reuse_or_generate JWT_SECRET              "$PPOOL_ENV_PATH"  JWT_SECRET              rand_hex 32
reuse_or_generate POOL_WALLET_PASSPHRASE   "$PPOOL_ENV_PATH"  WALLET_PASSPHRASE       rand_base64 32
reuse_or_generate FAUCET_WALLET_PASSPHRASE "$FAUCET_ENV_PATH" FAUCET_WALLET_PASS      rand_base64 32
reuse_or_generate FAUCET_DB_PASS           "$FAUCET_ENV_PATH" FAUCET_DB_PASS          rand_base64 24
reuse_or_generate FAUCET_DB_ROOT_PASS      "$FAUCET_ENV_PATH" FAUCET_DB_ROOT_PASS     rand_base64 24
reuse_or_generate FAUCET_ADMIN_PASS        "$FAUCET_ENV_PATH" FAUCET_ADMIN_PASS       rand_base64 16

[ -n "$REUSED_SECRETS" ] && log "Aus vorherigem Lauf wiederverwendet (nicht neu generiert): ${REUSED_SECRETS}"

# RPC-Zugangsdaten (rpcauth.py) genauso wiederverwenden statt bei jedem Lauf
# neu zu erzeugen -- siehe Schritt 3 weiter unten, das ist hier nur die
# Vorab-Prüfung, ob es sie schon gibt.
REUSE_RPC_AUTH=false
EXISTING_RPC_AUTH_LINE="$(existing_value "$BITCOIN_CONF_PATH" rpcauth)"
EXISTING_RPC_USER="${EXISTING_RPC_AUTH_LINE%%:*}"
EXISTING_RPC_PASSWORD="$(existing_value "$PPOOL_ENV_PATH" ELEKTRON_RPC_PASSWORD)"
if [ -n "$EXISTING_RPC_AUTH_LINE" ] && [ -n "$EXISTING_RPC_PASSWORD" ] && [ "$EXISTING_RPC_USER" = "$RPC_USER" ]; then
  REUSE_RPC_AUTH=true
fi

# Wallet-Adressen genauso: getnewaddress liefert bei jedem Aufruf eine NEUE,
# bislang unbenutzte Adresse -- ein Rerun darf also nicht einfach erneut
# aufrufen, sonst zeigt POOL_WALLET_ADDRESS/FAUCET_SENDER_ADDR danach auf
# eine leere Adresse, während bereits eingezahltes ELEK auf der alten liegt.
# Nur reuse-n, wenn der Wallet-Name seit dem letzten Lauf unverändert ist.
EXISTING_POOL_WALLET_ADDRESS=""
if [ "$(existing_value "$PPOOL_ENV_PATH" WALLET_RPC_WALLET_NAME)" = "$POOL_WALLET_NAME" ]; then
  EXISTING_POOL_WALLET_ADDRESS="$(existing_value "$PPOOL_ENV_PATH" POOL_WALLET_ADDRESS)"
fi
EXISTING_FAUCET_SENDER_ADDR=""
if [ "$(existing_value "$FAUCET_ENV_PATH" FAUCET_WALLET_NAME)" = "$FAUCET_WALLET_NAME" ]; then
  EXISTING_FAUCET_SENDER_ADDR="$(existing_value "$FAUCET_ENV_PATH" FAUCET_SENDER_ADDR)"
fi

command -v docker >/dev/null 2>&1 || die "Docker ist nicht installiert."
docker compose version >/dev/null 2>&1 || die "Docker Compose Plugin fehlt."
command -v git >/dev/null 2>&1    || die "git ist nicht installiert."
command -v python3 >/dev/null 2>&1 || die "python3 ist nicht installiert (wird für rpcauth.py gebraucht)."
command -v openssl >/dev/null 2>&1 || die "openssl ist nicht installiert."

# --- Tatsächlich konfigurierte IPv6-Adresse auf diesem Server auslesen ---
# Das Hetzner-Panel zeigt nur das geroutete /64, nicht die konkrete Adresse,
# die der Server sich selbst gegeben hat -- also lieber direkt nachsehen,
# statt der Fallback-Annahme (::1) blind zu vertrauen.
DETECTED_IPV6="$(ip -6 addr show scope global 2>/dev/null | awk '/inet6/{print $2}' | cut -d/ -f1 | grep -v '^fe80' | head -n1 || true)"
if [ -n "$DETECTED_IPV6" ] && [ "$DETECTED_IPV6" != "$SERVER_IPV6" ]; then
  warn "Erkannte IPv6-Adresse auf diesem Server ($DETECTED_IPV6) weicht vom CONFIG-Wert ($SERVER_IPV6) ab -- verwende die erkannte Adresse."
  SERVER_IPV6="$DETECTED_IPV6"
elif [ -z "$DETECTED_IPV6" ]; then
  warn "Konnte keine globale IPv6-Adresse auf diesem Server finden -- IPv6 evtl. noch nicht konfiguriert. Verwende weiterhin den CONFIG-Wert ($SERVER_IPV6), bitte prüfen."
fi

# --- Soft DNS sanity check (does not abort on mismatch, just warns) ---
for d in "$NODE_DOMAIN" "$POOL_DOMAIN" "$FAUCET_DOMAIN"; do
  resolved="$(getent ahostsv4 "$d" 2>/dev/null | awk '{print $1}' | head -n1 || true)"
  if [ -z "$resolved" ]; then
    warn "$d löst (noch) nicht auf. Caddy wird für dieses Encpoint kein TLS bekommen, bis DNS propagiert ist."
  elif [ "$resolved" != "$SERVER_IP" ]; then
    warn "$d löst auf $resolved auf, nicht auf $SERVER_IP. Bitte DNS-Eintrag prüfen."
  fi

  resolved6="$(getent ahostsv6 "$d" 2>/dev/null | awk '{print $1}' | head -n1 || true)"
  if [ -z "$resolved6" ]; then
    warn "$d hat (noch) keinen AAAA-Eintrag -- IPv6-Erreichbarkeit fehlt, IPv4 funktioniert trotzdem."
  elif [ "$resolved6" != "$SERVER_IPV6" ]; then
    warn "$d (AAAA) löst auf $resolved6 auf, nicht auf $SERVER_IPV6. Bitte DNS-Eintrag prüfen."
  fi
done

# ============================================================================
# 1. Repos klonen
# ============================================================================
mkdir -p "$STACK_DIR"
cd "$STACK_DIR"

update_if_enabled() {
  # Only ever fast-forwards the CURRENTLY checked-out branch to its own
  # upstream tracking branch -- never force, never rebase, never touches
  # an intentionally checked-out different branch/commit. A diverged
  # branch (local commits ahead, or no upstream configured) is left
  # completely alone, just reported.
  local repo="$1"
  [ "$AUTO_UPDATE_REPOS" = "true" ] || return 0
  ( cd "$repo" \
    && git fetch --quiet \
    && local_head="$(git rev-parse HEAD)" \
    && remote_head="$(git rev-parse '@{upstream}' 2>/dev/null || true)" \
    && if [ -z "$remote_head" ]; then
         warn "$repo: kein Upstream-Tracking-Branch gefunden, überspringe Update-Check."
       elif [ "$local_head" = "$remote_head" ]; then
         log "$repo: bereits aktuell, keine neuen Commits."
       elif git merge-base --is-ancestor HEAD "@{upstream}"; then
         log "$repo: neue Commits gefunden, aktualisiere (fast-forward):"
         git log --oneline "HEAD..@{upstream}"
         git pull --ff-only --quiet
       else
         warn "$repo: lokaler Branch ist vom Upstream abgewichen (eigene Commits?) -- überspringe automatisches Update, bitte manuell prüfen."
       fi
  )
}

clone_or_skip() {
  local repo="$1"
  if [ -d "$repo/.git" ]; then
    log "Repo $repo existiert schon (vollständiger git-Klon), überspringe Neu-Klonen."
    update_if_enabled "$repo"
    return
  fi

  if [ -d "$repo" ] && [ "$(ls -A "$repo" 2>/dev/null)" ]; then
    # Verzeichnis existiert bereits und ist nicht leer -- typischerweise weil
    # es aus DIESEM Deploy-Repo (elektron-net-stack) kommt und schon unsere
    # Zusatzdateien enthält (Dockerfile, bitcoin.conf, .env-Template, ...).
    # `git clone` würde hier mit "destination path already exists and is
    # not an empty directory" abbrechen -- also stattdessen in ein
    # Temp-Verzeichnis klonen und nur das reinkopieren, was noch nicht da
    # ist (unsere bereits vorhandenen Dateien bleiben unangetastet).
    log "Verzeichnis $repo existiert schon und ist nicht leer -- klone Upstream in ein Temp-Verzeichnis und merge non-destruktiv rein."
    local tmp
    tmp="$(mktemp -d)"
    git clone "https://github.com/${GITHUB_USER}/${repo}.git" "$tmp"
    rm -rf "$tmp/.git"
    cp -rn "$tmp"/. "$repo"/
    rm -rf "$tmp"
  else
    log "Klone $repo ..."
    git clone "https://github.com/${GITHUB_USER}/${repo}.git" "$repo"
  fi
}

clone_or_skip "elektron-net"
clone_or_skip "elektron-net-ppool"
clone_or_skip "elektron-net-ppool-ui"
clone_or_skip "elektron-net-faucet"

mkdir -p caddy data/elektron-net data/ppool-DB data/faucet-db data/faucet-config external-wallets

# ============================================================================
# 2. elektron-net: Dockerfile + Entrypoint (existieren im Repo noch nicht)
# ============================================================================
log "Schreibe elektron-net/Dockerfile ..."
cat > elektron-net/Dockerfile <<'DOCKERFILE_EOF'
############################
# Build stage              #
############################
FROM debian:bookworm-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake pkgconf python3 \
        libevent-dev libboost-dev libsqlite3-dev libzmq3-dev \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY . .

RUN cmake -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_GUI=OFF \
        -DWITH_ZMQ=ON \
        -DENABLE_IPC=OFF \
    && cmake --build build -j"$(nproc)" \
    && cmake --install build

############################
# Runtime stage            #
############################
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        libevent-2.1-7 libevent-pthreads-2.1-7 libevent-extra-2.1-7 \
        libsqlite3-0 libzmq5 \
        ca-certificates gosu \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -r elektron && useradd -r -g elektron -d /data -s /usr/sbin/nologin elektron \
    && mkdir -p /data && chown elektron:elektron /data

COPY --from=build /usr/local/bin/elektron* /usr/local/bin/

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

VOLUME ["/data"]
EXPOSE 8333 8332

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["elektrond", "-conf=/data/bitcoin.conf", "-datadir=/data", "-printtoconsole"]
DOCKERFILE_EOF

log "Schreibe elektron-net/docker-entrypoint.sh ..."
cat > elektron-net/docker-entrypoint.sh <<'ENTRYPOINT_EOF'
#!/bin/sh
set -e
# bitcoin.conf is bind-mounted read-only directly at /data/bitcoin.conf --
# `chown -R` on the whole tree would fail on it (Read-only file system)
# and, under `set -e`, abort this script before elektrond ever starts.
# It doesn't need to be owned by elektron anyway, just readable (world-
# readable by default from how the install script writes it) -- so chown
# everything else under /data and leave that one path alone.
chown elektron:elektron /data
find /data -mindepth 1 -maxdepth 1 ! -name bitcoin.conf -exec chown -R elektron:elektron {} +
exec gosu elektron "$@"
ENTRYPOINT_EOF
chmod +x elektron-net/docker-entrypoint.sh

# ============================================================================
# 3. rpcauth generieren
# ============================================================================
if [ "$REUSE_RPC_AUTH" = true ]; then
  log "RPC-Zugangsdaten aus vorherigem Lauf gefunden -- wiederverwenden (Node-Passwort bleibt gleich)."
  RPC_AUTH_LINE="$EXISTING_RPC_AUTH_LINE"
  RPC_PASSWORD="$EXISTING_RPC_PASSWORD"
else
  log "Generiere RPC-Zugangsdaten (rpcauth.py) ..."
  RPCAUTH_JSON="$(python3 elektron-net/share/rpcauth/rpcauth.py "$RPC_USER" -j)"
  RPC_AUTH_LINE="$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['rpcauth'])" "$RPCAUTH_JSON")"
  RPC_PASSWORD="$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['password'])" "$RPCAUTH_JSON")"
fi

# ============================================================================
# 4. elektron-net/bitcoin.conf
# ============================================================================
log "Schreibe elektron-net/bitcoin.conf ..."
cat > elektron-net/bitcoin.conf <<CONF_EOF
server=1
listen=1
bind=0.0.0.0:8333
maxconnections=125

rpcbind=0.0.0.0
rpcallowip=172.16.0.0/12
rpcauth=${RPC_AUTH_LINE}

zmqpubrawblock=tcp://0.0.0.0:28332
zmqpubrawtx=tcp://0.0.0.0:28333

disablewallet=0
CONF_EOF

# ============================================================================
# 5. docker-compose.yml
# ============================================================================
log "Schreibe docker-compose.yml ..."
cat > docker-compose.yml <<'COMPOSE_EOF'
services:

  elektron-net:
    container_name: elektron-net
    build:
      context: ./elektron-net
    restart: unless-stopped
    networks:
      - backend
    ports:
      - "8333:8333"
    volumes:
      - "./elektron-net/bitcoin.conf:/data/bitcoin.conf:ro"
      - "./data/elektron-net:/data"

  elektron-ppool:
    container_name: elektron-ppool
    build:
      context: ./elektron-net-ppool
    restart: unless-stopped
    depends_on:
      - elektron-net
    networks:
      - backend
    ports:
      - "3333:3333"
    volumes:
      - "./elektron-net-ppool/.env:/elektron-pool/.env:ro"
      - "./data/ppool-DB:/elektron-pool/DB"

  elektron-ppool-ui:
    container_name: elektron-ppool-ui
    build:
      context: ./elektron-net-ppool-ui
    restart: unless-stopped
    depends_on:
      - elektron-ppool
    networks:
      - backend
      - web
    environment:
      - API_UPSTREAM=elektron-ppool:3334

  elektron-faucet-db:
    container_name: elektron-faucet-db
    image: mariadb:11.4
    restart: unless-stopped
    env_file: ./elektron-net-faucet/.env
    environment:
      MYSQL_DATABASE: ${FAUCET_DB_NAME}
      MYSQL_USER: ${FAUCET_DB_USER}
      MYSQL_PASSWORD: ${FAUCET_DB_PASS}
      MYSQL_ROOT_PASSWORD: ${FAUCET_DB_ROOT_PASS}
    networks:
      - backend
    volumes:
      - "./data/faucet-db:/var/lib/mysql"
    healthcheck:
      test: ["CMD-SHELL", "mysqladmin ping -uroot -p$$MYSQL_ROOT_PASSWORD --silent"]
      interval: 5s
      timeout: 5s
      retries: 20

  elektron-faucet-app:
    container_name: elektron-faucet-app
    build:
      context: ./elektron-net-faucet
    restart: unless-stopped
    depends_on:
      elektron-faucet-db:
        condition: service_healthy
      elektron-net:
        condition: service_started
    env_file: ./elektron-net-faucet/.env
    environment:
      FAUCET_CONFIG: /config/config.php
    networks:
      - backend
      - web
    volumes:
      - "./data/faucet-config:/config"

  caddy:
    container_name: elektron-caddy
    image: caddy:2-alpine
    restart: unless-stopped
    networks:
      - web
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "./caddy/Caddyfile:/etc/caddy/Caddyfile:ro"
      - "caddy_data:/data"
      - "caddy_config:/config"

networks:
  backend:
  web:

volumes:
  caddy_data:
  caddy_config:
COMPOSE_EOF

# ============================================================================
# 6. Caddyfile
# ============================================================================
log "Schreibe caddy/Caddyfile ..."
{
  if [ -n "$CADDY_EMAIL" ]; then
    echo "{"
    echo "	email ${CADDY_EMAIL}"
    echo "}"
    echo
  fi
  echo "# ${NODE_DOMAIN} bekommt bewusst keinen Block -- reiner P2P-Seed (Port 8333)."
  echo
  echo "${POOL_DOMAIN} {"
  echo "	reverse_proxy elektron-ppool-ui:80"
  echo "}"
  echo
  echo "${FAUCET_DOMAIN} {"
  echo "	reverse_proxy elektron-faucet-app:80"
  echo "}"
} > caddy/Caddyfile

# ============================================================================
# 7. elektron-net-ppool/.env
# ============================================================================
log "Schreibe elektron-net-ppool/.env ..."
cat > elektron-net-ppool/.env <<ENV_EOF
ELEKTRON_RPC_URL=http://elektron-net
ELEKTRON_RPC_USER=${RPC_USER}
ELEKTRON_RPC_PASSWORD=${RPC_PASSWORD}
ELEKTRON_RPC_PORT=8332
ELEKTRON_RPC_TIMEOUT=10000
ELEKTRON_ZMQ_HOST=tcp://elektron-net:28332

API_PORT=${API_PORT}
STRATUM_PORT=${STRATUM_PORT}
STRATUM_MAX_CONNECTIONS_PER_LISTENER=10000
JOB_REFRESH_INTERVAL_MS=30000
DIFFICULTY_CHECK_INTERVAL_MS=60000

NETWORK=mainnet
API_SECURE=false
POOL_IDENTIFIER="${POOL_IDENTIFIER}"

HOBBY_MINER_USER_AGENTS=NerdMiner,NerdminerV2,nerdminer,NerdAxe,NerdQAxe
HOBBY_MINER_DIFFICULTY=0.001
DIAGNOSTIC_SHARE_LOGGING_MODES=

# Optional -- leer lassen deaktiviert die jeweilige Integration.
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
TELEGRAM_BOT_USERNAME=${TELEGRAM_BOT_USERNAME}
DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN}
DISCORD_BOT_CLIENTID=${DISCORD_BOT_CLIENTID}
DISCORD_BOT_GUILD_ID=${DISCORD_BOT_GUILD_ID}
DISCORD_BOT_CHANNEL_ID=${DISCORD_BOT_CHANNEL_ID}

# wird nach der Wallet-Erstellung automatisch von diesem Skript eingetragen:
POOL_WALLET_ADDRESS=

PPLNS_WINDOW_MINUTES=${PPLNS_WINDOW_MINUTES}
POOL_FEE_PERCENT=${POOL_FEE_PERCENT}
MIN_PAYOUT_THRESHOLD_SATS=${MIN_PAYOUT_THRESHOLD_SATS}
PAYOUT_INTERVAL_MINUTES=${PAYOUT_INTERVAL_MINUTES}
PAYOUT_CONFIRMATIONS_REQUIRED=${PAYOUT_CONFIRMATIONS_REQUIRED}
PAYOUT_DRY_RUN=${PAYOUT_DRY_RUN}

WALLET_RPC_WALLET_NAME=${POOL_WALLET_NAME}

# Pool-Wallet ist verschlüsselt (siehe README "vor echten Auszahlungen
# empfohlen") -- ppool entsperrt sie hiermit automatisch für jede
# Auszahlung und sperrt sie danach sofort wieder (wallet-rpc.service.ts).
WALLET_PASSPHRASE=${POOL_WALLET_PASSPHRASE}
WALLET_UNLOCK_SECONDS=${WALLET_UNLOCK_SECONDS}

JWT_SECRET=${JWT_SECRET}
ENV_EOF

# ============================================================================
# 8. elektron-net-faucet/.env
# ============================================================================
log "Schreibe elektron-net-faucet/.env ..."
cat > elektron-net-faucet/.env <<ENV_EOF
FAUCET_PORT=8080

FAUCET_DB_HOST=elektron-faucet-db
FAUCET_DB_PORT=3306
FAUCET_DB_NAME=${FAUCET_DB_NAME}
FAUCET_DB_USER=${FAUCET_DB_USER}
FAUCET_DB_PASS=${FAUCET_DB_PASS}
FAUCET_DB_ROOT_PASS=${FAUCET_DB_ROOT_PASS}

FAUCET_ADMIN_USER=${FAUCET_ADMIN_USER}
FAUCET_ADMIN_PASS=${FAUCET_ADMIN_PASS}

FAUCET_RPC_HOST=http://elektron-net
FAUCET_RPC_PORT=8332
FAUCET_RPC_USER=${RPC_USER}
FAUCET_RPC_PASS=${RPC_PASSWORD}
FAUCET_WALLET_NAME=${FAUCET_WALLET_NAME}
FAUCET_WALLET_PASS=${FAUCET_WALLET_PASSPHRASE}
FAUCET_RPC_TLS_VERIFY=1
FAUCET_RPC_TLS_VERIFY_HOST=0

FAUCET_HCAPTCHA_SITE=${FAUCET_HCAPTCHA_SITE}
FAUCET_HCAPTCHA_SECRET=${FAUCET_HCAPTCHA_SECRET}

FAUCET_TITLE=${FAUCET_TITLE}
FAUCET_MESSAGE=${FAUCET_MESSAGE}
FAUCET_AMOUNT_ELEK=${FAUCET_AMOUNT_ELEK}
FAUCET_DAILY_BUDGET=${FAUCET_DAILY_BUDGET}
FAUCET_HOURLY_BUDGET=${FAUCET_HOURLY_BUDGET}
FAUCET_PER_ADDR_COOLDOWN_H=${FAUCET_PER_ADDR_COOLDOWN_H}
FAUCET_PER_IP_COOLDOWN_H=${FAUCET_PER_IP_COOLDOWN_H}
# wird nach der Wallet-Erstellung automatisch von diesem Skript eingetragen:
FAUCET_SENDER_ADDR=
FAUCET_EXPLORER_URL=${FAUCET_EXPLORER_URL}
FAUCET_DEFAULT_LANG=${FAUCET_DEFAULT_LANG}
ENV_EOF

# Docker Compose braucht eine .env im Projekt-Root, um ${FAUCET_DB_*} in
# docker-compose.yml aufzulösen -- Symlink hält beide Dateien synchron.
ln -sf elektron-net-faucet/.env .env

# ============================================================================
# 9. Node zuerst hochfahren
# ============================================================================
log "Baue und starte elektron-net ..."
docker compose up -d --build elektron-net

wait_for_rpc() {
  local retries=60 i=0
  until docker compose exec -T elektron-net elektron-cli getblockchaininfo >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -ge "$retries" ] && die "Timeout: elektron-net RPC antwortet nach 5 Minuten nicht."
    sleep 5
  done
}

log "Warte auf RPC-Bereitschaft von elektron-net ..."
wait_for_rpc

# ============================================================================
# 10. Wallets anlegen -- PFLICHT für Pool und Faucet
# ============================================================================
wallet_loaded() {
  docker compose exec -T elektron-net elektron-cli listwallets | grep -q "\"$1\""
}

create_wallet_if_missing() {
  local wname="$1"
  if wallet_loaded "$wname"; then
    log "Wallet '$wname' ist bereits vorhanden/geladen, überspringe Erstellung."
  else
    log "Erstelle Wallet '$wname' ..."
    docker compose exec -T elektron-net elektron-cli createwallet "$wname" >/dev/null \
      || docker compose exec -T elektron-net elektron-cli loadwallet "$wname" >/dev/null
  fi
}

log "Lege Pool-Wallet an ..."
create_wallet_if_missing "$POOL_WALLET_NAME"
if [ -n "$EXISTING_POOL_WALLET_ADDRESS" ]; then
  POOL_ADDR="$EXISTING_POOL_WALLET_ADDRESS"
  log "Pool-Wallet-Adresse aus vorherigem Lauf wiederverwendet: ${POOL_ADDR}"
else
  POOL_ADDR="$(docker compose exec -T elektron-net elektron-cli -rpcwallet="$POOL_WALLET_NAME" getnewaddress "" bech32 | tr -d '\r\n')"
  log "Neue Pool-Wallet-Adresse: ${POOL_ADDR}"
fi
sed -i "s#^POOL_WALLET_ADDRESS=.*#POOL_WALLET_ADDRESS=${POOL_ADDR}#" elektron-net-ppool/.env

# Verschlüsseln, falls noch nicht verschlüsselt -- empfohlen bevor echte
# Auszahlungen laufen (siehe ppool-.env-Kommentar zu WALLET_PASSPHRASE):
# ohne das schlägt jede echte Auszahlung mit RPC-Fehler -13 fehl, sobald
# PAYOUT_DRY_RUN=false gesetzt wird. ppool entsperrt die Wallet dafür
# automatisch für WALLET_UNLOCK_SECONDS vor jedem sendmany und sperrt sie
# danach sofort wieder (encryptwallet stoppt den Node-Prozess kurz -- das
# ist normales Bitcoin-Core-Verhalten, der Container kommt dank
# restart:unless-stopped von selbst wieder hoch).
encrypt_wallet_if_missing() {
  local wname="$1" passphrase="$2"
  local info
  info="$(docker compose exec -T elektron-net elektron-cli -rpcwallet="$wname" getwalletinfo)"
  if echo "$info" | grep -q '"unlocked_until"'; then
    log "Wallet '$wname' ist bereits verschlüsselt, überspringe encryptwallet."
  else
    log "Verschlüssele Wallet '$wname' (Node startet dabei kurz neu) ..."
    docker compose exec -T elektron-net elektron-cli -rpcwallet="$wname" encryptwallet "$passphrase" || true
    sleep 8
    wait_for_rpc
    wallet_loaded "$wname" || docker compose exec -T elektron-net elektron-cli loadwallet "$wname" >/dev/null
  fi
}

encrypt_wallet_if_missing "$POOL_WALLET_NAME" "$POOL_WALLET_PASSPHRASE"

log "Lege Faucet-Wallet an ..."
create_wallet_if_missing "$FAUCET_WALLET_NAME"
encrypt_wallet_if_missing "$FAUCET_WALLET_NAME" "$FAUCET_WALLET_PASSPHRASE"

if [ -n "$EXISTING_FAUCET_SENDER_ADDR" ]; then
  FAUCET_ADDR="$EXISTING_FAUCET_SENDER_ADDR"
  log "Faucet-Wallet-Adresse aus vorherigem Lauf wiederverwendet: ${FAUCET_ADDR}"
else
  FAUCET_ADDR="$(docker compose exec -T elektron-net elektron-cli -rpcwallet="$FAUCET_WALLET_NAME" getnewaddress "" bech32 | tr -d '\r\n')"
  log "Neue Faucet-Wallet-Adresse: ${FAUCET_ADDR}"
fi
sed -i "s#^FAUCET_SENDER_ADDR=.*#FAUCET_SENDER_ADDR=${FAUCET_ADDR}#" elektron-net-faucet/.env

# ============================================================================
# 10b. Wallet-Backups -- vollständiger Private-Key-Export (einmalig)
# ============================================================================
# "Komplettes Backup" heißt hier: nicht nur die Passphrase (siehe oben),
# sondern die tatsächlichen privaten Schlüssel der Pool-/Faucet-Wallet.
# dumpwallet funktioniert nur bei Legacy-Wallets; ist die hier von
# createwallet angelegte Wallet eine Descriptor-Wallet, schlägt es fehl und
# wir weichen auf "listdescriptors true" aus (liefert dieselben privaten
# Schlüssel als Descriptor-Strings). Läuft nur EINMAL -- existiert die
# Backup-Datei schon, wird nichts erneut geschrieben/überschrieben.
backup_wallet_privkeys() {
  local wname="$1" host_path="$2" container_path="$3"
  if [ -f "$host_path" ]; then
    log "Wallet-Backup für '$wname' existiert bereits, überspringe: ${host_path}"
    return
  fi
  log "Exportiere private Schlüssel der Wallet '$wname' (vollständiges Backup) ..."
  if docker compose exec -T elektron-net elektron-cli -rpcwallet="$wname" dumpwallet "$container_path" >/dev/null 2>&1; then
    log "Wallet-Backup (dumpwallet, Legacy-Format) gespeichert: ${host_path}"
  elif docker compose exec -T elektron-net elektron-cli -rpcwallet="$wname" listdescriptors true > "$host_path" 2>/dev/null; then
    log "Wallet-Backup (private Descriptors) gespeichert: ${host_path}"
  else
    warn "Konnte kein automatisches Wallet-Backup für '$wname' erstellen -- bitte manuell prüfen: docker compose exec elektron-net elektron-cli -rpcwallet=$wname listdescriptors true"
    rm -f "$host_path"
    return
  fi
  chmod 600 "$host_path" 2>/dev/null || true
}

POOL_WALLET_DUMP_HOST="${STACK_DIR}/data/elektron-net/pool-wallet-privkeys-backup.txt"
FAUCET_WALLET_DUMP_HOST="${STACK_DIR}/data/elektron-net/faucet-wallet-privkeys-backup.txt"

# Beide Wallets sind mittlerweile verschlüsselt (siehe 10.) -- also für
# beide erst kurz entsperren, exportieren, danach sofort wieder sperren.
export_wallet_backup() {
  local wname="$1" passphrase="$2" host_path="$3" container_path="$4"
  if [ -f "$host_path" ]; then
    log "Wallet-Backup für '$wname' existiert bereits, überspringe: ${host_path}"
    return
  fi
  log "Entsperre Wallet '$wname' kurz für den Private-Key-Export ..."
  docker compose exec -T elektron-net elektron-cli -rpcwallet="$wname" walletpassphrase "$passphrase" 60 >/dev/null 2>&1 \
    || warn "Konnte Wallet '$wname' nicht entsperren -- Private-Key-Export wird wahrscheinlich fehlschlagen, Passphrase prüfen."
  backup_wallet_privkeys "$wname" "$host_path" "$container_path"
  docker compose exec -T elektron-net elektron-cli -rpcwallet="$wname" walletlock >/dev/null 2>&1 || true
}

export_wallet_backup "$POOL_WALLET_NAME"   "$POOL_WALLET_PASSPHRASE"   "$POOL_WALLET_DUMP_HOST"   "/data/pool-wallet-privkeys-backup.txt"
export_wallet_backup "$FAUCET_WALLET_NAME" "$FAUCET_WALLET_PASSPHRASE" "$FAUCET_WALLET_DUMP_HOST" "/data/faucet-wallet-privkeys-backup.txt"

# ============================================================================
# 11. Rest des Stacks hochfahren
# ============================================================================
log "Baue und starte den restlichen Stack (ppool, ppool-ui, faucet, caddy) ..."
docker compose up -d --build

# ============================================================================
# 12. Firewall
# ============================================================================
if command -v ufw >/dev/null 2>&1; then
  if [ "$FIREWALL_AUTO_CONFIGURE" = "true" ]; then
    log "Konfiguriere ufw (IPv4 + IPv6) ..."
    # Ubuntu default: /etc/default/ufw hat IPV6=yes -- ufw legt dann für
    # jede Regel automatisch auch die passende ip6tables-Regel an.
    if grep -q '^IPV6=no' /etc/default/ufw 2>/dev/null; then
      warn "IPv6 war in /etc/default/ufw deaktiviert -- aktiviere es."
      sed -i 's/^IPV6=no/IPV6=yes/' /etc/default/ufw
    fi
    ufw allow 8333/tcp comment 'Elektron P2P seed' || true
    ufw allow 3333/tcp comment 'Elektron PPLNS Stratum' || true
    ufw allow 80/tcp  || true
    ufw allow 443/tcp || true
    ufw reload || true
  else
    warn "FIREWALL_AUTO_CONFIGURE=false -- bitte manuell öffnen: ufw allow 8333/tcp 3333/tcp 80/tcp 443/tcp"
  fi
else
  warn "ufw nicht gefunden -- Ports 8333, 3333, 80, 443 manuell im Hetzner Cloud Firewall öffnen."
fi
warn "Zusätzlich im Hetzner Cloud-Firewall-Panel (Tab 'Firewalls') dieselben 4 Ports öffnen -- dort für IPv4 UND IPv6 getrennt aktivieren, ufw allein reicht bei Cloud-Firewalls nicht."

# ============================================================================
# 13. Zusammenfassung -- wird angezeigt UND dauerhaft in eine Datei
#     geschrieben (SUMMARY_FILE), damit du sie nicht bei diesem einen Lauf
#     abschreiben musst.
# ============================================================================
SUMMARY_FILE="${STACK_DIR}/ZUGANGSDATEN.txt"
GENERATED_AT="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

# Jede Wallet bleibt ihre eigene, separat schützbare Datei (chmod 600) --
# hier wird für die Übersicht nur AUFGELISTET, was in external-wallets/
# liegt (Dateiname + Pfad), der Private-Key-Inhalt selbst wird NICHT
# zusätzlich in ZUGANGSDATEN.txt hineinkopiert. So gibt es pro Wallet genau
# eine Stelle mit dem eigentlichen Geheimnis, statt es zu duplizieren.
EXTERNAL_WALLETS_DIR="${STACK_DIR}/external-wallets"
EXTERNAL_WALLETS_BLOCK="(keine Dateien in ${EXTERNAL_WALLETS_DIR}/ gefunden)"
if [ -d "$EXTERNAL_WALLETS_DIR" ] && [ -n "$(ls -A "$EXTERNAL_WALLETS_DIR" 2>/dev/null)" ]; then
  EXTERNAL_WALLETS_BLOCK=""
  for f in "$EXTERNAL_WALLETS_DIR"/*; do
    [ -f "$f" ] || continue
    chmod 600 "$f" 2>/dev/null || true
    EXTERNAL_WALLETS_BLOCK="${EXTERNAL_WALLETS_BLOCK}
  - $(basename "$f")
    -> ${f}"
  done
fi

{
cat <<SUMMARY

============================================================================
 ELEKTRON NET STACK -- ZUGANGSDATEN UND SERVER-INFOS
 Zuletzt aktualisiert: ${GENERATED_AT}  (bei jedem Lauf von install-elektron-stack.sh neu geschrieben)
============================================================================
# Diese Datei ist die zentrale ÜBERSICHT über ALLE Zugangsdaten dieses
# Stacks: RPC-/DB-/JWT-/Faucet-Admin-Passwörter stehen direkt unten drin.
# Wallet-Private-Keys dagegen bleiben bewusst in ihren jeweils EIGENEN
# Dateien (Pool/Faucet-Backup, alles in ${EXTERNAL_WALLETS_DIR}/) -- hier
# stehen nur deren Dateiname und Pfad als Verweis, damit jedes Wallet-
# Geheimnis nur an einer einzigen Stelle liegt statt dupliziert zu werden.
#
# Trotzdem: chmod 600 ist unten bereits automatisch gesetzt; nicht
# kopieren/committen/per Klartext-Mail verschicken. Einmalig offline
# sichern (z.B. per WinSCP/scp herunterladen, siehe README "Dateien auf den
# Server bringen") -- am besten zusammen mit den referenzierten
# Wallet-Dateien -- und danach auf dem Server unter Verschluss lassen.
============================================================================

 Node (P2P-Seed):     ${NODE_DOMAIN}:8333
 Server IPv4:          ${SERVER_IP}
 Server IPv6 (erkannt/verwendet): ${SERVER_IPV6}
 Pool Dashboard:       https://${POOL_DOMAIN}
 Faucet:               https://${FAUCET_DOMAIN}
 Faucet Admin:          https://${FAUCET_DOMAIN}/admin.php
   User:     ${FAUCET_ADMIN_USER}
   Passwort: ${FAUCET_ADMIN_PASS}

 Pool-Wallet-Adresse:   ${POOL_ADDR}
 Faucet-Wallet-Adresse: ${FAUCET_ADDR}

 Vollständiger Private-Key-Export dieser beiden Wallets (Legacy-Dump oder
 Descriptor-Fallback, je nachdem was unterstützt wurde):
   ${POOL_WALLET_DUMP_HOST}
   ${FAUCET_WALLET_DUMP_HOST}
 (chmod 600, einmalig beim ersten Anlegen erzeugt -- wird bei Reruns nicht
 überschrieben. Das ist die eigentliche Wiederherstellungs-Grundlage für
 den Fall, dass der Server verloren geht; die Passphrase oben allein reicht
 dafür NICHT, die entsperrt nur eine bereits vorhandene Wallet-Datei.)

 ----------------------------------------------------------------------------
 ALLE ZUGANGSDATEN AUF EINEN BLICK:

   RPC-Benutzer (Node):          ${RPC_USER}
   RPC-Passwort (Node):          ${RPC_PASSWORD}
   Pool JWT_SECRET:              ${JWT_SECRET}
   Pool-Wallet-Passphrase:       ${POOL_WALLET_PASSPHRASE}
   Faucet-DB-Passwort:           ${FAUCET_DB_PASS}
   Faucet-DB-Root-Passwort:      ${FAUCET_DB_ROOT_PASS}
   Faucet-Admin-Passwort:        ${FAUCET_ADMIN_PASS}
   Faucet-Wallet-Passphrase:     ${FAUCET_WALLET_PASSPHRASE}
   hCaptcha Site-Key:            ${FAUCET_HCAPTCHA_SITE:-"(nicht gesetzt)"}
   hCaptcha Secret-Key:          ${FAUCET_HCAPTCHA_SECRET:-"(nicht gesetzt)"}

 Bei diesem Lauf neu generiert:
   ${GENERATED_SECRETS:-"(nichts -- alles oben stammt aus einem vorherigen Lauf oder wurde von dir vorgegeben)"}
 Aus einem vorherigen Lauf wiederverwendet (unverändert, kein Reset):
   ${REUSED_SECRETS:-"(nichts -- das war der erste Lauf)"}
 Alles andere oben hast du selbst vorgegeben (Config-Datei/Prompt).
 ----------------------------------------------------------------------------

 NÄCHSTE SCHRITTE:
 1. Beide Adressen oben von deinem Prepaid-Bestand aus mit ELEK befüllen
    (Hot Wallet klein halten).
 2. https://${FAUCET_DOMAIN}/admin.php -> Settings -> "Test RPC connection"
    und "Test wallet unlock" grün bekommen.
 3. public/install.php im Faucet löschen:
    docker compose -f ${STACK_DIR}/docker-compose.yml exec elektron-faucet-app rm -f public/install.php
 4. elektron-net-ppool/.env: PAYOUT_DRY_RUN=true lassen, bis eine simulierte
    Auszahlung im Log geprüft wurde, dann auf false stellen und
    'docker compose up -d --force-recreate elektron-ppool' ausführen.
 5. hCaptcha-Keys nachtragen, falls beim Ausführen leer gelassen.
 6. Falls noch nicht geschehen: AAAA-Records bei world4you anlegen
    (${NODE_DOMAIN}, ${POOL_DOMAIN}, ${FAUCET_DOMAIN} -> ${SERVER_IPV6}).
    P2P (8333), Stratum (3333) und Caddy (80/443) sind bereits Dual-Stack
    published -- sobald AAAA existiert, funktioniert alles auch über IPv6.
 7. Optional, aber für einen öffentlichen Seed-Node empfehlenswert: Reverse
    DNS (PTR) für ${SERVER_IPV6} im Hetzner-Panel setzen (Networking -> bei
    der IPv6-Zeile die "..." -> Reverse DNS, zeigte bei dir "0 Einträge"),
    z.B. auf ${NODE_DOMAIN} -- viele Peers werten das bei der Node-Reputation
    positiv.

 Hinweis zur privaten Netzwerk-IP (10.0.0.2, Hetzner vSwitch):
 Wird von diesem Stack aktuell nicht gebraucht -- alle Container sprechen
 intern über Docker-eigene Netzwerke. Nützlich erst, falls du später z.B.
 die Wallet auf einen zweiten, isolierten Hetzner-Server auslagerst (siehe
 ppool-README §9, "network-isolated wallet server").

 ----------------------------------------------------------------------------
 NÜTZLICHE BEFEHLE (siehe auch README "Stack aktualisieren"):

   Status aller Container:
     docker compose -f ${STACK_DIR}/docker-compose.yml ps
   Logs verfolgen (z.B. Node):
     docker compose -f ${STACK_DIR}/docker-compose.yml logs -f elektron-net
   Node-Sync-Status:
     docker compose -f ${STACK_DIR}/docker-compose.yml exec elektron-net elektron-cli getblockchaininfo
   Nur einen Service nach einer .env-Änderung neu starten:
     docker compose -f ${STACK_DIR}/docker-compose.yml up -d --force-recreate <service>
   Diese Übersicht jederzeit erneut ansehen:
     cat ${SUMMARY_FILE}
 ----------------------------------------------------------------------------

 Diese Zusammenfassung wird bei jedem (Re-)Lauf des Skripts hier neu
 geschrieben: ${SUMMARY_FILE}
 Die zugrundeliegenden Rohdaten stehen außerdem dauerhaft in:
   ${STACK_DIR}/elektron-net-ppool/.env
   ${STACK_DIR}/elektron-net-faucet/.env
   ${STACK_DIR}/elektron-net/bitcoin.conf  (rpcauth-Hash, nicht das Klartext-Passwort)
 (alle chmod 600, nicht committen.)

 WICHTIG: encryptwallet ist ein Einwegvorgang -- Pool- UND Faucet-Wallet
 sind mittlerweile beide verschlüsselt. Die Passphrasen oben stehen NUR in
 dieser Datei und in ${STACK_DIR}/elektron-net-ppool/.env (Feld
 WALLET_PASSPHRASE) bzw. ${STACK_DIR}/elektron-net-faucet/.env (Feld
 FAUCET_WALLET_PASS) -- plus im vollständigen Private-Key-Export weiter
 oben. Es gibt keine andere Kopie, auch nicht auf der Blockchain. Verlierst
 du alle diese Dateien, ist das jeweilige Wallet-Guthaben nicht mehr
 ausgebbar.

 Weiterer wichtiger Ort: der Faucet-App generiert beim allerersten Start
 selbst einen Verschlüsselungs-Key für Daten "at rest" (FAUCET_APP_KEY) und
 schreibt ihn NUR nach ${STACK_DIR}/data/faucet-config/config.php -- steht
 in keiner .env und wird von diesem Skript nicht verwaltet, gehört aber zum
 selben Bedrohungsmodell wie alles andere hier (mit sichern, chmod 600).

 ----------------------------------------------------------------------------
 EXTERNE / SELBST ERZEUGTE WALLETS
 (jede Datei in ${EXTERNAL_WALLETS_DIR}/ -- z.B. eine offline mit einem
 eigenen Skript wie generate_address.py erzeugte Prepaid-Wallet -- bleibt
 ihre eigene separate Datei mit chmod 600. Hier nur Name + Pfad als
 Verweis, der eigentliche Private Key steht NUR in der jeweiligen Datei
 selbst, nicht zusätzlich hier. Lege dort beliebige Dateien ab, dann
 tauchen sie ab dem nächsten Lauf hier in der Liste auf.)
${EXTERNAL_WALLETS_BLOCK}
============================================================================
SUMMARY
} | tee "$SUMMARY_FILE"
chmod 600 "$SUMMARY_FILE"
# Falls die Faucet-App ihren FAUCET_APP_KEY bereits geschrieben hat (siehe
# Hinweis oben) -- nur ein Best-effort-chmod, kein Fehler falls noch nicht
# vorhanden (der Container kann noch ein paar Sekunden brauchen).
if [ -f "${STACK_DIR}/data/faucet-config/config.php" ]; then
  chmod 600 "${STACK_DIR}/data/faucet-config/config.php" 2>/dev/null || true
fi
