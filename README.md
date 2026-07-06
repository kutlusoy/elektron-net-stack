# Elektron Net Stack auf Hetzner (46.225.163.85)

Enthält: `elektron-net` (Seed-Node), `elektron-net-ppool` + `elektron-net-ppool-ui`
(PPLNS-Pool), `elektron-net-faucet`. Ein Caddy als gemeinsamer Reverse Proxy
für HTTPS.

## Schnellstart (automatisiert)

Die Schritte 1-7 weiter unten (Repos klonen, RPC-Zugangsdaten generieren,
`.env`-Dateien ausfüllen, Node hochfahren, Wallets anlegen, Firewall öffnen)
erledigt `install-elektron-stack.sh` automatisch für dich. Alle Passwörter
(RPC, JWT_SECRET, DB, Wallet-Passphrase, Faucet-Admin) werden dabei sicher
generiert, sofern du sie nicht selbst vorgibst. Manuell bleiben nur die
**DNS-Einträge (Schritt 1)** und ein paar Minuten Warten, bis der Node
synchronisiert ist -- der Rest läuft in einem Durchlauf durch.

Bring das Skript (und optional deine ausgefüllte Config-Datei, siehe unten)
auf den Server -- wie genau, hängt von deinem Zugang ab, siehe
["Dateien auf den Server bringen"](#dateien-auf-den-server-bringen-nur-hetzner-console-windows)
weiter unten, falls du nur die Hetzner-Browser-Console hast. Dann:

```bash
chmod +x install-elektron-stack.sh
./install-elektron-stack.sh
```

Für die serverspezifischen Angaben (Domains, IPv4/IPv6, GitHub-Benutzer,
hCaptcha-Keys, Let's-Encrypt-Mail) hast du zwei gleichwertige Optionen --
sensible Daten müssen also **nicht** vorher in eine Datei im Repo
eingetragen werden:

1. **Eingabe auf der Konsole:** Läuft das Skript in einem Terminal, fragt
   es jeden Wert einzeln ab und zeigt den aktuellen Default in `[...]` --
   Enter übernimmt ihn einfach. So dauert die Installation nur wenige
   Tastendrücke -- **du brauchst dafür keine einzige Datei hochzuladen.**
2. **Config-Datei:** `elektron-stack.conf.example` nach
   `elektron-stack.conf` kopieren, dort deine Werte eintragen, die Datei
   neben `install-elektron-stack.sh` ablegen (oder mit `--config
   /pfad/zur/datei` angeben). Das Skript findet eine `elektron-stack.conf`
   im selben Verzeichnis automatisch. Alles, was darin leer bleibt, wird
   -- falls interaktiv gestartet -- trotzdem abgefragt, oder mit `--yes`
   komplett automatisch (Default-Wert bzw. Auto-Generierung) übernommen --
   praktisch für unbeaufsichtigte/CI-Läufe.

`elektron-stack.conf` wird nie committet (siehe `.gitignore`) -- lege sie
also ruhig direkt auf dem Server ab, ohne sie ins Repo einzuchecken.

**Wichtig:** Die eigentlichen `.env`-Dateien und `bitcoin.conf` in den
Unterordnern (`elektron-net-ppool/.env`, `elektron-net-faucet/.env`,
`elektron-net/bitcoin.conf`) musst du bei Nutzung des Skripts **nirgends
selbst hochladen oder hineinkopieren** -- das Skript schreibt sie komplett
selbst, aus deinen Konsolen-Antworten bzw. aus `elektron-stack.conf`. Das
manuelle Kopieren der `*.example`-Vorlagen in Schritt 2 unten ist nur für
den rein manuellen Weg ohne Skript nötig.

Das Skript ist idempotent: schon geklonte Repos, bereits existierende
Wallets usw. werden erkannt und übersprungen, ein erneuter Lauf (z. B. nach
einem Server-Reboot oder um eine Einstellung nachzuziehen) richtet nichts
kaputt.

Details zu jedem einzelnen Schritt -- z. B. falls du lieber alles von Hand
nachvollziehen oder etwas debuggen willst -- stehen in den Abschnitten
0-8 unten; das Skript automatisiert genau das, was dort beschrieben ist.

## Dateien auf den Server bringen (nur Hetzner-Console, Windows)

Wenn du auf Hetzner bisher nur die **Browser-Console** (Cloud-Panel ->
Server -> "Console", ein VNC-Fenster im Browser) nutzt und noch keinen
SSH-Zugang eingerichtet hast, gibt es dort naturgemäß kein Drag & Drop für
Datei-Uploads. Drei Wege, vom einfachsten zum aufwendigsten:

**A) Gar nichts hochladen -- direkt auf dem Server herunterladen.**
Dieses Repo ist öffentlich, du kannst beide Dateien in der Browser-Console
direkt per `curl` holen, ganz ohne Windows-Zwischenschritt:

```bash
curl -O https://raw.githubusercontent.com/kutlusoy/elektron-net-stack/main/install-elektron-stack.sh
chmod +x install-elektron-stack.sh
./install-elektron-stack.sh
```

Nutzt du dabei die interaktive Konsolen-Eingabe (Option 1 oben), brauchst
du überhaupt keine Config-Datei -- die Werte tippst du direkt im
Browser-Fenster ein, fertig.

**B) `elektron-stack.conf` auf dem Server anlegen -- kein interaktives
Eintippen bei jedem Lauf.** Damit füllst du alle Werte einmal aus, speicherst
die Datei dauerhaft auf dem Server, und das Skript liest sie bei jedem
(erneuten) Lauf automatisch -- keine Rückfragen mehr. Schritt für Schritt:

**1. Browser-Console öffnen** (Hetzner Cloud-Panel -> dein Server ->
Tab "Console") und einloggen.

**2. Arbeitsverzeichnis anlegen** (beliebiger Ort, hier `/root`):

```bash
mkdir -p ~/elektron-net-stack-install
cd ~/elektron-net-stack-install
```

**3. Skript und Config-Vorlage herunterladen** (Repo ist öffentlich, kein
Login nötig):

```bash
curl -O https://raw.githubusercontent.com/kutlusoy/elektron-net-stack/main/install-elektron-stack.sh
curl -O https://raw.githubusercontent.com/kutlusoy/elektron-net-stack/main/elektron-stack.conf.example
chmod +x install-elektron-stack.sh
```

**4. Vorlage kopieren** (die `.example`-Datei bleibt als Referenz unverändert
liegen, du bearbeitest nur die Kopie):

```bash
cp elektron-stack.conf.example elektron-stack.conf
```

**5. Config-Datei mit `nano` bearbeiten:**

```bash
nano elektron-stack.conf
```

`nano` öffnet die Datei direkt im Terminal. Mit den Pfeiltasten navigieren,
Werte hinter dem `=` überschreiben. Die wichtigsten Kurzbefehle unten in
der Fußzeile von `nano` (`^` steht für Strg):

| Taste | Aktion |
|---|---|
| `Strg+O`, dann `Enter` | Speichern (write out) |
| `Strg+X` | Verlassen (nach dem Speichern) |
| `Strg+K` | Aktuelle Zeile ausschneiden |
| `Strg+W` | Suchen |

Trag mindestens diese Werte ein (Rest kann auf dem Default bleiben, siehe
`elektron-stack.conf.example` für alle Felder mit Erklärung):

```ini
GITHUB_USER=kutlusoy
SERVER_IP=46.225.163.85
SERVER_IPV6=2a01:4f8:1c18:ea01::1
NODE_DOMAIN=node1.elektron-net.org
POOL_DOMAIN=pplns.elektron-net.org
FAUCET_DOMAIN=faucet.elektron-net.org
CADDY_EMAIL=deine@email.de
FAUCET_HCAPTCHA_SITE=dein-hcaptcha-site-key
FAUCET_HCAPTCHA_SECRET=dein-hcaptcha-secret-key
```

Alle Passwort-/Secret-Felder (`JWT_SECRET`, `FAUCET_DB_PASS`,
`FAUCET_WALLET_PASSPHRASE`, `FAUCET_ADMIN_PASS`, ...) kannst du leer
lassen -- die generiert das Skript beim Ausführen automatisch sicher.

Für Werte, die du von deinem Windows-Rechner kopierst (z. B. hCaptcha-Keys):
Die Hetzner-Browser-Console hat oben in der Werkzeugleiste ein
Tastatur-/Zwischenablage-Symbol ("Paste text" o. ä.) -- damit fügst du
Text aus der Windows-Zwischenablage direkt in die Console ein, statt lange
Werte von Hand abzutippen.

**6. Rechte einschränken** (die Datei bekommt gleich reale Zugangsdaten):

```bash
chmod 600 elektron-stack.conf
```

**7. Installieren.** Weil `elektron-stack.conf` im selben Verzeichnis wie
das Skript liegt, wird sie automatisch gefunden -- kein `--config`-Flag
nötig. Mit `--yes` läuft alles komplett ohne Rückfragen durch:

```bash
./install-elektron-stack.sh --yes
```

Fehlt in der Datei noch ein Wert, den das Skript braucht, wird er trotzdem
mit dem eingebauten Default bzw. per Auto-Generierung befüllt -- `--yes`
bricht nie ab, es fragt nur nicht nach.

**8. Später etwas ändern?** Einfach `nano elektron-stack.conf` erneut öffnen,
Wert anpassen, speichern, `./install-elektron-stack.sh --yes` erneut
ausführen. Das Skript ist idempotent (erkennt bereits vorhandene Repos,
Wallets usw.) -- ein erneuter Lauf richtet nichts kaputt, du musst dafür
nie wieder etwas interaktiv eintippen.

**C) Echter Datei-Upload von Windows aus -- braucht SSH/SFTP.** Das geht
nur, wenn SSH auf dem Server erreichbar ist, nicht über die reine
Browser-Console. Erst prüfen, ob SSH schon klappt (Windows 10/11 haben
einen OpenSSH-Client eingebaut, PowerShell oder Windows Terminal öffnen):

```powershell
ssh root@46.225.163.85
```

Das root-Passwort steht in der Hetzner-Bestätigungsmail bzw. wurde beim
Anlegen des Servers einmalig angezeigt -- falls du dabei stattdessen einen
SSH-Key hinterlegt hast, wirst du automatisch ohne Passwort eingeloggt.
Meldet sich der Server, kannst du:

- **[WinSCP](https://winscp.net)** benutzen (grafisch, Drag & Drop) --
  neue Verbindung mit Protokoll SFTP, Host = deine Server-IP, Benutzer
  `root`.
- oder direkt in PowerShell: `scp .\elektron-stack.conf root@46.225.163.85:/opt/elektron-net-stack/`

Antwortet SSH nicht: im Hetzner Cloud-Firewall-Panel (Tab "Firewalls")
prüfen, ob Port 22 für dein Netzwerk erlaubt ist -- Standard-Images haben
den SSH-Server bereits vorinstalliert und laufend, nur eine zu strenge
Cloud-Firewall blockiert dann typischerweise den Zugriff.

## 0. Voraussetzung

Docker CE + Compose-Plugin bereits installiert (laut dir schon erledigt).
Prüfen:
```bash
docker version
docker compose version
```

## 1. DNS bei world4you anlegen

A-Records (alle auf `46.225.163.85`) UND AAAA-Records (alle auf deine
IPv6-Adresse, siehe Hetzner Console → Networking; üblicherweise die erste
Adresse in deinem `/64`-Subnetz, z. B. `2a01:4f8:1c18:ea01::1` -- exakten
Wert im Panel verifizieren):

| Subdomain | Typ | Ziel |
|---|---|---|
| `node1.elektron-net.org` | A | 46.225.163.85 |
| `node1.elektron-net.org` | AAAA | 2a01:4f8:1c18:ea01::1 |
| `pplns.elektron-net.org` | A | 46.225.163.85 |
| `pplns.elektron-net.org` | AAAA | 2a01:4f8:1c18:ea01::1 |
| `faucet.elektron-net.org` | A | 46.225.163.85 |
| `faucet.elektron-net.org` | AAAA | 2a01:4f8:1c18:ea01::1 |

Bei world4you als eigener A-Record mit vollem Namen `faucet` (oder je nach
Panel `faucet.elektron-net.org.`) anlegen -- AAAA analog dazu.

Kurz warten/prüfen: `dig +short pplns.elektron-net.org` und
`dig +short AAAA pplns.elektron-net.org` sollten jeweils die passende IP
liefern, bevor du Caddy startest (sonst schlägt die Let's-Encrypt-Anfrage
fehl).

**IPv6 im Stack:** P2P (8333), Stratum (3333) und Caddy (80/443) sind im
mitgelieferten `docker-compose.yml` bereits dual-stack published
(`"[::]:PORT:PORT"` zusätzlich zur IPv4-Zeile) -- das braucht keine
Docker-Daemon-Konfiguration, weil Docker den eingehenden IPv6-Traffic per
`docker-proxy` einfach an die (intern weiterhin IPv4-basierten) Container
weiterreicht. Sobald die AAAA-Records oben stehen, ist alles automatisch
auch über IPv6 erreichbar.

**Private Netzwerk-IP (10.0.0.2, Hetzner vSwitch):** wird von diesem Stack
aktuell nicht verwendet -- alle Container kommunizieren intern über die
eigenen Docker-Netzwerke (`backend`/`web`). Relevant wird sie erst, wenn du
später z. B. die Wallet auf einen zweiten, isolierten Hetzner-Server
auslagerst (siehe `elektron-net-ppool`-README, Abschnitt zur
"network-isolated wallet server"-Topologie).

**Reverse DNS (PTR) für IPv6:** Im Hetzner-Panel (Networking → IPv6-Zeile →
"…" → Reverse DNS) stand bei dir "0 Einträge". Für die IPv4 gibt es bereits
automatisch `static.85.163.225.46.clients.your-server.de`. Für einen
öffentlichen Seed-Node lohnt es sich, dort auch für die IPv6-Adresse einen
PTR-Eintrag zu setzen (z. B. auf `node1.elektron-net.org`) -- manche Peers
werten fehlendes/verdächtiges rDNS bei der Node-Reputation negativ. Optional,
aber empfehlenswert.


## 2. Repos klonen

```bash
mkdir -p /opt/elektron-net-stack && cd /opt/elektron-net-stack

git clone https://github.com/kutlusoy/elektron-net.git
git clone https://github.com/kutlusoy/elektron-net-ppool.git
git clone https://github.com/kutlusoy/elektron-net-ppool-ui.git
git clone https://github.com/kutlusoy/elektron-net-faucet.git
```

Dann die Dateien aus diesem Paket **in dieselbe Struktur** kopieren (überschreibt
nichts Bestehendes, ergänzt nur). Die `*.example`-Dateien sind Vorlagen --
beim Kopieren die Endung `.example` weglassen (siehe Zielname rechts):

```
/opt/elektron-net-stack/
├── docker-compose.yml                      <- aus diesem Paket
├── caddy/Caddyfile                         <- aus diesem Paket
├── elektron-net/
│   ├── Dockerfile                          <- aus diesem Paket (existiert im Repo noch nicht)
│   ├── docker-entrypoint.sh                <- aus diesem Paket
│   └── bitcoin.conf.example  -> bitcoin.conf   (rpcauth noch eintragen, siehe 3.)
├── elektron-net-ppool/
│   ├── Dockerfile                          <- schon im Repo
│   └── .env.example          -> .env           (Passwörter noch eintragen)
├── elektron-net-ppool-ui/
│   └── Dockerfile                          <- schon im Repo (nichts weiter nötig)
└── elektron-net-faucet/
    ├── Dockerfile                          <- schon im Repo
    └── .env.example          -> .env           (Passwörter noch eintragen)
```

```bash
cp elektron-net-stack/elektron-net/bitcoin.conf.example        /opt/elektron-net-stack/elektron-net/bitcoin.conf
cp elektron-net-stack/elektron-net-ppool/.env.example           /opt/elektron-net-stack/elektron-net-ppool/.env
cp elektron-net-stack/elektron-net-faucet/.env.example          /opt/elektron-net-stack/elektron-net-faucet/.env
```

(Die Vorlagen selbst -- `*.example` -- bleiben unangetastet im Repo, damit
immer eine saubere Referenz online steht. `install-elektron-stack.sh`
braucht diesen manuellen Kopierschritt nicht, es schreibt `bitcoin.conf`
und beide `.env`-Dateien direkt selbst mit generierten Werten.)

## 3. RPC-Zugangsdaten generieren

```bash
python3 elektron-net/share/rpcauth/rpcauth.py elektron_svc
```

Ausgabe hat 3 Zeilen: eine `rpcauth=...`-Zeile (kommt in `elektron-net/bitcoin.conf`)
und darunter das **Klartext-Passwort** (kommt in beide `.env`-Dateien als
`ELEKTRON_RPC_PASSWORD` / `FAUCET_RPC_PASS`). Trag beides ein.

## 4. Secrets ausfüllen

In `elektron-net-ppool/.env`:
- `ELEKTRON_RPC_PASSWORD` (aus Schritt 3)
- `JWT_SECRET` → `openssl rand -hex 32`
- `POOL_WALLET_ADDRESS` bleibt vorerst leer (kommt in Schritt 6)

In `elektron-net-faucet/.env`:
- `FAUCET_RPC_PASS` (aus Schritt 3)
- `FAUCET_DB_PASS`, `FAUCET_DB_ROOT_PASS`, `FAUCET_ADMIN_PASS` → jeweils
  zufällig, z. B. `openssl rand -base64 24`
- `FAUCET_WALLET_PASS` bleibt vorerst leer (kommt in Schritt 6)
- `FAUCET_HCAPTCHA_SITE` / `FAUCET_HCAPTCHA_SECRET` von hcaptcha.com

Dann, damit Docker Compose die `${FAUCET_DB_*}`-Variablen im
`docker-compose.yml` auch außerhalb des faucet-Ordners findet:

```bash
cd /opt/elektron-net-stack
ln -s elektron-net-faucet/.env .env
```

## 5. Node zuerst hochfahren, synchronisieren lassen

```bash
cd /opt/elektron-net-stack
docker compose up -d --build elektron-net
docker compose logs -f elektron-net
```

Warten bis `getblockchaininfo` → `"initialblockdownload": false`:

```bash
docker compose exec elektron-net elektron-cli getblockchaininfo
```

## 6. Wallets anlegen (Pool + Faucet)

```bash
# Pool-Wallet
docker compose exec elektron-net elektron-cli createwallet "pool"
docker compose exec elektron-net elektron-cli -rpcwallet=pool getnewaddress "" bech32
# → be1q... in elektron-net-ppool/.env als POOL_WALLET_ADDRESS eintragen

# Faucet-Wallet (verschlüsselt!)
docker compose exec elektron-net elektron-cli createwallet "faucet"
docker compose exec elektron-net elektron-cli -rpcwallet=faucet encryptwallet "EIN-LANGES-PASSPHRASE"
docker compose exec elektron-net elektron-cli -rpcwallet=faucet getnewaddress "" bech32
# → Passphrase in elektron-net-faucet/.env als FAUCET_WALLET_PASS
# → be1q... später im Faucet-Admin-Panel als "Sender address" eintragen
```

Beide Adressen jetzt von deinem Prepaid-Bestand aus mit etwas ELEK befüllen
(Hot Wallet klein halten, regelmäßig nachfüllen).

## 7. Rest des Stacks hochfahren

```bash
docker compose up -d --build
docker compose ps
```

Firewall (ufw Beispiel -- deckt bei aktivem `IPV6=yes` in `/etc/default/ufw`,
Ubuntu-Standard, automatisch auch IPv6 mit ab):
```bash
sudo ufw allow 8333/tcp comment 'Elektron P2P seed'
sudo ufw allow 3333/tcp comment 'Elektron PPLNS Stratum'
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```

Zusätzlich im **Hetzner Cloud-Firewall-Panel** (Tab "Firewalls") dieselben
4 Ports öffnen -- dort getrennt für IPv4 und IPv6 aktivieren, sonst greift
die Cloud-Firewall vor ufw und blockt IPv6-Traffic trotzdem.

Bei Hetzner zusätzlich im Cloud-Firewall-Panel dieselben 4 Ports öffnen.

## 8. Prüfen

- `https://pplns.elektron-net.org` → Pool-Dashboard
- `https://faucet.elektron-net.org` → Faucet, `/admin.php` mit
  `FAUCET_ADMIN_USER`/`FAUCET_ADMIN_PASS` einloggen, dort **Test RPC
  connection** und **Test wallet unlock** klicken
- Miner testweise auf `stratum+tcp://pplns.elektron-net.org:3333`
  verbinden lassen
- `elektron-net-ppool/.env`: `PAYOUT_DRY_RUN=true` lassen, bis du die erste
  simulierte Auszahlung im Log geprüft hast (siehe ppool-README
  "Verification before going live") — erst danach auf `false` stellen

## Wichtig

- `install.php` im Faucet nach erfolgreicher Einrichtung löschen:
  `docker compose exec elektron-faucet-app rm public/install.php`
- Beide `.env`-Dateien haben reale Passwörter — nicht committen, Rechte
  einschränken (`chmod 600`).
- `node1.elektron-net.org` hat absichtlich keinen Caddy-Block — das ist der
  reine P2P-Seed, kein Webdienst.
