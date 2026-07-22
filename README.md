# Elektron Net Stack - Self-Hosted Installation Guide

Includes: `elektron-net` (seed node), `elektron-net-ppool` + `elektron-net-ppool-ui`
(PPLNS pool), `elektron-net-faucet`, `elektron-net-mempool` (block explorer,
see ["Mempool Explorer (optional)"](#mempool-explorer-optional)). A Caddy
instance acts as the shared HTTPS reverse proxy. Optional, still in testing:
`elektron-net-seeder` (DNS crawler, see
["Seeder (optional, testing phase)"](#seeder-optional-testing-phase)) - not
installed by default, completely skipped on a normal run.

Pool, Faucet, Seeder and Mempool are all individually installable
components (see `INSTALL_POOL`/`INSTALL_FAUCET`/`INSTALL_SEEDER`/`INSTALL_MEMPOOL`
below) - only the node and Caddy are mandatory, since every other
component depends on the node and is reachable through Caddy.

This guide works on any server/VPS with a public IPv4 (and ideally IPv6)
address and root access - it isn't tied to a specific hosting provider.
Wherever a provider-specific detail is unavoidable (e.g. a particular
cloud panel), it's called out explicitly as an example; substitute your
own provider's equivalent feature.

## Quickstart (automated)

Steps 1-7 further down (clone repos, generate RPC credentials, fill in
`.env` files, start the node, create wallets, open the firewall) are all
handled automatically by `install-elektron-stack.sh`. All passwords (RPC,
JWT_SECRET, DB, wallet passphrase, faucet admin) are generated securely
unless you supply your own. The only manual parts are the **DNS records
(step 1)** and a short wait while the node syncs - everything else runs
in one pass.

**All credentials end up collected in one file on the server:**
`$STACK_DIR/ZUGANGSDATEN.txt` (default: `/opt/elektron-net-stack/ZUGANGSDATEN.txt`),
automatically `chmod 600`. Contains RPC/DB/wallet passwords, JWT_SECRET,
faucet admin login, pool/faucet wallet addresses, domains/IPs and a
command reference - rewritten on every (re-)run of the script, so you
never have to copy anything down from the one-time terminal output.

**Both wallets (pool and faucet) get encrypted.** The pool wallet
passphrase (`WALLET_PASSPHRASE` in `elektron-net-ppool/.env`) is
generated automatically, just like the faucet passphrase, unless you
supply your own; `ppool` then unlocks the wallet automatically for
`WALLET_UNLOCK_SECONDS` on every payout run and locks it again
immediately afterward. Without this, any real payout fails with RPC
error `-13` as soon as `PAYOUT_DRY_RUN=false` is set.

For a **truly complete backup** the script additionally creates (once,
the first time each wallet is set up) - each wallet deliberately gets its
own, separately protectable file instead of bundling everything into one
giant file:

- `$STACK_DIR/data/elektron-net/pool-wallet-privkeys-backup.txt` and
  `.../faucet-wallet-privkeys-backup.txt` - a full export of the
  **private keys** of the pool and faucet wallet (`dumpwallet`, falling
  back to `listdescriptors true` depending on what the wallet supports).
  The passphrase alone is not enough in a disaster scenario - it only
  unlocks an already-existing wallet file; this export is the actual
  recovery basis.
- Anything you place yourself as its own file under
  `$STACK_DIR/external-wallets/` (e.g. a prepaid wallet with a private
  key/WIF generated offline with your own script such as
  `generate_address.py`) - see ["Getting files onto the
  server"](#getting-files-onto-the-server-browser-console-only-windows)
  for ways to get it there. The script automatically sets `chmod 600` on
  every file placed there.

One more location that this script does not manage but is just as
sensitive: the faucet app generates its own encryption key ("secrets at
rest", `FAUCET_APP_KEY`) the first time it starts and writes it directly
to `$STACK_DIR/data/faucet-config/config.php` - it lives in no `.env`
file, but gets backed up along with everything else if you include
`data/` in your backups.

`ZUGANGSDATEN.txt` itself does **not** duplicate these wallet files - it
only lists filename and path as a reference, so each wallet secret lives
in exactly one place instead of lying around in plaintext multiple
times. RPC/DB/JWT/faucet-admin passwords, on the other hand, sit directly
in `ZUGANGSDATEN.txt`, since there is no separate wallet file for those.

Even so, `ZUGANGSDATEN.txt` remains the central, sensitive overview file
of the stack. Back it up offline once (SFTP/SCP) - ideally together with
the referenced wallet files - then keep it locked down on the server,
never send it by plaintext email or upload it anywhere.

Get the script (and optionally your filled-in config file, see below)
onto the server - how exactly depends on your access, see ["Getting
files onto the server"](#getting-files-onto-the-server-browser-console-only-windows)
below if you only have a browser-based console. Then:

```bash
chmod +x install-elektron-stack.sh
./install-elektron-stack.sh
```

For the server-specific values (domains, IPv4/IPv6, GitHub user,
hCaptcha keys, Let's Encrypt email) you have two equally valid options -
sensitive data never has to be entered into a file in the repo
beforehand:

1. **Type it in at the console:** if the script runs in a terminal, it
   asks for every value individually, showing the current default in
   `[...]` - press Enter to keep it. Installation then takes only a
   handful of keystrokes - **you don't need to upload a single file for
   this.**
2. **Config file:** copy `elektron-stack.conf.example` to
   `elektron-stack.conf`, fill in your values there, place the file next
   to `install-elektron-stack.sh` (or point to it with `--config
   /path/to/file`). The script automatically picks up an
   `elektron-stack.conf` in the same directory. Anything left blank in
   there is still asked interactively, or filled in fully automatically
   (built-in default / auto-generated) with `--yes` - handy for
   unattended/CI runs.

`elektron-stack.conf` is never committed (see `.gitignore`) - feel free
to keep it directly on the server without checking it into the repo.

**Important:** the actual `.env` files and `bitcoin.conf` in the
subfolders (`elektron-net-ppool/.env`, `elektron-net-faucet/.env`,
`elektron-net/bitcoin.conf`) never need to be uploaded or copied in
yourself when using the script - it writes them entirely on its own,
from your console answers or from `elektron-stack.conf`. Manually
copying the `*.example` templates in step 2 below is only needed for the
fully manual path without the script.

The script is idempotent: already-cloned repos, already-existing
wallets, etc. are detected and skipped, so a rerun (e.g. after a server
reboot, or to pick up one changed setting) never breaks anything.

Details for each individual step - e.g. if you'd rather walk through
everything by hand, or want to debug something - are in sections 0-8
below; the script automates exactly what's described there.

## Getting files onto the server (browser console only, Windows)

If you only have a **browser-based console** (a VNC-style window in your
provider's web panel, e.g. Hetzner Cloud's "Console" tab, DigitalOcean's
"Droplet Console", Vultr's or Linode's browser console) and haven't set
up SSH access yet, there's naturally no drag-and-drop file upload there.
Three approaches, from simplest to most involved:

**A) Don't upload anything - download directly on the server.** This
repo is public, so you can fetch both files straight from the browser
console with `curl`, no local/Windows step needed at all:

```bash
curl -O https://raw.githubusercontent.com/kutlusoy/elektron-net-stack/main/install-elektron-stack.sh
chmod +x install-elektron-stack.sh
./install-elektron-stack.sh
```

If you then use interactive console input (option 1 above), you don't
need a config file at all - just type the values directly into the
browser window, done.

**B) Create `elektron-stack.conf` on the server - no interactive typing
on every run.** This way you fill in all the values once, save the file
permanently on the server, and the script reads it automatically on
every (re-)run - no more prompts. Step by step:

**1. Open the browser console** (your provider's cloud panel -> your
server -> "Console" tab) and log in.

**2. Create a working directory** (any location, `/root` here):

```bash
mkdir -p ~/elektron-net-stack-install
cd ~/elektron-net-stack-install
```

**3. Download the script and config template** (the repo is public, no
login needed):

```bash
curl -O https://raw.githubusercontent.com/kutlusoy/elektron-net-stack/main/install-elektron-stack.sh
curl -O https://raw.githubusercontent.com/kutlusoy/elektron-net-stack/main/elektron-stack.conf.example
chmod +x install-elektron-stack.sh
```

**4. Copy the template** (the `.example` file itself stays untouched as
a reference, you only edit the copy):

```bash
cp elektron-stack.conf.example elektron-stack.conf
```

**5. Edit the config file with `nano`:**

```bash
nano elektron-stack.conf
```

`nano` opens the file directly in the terminal. Navigate with the arrow
keys, overwrite values after the `=`. The most important shortcuts are
shown at the bottom of `nano`'s footer (`^` means Ctrl):

| Key | Action |
|---|---|
| `Ctrl+O`, then `Enter` | Save (write out) |
| `Ctrl+X` | Exit (after saving) |
| `Ctrl+K` | Cut current line |
| `Ctrl+W` | Search |

Fill in at least these values (everything else can stay at its default,
see `elektron-stack.conf.example` for every field with an explanation):

```ini
GITHUB_USER=kutlusoy
SERVER_IP=YOUR_SERVER_IPV4
SERVER_IPV6=YOUR_SERVER_IPV6
NODE_DOMAIN=node.example.com
POOL_DOMAIN=pool.example.com
FAUCET_DOMAIN=faucet.example.com
CADDY_EMAIL=you@example.com
FAUCET_HCAPTCHA_SITE=your-hcaptcha-site-key
FAUCET_HCAPTCHA_SECRET=your-hcaptcha-secret-key
```

All password/secret fields (`JWT_SECRET`, `FAUCET_DB_PASS`,
`FAUCET_WALLET_PASSPHRASE`, `FAUCET_ADMIN_PASS`, ...) can be left blank -
the script generates them securely on its own when it runs.

For values you copy from your own machine (e.g. hCaptcha keys): most
browser consoles (Hetzner's included) have a keyboard/clipboard icon
("Paste text" or similar) in the toolbar - use it to paste text from
your local clipboard directly into the console instead of typing long
values by hand.

**6. Restrict permissions** (the file is about to hold real credentials):

```bash
chmod 600 elektron-stack.conf
```

**7. Install.** Since `elektron-stack.conf` sits in the same directory as
the script, it's found automatically - no `--config` flag needed. With
`--yes` everything runs through without any prompts:

```bash
./install-elektron-stack.sh --yes
```

If a value the script needs is still missing from the file, it gets
filled in with the built-in default or auto-generated anyway - `--yes`
never aborts, it just doesn't ask.

**8. Want to change something later?** Just reopen `nano elektron-stack.conf`,
adjust the value, save, and run `./install-elektron-stack.sh --yes`
again. The script is idempotent: already-existing repos, wallets,
secrets, RPC credentials and wallet addresses are detected and reused
unchanged instead of being regenerated - a rerun never rotates
credentials that running containers already use. Details and faster
alternatives (restarting just the affected container instead of the
whole script) are under ["Updating the stack"](#updating-the-stack)
below.

**C) A real file upload from your own machine - needs SSH/SFTP.** This
only works once SSH is reachable on the server, not through the plain
browser console. First check whether SSH already works (Windows 10/11
have a built-in OpenSSH client, open PowerShell or Windows Terminal):

```powershell
ssh root@YOUR_SERVER_IPV4
```

The root password is usually shown once when the server is created, or
sent in a confirmation email by your provider - if you set up an SSH key
instead, you'll be logged in automatically without a password. Once
connected, you can:

- use **[WinSCP](https://winscp.net)** (graphical, drag-and-drop) - new
  connection with protocol SFTP, host = your server's IP, user `root`.
- or directly in PowerShell: `scp .\elektron-stack.conf root@YOUR_SERVER_IPV4:/opt/elektron-net-stack/`

If SSH doesn't respond: check whether port 22 is allowed for your
network in your provider's separate firewall panel, if it has one (e.g.
Hetzner Cloud Firewall, AWS Security Groups) - most base images already
have an SSH server preinstalled and running, so an overly strict
network-level firewall is usually the culprit.

## Pre-filling values locally and uploading via SFTP

If you have SFTP/SCP access (see above), you can prepare everything
comfortably on your own machine and then upload it fully filled in,
instead of typing on the server. What matters is **which file** you use
for this:

**The right file: `elektron-stack.conf`.** This is the only file meant
to be filled in ahead of time, with its values carried over permanently:

1. Locally copy `elektron-stack.conf.example` to `elektron-stack.conf`
   and fill it in (see all fields below and commented in the file
   itself).
2. Upload via SFTP/WinSCP/`scp` **into the same folder as
   `install-elektron-stack.sh`** (e.g. `/opt/elektron-net-stack/elektron-stack.conf`,
   if that's where you place the script - the exact folder doesn't
   matter, as long as both files sit together).
3. `./install-elektron-stack.sh --yes` - the file is found
   automatically, all values are carried over 1:1, anything left blank
   is auto-generated. No typing on the server needed at all.

**Not the right choice: uploading the raw `.env` files/`bitcoin.conf`
themselves ahead of time and expecting them to stay untouched.** The
script rewrites `elektron-net/bitcoin.conf`, `elektron-net-ppool/.env`
and `elektron-net-faucet/.env` completely on **every** run (from its own
template) - a pre-uploaded, hand-written version of these files would
mostly get overwritten on the first run. The one exception: a handful of
specific secret fields (`JWT_SECRET`, `WALLET_PASSPHRASE`,
`FAUCET_WALLET_PASS`, `FAUCET_DB_PASS`, `FAUCET_DB_ROOT_PASS`,
`FAUCET_ADMIN_PASS`, the RPC password via `bitcoin.conf`'s `rpcauth`
line) are detected and carried over unchanged if they're already present
in a file at the target location (`$STACK_DIR/...`) - that's exactly the
mechanism that makes reruns idempotent (see "Updating the stack" below),
but it's not a general way to pre-supply arbitrary content. **For
anything you want to determine yourself, the value belongs in
`elektron-stack.conf`, not directly in the target file.**

What you can pre-set in `elektron-stack.conf` - the complete list is in
`elektron-stack.conf.example` with comments, summarized here:

| Area | Fields |
|---|---|
| Server/domains | `GITHUB_USER`, `SERVER_IP`, `SERVER_IPV6`, `NODE_DOMAIN`, `POOL_DOMAIN`, `FAUCET_DOMAIN`, `CADDY_EMAIL` |
| Node/firewall | `RPC_USER`, `FIREWALL_AUTO_CONFIGURE` |
| Repo updates | `AUTO_UPDATE_REPOS` (blank/`false` = never auto-update, see "Updating the stack") |
| Pool (optional, on by default) | `INSTALL_POOL` (default `true`, Compose profile "pool"; disabling it also closes Stratum port 3333 again) |
| Pool behavior | `POOL_IDENTIFIER`, `POOL_FEE_PERCENT`, `PPLNS_WINDOW_MINUTES`, `MIN_PAYOUT_THRESHOLD_SATS`, `PAYOUT_INTERVAL_MINUTES`, `PAYOUT_CONFIRMATIONS_REQUIRED`, `PAYOUT_DRY_RUN`, `STRATUM_PORT`, `API_PORT` |
| Pool wallet | `POOL_WALLET_NAME`, `POOL_WALLET_PASSPHRASE` (blank = auto), `WALLET_UNLOCK_SECONDS` |
| Pool notifications (optional) | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_BOT_USERNAME`, `DISCORD_BOT_TOKEN`, `DISCORD_BOT_CLIENTID`, `DISCORD_BOT_GUILD_ID`, `DISCORD_BOT_CHANNEL_ID` |
| Faucet (optional, on by default) | `INSTALL_FAUCET` (default `true`, Compose profile "faucet"; no port of its own, runs behind Caddy) |
| Faucet wallet/DB | `FAUCET_WALLET_NAME`, `FAUCET_WALLET_PASSPHRASE` (blank = auto), `FAUCET_DB_NAME`, `FAUCET_DB_USER`, `FAUCET_DB_PASS`/`FAUCET_DB_ROOT_PASS` (blank = auto) |
| Faucet login | `FAUCET_ADMIN_USER`, `FAUCET_ADMIN_PASS` (blank = auto) |
| Faucet business rules | `FAUCET_HCAPTCHA_SITE`/`_SECRET`, `FAUCET_TITLE`, `FAUCET_MESSAGE`, `FAUCET_AMOUNT_ELEK`, `FAUCET_DAILY_BUDGET`, `FAUCET_HOURLY_BUDGET`, `FAUCET_PER_ADDR_COOLDOWN_H`, `FAUCET_PER_IP_COOLDOWN_H`, `FAUCET_DEFAULT_LANG`, `FAUCET_EXPLORER_URL` |
| Secrets (always auto, if blank) | `JWT_SECRET`, RPC password (no field for it - always generated) |
| Seeder (optional, off by default) | `INSTALL_SEEDER` (default `false`), `SEEDER_HOST`, `SEEDER_NS`, `SEEDER_MBOX`, `SEEDER_DNS_PORT`, `SEEDER_THREADS`, `SEEDER_DNS_THREADS` - see ["Seeder (optional, testing phase)"](#seeder-optional-testing-phase) |
| Mempool Explorer (optional, on by default) | `INSTALL_MEMPOOL` (default `true`), `MEMPOOL_DOMAIN`, `MEMPOOL_DB_NAME`, `MEMPOOL_DB_USER`, `MEMPOOL_DB_PASS`/`MEMPOOL_DB_ROOT_PASS` (blank = auto), `MEMPOOL_INDEXING_BLOCKS_AMOUNT`, `MEMPOOL_ACCELERATOR` (default `true`, see ["Mempool Explorer (optional)"](#mempool-explorer-optional)) |

Fields the script fills in automatically after wallet creation
(`POOL_WALLET_ADDRESS`, `FAUCET_SENDER_ADDR`) do **not** belong in
`elektron-stack.conf` - you can't pre-supply those at all, they only
come into existence live during the run.

**On Telegram/Discord:** both are purely optional (miner notifications
in the pool). Leaving them blank disables them cleanly - the ppool
application itself checks whether all required fields are set and
otherwise turns itself off without throwing an error. For Discord all
four fields must be set together (token, client ID, guild ID, channel
ID), otherwise the integration stays inactive.

If you get `/usr/bin/env: 'bash\r': No such file or directory` when
running it - see [Troubleshooting](#troubleshooting) at the very bottom.

## Updating the stack

Three different situations, each with its own matching approach. Short
version first, details below:

| What changed? | What to do? |
|---|---|
| A setting in `elektron-stack.conf` (domain, hCaptcha key, payout parameter, ...) | `nano elektron-stack.conf` -> `./install-elektron-stack.sh --yes` |
| Source code of one of the repos (new version on GitHub) | `git pull` in that folder -> `docker compose up -d --build <service>` |
| Caddy or MariaDB image (upstream update) | `docker compose --profile pool --profile faucet --profile mempool pull caddy elektron-faucet-db elektron-mempool-db` -> `docker compose --profile pool --profile faucet --profile mempool up -d` |

### A) Just one setting changed

```bash
cd ~/elektron-net-stack-install   # or wherever elektron-stack.conf lives
nano elektron-stack.conf          # change the value, save
./install-elektron-stack.sh --yes
```

This is the simplest way, and safe on repeated calls thanks to the
script's idempotency safeguards: JWT_SECRET, all faucet passwords, the
RPC password and the pool/faucet wallet addresses are **recognized and
carried over unchanged** from the previous run instead of being
regenerated - a rerun never rotates credentials that running containers
already use, and never sends you to a new, empty wallet address. At the
end of the run the summary shows which values were "newly generated" vs.
"reused".

Faster, if you only want to touch a single file (without re-running the
DNS/firewall checks): edit the target file directly and only recreate
the affected service:

```bash
cd /opt/elektron-net-stack
nano elektron-net-faucet/.env        # or elektron-net-ppool/.env, caddy/Caddyfile, elektron-net/bitcoin.conf
docker compose --profile faucet up -d --force-recreate elektron-faucet-app   # use --profile pool instead of --profile faucet for ppool/.env
```

| Changed file | Service to recreate |
|---|---|
| `caddy/Caddyfile` | `caddy` |
| `elektron-net-ppool/.env` (only if `INSTALL_POOL=true`) | `docker compose --profile pool up -d --force-recreate elektron-ppool` (don't forget `--profile pool`, otherwise Compose ignores the service) |
| `elektron-net-ppool-ui` environment (only if `INSTALL_POOL=true`) | `docker compose --profile pool up -d --force-recreate elektron-ppool-ui` |
| `elektron-net-faucet/.env` (only if `INSTALL_FAUCET=true`) | `docker compose --profile faucet up -d --force-recreate elektron-faucet-app` (don't forget `--profile faucet`, otherwise Compose ignores the service) |
| `elektron-net/bitcoin.conf` | `elektron-net` (brief node restart, P2P offline for a moment) |
| `elektron-net-mempool/.env` (only if `INSTALL_MEMPOOL=true`) | `docker compose --profile mempool up -d --force-recreate elektron-mempool-api elektron-mempool-web` |
| `elektron-net-seeder/.env` (only if `INSTALL_SEEDER=true`) | `docker compose --profile seeder up -d --force-recreate elektron-net-seeder` (don't forget `--profile seeder`, otherwise Compose ignores the service) |

**Careful:** changing `FAUCET_DB_PASS`, `FAUCET_DB_ROOT_PASS` or
`FAUCET_WALLET_PASSPHRASE` by hand in the `.env` breaks the connection to
the already-initialized MariaDB or the already-encrypted wallet - don't
touch these three by hand after initial setup (the script itself already
leaves them untouched on a rerun, see above).

### B) Source code update (elektron-net, -ppool, -ppool-ui, -faucet, -mempool)

**Automatically on a script run:** answer "yes" to the question *"Check
the cloned repos for updates before building ...?"* (asked right at the
start, before the other prompts), or set `AUTO_UPDATE_REPOS=true` in
`elektron-stack.conf`. The script then fetches the latest commits for
every already-cloned repo via `git fetch`, shows them, and applies them
via `git pull --ff-only` - never force/rebase; a locally diverged branch
(e.g. because you committed something yourself) is only reported, never
touched. The final `docker compose up -d --build` then automatically
builds the updated repos in. By default (Enter/`n`) nothing changes - a
rerun then deliberately fetches **no** new commits, so a normal rerun
(e.g. just to change one setting) never unexpectedly updates code.

**Manually, targeted at one repo:** if you just want to update this one
time, without using the prompt in the script - `git pull` yourself, then
rebuild only the affected container:

```bash
cd /opt/elektron-net-stack/elektron-net-ppool   # the repo with the new version
git pull
cd /opt/elektron-net-stack
docker compose up -d --build elektron-ppool     # rebuilds only this image and replaces the container
```

Service names for the other repos: `elektron-net`, `elektron-ppool-ui`,
`elektron-faucet-app`, `elektron-mempool-api`/`elektron-mempool-web`
(only if `INSTALL_MEMPOOL=true` - the build context for the latter is
re-staged from `elektron-net-mempool/docker/` on every script run, so a
plain `git pull` without rerunning the script isn't enough by itself,
see ["Mempool Explorer"](#mempool-explorer-optional)). For all repos at
once:

```bash
cd /opt/elektron-net-stack
for d in elektron-net elektron-net-ppool elektron-net-ppool-ui elektron-net-faucet elektron-net-mempool elektron-net-electrs; do
  [ -d "$d" ] && (cd "$d" && git pull)
done
docker compose --profile pool --profile faucet --profile mempool up -d --build   # only pass the profiles you actually have enabled (INSTALL_POOL/FAUCET/MEMPOOL)
```

### C) Updating Docker images (Caddy, MariaDB)

`caddy`, `elektron-faucet-db` (if `INSTALL_FAUCET=true`) and (if
`INSTALL_MEMPOOL=true`) `elektron-mempool-db` are ready-made images from
Docker Hub (no build of your own) - pull the new version and restart the
containers with it:

```bash
cd /opt/elektron-net-stack
docker compose --profile faucet --profile mempool pull caddy elektron-faucet-db elektron-mempool-db
docker compose --profile faucet --profile mempool up -d
```

The database data lives in the bind mounts `./data/faucet-db` and
`./data/mempool-db` respectively and survives the image update (MariaDB
minor updates are backward-compatible; check their release notes first
before a major version jump).

### Everything at once (maintenance window)

```bash
cd /opt/elektron-net-stack
for d in elektron-net elektron-net-ppool elektron-net-ppool-ui elektron-net-faucet elektron-net-mempool elektron-net-electrs; do
  [ -d "$d" ] && (cd "$d" && git pull)
done
docker compose --profile pool --profile faucet --profile mempool pull
docker compose --profile pool --profile faucet --profile mempool up -d --build
```

Quick note: restarting the `elektron-net` container briefly interrupts
P2P operation (seconds to a few minutes, until the node is back in
sync) - pick a quiet time for the node; pool and faucet can be restarted
independently of it.

## Importing external wallets (WIF/private key)

Did you generate an address offline (e.g. with
`elektron-net/mining/generate_address.py`, like the file in
`external-wallets/`) and want to make the private key usable somewhere -
to spend from it, to watch it, or to add it to a GUI wallet -
**important:** `importprivkey` and `dumpwallet` no longer exist in this
fork (`error code: -32601, Method not found`, tested live). Like modern
Bitcoin Core, it exclusively uses descriptor wallets; the replacement is
`importdescriptors`. Three ways, depending on where you want to do the
import:

### A) On the server, into the running node (CLI)

Uses the already-running `elektron-net` container from this stack - no
extra program needed:

```bash
cd /opt/elektron-net-stack

# 1. Create a dedicated wallet for this (separate from pool/faucet,
#    without auto-generated keys)
docker compose exec elektron-net elektron-cli createwallet "prepaid" false true

# 2. Get the checksum for the descriptor -- combo(...) derives all three
#    standard address formats from it (P2PKH, P2SH-SegWit, P2WPKH/bech32),
#    not just one:
docker compose exec elektron-net elektron-cli getdescriptorinfo "combo(<WIF>)"
# -> copy the "checksum" field from the response, e.g. "7xr75u5v"

# 3. Import using the WIF + checksum
docker compose exec elektron-net elektron-cli -rpcwallet=prepaid importdescriptors \
  '[{"desc": "combo(<WIF>)#<checksum>", "timestamp": 0, "label": "prepaid-import"}]'
```

`timestamp`: **`0`** scans the entire chain for UTXOs already belonging
to this address - needed if ELEK was already sent to it before the
import (can take over an hour for a very old address, per Bitcoin Core's
docs). **`"now"`** skips scanning entirely, only useful for a
brand-new, never-used key.

Afterward it's usable normally: `docker compose exec elektron-net
elektron-cli -rpcwallet=prepaid getbalance`, `sendtoaddress`,
`listunspent`, etc.

### B) Locally on Windows - official GUI wallet (elektron-qt)

For when you want to manage the key locally on your own Windows machine
instead of on the server, without compiling anything yourself:

1. Download the official release: [github.com/kutlusoy/elektron-net/releases](https://github.com/kutlusoy/elektron-net/releases)
   - either the portable ZIP or the setup installer
   (`elektron-net-windows-*_portable.zip` or `..._setup.exe`).
2. Start `elektron-qt.exe` (the GUI, equivalent to Bitcoin-Qt - runs as
   its own, fully independent node, syncing with the Elektron Net
   network on its own).
3. **There is no dedicated "import private key" dialog in the GUI** -
   that was never the case in Bitcoin-Qt either. Instead: open menu
   **Help -> Debug window -> Console** and type in exactly the same
   three commands as under A) (without the `docker compose exec
   elektron-net` prefix - the console already talks directly to the
   local node):
   ```
   createwallet "prepaid" false true
   getdescriptorinfo "combo(<WIF>)"
   importdescriptors [{"desc": "combo(<WIF>)#<checksum>", "timestamp": 0, "label": "prepaid-import"}]
   ```
4. Balances/addresses then appear in the GUI's normal wallet tab.

This local GUI wallet is completely independent of the server-side stack
- it syncs its own copy of the chain and has nothing to do with the
pool/faucet wallets on the server.

### C) Other methods (briefly)

- **Plain `elektron-cli` without a GUI**, e.g. on a second server or
  locally: the same three commands from A), just directly against the
  locally running `elektrond` instead of via `docker compose exec`.
- **Watch-only, unable to spend** (no private key in the target
  wallet): `createwallet "watch-only" true` (the second parameter,
  `disable_private_keys`, makes it watch-only), then
  `importdescriptors` with a descriptor **without** a private key (just
  the address/public key), e.g. `addr(<address>)` instead of
  `combo(<WIF>)`.
- All paths end up producing the same addresses from the same key -
  which method you use only depends on where you want to use the key,
  not on any technical restriction.

## 0. Prerequisite

Docker CE + Compose plugin already installed. Check:
```bash
docker version
docker compose version
```

## 1. Set up DNS

A records (all pointing to your server's public IPv4, e.g.
`203.0.113.10` in the example below) AND AAAA records (all pointing to
your server's IPv6 address, e.g. `2001:db8::1` - check your provider's
panel for the exact value):

| Subdomain | Type | Target |
|---|---|---|
| `node.example.com` | A | 203.0.113.10 |
| `node.example.com` | AAAA | 2001:db8::1 |
| `pool.example.com` | A | 203.0.113.10 |
| `pool.example.com` | AAAA | 2001:db8::1 |
| `faucet.example.com` | A | 203.0.113.10 |
| `faucet.example.com` | AAAA | 2001:db8::1 |

Create these at whichever DNS provider hosts your domain, as a plain
A record for the subdomain (e.g. `faucet`), with a matching AAAA record.

Briefly wait/check: `dig +short pool.example.com` and
`dig +short AAAA pool.example.com` should each return the right IP
before you start Caddy (otherwise the Let's Encrypt request fails).

**IPv6 in the stack:** P2P (8333), Stratum (3333) and Caddy (80/443) are
published in the included `docker-compose.yml` using the plain form
(`"PORT:PORT"`, without a host IP) - Docker itself (from Docker Engine
27 onward, tested with 27.5.1) automatically sets up two `docker-proxy`
processes, one for `0.0.0.0` (IPv4) and one for `[::]` (IPv6), and
forwards both to the (internally still IPv4-based) container. This needs
no Docker daemon configuration and no additional `"[::]:PORT:PORT"`
line - an earlier version of this file had exactly such a line set
explicitly, which causes `Error ... bind: address already in use` on
some Docker versions (the explicit entry collides with Docker's own
automatic IPv6 binding). Once the AAAA records above exist, everything
is automatically reachable over IPv6 too - check with `ss -tlnp | grep
<port>`, which should show both a `0.0.0.0` and a `[::]` line with
`docker-proxy`.

**Private network IP (provider VLAN/vSwitch, e.g. Hetzner's vSwitch):**
not used by this stack currently - all containers communicate
internally over their own Docker networks (`backend`/`web`). This only
becomes relevant if you later, say, move the wallet to a second,
isolated server (see the `elektron-net-ppool` README, section on the
"network-isolated wallet server" topology).

**Reverse DNS (PTR) for IPv6:** many providers only auto-assign a
reverse DNS entry for IPv4 by default, leaving IPv6 unset (check your
provider's networking panel). For a public seed node it's worth setting
a PTR record for the IPv6 address too (e.g. pointing to
`node.example.com`) - some peers weight missing/suspicious rDNS
negatively in node reputation. Optional, but recommended.


## 2. Clone the repos

```bash
mkdir -p /opt/elektron-net-stack && cd /opt/elektron-net-stack

git clone https://github.com/kutlusoy/elektron-net.git
git clone https://github.com/kutlusoy/elektron-net-ppool.git
git clone https://github.com/kutlusoy/elektron-net-ppool-ui.git
git clone https://github.com/kutlusoy/elektron-net-faucet.git
```

Then copy the files from this package **into the same structure**
(overwrites nothing existing, only adds). The `*.example` files are
templates - drop the `.example` extension when copying (see target name
on the right):

```
/opt/elektron-net-stack/
├── docker-compose.yml                      <- from this package
├── caddy/Caddyfile                         <- from this package
├── elektron-net/
│   ├── Dockerfile                          <- from this package (doesn't exist in the repo yet)
│   ├── docker-entrypoint.sh                <- from this package
│   └── bitcoin.conf.example  -> bitcoin.conf   (still fill in rpcauth, see 3.)
├── elektron-net-ppool/
│   ├── Dockerfile                          <- already in the repo
│   └── .env.example          -> .env           (still fill in passwords)
├── elektron-net-ppool-ui/
│   └── Dockerfile                          <- already in the repo (nothing else needed)
└── elektron-net-faucet/
    ├── Dockerfile                          <- already in the repo
    └── .env.example          -> .env           (still fill in passwords)
```

```bash
cp elektron-net-stack/elektron-net/bitcoin.conf.example        /opt/elektron-net-stack/elektron-net/bitcoin.conf
cp elektron-net-stack/elektron-net-ppool/.env.example           /opt/elektron-net-stack/elektron-net-ppool/.env
cp elektron-net-stack/elektron-net-faucet/.env.example          /opt/elektron-net-stack/elektron-net-faucet/.env
```

(The templates themselves - `*.example` - stay untouched in the repo, so
there's always a clean reference online. `install-elektron-stack.sh`
doesn't need this manual copy step, it writes `bitcoin.conf` and both
`.env` files itself with generated values.)

## 3. Generate RPC credentials

```bash
python3 elektron-net/share/rpcauth/rpcauth.py elektron_svc
```

The output has 3 lines: an `rpcauth=...` line (goes into
`elektron-net/bitcoin.conf`) and below it the **plaintext password**
(goes into both `.env` files as `ELEKTRON_RPC_PASSWORD` /
`FAUCET_RPC_PASS`). Fill in both.

## 4. Fill in secrets

In `elektron-net-ppool/.env`:
- `ELEKTRON_RPC_PASSWORD` (from step 3)
- `JWT_SECRET` -> `openssl rand -hex 32`
- `POOL_WALLET_ADDRESS` stays blank for now (comes in step 6)

In `elektron-net-faucet/.env`:
- `FAUCET_RPC_PASS` (from step 3)
- `FAUCET_DB_PASS`, `FAUCET_DB_ROOT_PASS`, `FAUCET_ADMIN_PASS` -> each
  random, e.g. `openssl rand -base64 24`
- `FAUCET_WALLET_PASS` stays blank for now (comes in step 6)
- `FAUCET_HCAPTCHA_SITE` / `FAUCET_HCAPTCHA_SECRET` from hcaptcha.com

Then, so Docker Compose can find the `${FAUCET_DB_*}` variables in
`docker-compose.yml` outside the faucet folder too:

```bash
cd /opt/elektron-net-stack
ln -s elektron-net-faucet/.env .env
```

## 5. Start the node first, let it sync

```bash
cd /opt/elektron-net-stack
docker compose up -d --build elektron-net
docker compose logs -f elektron-net
```

Wait until `getblockchaininfo` shows `"initialblockdownload": false`:

```bash
docker compose exec elektron-net elektron-cli getblockchaininfo
```

## 6. Create wallets (pool + faucet)

```bash
# Pool wallet
docker compose exec elektron-net elektron-cli createwallet "pool"
docker compose exec elektron-net elektron-cli -rpcwallet=pool getnewaddress "" bech32
# -> enter the be1q... address in elektron-net-ppool/.env as POOL_WALLET_ADDRESS

# Faucet wallet (encrypted!)
docker compose exec elektron-net elektron-cli createwallet "faucet"
docker compose exec elektron-net elektron-cli -rpcwallet=faucet encryptwallet "A-LONG-PASSPHRASE"
docker compose exec elektron-net elektron-cli -rpcwallet=faucet getnewaddress "" bech32
# -> enter the passphrase in elektron-net-faucet/.env as FAUCET_WALLET_PASS
# -> enter the be1q... address later in the faucet admin panel as "Sender address"
```

Fund both addresses now from your prepaid balance with some ELEK (keep
the hot wallet small, top it up regularly).

## 7. Start the rest of the stack

```bash
docker compose up -d --build
docker compose ps
```

Firewall (ufw example - with `IPV6=yes` active in `/etc/default/ufw`,
the Ubuntu default, this automatically covers IPv6 too). Always open,
regardless of optional components (node + Caddy are mandatory):
```bash
sudo ufw allow 8333/tcp comment 'Elektron P2P seed'
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```

That's the 3 baseline ports. If your provider has a separate
network-level firewall panel (e.g. Hetzner Cloud Firewall, AWS Security
Groups, DigitalOcean Cloud Firewalls), open the same ports there too -
enable them separately for IPv4 and IPv6, otherwise the provider
firewall sits in front of ufw and blocks IPv6 traffic regardless.

**If `INSTALL_POOL=true` (default):** one more port is added -
`3333/tcp` (PPLNS Stratum). `install-elektron-stack.sh` handles this
automatically with `FIREWALL_AUTO_CONFIGURE=true` (including closing it
again if `INSTALL_POOL` is later set back to `false`); manually:
```bash
sudo ufw allow 3333/tcp comment 'Elektron PPLNS Stratum'
sudo ufw reload
```

**If `INSTALL_MEMPOOL=true` (default):** two more ports are added -
`50001/tcp` and `50002/tcp` (electrs, see ["Mempool
Explorer"](#mempool-explorer-optional)). `install-elektron-stack.sh`
handles this the same way (including closing them again if
`INSTALL_MEMPOOL=false`); manually:
```bash
sudo ufw allow 50001/tcp comment 'Elektron electrs Electrum (t)'
sudo ufw allow 50002/tcp comment 'Elektron electrs Electrum (s, plain TCP despite the port name)'
sudo ufw reload
```

`INSTALL_FAUCET` needs **no** port of its own (runs only behind Caddy,
like the pool dashboard).

With the defaults (pool + faucet + mempool on, seeder off) that's 6
ports in ufw AND in your provider's firewall panel, if it has one. The
script always shows the number actually needed for your current
configuration at the end of the run.

## 8. Verify

- `https://pool.example.com` -> pool dashboard
- `https://faucet.example.com` -> faucet, log into `/admin.php` with
  `FAUCET_ADMIN_USER`/`FAUCET_ADMIN_PASS`, click **Test RPC
  connection** and **Test wallet unlock** there
- Have a miner connect to `stratum+tcp://pool.example.com:3333` as a test
- `elektron-net-ppool/.env`: keep `PAYOUT_DRY_RUN=true` until you've
  checked the first simulated payout in the logs (see the ppool README,
  "Verification before going live") - only then switch it to `false`

## Seeder (optional, testing phase)

[`elektron-net-seeder`](https://github.com/kutlusoy/elektron-net-seeder)
is a DNS seed crawler (a fork of Bitcoin's `dnsseed`): crawls known peers
and answers DNS queries with a list of currently reachable nodes - this
is what `elektron-qt`/`elektrond` use for peer discovery without a fixed,
hardcoded address list.

Resource needs: low (a few tens of MB of RAM, I/O- rather than
CPU-bound), fits comfortably alongside node/pool/faucet. No P2P port of
its own - only outgoing connections. The only open port: **53 (DNS,
UDP+TCP)**.

Not installed by default (`INSTALL_SEEDER=false`), because
`SEEDER_HOST` needs its own **NS delegation** (not a simple A/AAAA entry
like the other domains) - more error-prone and worth testing before
production use.

### Enabling it

```ini
INSTALL_SEEDER=true
SEEDER_HOST=seeder.example.com
SEEDER_NS=node.example.com
SEEDER_MBOX=admin.example.com
```

or answer "yes" to the prompt in the script interactively. `SEEDER_NS`
can be the same server as the node, but it must be entered as the
authoritative nameserver for `SEEDER_HOST` (see below). `SEEDER_MBOX`:
email address for the SOA record, with `@` written as `.`.

A rerun clones `elektron-net-seeder`, writes its `.env`, builds and
starts the container in addition - node/pool/faucet stay unchanged
(Compose detects no change in their service blocks). You don't need to
upload `docker-compose.yml` separately, the script writes it itself on
every run.

### Disabling it again

`INSTALL_SEEDER=false` + rerun is enough: the script stops/removes the
container and closes port 53 again (a Compose profile alone doesn't stop
an already-running container, so the script does this step explicitly).
Source code, `.env` and `dnsseed.dat`/`.dump` are kept for a later
re-activation - to remove completely:
`rm -rf elektron-net-seeder data/elektron-net-seeder`.

Manually, without the script:
```bash
docker compose stop elektron-net-seeder && docker compose rm -f elektron-net-seeder
sudo ufw delete allow 53/udp && sudo ufw delete allow 53/tcp
```

### Setting up DNS delegation

Unlike the other domains, a plain A/AAAA record isn't enough here - it
would be answered by your normal DNS provider and never reach the
seeder container. Instead, an **NS record**:

| Subdomain | Type | Target |
|---|---|---|
| `seeder.example.com` | NS | `node.example.com` (or your `SEEDER_NS`) |

If A/AAAA records already exist for `SEEDER_HOST`: remove them - NS and
A/AAAA at the same time produce a contradictory delegation. Check with:
`dig -t NS seeder.example.com`.

### First tests before going live

```bash
dig @<SERVER_IP> -p 53 seeder.example.com   # works even before the delegation has propagated
dig seeder.example.com                       # normal resolution, once propagated
docker compose logs -f elektron-net-seeder
cat data/elektron-net-seeder/dnsseed.dump         # crawl status of all known peers
```

Only link it in production as a `seednode=`/`dnsseed=` once normal
resolution reliably returns IPs and `dnsseed.dump` shows plausible
peers.

### Configurable fields (`elektron-net-seeder/.env`)

| Variable | Meaning | Default |
|---|---|---|
| `SEEDER_HOST` | Hostname of the DNS seed itself | - (required) |
| `SEEDER_NS` | Its authoritative nameserver | - (required) |
| `SEEDER_MBOX` | Email for the SOA record (`@` as `.`) | - (required) |
| `SEEDER_DNS_PORT` | UDP/TCP port for DNS answers | `53` |
| `SEEDER_BIND_ADDRESS` | Bind address | `::` (all) |
| `SEEDER_THREADS` | Parallel crawler threads | `96` |
| `SEEDER_DNS_THREADS` | DNS server threads | `4` |
| `SEEDER_P2P_PORT` | P2P port of the crawled peers | blank = `8333` (Elektron default) |
| `SEEDER_MAGIC` | Network magic bytes (hex) | blank = Elektron Net default |
| `SEEDER_MIN_HEIGHT` | Minimum block height for a peer to count as "good" | `70000` (see below) |
| `SEEDER_EXTRA_SEEDS` | Comma-separated, replaces the built-in starting list | blank |
| `SEEDER_FILTERS` | Comma-separated, allowed service-flag combinations | blank (all) |
| `SEEDER_TESTNET` / `SEEDER_WIPE_BAN` / `SEEDER_WIPE_IGNORE` | `true`/`false` | `false` |

`SEEDER_P2P_PORT` and `SEEDER_MAGIC` normally don't need to be set - the
seeder already defaults to Elektron Net's own P2P port (8333) and
network magic, just like `elektron-net` itself.

### When does a peer count as "good"? (distributed over DNS)

A crawled peer first has to pass **all** of these hard filters:

| Check | Condition |
|---|---|
| Port | exactly `8333` (or `SEEDER_P2P_PORT`) |
| Services | offers `NODE_NETWORK` (full node) |
| Routability | public, routable IP (no private/local addresses) |
| Protocol version | >= 70017 - fixed in the seeder's source (`db.h`, `REQUIRE_VERSION`) |
| Block height | >= `SEEDER_MIN_HEIGHT` (default `70000`, instead of the mainnet-standard 350000) |

After that, **one** of several reliability conditions is enough: either
the very first successful contact with a new peer (a trust grace period
for the first three attempts), or a sufficiently high success rate over
one of five rolling time windows (2h/8h/1d/1week/1month) - the longer the
window, the lower the required rate, but the more samples are demanded.
Once marked "good", a peer stays that way until a later failed contact
removes it from the list again.

### StartOS variant

There's also [`elektron-seeder-startos`](https://github.com/kutlusoy/elektron-seeder-startos)
for StartOS (e.g. a home server via router + DynDNS) - independent of
this integration, currently not actively maintained.

## Mempool Explorer (optional)

[`elektron-net-mempool`](https://github.com/kutlusoy/elektron-net-mempool)
is a fork of [mempool.space](https://github.com/mempool/mempool): block
and mempool explorer, mining dashboard, fee estimation. Runs behind
Caddy like Pool UI and Faucet (no new HTTP port). It additionally brings
`elektron-electrs`, though, which publishes its own Electrum RPC port
directly from the host (no Caddy, since it's raw TCP/JSON-RPC rather
than HTTP) - **two new ports, 50001/tcp and 50002/tcp**, see "Important
limitations" below and the firewall note in step 7.

Installed by default (`INSTALL_MEMPOOL=true`) - unlike the seeder, this
integration is considered stable, not a testing phase. Four additional
containers: `elektron-mempool-db` (its own MariaDB instance, separate
from the faucet DB), `elektron-mempool-api` (backend, RPC client against
`elektron-net`), `elektron-mempool-web` (frontend, reachable via Caddy)
and `elektron-electrs` ([`elektron-net-electrs`](https://github.com/kutlusoy/elektron-net-electrs),
an Electrum server for the explorer's address lookups AND for external
Electrum wallet clients; its configuration is generated by the installer
into `elektron-net-electrs/electrs.toml` - electrs only accepts RPC
credentials via a config file). All four share the Compose profile
`mempool` and are installed, started and removed together.

### Accelerator (menu + boost button)

Active by default (`MEMPOOL_ACCELERATOR=true`): unlocks the
"Acceleration" menu item (dashboard) and the "Boost" button on the
transaction page in the explorer frontend. Both are purely frontend
flags (`ACCELERATOR`/`ACCELERATOR_BUTTON` in the generated
`elektron-net-mempool/.env`) and link to mempool.space's own, central
fee acceleration service - this is a purely outbound HTTPS request to
`SERVICES_API`, no extra port is opened and no firewall rule is needed.
To disable:

```ini
MEMPOOL_ACCELERATOR=false
```

then `./install-elektron-stack.sh --yes` (or run it interactively again)
and `docker compose up -d --force-recreate elektron-mempool-web`.

### Disabling it

```ini
INSTALL_MEMPOOL=false
```

or answer "no" to the prompt in the script interactively, then
`./install-elektron-stack.sh --yes` (or run it interactively again). The
script stops/removes all four containers (a Compose profile alone
doesn't stop an already-running container, so the script does this step
explicitly, just like for the seeder) AND closes the two electrs ports
(50001/tcp, 50002/tcp) again, if `FIREWALL_AUTO_CONFIGURE=true`. Data in
`data/mempool-db/`, `data/mempool-cache/` and `data/electrs/` is kept
for a later re-activation - to remove completely:
`rm -rf elektron-net-mempool elektron-net-electrs data/mempool-db data/mempool-cache data/electrs`.

Manually, without the script:
```bash
docker compose stop elektron-mempool-web elektron-mempool-api elektron-mempool-db elektron-electrs
docker compose rm -f elektron-mempool-web elektron-mempool-api elektron-mempool-db elektron-electrs
sudo ufw delete allow 50001/tcp && sudo ufw delete allow 50002/tcp
```

### Important limitations

- **~137 days of block history:** Elektron Net enforces pruning on
  every node (`MandatoryPruneDepth`, ~197,280 blocks) - the explorer
  fundamentally cannot show older blocks, that's intentional, not a
  bug.
- **Address lookups via electrs:** `MEMPOOL_BACKEND=electrum` - address
  history and balance come from the co-installed `elektron-electrs`.
  Right after the initial install, its index build needs a few minutes;
  until then, address search may return empty results.
- **electrs ports 50001 ("t") and 50002 ("s") are BOTH plain TCP, no
  real SSL/TLS:** electrs itself doesn't terminate TLS, and this stack
  currently has no separate TLS terminator in front of it. Port 50002
  only follows the naming convention ("s" for SSL, common for Electrum
  server listings), but technically delivers the same plain TCP as
  50001 - external Electrum wallets that strictly require TLS on 50002
  will fail there and should use 50001 or a "no SSL" setting instead.
  Real TLS for 50002 (e.g. via stunnel + a Let's Encrypt certificate) is
  not implemented yet.
- **Own mining pool list:** `elektron-net-mempool/pools-v2.json` (not
  Bitcoin's `mempool/mining-pools`) - PPLNS pools are recognized by
  their payout address (a pool tag in the coinbase scriptSig would break
  UTXO attestation, see
  `elektron-net-mempool/backend/src/api/pools-parser.ts`). Anything
  unknown/solo-found shows up as "Solo Pool Miner". New pools are added
  to `pools-v2.json` (your own branch/fork, then adjust
  `MEMPOOL_POOLS_JSON_URL`/`_TREE_URL` in the generated
  `elektron-net-mempool/.env`).

### Updating it

Unlike the other four repos, a plain manual `git pull` +
`docker compose up -d --build` is **not** enough by itself here: the
Docker build context (`backend/`, `frontend/`) only gets created by the
staging step in `install-elektron-stack.sh`, out of `docker/` (see
above, "Important limitations" -> build context). A rerun of the script
covers both in one go: `AUTO_UPDATE_REPOS=true` (or answering "yes" to
the corresponding prompt) lets `elektron-net-mempool` update via
`git pull --ff-only`, re-stages the build context, and rebuilds both
containers:

```bash
cd /opt/elektron-net-stack-install   # or wherever elektron-stack.conf lives
./install-elektron-stack.sh --yes
```

Manually, without rerunning the script: `git pull`, then replicate the
staging step yourself (see `install-elektron-stack.sh`, section "1b."),
only rebuild afterward.

## Important

- Delete `install.php` in the Faucet after successful setup:
  `docker compose exec elektron-faucet-app rm public/install.php`
- Both `.env` files hold real passwords - do not commit them, restrict
  permissions (`chmod 600`).
- `node.example.com` intentionally gets no Caddy block - that's the
  plain P2P seed, not a web service.
- If you use `install-elektron-stack.sh`, there's additionally a bundled
  overview of all credentials in `$STACK_DIR/ZUGANGSDATEN.txt` (`chmod
  600`, updated on every run), including the complete private-key
  exports of the pool/faucet wallet
  (`data/elektron-net/*-wallet-privkeys-backup.txt`) and everything in
  `external-wallets/` - back it up offline once (see ["Getting files
  onto the server"](#getting-files-onto-the-server-browser-console-only-windows)
  for WinSCP/scp), then keep it locked down on the server. That's the
  single most sensitive file in the stack - access to it means control
  over all balances.

## Troubleshooting

**`/usr/bin/env: 'bash\r': No such file or directory`** - the file has
Windows line endings (`\r\n`), e.g. from a Windows editor or an upload
in text mode. Fix directly on the server:

```bash
sed -i 's/\r$//' install-elektron-stack.sh elektron-stack.conf
./install-elektron-stack.sh
```

(`dos2unix install-elektron-stack.sh elektron-stack.conf` works just as
well, if installed.) For future uploads: in WinSCP set the transfer mode
to **Binary** (Transfer Settings -> Transfer mode -> Binary) instead of
"Automatic"/"Text".

**`bind: address already in use` when starting `elektron-net-seeder`**
(port 53) - `systemd-resolved` occupies port 53 on most Ubuntu servers by
default (`127.0.0.53`/`127.0.0.54`), which collides with a wildcard bind
(`0.0.0.0:53`). The seeder service in `docker-compose.yml` therefore
binds explicitly to `SERVER_IP`/`SERVER_IPV6` instead of the wildcard
address - this avoids the collision entirely, without touching
`systemd-resolved` (and without the side effect that other containers
would suddenly stop resolving external hostnames, as would happen with a
`DNSStubListener=no` fix). If the error still occurs: check whether
`SERVER_IP`/`SERVER_IPV6` in `elektron-stack.conf` match this server's
actual address.
