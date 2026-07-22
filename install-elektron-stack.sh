#!/usr/bin/env bash
#
# Elektron Net -- one-shot install script (node + ppool + ppool-ui + faucet + Caddy)
#
# Usage:
#   1. Copy this file (and, if you have one, elektron-stack.conf) onto your
#      server (browser console / scp).
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
# Fallback value, used only if the automatic detection further below
# (ip -6 addr) finds nothing. Some provider panels (e.g. Hetzner's) only
# show the routed /64 subnet in their networking tab (e.g.
# 2a01:4f8:1c18:ea01::/64), NOT the exact configured host address -- that
# gets read live on this server right below instead.
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
INSTALL_POOL="true"                           # true = clone/build/start ppool + ppool-ui (Compose profile "pool"); publishes STRATUM_PORT
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
INSTALL_FAUCET="true"                         # true = clone/build/start faucet-db + faucet-app (Compose profile "faucet"); no new port, Caddy-proxied
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

# --- Seeder (elektron-net-seeder) -- OPTIONAL, still in testing ---
INSTALL_SEEDER="false"                        # true = clone/build/start via the "seeder" Compose profile; needs NS delegation for SEEDER_HOST, see README
SEEDER_HOST="seeder.eleknet.org"
SEEDER_NS="${NODE_DOMAIN}"
SEEDER_MBOX="admin.eleknet.org"
SEEDER_DNS_PORT="53"
SEEDER_THREADS="96"
SEEDER_DNS_THREADS="4"
SEEDER_MIN_HEIGHT="70000"                     # young chain -- lower than the seeder's built-in mainnet default of 350000

# --- Mempool Explorer (elektron-net-mempool) -- OPTIONAL, stable ---
INSTALL_MEMPOOL="true"                        # true = clone/build/start via the "mempool" Compose profile; no new public port, Caddy-proxied like Pool/Faucet
MEMPOOL_DOMAIN="mempool.elektron-net.org"
MEMPOOL_DB_NAME="mempool"
MEMPOOL_DB_USER="mempool"
# leave empty to auto-generate:
MEMPOOL_DB_PASS=""
MEMPOOL_DB_ROOT_PASS=""
MEMPOOL_INDEXING_BLOCKS_AMOUNT="1000"         # small positive window -- see elektron-net-mempool/docker-compose.yml comment for why (no -txindex, and never 0)
MEMPOOL_ACCELERATOR="true"                    # true = "Acceleration" menu + tx-page "Boost" button in the explorer frontend; both just link out to mempool.space's own accelerator service over outbound HTTPS, no inbound port/firewall change needed

# Every variable a config file / prompt round is allowed to touch -- keep in
# sync with the block above. Doubles as the whitelist for config-file keys
# (so an uploaded file can only ever set plain values, never run code).
CONFIG_VARS="STACK_DIR GITHUB_USER AUTO_UPDATE_REPOS SERVER_IP SERVER_IPV6 NODE_DOMAIN POOL_DOMAIN
FAUCET_DOMAIN CADDY_EMAIL RPC_USER FIREWALL_AUTO_CONFIGURE INSTALL_POOL POOL_WALLET_NAME
POOL_WALLET_PASSPHRASE WALLET_UNLOCK_SECONDS
POOL_IDENTIFIER POOL_FEE_PERCENT PPLNS_WINDOW_MINUTES MIN_PAYOUT_THRESHOLD_SATS
PAYOUT_INTERVAL_MINUTES PAYOUT_CONFIRMATIONS_REQUIRED PAYOUT_DRY_RUN STRATUM_PORT
API_PORT JWT_SECRET TELEGRAM_BOT_TOKEN TELEGRAM_BOT_USERNAME DISCORD_BOT_TOKEN
DISCORD_BOT_CLIENTID DISCORD_BOT_GUILD_ID DISCORD_BOT_CHANNEL_ID
INSTALL_FAUCET FAUCET_WALLET_NAME FAUCET_WALLET_PASSPHRASE FAUCET_DB_NAME
FAUCET_DB_USER FAUCET_DB_PASS FAUCET_DB_ROOT_PASS FAUCET_ADMIN_USER FAUCET_ADMIN_PASS
FAUCET_HCAPTCHA_SITE FAUCET_HCAPTCHA_SECRET FAUCET_TITLE FAUCET_MESSAGE FAUCET_AMOUNT_ELEK
FAUCET_DAILY_BUDGET FAUCET_HOURLY_BUDGET FAUCET_PER_ADDR_COOLDOWN_H FAUCET_PER_IP_COOLDOWN_H
FAUCET_DEFAULT_LANG FAUCET_EXPLORER_URL
INSTALL_SEEDER SEEDER_HOST SEEDER_NS SEEDER_MBOX SEEDER_DNS_PORT SEEDER_THREADS SEEDER_DNS_THREADS SEEDER_MIN_HEIGHT
INSTALL_MEMPOOL MEMPOOL_DOMAIN MEMPOOL_DB_NAME MEMPOOL_DB_USER MEMPOOL_DB_PASS MEMPOOL_DB_ROOT_PASS MEMPOOL_INDEXING_BLOCKS_AMOUNT MEMPOOL_ACCELERATOR"

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
    *) die "Unknown option: $1 (see --help)" ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$CONFIG_FILE" ] && [ -f "${SCRIPT_DIR}/elektron-stack.conf" ]; then
  CONFIG_FILE="${SCRIPT_DIR}/elektron-stack.conf"
  log "Found config file, using it automatically: ${CONFIG_FILE}"
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
  [ -f "$CONFIG_FILE" ] || die "Config file not found: $CONFIG_FILE"
  log "Loading configuration from ${CONFIG_FILE} ..."
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -z "$line" ] && continue
    case "$line" in
      *=*) ;;
      *) warn "Ignoring line without '=' in ${CONFIG_FILE}: $line"; continue ;;
    esac
    key="$(printf '%s' "${line%%=*}" | sed -e 's/[[:space:]]*$//')"
    val="$(printf '%s' "${line#*=}" | sed -e 's/^[[:space:]]*//')"
    val="$(printf '%s' "$val" | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/")"
    if is_config_var "$key"; then
      printf -v "$key" '%s' "$val"
    else
      warn "Ignoring unknown key in ${CONFIG_FILE}: $key"
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
  read -rp "$prompt_text [${current:-empty}]: " input
  if [ -n "$input" ]; then
    printf -v "$var_name" '%s' "$input"
  fi
}

# Strict y/n prompt for boolean settings -- anything that isn't a clear
# yes/no answer keeps the current default rather than guessing.
ask_yes_no() {
  local var_name="$1" prompt_text="$2" current input default_label
  current="${!var_name}"
  [ "$current" = "true" ] && default_label="Y/n" || default_label="y/N"
  read -rp "$prompt_text [$default_label]: " input
  case "$input" in
    [yY]*) printf -v "$var_name" 'true' ;;
    [nN]*) printf -v "$var_name" 'false' ;;
    "") : ;;
    *) warn "Unclear input ('$input') -- keeping the current value ($current)." ;;
  esac
}

if [ "$ASSUME_YES" = false ] && [ -t 0 ]; then
  log "Interactive configuration -- Enter keeps the default/config value. Skip this with --yes."
  ask_yes_no AUTO_UPDATE_REPOS "Check the cloned repos for updates before building, and apply them via 'git pull --ff-only'?"
  ask GITHUB_USER   "GitHub username (github.com/<user>/elektron-net...)"
  ask SERVER_IP     "Public IPv4 address of this server"
  ask SERVER_IPV6   "Public IPv6 address (also auto-detected below)"
  ask NODE_DOMAIN   "Domain for the P2P seed node"
  ask CADDY_EMAIL   "Email for Let's Encrypt (optional, press Enter to skip)"
  log "All passwords/secrets (JWT_SECRET, DB passwords, wallet passphrase, RPC password,"
  log "faucet admin password) will be generated automatically in a moment, unless supplied via the config file."
  ask_yes_no INSTALL_POOL "Install the PPLNS mining pool (elektron-net-ppool + dashboard)?"
  if [ "$INSTALL_POOL" = "true" ]; then
    ask POOL_DOMAIN "Domain for the pool dashboard"
  fi
  ask_yes_no INSTALL_FAUCET "Install the faucet (elektron-net-faucet)?"
  if [ "$INSTALL_FAUCET" = "true" ]; then
    ask FAUCET_DOMAIN "Domain for the faucet"
    ask FAUCET_HCAPTCHA_SITE   "hCaptcha site key from hcaptcha.com (optional, but recommended)"
    ask FAUCET_HCAPTCHA_SECRET "hCaptcha secret key (optional)"
  fi
  ask_yes_no INSTALL_SEEDER "Also install the seeder (DNS crawler, optional, still in testing)? See README 'Seeder (optional, testing phase)'"
  if [ "$INSTALL_SEEDER" = "true" ]; then
    ask SEEDER_HOST "Hostname of the DNS seed itself (needs its own NS delegation in DNS, see README)"
    ask SEEDER_NS   "Hostname of the nameserver for the seed"
    ask SEEDER_MBOX "Email address for the SOA record (@ written as ., e.g. admin.example.com)"
  fi
  ask_yes_no INSTALL_MEMPOOL "Also install the Mempool Explorer (block explorer/visualizer, like mempool.space)?"
  if [ "$INSTALL_MEMPOOL" = "true" ]; then
    ask MEMPOOL_DOMAIN "Domain for the Mempool Explorer"
    ask_yes_no MEMPOOL_ACCELERATOR "Enable the Accelerator menu/boost button in the explorer (links to mempool.space's fee acceleration service, purely outbound request, no new port)?"
  fi
else
  log "Non-interactive mode (--yes or no terminal) -- using defaults/config file without prompting."
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
  # KEY=VALUE file, or nothing if the file/key doesn't exist yet. A missing
  # key is the normal, expected case for every caller below -- must not
  # propagate grep's no-match exit code, or "set -e -o pipefail" aborts the
  # whole script silently on every rerun where an older .env predates a key.
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  grep "^${key}=" "$file" 2>/dev/null | tail -n1 | cut -d= -f2- || true
}

PPOOL_ENV_PATH="${STACK_DIR}/elektron-net-ppool/.env"
FAUCET_ENV_PATH="${STACK_DIR}/elektron-net-faucet/.env"
BITCOIN_CONF_PATH="${STACK_DIR}/elektron-net/bitcoin.conf"
MEMPOOL_ENV_PATH="${STACK_DIR}/elektron-net-mempool/.env"

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
# MariaDB's own image only ever reads MYSQL_PASSWORD/MYSQL_ROOT_PASSWORD --
# those (plus DATABASE_PASSWORD, same value, read by the mempool backend)
# are the actual key names that end up in the .env below, NOT
# "MEMPOOL_DB_PASS"/"MEMPOOL_DB_ROOT_PASS" (those are only this script's own
# bash variable names). Look up the real key so a rerun finds what's
# actually there instead of silently minting a fresh password every time.
reuse_or_generate MEMPOOL_DB_PASS          "$MEMPOOL_ENV_PATH" MYSQL_PASSWORD        rand_base64 24
reuse_or_generate MEMPOOL_DB_ROOT_PASS     "$MEMPOOL_ENV_PATH" MYSQL_ROOT_PASSWORD   rand_base64 24

[ -n "$REUSED_SECRETS" ] && log "Reused from a previous run (not regenerated): ${REUSED_SECRETS}"

# ----------------------------------------------------------------------------
# Defense in depth against the exact class of bug just described (a reuse
# lookup key that doesn't match what's actually in the .env, whether from
# today's mismatch or some future rename): if a DB-backed service's data
# directory already has an initialized database on disk, but its password
# was just freshly generated rather than reused, the two are guaranteed to
# be out of sync -- MariaDB only reads MYSQL_PASSWORD on the very first boot
# against an empty datadir, so an already-populated one has some *other*
# password baked in for good. Proceeding would silently lock the service out
# of its own database instead of failing loudly where it's still fixable.
# ----------------------------------------------------------------------------
refuse_fresh_secret_for_existing_data() {
  local var_name="$1" data_dir="$2"
  [ -d "$data_dir" ] || return 0
  [ -n "$(ls -A "$data_dir" 2>/dev/null)" ] || return 0
  case " $REUSED_SECRETS " in
    *" ${var_name} "*) return 0 ;;
  esac
  die "Safety stop: '${data_dir}' already contains database files, but ${var_name} was just freshly generated instead of being reused from an existing config. That would lock the service out of its own, already-populated database. Please check manually under which key the existing .env stores the password actually in use, and adjust reuse_or_generate() accordingly (or enter the password there by hand), before running this script again."
}

if [ "$INSTALL_MEMPOOL" = "true" ]; then
  refuse_fresh_secret_for_existing_data MEMPOOL_DB_PASS      "${STACK_DIR}/data/mempool-db"
  refuse_fresh_secret_for_existing_data MEMPOOL_DB_ROOT_PASS "${STACK_DIR}/data/mempool-db"
fi
refuse_fresh_secret_for_existing_data FAUCET_DB_PASS       "${STACK_DIR}/data/faucet-db"
refuse_fresh_secret_for_existing_data FAUCET_DB_ROOT_PASS  "${STACK_DIR}/data/faucet-db"

# Reuse the RPC credentials (rpcauth.py) the same way instead of generating
# new ones on every run -- see step 3 further below, this here is just the
# upfront check for whether they already exist.
REUSE_RPC_AUTH=false
EXISTING_RPC_AUTH_LINE="$(existing_value "$BITCOIN_CONF_PATH" rpcauth)"
EXISTING_RPC_USER="${EXISTING_RPC_AUTH_LINE%%:*}"
EXISTING_RPC_PASSWORD="$(existing_value "$PPOOL_ENV_PATH" ELEKTRON_RPC_PASSWORD)"
if [ -n "$EXISTING_RPC_AUTH_LINE" ] && [ -n "$EXISTING_RPC_PASSWORD" ] && [ "$EXISTING_RPC_USER" = "$RPC_USER" ]; then
  REUSE_RPC_AUTH=true
fi

# Wallet addresses the same way: getnewaddress returns a NEW, previously
# unused address on every call -- so a rerun must not simply call it again,
# or POOL_WALLET_ADDRESS/FAUCET_SENDER_ADDR would end up pointing at an
# empty address while any already-deposited ELEK sits on the old one. Only
# reuse it if the wallet name is unchanged since the last run.
EXISTING_POOL_WALLET_ADDRESS=""
if [ "$(existing_value "$PPOOL_ENV_PATH" WALLET_RPC_WALLET_NAME)" = "$POOL_WALLET_NAME" ]; then
  EXISTING_POOL_WALLET_ADDRESS="$(existing_value "$PPOOL_ENV_PATH" POOL_WALLET_ADDRESS)"
fi
EXISTING_FAUCET_SENDER_ADDR=""
if [ "$(existing_value "$FAUCET_ENV_PATH" FAUCET_WALLET_NAME)" = "$FAUCET_WALLET_NAME" ]; then
  EXISTING_FAUCET_SENDER_ADDR="$(existing_value "$FAUCET_ENV_PATH" FAUCET_SENDER_ADDR)"
fi

command -v docker >/dev/null 2>&1 || die "Docker is not installed."
docker compose version >/dev/null 2>&1 || die "Docker Compose plugin is missing."
command -v git >/dev/null 2>&1    || die "git is not installed."
command -v python3 >/dev/null 2>&1 || die "python3 is not installed (needed for rpcauth.py)."
command -v openssl >/dev/null 2>&1 || die "openssl is not installed."

# --- Read the actually configured IPv6 address on this server ---
# Some provider panels only show the routed /64, not the specific address
# the server has given itself -- so check directly instead of blindly
# trusting the fallback assumption (::1).
DETECTED_IPV6="$(ip -6 addr show scope global 2>/dev/null | awk '/inet6/{print $2}' | cut -d/ -f1 | grep -v '^fe80' | head -n1 || true)"
if [ -n "$DETECTED_IPV6" ] && [ "$DETECTED_IPV6" != "$SERVER_IPV6" ]; then
  warn "Detected IPv6 address on this server ($DETECTED_IPV6) differs from the CONFIG value ($SERVER_IPV6) -- using the detected address."
  SERVER_IPV6="$DETECTED_IPV6"
elif [ -z "$DETECTED_IPV6" ]; then
  warn "Could not find a global IPv6 address on this server -- IPv6 may not be configured yet. Still using the CONFIG value ($SERVER_IPV6), please check."
fi

# --- Soft DNS sanity check (does not abort on mismatch, just warns) ---
DOMAINS_TO_CHECK="$NODE_DOMAIN"
[ "$INSTALL_POOL" = "true" ] && DOMAINS_TO_CHECK="$DOMAINS_TO_CHECK $POOL_DOMAIN"
[ "$INSTALL_FAUCET" = "true" ] && DOMAINS_TO_CHECK="$DOMAINS_TO_CHECK $FAUCET_DOMAIN"
[ "$INSTALL_MEMPOOL" = "true" ] && DOMAINS_TO_CHECK="$DOMAINS_TO_CHECK $MEMPOOL_DOMAIN"
for d in $DOMAINS_TO_CHECK; do
  resolved="$(getent ahostsv4 "$d" 2>/dev/null | awk '{print $1}' | head -n1 || true)"
  if [ -z "$resolved" ]; then
    warn "$d does not resolve (yet). Caddy won't get TLS for this endpoint until DNS has propagated."
  elif [ "$resolved" != "$SERVER_IP" ]; then
    warn "$d resolves to $resolved, not to $SERVER_IP. Please check the DNS record."
  fi

  resolved6="$(getent ahostsv6 "$d" 2>/dev/null | awk '{print $1}' | head -n1 || true)"
  if [ -z "$resolved6" ]; then
    warn "$d has no AAAA record (yet) -- IPv6 reachability is missing, IPv4 still works."
  elif [ "$resolved6" != "$SERVER_IPV6" ]; then
    warn "$d (AAAA) resolves to $resolved6, not to $SERVER_IPV6. Please check the DNS record."
  fi
done

# ============================================================================
# 1. Clone the repos
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
         warn "$repo: no upstream tracking branch found, skipping update check."
       elif [ "$local_head" = "$remote_head" ]; then
         log "$repo: already up to date, no new commits."
       elif git merge-base --is-ancestor HEAD "@{upstream}"; then
         log "$repo: new commits found, updating (fast-forward):"
         git log --oneline "HEAD..@{upstream}"
         git pull --ff-only --quiet
       else
         warn "$repo: local branch has diverged from upstream (own commits?) -- skipping automatic update, please check manually."
       fi
  )
}

clone_or_skip() {
  local repo="$1"
  if [ -d "$repo/.git" ]; then
    log "Repo $repo already exists (full git clone), skipping re-clone."
    update_if_enabled "$repo"
    return
  fi

  if [ -d "$repo" ] && [ "$(ls -A "$repo" 2>/dev/null)" ]; then
    # Directory already exists and isn't empty -- typically because it
    # comes from THIS deploy repo (elektron-net-stack) and already
    # contains our extra files (Dockerfile, bitcoin.conf, .env template,
    # ...). `git clone` would abort here with "destination path already
    # exists and is not an empty directory" -- so clone upstream into a
    # temp directory instead and only copy in what isn't there yet (our
    # already-existing files stay untouched).
    log "Directory $repo already exists and isn't empty -- cloning upstream into a temp directory and merging non-destructively."
    local tmp
    tmp="$(mktemp -d)"
    git clone "https://github.com/${GITHUB_USER}/${repo}.git" "$tmp"
    rm -rf "$tmp/.git"
    cp -rn "$tmp"/. "$repo"/
    rm -rf "$tmp"
  else
    log "Cloning $repo ..."
    git clone "https://github.com/${GITHUB_USER}/${repo}.git" "$repo"
  fi
}

clone_or_skip "elektron-net"
[ "$INSTALL_POOL" = "true" ] && clone_or_skip "elektron-net-ppool"
[ "$INSTALL_POOL" = "true" ] && clone_or_skip "elektron-net-ppool-ui"
[ "$INSTALL_FAUCET" = "true" ] && clone_or_skip "elektron-net-faucet"
[ "$INSTALL_SEEDER" = "true" ] && clone_or_skip "elektron-net-seeder"
[ "$INSTALL_MEMPOOL" = "true" ] && clone_or_skip "elektron-net-mempool"
# elektron-net-electrs (Electrum server) belongs firmly to the Mempool
# Explorer: it provides its address lookups (MEMPOOL_BACKEND=electrum) and
# shares its Compose profile "mempool" -- always installed/started/removed
# together.
[ "$INSTALL_MEMPOOL" = "true" ] && clone_or_skip "elektron-net-electrs"

mkdir -p caddy data/elektron-net external-wallets
[ "$INSTALL_POOL" = "true" ] && mkdir -p data/ppool-DB
[ "$INSTALL_FAUCET" = "true" ] && mkdir -p data/faucet-db data/faucet-config
[ "$INSTALL_SEEDER" = "true" ] && mkdir -p data/elektron-net-seeder
[ "$INSTALL_MEMPOOL" = "true" ] && mkdir -p data/mempool-db data/mempool-cache data/electrs

# ============================================================================
# 1b. elektron-net-mempool: prepare the Docker build context
# ============================================================================
# Mirrors upstream mempool.space's docker/init.sh (not run automatically by
# the mempool repo itself, and not shipped as its own script there): stages
# docker/backend + docker/frontend into backend/ and frontend/, and patches
# the nginx configs for a non-localhost container. The __MEMPOOL_*__ tokens
# left in nginx.conf/nginx-mempool.conf are intentional -- they're resolved
# at container startup by the frontend's own entrypoint.sh from the
# BACKEND_MAINNET_HTTP_HOST/PORT and FRONTEND_HTTP_PORT env vars set below,
# not by this staging step. Always re-run (not just on first clone) so an
# AUTO_UPDATE_REPOS pull that changes these templates is picked up on the
# next build.
if [ "$INSTALL_MEMPOOL" = "true" ]; then
  log "Preparing elektron-net-mempool Docker build context (staging backend/frontend from docker/) ..."
  ( cd elektron-net-mempool \
    && cp -r ./docker/backend/. ./backend/ \
    && cp -r ./docker/frontend/. ./frontend/ \
    && mkdir -p ./backend/GeoIP \
    && cp ./nginx.conf ./http-basic.conf ./nginx-mempool.conf ./frontend/ \
    && sed -i -e "s#127.0.0.1:80#0.0.0.0:__MEMPOOL_FRONTEND_HTTP_PORT__#g" ./frontend/nginx.conf \
    && sed -i -e "s#127.0.0.1#0.0.0.0#g" ./frontend/nginx.conf \
    && sed -i -e "s#user nobody;##g" ./frontend/nginx.conf \
    && sed -i -e "s#/etc/nginx/nginx-mempool.conf#/etc/nginx/conf.d/nginx-mempool.conf#g" ./frontend/nginx.conf \
    && sed -i -e "s#127.0.0.1:8999#__MEMPOOL_BACKEND_MAINNET_HTTP_HOST__:__MEMPOOL_BACKEND_MAINNET_HTTP_PORT__#g" ./frontend/nginx-mempool.conf \
  )
fi

# ============================================================================
# 2. elektron-net: Dockerfile + entrypoint (don't exist in the repo yet)
# ============================================================================
log "Writing elektron-net/Dockerfile ..."
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

log "Writing elektron-net/docker-entrypoint.sh ..."
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
# 3. Generate rpcauth
# ============================================================================
if [ "$REUSE_RPC_AUTH" = true ]; then
  log "Found RPC credentials from a previous run -- reusing them (node password stays the same)."
  RPC_AUTH_LINE="$EXISTING_RPC_AUTH_LINE"
  RPC_PASSWORD="$EXISTING_RPC_PASSWORD"
else
  log "Generating RPC credentials (rpcauth.py) ..."
  RPCAUTH_JSON="$(python3 elektron-net/share/rpcauth/rpcauth.py "$RPC_USER" -j)"
  RPC_AUTH_LINE="$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['rpcauth'])" "$RPCAUTH_JSON")"
  RPC_PASSWORD="$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['password'])" "$RPCAUTH_JSON")"
fi

# ============================================================================
# 4. elektron-net/bitcoin.conf
# ============================================================================
log "Writing elektron-net/bitcoin.conf ..."
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
# Auto-load these wallets on every node startup -- without this, a restart
# leaves listwallets empty and pool/faucet payouts fail until someone runs
# `loadwallet` by hand. Only listed here for whichever of pool/faucet is
# actually installed, so the node never tries to auto-load a wallet that
# was never created.
$( [ "$INSTALL_POOL" = "true" ] && echo "wallet=${POOL_WALLET_NAME}" )
$( [ "$INSTALL_FAUCET" = "true" ] && echo "wallet=${FAUCET_WALLET_NAME}" )
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
    profiles:
      - pool
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
    profiles:
      - pool
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
    profiles:
      - faucet
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
      test: ["CMD-SHELL", "mariadb-admin ping -uroot -p$$MYSQL_ROOT_PASSWORD --silent"]
      interval: 5s
      timeout: 5s
      retries: 20

  elektron-faucet-app:
    container_name: elektron-faucet-app
    profiles:
      - faucet
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

  elektron-net-seeder:
    container_name: elektron-net-seeder
    profiles:
      - seeder
    build:
      context: ./elektron-net-seeder
    restart: unless-stopped
    networks:
      - backend
    ports:
      - "<SERVER_IP>:53:53/udp"
      - "<SERVER_IP>:53:53/tcp"
      - "[<SERVER_IPV6>]:53:53/udp"
      - "[<SERVER_IPV6>]:53:53/tcp"
    env_file: ./elektron-net-seeder/.env
    volumes:
      - "./data/elektron-net-seeder:/data"

  elektron-mempool-db:
    container_name: elektron-mempool-db
    image: mariadb:11.4
    restart: unless-stopped
    profiles:
      - mempool
    env_file: ./elektron-net-mempool/.env
    networks:
      - backend
    volumes:
      - "./data/mempool-db:/var/lib/mysql"
    healthcheck:
      test: ["CMD-SHELL", "mariadb-admin ping -uroot -p$$MYSQL_ROOT_PASSWORD --silent"]
      interval: 5s
      timeout: 5s
      retries: 20

  # Electrum server for the Mempool Explorer's address lookups AND for
  # external Electrum wallet clients (e.g. Elektron Electrum). Same
  # profile as the mempool services: exists exactly when the explorer is
  # installed. All settings (including RPC credentials, the Elektron P2P
  # magic e1ec7a6e and the node's P2P address for block download) come
  # from the generated elektron-net-electrs/electrs.toml -- electrs
  # fundamentally does NOT accept credentials via env var or CLI.
  #
  # ports: publishes electrs' single Electrum RPC listener (internally
  # "0.0.0.0:50001", see electrs.toml) twice from the host -- as the
  # conventional "t" (50001, plain TCP) AND as "s" (50002), both mapped to
  # the same container port. IMPORTANT: electrs itself cannot terminate
  # TLS (no certificate handling in the upstream code), and this stack
  # currently has NO separate TLS terminator in front of it -- so 50002,
  # despite the "s" convention, is also plain TCP, no real SSL. Wallets
  # that strictly require a TLS handshake on the "s" port will fail
  # there; they're best off relying on 50001 ("t") or a "no SSL" setting
  # for the server entry. Without this mapping, electrs would only be
  # reachable over the internal "backend" Docker network, not from the
  # outside -- that was the reason for the initially failing wallet
  # connection to electrs.elektron-net.org:50002.
  elektron-electrs:
    container_name: elektron-electrs
    profiles:
      - mempool
    build:
      context: ./elektron-net-electrs
    restart: unless-stopped
    depends_on:
      elektron-net:
        condition: service_started
    networks:
      - backend
    ports:
      - "50001:50001"
      - "50002:50001"
    # the image defines no CMD/ENTRYPOINT; config is read automatically
    # from /etc/electrs/config.toml (electrs' standard search path)
    command: ["electrs"]
    volumes:
      - "./elektron-net-electrs/electrs.toml:/etc/electrs/config.toml:ro"
      - "./data/electrs:/data"

  elektron-mempool-api:
    container_name: elektron-mempool-api
    profiles:
      - mempool
    build:
      context: ./elektron-net-mempool/backend
      additional_contexts:
        - "backend=./elektron-net-mempool/backend"
        - "rustgbt=./elektron-net-mempool/rust"
      args:
        commitHash: "local"
    restart: unless-stopped
    depends_on:
      elektron-net:
        condition: service_started
      elektron-mempool-db:
        condition: service_healthy
      elektron-electrs:
        condition: service_started
    networks:
      - backend
    env_file: ./elektron-net-mempool/.env
    volumes:
      - "./data/mempool-cache:/backend/cache"

  elektron-mempool-web:
    container_name: elektron-mempool-web
    profiles:
      - mempool
    build:
      context: ./elektron-net-mempool/frontend
    restart: unless-stopped
    depends_on:
      - elektron-mempool-api
    networks:
      - backend
      - web
    env_file: ./elektron-net-mempool/.env

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

# Bind the seeder ports to the specific server IP instead of the wildcard
# address -- avoids a collision with systemd-resolved (which typically only
# listens on 127.0.0.53/54:53, not the public IP).
sed -i "s/<SERVER_IP>/${SERVER_IP}/g; s/<SERVER_IPV6>/${SERVER_IPV6}/g" docker-compose.yml

# ============================================================================
# 6. Caddyfile
# ============================================================================
log "Writing caddy/Caddyfile ..."
{
  if [ -n "$CADDY_EMAIL" ]; then
    echo "{"
    echo "	email ${CADDY_EMAIL}"
    echo "}"
    echo
  fi
  echo "# ${NODE_DOMAIN} deliberately gets no block -- plain P2P seed (port 8333)."
  if [ "$INSTALL_POOL" = "true" ]; then
    echo
    echo "${POOL_DOMAIN} {"
    echo "	reverse_proxy elektron-ppool-ui:80"
    echo "}"
  fi
  if [ "$INSTALL_FAUCET" = "true" ]; then
    echo
    echo "${FAUCET_DOMAIN} {"
    echo "	reverse_proxy elektron-faucet-app:80"
    echo "}"
  fi
  if [ "$INSTALL_MEMPOOL" = "true" ]; then
    echo
    echo "${MEMPOOL_DOMAIN} {"
    echo "	reverse_proxy elektron-mempool-web:8080"
    echo "}"
  fi
} > caddy/Caddyfile

# ============================================================================
# 7. elektron-net-ppool/.env -- only if INSTALL_POOL=true
# ============================================================================
if [ "$INSTALL_POOL" = "true" ]; then
log "Writing elektron-net-ppool/.env ..."
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

# Optional -- leave blank to disable the respective integration.
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
TELEGRAM_BOT_USERNAME=${TELEGRAM_BOT_USERNAME}
DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN}
DISCORD_BOT_CLIENTID=${DISCORD_BOT_CLIENTID}
DISCORD_BOT_GUILD_ID=${DISCORD_BOT_GUILD_ID}
DISCORD_BOT_CHANNEL_ID=${DISCORD_BOT_CHANNEL_ID}

# filled in automatically by this script after wallet creation:
POOL_WALLET_ADDRESS=

PPLNS_WINDOW_MINUTES=${PPLNS_WINDOW_MINUTES}
POOL_FEE_PERCENT=${POOL_FEE_PERCENT}
MIN_PAYOUT_THRESHOLD_SATS=${MIN_PAYOUT_THRESHOLD_SATS}
PAYOUT_INTERVAL_MINUTES=${PAYOUT_INTERVAL_MINUTES}
PAYOUT_CONFIRMATIONS_REQUIRED=${PAYOUT_CONFIRMATIONS_REQUIRED}
PAYOUT_DRY_RUN=${PAYOUT_DRY_RUN}

WALLET_RPC_WALLET_NAME=${POOL_WALLET_NAME}

# The pool wallet is encrypted (see README, "recommended before real
# payouts") -- ppool unlocks it automatically for every payout using
# this and locks it again immediately afterward (wallet-rpc.service.ts).
WALLET_PASSPHRASE=${POOL_WALLET_PASSPHRASE}
WALLET_UNLOCK_SECONDS=${WALLET_UNLOCK_SECONDS}

JWT_SECRET=${JWT_SECRET}
ENV_EOF
fi

# ============================================================================
# 8. elektron-net-faucet/.env -- only if INSTALL_FAUCET=true
# ============================================================================
if [ "$INSTALL_FAUCET" = "true" ]; then
log "Writing elektron-net-faucet/.env ..."
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
# filled in automatically by this script after wallet creation:
FAUCET_SENDER_ADDR=
FAUCET_EXPLORER_URL=${FAUCET_EXPLORER_URL}
FAUCET_DEFAULT_LANG=${FAUCET_DEFAULT_LANG}
ENV_EOF
fi

# ============================================================================
# 8b. elektron-net-seeder/.env -- only if INSTALL_SEEDER=true
# ============================================================================
if [ "$INSTALL_SEEDER" = "true" ]; then
  log "Writing elektron-net-seeder/.env ..."
  cat > elektron-net-seeder/.env <<ENV_EOF
SEEDER_HOST=${SEEDER_HOST}
SEEDER_NS=${SEEDER_NS}
SEEDER_MBOX=${SEEDER_MBOX}
SEEDER_DNS_PORT=${SEEDER_DNS_PORT}
SEEDER_BIND_ADDRESS=::
SEEDER_THREADS=${SEEDER_THREADS}
SEEDER_DNS_THREADS=${SEEDER_DNS_THREADS}
SEEDER_P2P_PORT=
SEEDER_MAGIC=
SEEDER_MIN_HEIGHT=${SEEDER_MIN_HEIGHT}
SEEDER_TOR_PROXY=
SEEDER_IPV4_PROXY=
SEEDER_IPV6_PROXY=
SEEDER_TESTNET=false
SEEDER_WIPE_BAN=false
SEEDER_WIPE_IGNORE=false
SEEDER_EXTRA_SEEDS=
SEEDER_FILTERS=
ENV_EOF
fi

# ============================================================================
# 8c. elektron-net-mempool/.env -- only if INSTALL_MEMPOOL=true
# ============================================================================
# One shared .env for all three mempool containers (db/api/web) -- each key
# is named for whichever consumer actually reads it (MYSQL_* for the stock
# MariaDB image, DATABASE_*/CORE_RPC_* for the backend, the rest for the
# frontend's entrypoint.sh), so a single env_file: per service is enough --
# no docker-compose.yml-level ${VAR} substitution needed for this service.
if [ "$INSTALL_MEMPOOL" = "true" ]; then
  log "Writing elektron-net-mempool/.env ..."
  cat > elektron-net-mempool/.env <<ENV_EOF
# --- Node RPC (shared with ppool/faucet) ---
CORE_RPC_HOST=elektron-net
CORE_RPC_PORT=8332
CORE_RPC_USERNAME=${RPC_USER}
CORE_RPC_PASSWORD=${RPC_PASSWORD}

# --- Backend ---
MEMPOOL_NETWORK=mainnet
# "electrum" = address lookups via the co-installed elektron-electrs
# (same Compose profile "mempool", see docker-compose.yml).
MEMPOOL_BACKEND=electrum
ELECTRUM_HOST=elektron-electrs
ELECTRUM_PORT=50001
ELECTRUM_TLS_ENABLED=false
STATISTICS_ENABLED=true
FIAT_PRICE_ENABLED=false
MEMPOOL_INDEXING_BLOCKS_AMOUNT=${MEMPOOL_INDEXING_BLOCKS_AMOUNT}
# Our own mining pool list instead of Bitcoin's -- see
# elektron-net-mempool/backend/src/api/pools-parser.ts for why a pool
# identifier can't be embedded in the coinbase scriptSig here.
MEMPOOL_POOLS_JSON_URL=https://raw.githubusercontent.com/${GITHUB_USER}/elektron-net-mempool/main/pools-v2.json
MEMPOOL_POOLS_JSON_TREE_URL=https://api.github.com/repos/${GITHUB_USER}/elektron-net-mempool/git/trees/main

# --- Database (own dedicated MariaDB instance, elektron-mempool-db) ---
DATABASE_ENABLED=true
DATABASE_HOST=elektron-mempool-db
DATABASE_DATABASE=${MEMPOOL_DB_NAME}
DATABASE_USERNAME=${MEMPOOL_DB_USER}
DATABASE_PASSWORD=${MEMPOOL_DB_PASS}
MYSQL_DATABASE=${MEMPOOL_DB_NAME}
MYSQL_USER=${MEMPOOL_DB_USER}
MYSQL_PASSWORD=${MEMPOOL_DB_PASS}
MYSQL_ROOT_PASSWORD=${MEMPOOL_DB_ROOT_PASS}

# --- Frontend ---
FRONTEND_HTTP_PORT=8080
BACKEND_MAINNET_HTTP_HOST=elektron-mempool-api
BACKEND_MAINNET_HTTP_PORT=8999
MEMPOOL_WEBSITE_URL=https://${MEMPOOL_DOMAIN}
HISTORICAL_PRICE=false
# The menu icon ("Acceleration" dashboard) and the boost button on the TX
# page are two separate frontend flags (see
# elektron-net-mempool/frontend/mempool-frontend-config.sample.json) --
# coupled to the same toggle here. Both only make outbound HTTPS calls to
# SERVICES_API (mempool.space), no new port needed.
ACCELERATOR=${MEMPOOL_ACCELERATOR}
ACCELERATOR_BUTTON=${MEMPOOL_ACCELERATOR}
SERVICES_API=
ENV_EOF
fi

# ============================================================================
# 8d. elektron-net-electrs/electrs.toml -- only if INSTALL_MEMPOOL=true
# ============================================================================
# electrs accepts RPC credentials EXCLUSIVELY from a config file (a
# deliberate anti-leak measure upstream: neither a CLI argument nor an env
# var is possible), so everything here gets written into a generated file
# that's mounted to /etc/electrs/config.toml via docker-compose.yml.
if [ "$INSTALL_MEMPOOL" = "true" ]; then
  log "Writing elektron-net-electrs/electrs.toml ..."
  cat > elektron-net-electrs/electrs.toml <<ELECTRS_EOF
# Generated by install-elektron-stack.sh -- changes here get overwritten
# on the next installer run.

# Node RPC (same credentials as ppool/faucet/mempool)
auth = "${RPC_USER}:${RPC_PASSWORD}"

# Node endpoints on the backend network: RPC for mempool/broadcast,
# P2P for block download.
daemon_rpc_addr = "elektron-net:8332"
daemon_p2p_addr = "elektron-net:8333"

# Elektron Net mainnet magic (chainparams.cpp) -- without it the node
# rejects every P2P message from electrs. The option keeps its upstream
# name, but in our fork applies to every network.
signet_magic = "e1ec7a6e"

# Electrum RPC -- a single listener (electrs doesn't support multi-bind),
# used internally by elektron-mempool-api (ELECTRUM_HOST/ELECTRUM_PORT)
# AND externally for wallet clients via the docker-compose.yml port-mapping
# trick (50001 AND 50002 -> this one port), see the comment there.
electrum_rpc_addr = "0.0.0.0:50001"

# Index database, persisted via ./data/electrs
db_dir = "/data"

log_filters = "INFO"
ELECTRS_EOF
  chmod 600 elektron-net-electrs/electrs.toml
fi

# Docker Compose needs a .env in the project root to resolve ${FAUCET_DB_*}
# in docker-compose.yml -- the symlink keeps both files in sync. Only
# needed if the faucet is also installed (or was -- the file is kept when
# uninstalling, see "Disabling the faucet" further below).
[ "$INSTALL_FAUCET" = "true" ] && ln -sf elektron-net-faucet/.env .env

# ============================================================================
# 9. Start the node first
# ============================================================================
log "Building and starting elektron-net ..."
docker compose up -d --build elektron-net

# `docker compose exec` runs as root by default (the Dockerfile has no
# USER directive -- only the container's own PID 1 gets dropped to the
# "elektron" user, via gosu in docker-entrypoint.sh). elektron-cli's
# automatic cookie-file lookup uses $HOME/<default-datadir>, which for
# root is /root/... -- NOT /data, where the real cookie file actually is.
# So every elektron-cli call needs the RPC credentials passed explicitly;
# relying on auto-discovery here silently fails auth every time.
node_cli() {
  docker compose exec -T elektron-net elektron-cli -rpcuser="$RPC_USER" -rpcpassword="$RPC_PASSWORD" "$@"
}

wait_for_rpc() {
  local retries=60 i=0
  until node_cli getblockchaininfo >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -ge "$retries" ] && die "Timeout: elektron-net RPC hasn't responded after 5 minutes."
    sleep 5
  done
}

log "Waiting for elektron-net's RPC to become ready ..."
wait_for_rpc

# ============================================================================
# 10. Create wallets -- depending on whether Pool/Faucet are installed
# ============================================================================
# POOL_ADDR/FAUCET_ADDR stay blank if the respective component isn't
# installed -- under "set -u" this needs to be explicitly pre-set instead
# of relying on the block further below to set it.
POOL_ADDR=""
FAUCET_ADDR=""

wallet_loaded() {
  node_cli listwallets | grep -q "\"$1\""
}

create_wallet_if_missing() {
  local wname="$1"
  if wallet_loaded "$wname"; then
    log "Wallet '$wname' already exists/is loaded, skipping creation."
  else
    log "Creating wallet '$wname' ..."
    node_cli createwallet "$wname" >/dev/null \
      || node_cli loadwallet "$wname" >/dev/null
  fi
}

if [ "$INSTALL_POOL" = "true" ]; then
  log "Setting up the pool wallet ..."
  create_wallet_if_missing "$POOL_WALLET_NAME"
  if [ -n "$EXISTING_POOL_WALLET_ADDRESS" ]; then
    POOL_ADDR="$EXISTING_POOL_WALLET_ADDRESS"
    log "Reused pool wallet address from a previous run: ${POOL_ADDR}"
  else
    POOL_ADDR="$(node_cli -rpcwallet="$POOL_WALLET_NAME" getnewaddress "" bech32 | tr -d '\r\n')"
    log "New pool wallet address: ${POOL_ADDR}"
  fi
  sed -i "s#^POOL_WALLET_ADDRESS=.*#POOL_WALLET_ADDRESS=${POOL_ADDR}#" elektron-net-ppool/.env
fi

# Encrypt if not already encrypted -- recommended before real payouts run
# (see the ppool .env comment on WALLET_PASSPHRASE): without this, any real
# payout fails with RPC error -13 as soon as PAYOUT_DRY_RUN=false is set.
# ppool unlocks the wallet automatically for WALLET_UNLOCK_SECONDS before
# every sendmany and locks it again immediately afterward (encryptwallet
# briefly stops the node process -- that's normal Bitcoin Core behavior,
# the container comes back up on its own thanks to restart:unless-stopped).
encrypt_wallet_if_missing() {
  local wname="$1" passphrase="$2"
  local info
  info="$(node_cli -rpcwallet="$wname" getwalletinfo)"
  if echo "$info" | grep -q '"unlocked_until"'; then
    log "Wallet '$wname' is already encrypted, skipping encryptwallet."
  else
    log "Encrypting wallet '$wname' (node restarts briefly) ..."
    node_cli -rpcwallet="$wname" encryptwallet "$passphrase" || true
    sleep 8
    wait_for_rpc
    wallet_loaded "$wname" || node_cli loadwallet "$wname" >/dev/null
  fi
}

[ "$INSTALL_POOL" = "true" ] && encrypt_wallet_if_missing "$POOL_WALLET_NAME" "$POOL_WALLET_PASSPHRASE"

if [ "$INSTALL_FAUCET" = "true" ]; then
  log "Setting up the faucet wallet ..."
  create_wallet_if_missing "$FAUCET_WALLET_NAME"
  encrypt_wallet_if_missing "$FAUCET_WALLET_NAME" "$FAUCET_WALLET_PASSPHRASE"

  if [ -n "$EXISTING_FAUCET_SENDER_ADDR" ]; then
    FAUCET_ADDR="$EXISTING_FAUCET_SENDER_ADDR"
    log "Reused faucet wallet address from a previous run: ${FAUCET_ADDR}"
  else
    FAUCET_ADDR="$(node_cli -rpcwallet="$FAUCET_WALLET_NAME" getnewaddress "" bech32 | tr -d '\r\n')"
    log "New faucet wallet address: ${FAUCET_ADDR}"
  fi
  sed -i "s#^FAUCET_SENDER_ADDR=.*#FAUCET_SENDER_ADDR=${FAUCET_ADDR}#" elektron-net-faucet/.env
fi

# ============================================================================
# 10a. Wallet backups -- full private-key export (once)
# ============================================================================
# "Complete backup" here means not just the passphrase (see above), but
# the actual private keys of the pool/faucet wallet. dumpwallet only works
# for legacy wallets; if the wallet created here by createwallet is a
# descriptor wallet, it fails and we fall back to "listdescriptors true"
# (returns the same private keys as descriptor strings). Runs only ONCE --
# if the backup file already exists, nothing gets written/overwritten again.
backup_wallet_privkeys() {
  local wname="$1" host_path="$2" container_path="$3"
  if [ -f "$host_path" ]; then
    log "Wallet backup for '$wname' already exists, skipping: ${host_path}"
    return
  fi
  log "Exporting private keys of wallet '$wname' (complete backup) ..."
  if node_cli -rpcwallet="$wname" dumpwallet "$container_path" >/dev/null 2>&1; then
    log "Wallet backup (dumpwallet, legacy format) saved: ${host_path}"
  elif node_cli -rpcwallet="$wname" listdescriptors true > "$host_path" 2>/dev/null; then
    log "Wallet backup (private descriptors) saved: ${host_path}"
  else
    warn "Could not create an automatic wallet backup for '$wname' -- please check manually: docker compose exec elektron-net elektron-cli -rpcuser=$RPC_USER -rpcpassword=<see CREDENTIALS.txt> -rpcwallet=$wname listdescriptors true"
    rm -f "$host_path"
    return
  fi
  chmod 600 "$host_path" 2>/dev/null || true
}

POOL_WALLET_DUMP_HOST="${STACK_DIR}/data/elektron-net/pool-wallet-privkeys-backup.txt"
FAUCET_WALLET_DUMP_HOST="${STACK_DIR}/data/elektron-net/faucet-wallet-privkeys-backup.txt"

# Both wallets are encrypted by now (see 10.) -- so briefly unlock each one,
# export, then lock it again immediately afterward.
export_wallet_backup() {
  local wname="$1" passphrase="$2" host_path="$3" container_path="$4"
  if [ -f "$host_path" ]; then
    log "Wallet backup for '$wname' already exists, skipping: ${host_path}"
    return
  fi
  log "Briefly unlocking wallet '$wname' for the private-key export ..."
  node_cli -rpcwallet="$wname" walletpassphrase "$passphrase" 60 >/dev/null 2>&1 \
    || warn "Could not unlock wallet '$wname' -- the private-key export will likely fail, check the passphrase."
  backup_wallet_privkeys "$wname" "$host_path" "$container_path"
  node_cli -rpcwallet="$wname" walletlock >/dev/null 2>&1 || true
}

[ "$INSTALL_POOL" = "true" ]   && export_wallet_backup "$POOL_WALLET_NAME"   "$POOL_WALLET_PASSPHRASE"   "$POOL_WALLET_DUMP_HOST"   "/data/pool-wallet-privkeys-backup.txt"
[ "$INSTALL_FAUCET" = "true" ] && export_wallet_backup "$FAUCET_WALLET_NAME" "$FAUCET_WALLET_PASSPHRASE" "$FAUCET_WALLET_DUMP_HOST" "/data/faucet-wallet-privkeys-backup.txt"

# ============================================================================
# 10c. Disable the pool, if INSTALL_POOL is (again) set to false
# ============================================================================
if [ "$INSTALL_POOL" != "true" ]; then
  for svc in elektron-ppool-ui elektron-ppool; do
    if docker compose ps -a --format '{{.Service}}' 2>/dev/null | grep -qx "$svc"; then
      log "INSTALL_POOL=false -- stopping and removing ${svc} (data in data/ppool-DB/ is kept) ..."
      docker compose stop "$svc" 2>/dev/null || true
      docker compose rm -f "$svc" 2>/dev/null || true
    fi
  done
fi

# ============================================================================
# 10d. Disable the faucet, if INSTALL_FAUCET is (again) set to false
# ============================================================================
if [ "$INSTALL_FAUCET" != "true" ]; then
  for svc in elektron-faucet-app elektron-faucet-db; do
    if docker compose ps -a --format '{{.Service}}' 2>/dev/null | grep -qx "$svc"; then
      log "INSTALL_FAUCET=false -- stopping and removing ${svc} (data in data/faucet-db/ and data/faucet-config/ is kept) ..."
      docker compose stop "$svc" 2>/dev/null || true
      docker compose rm -f "$svc" 2>/dev/null || true
    fi
  done
fi

# ============================================================================
# 10e. Disable the seeder, if INSTALL_SEEDER is (again) set to false
# ============================================================================
# A deactivated Compose profile doesn't by itself stop an already-running
# container -- without this teardown, INSTALL_SEEDER=false wouldn't
# actually uninstall anything.
if [ "$INSTALL_SEEDER" != "true" ]; then
  if docker compose ps -a --format '{{.Service}}' 2>/dev/null | grep -qx "elektron-net-seeder"; then
    log "INSTALL_SEEDER=false -- stopping and removing the seeder container (data in data/elektron-net-seeder/ is kept) ..."
    docker compose stop elektron-net-seeder 2>/dev/null || true
    docker compose rm -f elektron-net-seeder 2>/dev/null || true
  fi
fi

# ============================================================================
# 10f. Disable the Mempool Explorer, if INSTALL_MEMPOOL is (again) set to false
# ============================================================================
if [ "$INSTALL_MEMPOOL" != "true" ]; then
  # elektron-electrs belongs to the explorer (same profile) and gets removed
  # along with it; its index in data/electrs/ is kept -- like the mempool
  # DB -- for a later re-activation.
  for svc in elektron-mempool-web elektron-mempool-api elektron-mempool-db elektron-electrs; do
    if docker compose ps -a --format '{{.Service}}' 2>/dev/null | grep -qx "$svc"; then
      log "INSTALL_MEMPOOL=false -- stopping and removing ${svc} (data in data/mempool-db/, data/mempool-cache/ and data/electrs/ is kept) ..."
      docker compose stop "$svc" 2>/dev/null || true
      docker compose rm -f "$svc" 2>/dev/null || true
    fi
  done
fi

# ============================================================================
# 11. Start the rest of the stack
# ============================================================================
COMPOSE_PROFILE_ARGS=""
BASE_SERVICES_LABEL="caddy"
if [ "$INSTALL_POOL" = "true" ]; then
  COMPOSE_PROFILE_ARGS="${COMPOSE_PROFILE_ARGS} --profile pool"
  BASE_SERVICES_LABEL="${BASE_SERVICES_LABEL}, ppool + ppool-ui"
fi
if [ "$INSTALL_FAUCET" = "true" ]; then
  COMPOSE_PROFILE_ARGS="${COMPOSE_PROFILE_ARGS} --profile faucet"
  BASE_SERVICES_LABEL="${BASE_SERVICES_LABEL}, faucet"
fi
EXTRA_SERVICES_LABEL=""
if [ "$INSTALL_SEEDER" = "true" ]; then
  COMPOSE_PROFILE_ARGS="${COMPOSE_PROFILE_ARGS} --profile seeder"
  EXTRA_SERVICES_LABEL="${EXTRA_SERVICES_LABEL}, seeder"
fi
if [ "$INSTALL_MEMPOOL" = "true" ]; then
  COMPOSE_PROFILE_ARGS="${COMPOSE_PROFILE_ARGS} --profile mempool"
  EXTRA_SERVICES_LABEL="${EXTRA_SERVICES_LABEL}, mempool explorer + electrs"
fi
log "Building and starting the rest of the stack (${BASE_SERVICES_LABEL}${EXTRA_SERVICES_LABEL}) ..."
docker compose $COMPOSE_PROFILE_ARGS up -d --build

# ============================================================================
# 11b. Clean up the Docker build cache
# ============================================================================
# Every rebuild accumulates build cache that's no longer needed afterward --
# the finished images stay unaffected by this. Only delete entries unused
# for the past 24h, so a rebuild shortly afterward doesn't start from
# scratch again.
log "Cleaning up old Docker build cache (unused for >24h) ..."
docker builder prune -f --filter "until=24h" >/dev/null || true

# ============================================================================
# 12. Firewall
# ============================================================================
# Note: MEMPOOL_ACCELERATOR needs NO additional port -- the menu and boost
# button only make outbound calls to mempool.space's public services API
# (SERVICES_API) over HTTPS, no new inbound port.
if command -v ufw >/dev/null 2>&1; then
  if [ "$FIREWALL_AUTO_CONFIGURE" = "true" ]; then
    log "Configuring ufw (IPv4 + IPv6) ..."
    # Ubuntu default: /etc/default/ufw has IPV6=yes -- ufw then automatically
    # adds the matching ip6tables rule for every rule too.
    if grep -q '^IPV6=no' /etc/default/ufw 2>/dev/null; then
      warn "IPv6 was disabled in /etc/default/ufw -- enabling it."
      sed -i 's/^IPV6=no/IPV6=yes/' /etc/default/ufw
    fi
    ufw allow 8333/tcp comment 'Elektron P2P seed' || true
    if [ "$INSTALL_POOL" = "true" ]; then
      ufw allow 3333/tcp comment 'Elektron PPLNS Stratum' || true
    else
      # Close it symmetrically again, in case it was open from a previous run.
      ufw delete allow 3333/tcp 2>/dev/null || true
    fi
    ufw allow 80/tcp  || true
    ufw allow 443/tcp || true
    if [ "$INSTALL_SEEDER" = "true" ]; then
      ufw allow 53/udp comment 'Elektron DNS seeder' || true
      ufw allow 53/tcp comment 'Elektron DNS seeder (TCP fallback)' || true
    else
      # Close it symmetrically again, in case it was open from a previous run.
      ufw delete allow 53/udp 2>/dev/null || true
      ufw delete allow 53/tcp 2>/dev/null || true
    fi
    if [ "$INSTALL_MEMPOOL" = "true" ]; then
      ufw allow 50001/tcp comment 'Elektron electrs Electrum (t)' || true
      ufw allow 50002/tcp comment 'Elektron electrs Electrum (s, plain TCP despite the port name)' || true
    else
      # Close it symmetrically again, in case it was open from a previous run.
      ufw delete allow 50001/tcp 2>/dev/null || true
      ufw delete allow 50002/tcp 2>/dev/null || true
    fi
    ufw reload || true
  else
    warn "FIREWALL_AUTO_CONFIGURE=false -- please open manually: ufw allow 8333/tcp$( [ "$INSTALL_POOL" = "true" ] && echo ' 3333/tcp' ) 80/tcp 443/tcp$( [ "$INSTALL_SEEDER" = "true" ] && echo ' 53/udp 53/tcp' )$( [ "$INSTALL_MEMPOOL" = "true" ] && echo ' 50001/tcp 50002/tcp' )"
  fi
else
  warn "ufw not found -- please open ports 8333, 80, 443$( [ "$INSTALL_POOL" = "true" ] && echo ', 3333' )$( [ "$INSTALL_SEEDER" = "true" ] && echo ', 53 (udp+tcp)' )$( [ "$INSTALL_MEMPOOL" = "true" ] && echo ', 50001, 50002' ) manually in your provider's network firewall panel, if it has one."
fi
FIREWALL_PORT_COUNT=3
[ "$INSTALL_POOL" = "true" ] && FIREWALL_PORT_COUNT=$((FIREWALL_PORT_COUNT + 1))
[ "$INSTALL_SEEDER" = "true" ] && FIREWALL_PORT_COUNT=$((FIREWALL_PORT_COUNT + 1))
[ "$INSTALL_MEMPOOL" = "true" ] && FIREWALL_PORT_COUNT=$((FIREWALL_PORT_COUNT + 2))
warn "If your provider has a separate network-level firewall panel (e.g. Hetzner Cloud Firewall, AWS Security Groups), also open the same ${FIREWALL_PORT_COUNT} ports there -- enable them separately for IPv4 AND IPv6, ufw alone isn't enough behind such a firewall."

# ============================================================================
# 13. Summary -- shown on screen AND written permanently to a file
#     (SUMMARY_FILE), so you don't have to copy it down during this one run.
# ============================================================================
SUMMARY_FILE="${STACK_DIR}/CREDENTIALS.txt"
GENERATED_AT="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

# For the "encryptwallet is a one-way operation" note below: name, verb and
# .env references depending on which of the two wallets are actually
# installed -- precomputed as their own variables instead of nested command
# substitution directly in the text, to avoid text/grammar mistakes.
INSTALLED_WALLETS_LABEL=""
INSTALLED_WALLETS_VERB="is"
INSTALLED_WALLET_ENV_REFS=""
if [ "$INSTALL_POOL" = "true" ]; then
  INSTALLED_WALLETS_LABEL="the pool wallet"
  INSTALLED_WALLET_ENV_REFS="${INSTALLED_WALLET_ENV_REFS} and in ${STACK_DIR}/elektron-net-ppool/.env (field WALLET_PASSPHRASE)"
fi
if [ "$INSTALL_FAUCET" = "true" ]; then
  if [ -n "$INSTALLED_WALLETS_LABEL" ]; then
    INSTALLED_WALLETS_LABEL="${INSTALLED_WALLETS_LABEL} AND the faucet wallet"
    INSTALLED_WALLETS_VERB="are"
    INSTALLED_WALLET_ENV_REFS="${INSTALLED_WALLET_ENV_REFS} and in ${STACK_DIR}/elektron-net-faucet/.env (field FAUCET_WALLET_PASS)"
  else
    INSTALLED_WALLETS_LABEL="the faucet wallet"
    INSTALLED_WALLET_ENV_REFS="${INSTALLED_WALLET_ENV_REFS} and in ${STACK_DIR}/elektron-net-faucet/.env (field FAUCET_WALLET_PASS)"
  fi
fi

# Every wallet stays its own, separately protectable file (chmod 600) --
# here, only what's in external-wallets/ gets LISTED for the overview
# (filename + path), the private-key content itself does NOT additionally
# get copied into CREDENTIALS.txt. So each wallet has exactly one place
# holding the actual secret, instead of it being duplicated.
EXTERNAL_WALLETS_DIR="${STACK_DIR}/external-wallets"
EXTERNAL_WALLETS_BLOCK="(no files found in ${EXTERNAL_WALLETS_DIR}/)"
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
 ELEKTRON NET STACK -- CREDENTIALS AND SERVER INFO
 Last updated: ${GENERATED_AT}  (rewritten on every run of install-elektron-stack.sh)
============================================================================
# This file is the central OVERVIEW of ALL credentials for this stack:
# RPC/DB/JWT/faucet-admin passwords sit directly below. Wallet private
# keys, on the other hand, deliberately stay in their own separate files
# (pool/faucet backup, all under ${EXTERNAL_WALLETS_DIR}/) -- only their
# filename and path are listed here as a reference, so each wallet secret
# lives in exactly one place instead of being duplicated.
#
# Even so: chmod 600 is already set automatically below; don't
# copy/commit it or send it by plaintext email. Back it up offline once
# (e.g. download via WinSCP/scp, see README "Getting files onto the
# server") -- ideally together with the referenced wallet files -- then
# keep it locked down on the server.
============================================================================

 Node (P2P seed):     ${NODE_DOMAIN}:8333
 Server IPv4:          ${SERVER_IP}
 Server IPv6 (detected/used): ${SERVER_IPV6}
 Pool dashboard (PPLNS mining pool, optional):$( [ "$INSTALL_POOL" = "true" ] && echo " active -- https://${POOL_DOMAIN}" || echo " not installed (INSTALL_POOL=true to enable)" )
 Faucet (optional):$( [ "$INSTALL_FAUCET" = "true" ] && echo " active -- https://${FAUCET_DOMAIN}" || echo " not installed (INSTALL_FAUCET=true to enable)" )
$( [ "$INSTALL_FAUCET" = "true" ] && cat <<FAUCET_ADMIN_SUMMARY
 Faucet admin:          https://${FAUCET_DOMAIN}/admin.php
   User:     ${FAUCET_ADMIN_USER}
   Password: ${FAUCET_ADMIN_PASS}
FAUCET_ADMIN_SUMMARY
)

 Seeder (DNS crawler, optional):$( [ "$INSTALL_SEEDER" = "true" ] && echo " active -- ${SEEDER_HOST} (NS: ${SEEDER_NS})" || echo " not installed (INSTALL_SEEDER=true to enable)" )
$( [ "$INSTALL_SEEDER" = "true" ] && cat <<SEEDER_SUMMARY
   Container: elektron-net-seeder, port 53
   Data:      ${STACK_DIR}/data/elektron-net-seeder/
SEEDER_SUMMARY
)

 Mempool Explorer (block explorer, optional):$( [ "$INSTALL_MEMPOOL" = "true" ] && echo " active -- https://${MEMPOOL_DOMAIN}" || echo " not installed (INSTALL_MEMPOOL=true to enable)" )
$( [ "$INSTALL_MEMPOOL" = "true" ] && cat <<MEMPOOL_SUMMARY
   Containers: elektron-mempool-db, elektron-mempool-api, elektron-mempool-web,
               elektron-electrs (Electrum server for address lookups)
   Note:       only shows the last ~197,280 blocks (~137 days, mandatory
               pruning). Address lookups run via elektron-electrs
               (MEMPOOL_BACKEND=electrum); right after installation its
               index build needs a few minutes.
   Electrum:  ${NODE_DOMAIN}:50001 (t, plain TCP) and :50002 (s -- WARNING:
              despite the port name, also just plain TCP, no real SSL/TLS,
              see the docker-compose.yml comment at elektron-electrs)
   Accelerator: $( [ "$MEMPOOL_ACCELERATOR" = "true" ] && echo "active -- menu + boost button, links to mempool.space (no port of its own needed)" || echo "off (MEMPOOL_ACCELERATOR=true to enable)" )
MEMPOOL_SUMMARY
)

 Pool wallet address:   $( [ "$INSTALL_POOL" = "true" ] && echo "${POOL_ADDR}" || echo "(pool not installed)" )
 Faucet wallet address: $( [ "$INSTALL_FAUCET" = "true" ] && echo "${FAUCET_ADDR}" || echo "(faucet not installed)" )

$( { [ "$INSTALL_POOL" = "true" ] || [ "$INSTALL_FAUCET" = "true" ]; } && cat <<WALLET_DUMP_SUMMARY
 Full private-key export of the installed wallets (legacy dump or
 descriptor fallback, depending on what was supported):
$( [ "$INSTALL_POOL" = "true" ] && echo "   ${POOL_WALLET_DUMP_HOST}" )
$( [ "$INSTALL_FAUCET" = "true" ] && echo "   ${FAUCET_WALLET_DUMP_HOST}" )
 (chmod 600, created once the first time each wallet was set up -- not
 overwritten on reruns. This is the actual recovery basis in case the
 server is lost; the passphrase above alone is NOT enough, it only
 unlocks an already-existing wallet file.)
WALLET_DUMP_SUMMARY
)

 ----------------------------------------------------------------------------
 ALL CREDENTIALS AT A GLANCE:

   RPC username (node):          ${RPC_USER}
   RPC password (node):          ${RPC_PASSWORD}
$( [ "$INSTALL_POOL" = "true" ] && cat <<POOL_CREDS
   Pool JWT_SECRET:              ${JWT_SECRET}
   Pool wallet passphrase:       ${POOL_WALLET_PASSPHRASE}
POOL_CREDS
)
$( [ "$INSTALL_FAUCET" = "true" ] && cat <<FAUCET_CREDS
   Faucet DB password:           ${FAUCET_DB_PASS}
   Faucet DB root password:      ${FAUCET_DB_ROOT_PASS}
   Faucet admin password:        ${FAUCET_ADMIN_PASS}
   Faucet wallet passphrase:     ${FAUCET_WALLET_PASSPHRASE}
   hCaptcha site key:            ${FAUCET_HCAPTCHA_SITE:-"(not set)"}
   hCaptcha secret key:          ${FAUCET_HCAPTCHA_SECRET:-"(not set)"}
FAUCET_CREDS
)
$( [ "$INSTALL_MEMPOOL" = "true" ] && cat <<MEMPOOL_CREDS
   Mempool DB password:          ${MEMPOOL_DB_PASS}
   Mempool DB root password:     ${MEMPOOL_DB_ROOT_PASS}
MEMPOOL_CREDS
)

 Newly generated on this run:
   ${GENERATED_SECRETS:-"(nothing -- everything above came from a previous run or was supplied by you)"}
 Reused from a previous run (unchanged, no reset):
   ${REUSED_SECRETS:-"(nothing -- this was the first run)"}
 Everything else above you supplied yourself (config file/prompt).
 ----------------------------------------------------------------------------

 NEXT STEPS:
$( { [ "$INSTALL_POOL" = "true" ] || [ "$INSTALL_FAUCET" = "true" ]; } && cat <<PREPAID_NEXT
 - Fund the wallet address(es) above from your prepaid balance with ELEK
   (keep the hot wallet small).
PREPAID_NEXT
)
$( [ "$INSTALL_FAUCET" = "true" ] && cat <<FAUCET_NEXT
 - https://${FAUCET_DOMAIN}/admin.php -> Settings -> get "Test RPC
   connection" and "Test wallet unlock" green.
 - Delete public/install.php in the faucet:
   docker compose -f ${STACK_DIR}/docker-compose.yml exec elektron-faucet-app rm -f public/install.php
 - Fill in the hCaptcha keys if they were left blank when running the script.
FAUCET_NEXT
)
$( [ "$INSTALL_POOL" = "true" ] && cat <<POOL_NEXT
 - elektron-net-ppool/.env: keep PAYOUT_DRY_RUN=true until you've checked
   a simulated payout in the log, then switch it to false and run
   'docker compose --profile pool up -d --force-recreate elektron-ppool'.
POOL_NEXT
)
 - If not done yet: create AAAA records at your DNS provider
   (${NODE_DOMAIN}$( [ "$INSTALL_POOL" = "true" ] && echo ", ${POOL_DOMAIN}" )$( [ "$INSTALL_FAUCET" = "true" ] && echo ", ${FAUCET_DOMAIN}" ) -> ${SERVER_IPV6}).
   P2P (8333)$( [ "$INSTALL_POOL" = "true" ] && echo ", Stratum (3333)" ) and Caddy (80/443) are already
   published dual-stack -- once the AAAA record exists, everything works
   over IPv6 too.
 - Optional, but recommended for a public seed node: set reverse DNS
   (PTR) for ${SERVER_IPV6} in your provider's panel (networking section)
   -- e.g. pointing to ${NODE_DOMAIN} -- many peers weight this
   positively in node reputation.
$( [ "$INSTALL_SEEDER" = "true" ] && cat <<SEEDER_NEXT
 - Test the seeder before linking it in production:
   dig -t NS ${SEEDER_HOST}            (must point to ${SEEDER_NS})
   dig @${SERVER_IP} -p 53 ${SEEDER_HOST}   (works even before the delegation has propagated)
   docker compose -f ${STACK_DIR}/docker-compose.yml logs -f elektron-net-seeder
SEEDER_NEXT
)

 Note on the private network IP (provider VLAN/vSwitch, e.g. Hetzner's):
 not currently needed by this stack -- all containers communicate
 internally over Docker's own networks. Only becomes relevant if you
 later, say, move the wallet to a second, isolated server (see the
 ppool README, section 9, "network-isolated wallet server").

 ----------------------------------------------------------------------------
 USEFUL COMMANDS (see also the README, "Updating the stack"):

   Status of all containers:
     docker compose -f ${STACK_DIR}/docker-compose.yml ps
   Follow logs (e.g. the node):
     docker compose -f ${STACK_DIR}/docker-compose.yml logs -f elektron-net
   Node sync status (RPC credentials needed, since "docker compose exec"
   runs as root and automatic cookie-file discovery doesn't work then):
     docker compose -f ${STACK_DIR}/docker-compose.yml exec elektron-net elektron-cli -rpcuser=${RPC_USER} -rpcpassword=${RPC_PASSWORD} getblockchaininfo
   Restart just one service after a .env change:
     docker compose -f ${STACK_DIR}/docker-compose.yml up -d --force-recreate <service>
   View this summary again at any time:
     cat ${SUMMARY_FILE}
 ----------------------------------------------------------------------------

 This summary gets rewritten here on every (re-)run of the script:
 ${SUMMARY_FILE}
 The underlying raw data also lives permanently in:
$( [ "$INSTALL_POOL" = "true" ] && echo "   ${STACK_DIR}/elektron-net-ppool/.env" )
$( [ "$INSTALL_FAUCET" = "true" ] && echo "   ${STACK_DIR}/elektron-net-faucet/.env" )
   ${STACK_DIR}/elektron-net/bitcoin.conf  (rpcauth hash, not the plaintext password)
$( [ "$INSTALL_MEMPOOL" = "true" ] && echo "   ${STACK_DIR}/elektron-net-mempool/.env" )
 (all chmod 600, don't commit them.)

$( { [ "$INSTALL_POOL" = "true" ] || [ "$INSTALL_FAUCET" = "true" ]; } && cat <<WALLET_WARNING
 IMPORTANT: encryptwallet is a one-way operation -- ${INSTALLED_WALLETS_LABEL} ${INSTALLED_WALLETS_VERB} now encrypted. The passphrases above live ONLY in this file${INSTALLED_WALLET_ENV_REFS} -- plus in the complete private-key export further up. There is no
 other copy, not even on the blockchain. If you lose one of these
 files, the respective wallet balance can no longer be spent.
WALLET_WARNING
)

$( [ "$INSTALL_FAUCET" = "true" ] && cat <<FAUCET_APP_KEY_NOTE
 One more important location: the faucet app generates its own
 encryption key for data "at rest" (FAUCET_APP_KEY) the first time it
 starts and writes it ONLY to ${STACK_DIR}/data/faucet-config/config.php
 -- it lives in no .env and isn't managed by this script, but belongs to
 the same threat model as everything else here (back it up too, chmod 600).
FAUCET_APP_KEY_NOTE
)

 ----------------------------------------------------------------------------
 EXTERNAL / SELF-GENERATED WALLETS
 (every file in ${EXTERNAL_WALLETS_DIR}/ -- e.g. a prepaid wallet
 generated offline with your own script such as generate_address.py --
 stays its own separate file with chmod 600. Only name + path are listed
 here as a reference, the actual private key lives ONLY in that file
 itself, not additionally here. Drop any files there, and they'll show
 up in this list starting with the next run.)
${EXTERNAL_WALLETS_BLOCK}
============================================================================
SUMMARY
} | tee "$SUMMARY_FILE"
chmod 600 "$SUMMARY_FILE"
# In case the faucet app has already written its FAUCET_APP_KEY (see the
# note above) -- just a best-effort chmod, no error if it doesn't exist
# yet (the container may still need a few seconds).
if [ -f "${STACK_DIR}/data/faucet-config/config.php" ]; then
  chmod 600 "${STACK_DIR}/data/faucet-config/config.php" 2>/dev/null || true
fi
