# Elektron Net Stack auf Hetzner (46.225.163.85)

Enthält: `elektron-net` (Seed-Node), `elektron-net-ppool` + `elektron-net-ppool-ui`
(PPLNS-Pool), `elektron-net-faucet`. Ein Caddy als gemeinsamer Reverse Proxy
für HTTPS. Optional, noch in Testphase: `elektron-net-seeder` (DNS-Crawler,
siehe [„Seeder (optional, Testphase)"](#seeder-optional-testphase)) --
standardmäßig NICHT installiert, wird bei einem normalen Lauf komplett
übersprungen.

## Schnellstart (automatisiert)

Die Schritte 1-7 weiter unten (Repos klonen, RPC-Zugangsdaten generieren,
`.env`-Dateien ausfüllen, Node hochfahren, Wallets anlegen, Firewall öffnen)
erledigt `install-elektron-stack.sh` automatisch für dich. Alle Passwörter
(RPC, JWT_SECRET, DB, Wallet-Passphrase, Faucet-Admin) werden dabei sicher
generiert, sofern du sie nicht selbst vorgibst. Manuell bleiben nur die
**DNS-Einträge (Schritt 1)** und ein paar Minuten Warten, bis der Node
synchronisiert ist -- der Rest läuft in einem Durchlauf durch.

**Alle Zugangsdaten landen gesammelt in einer Datei auf dem Server:**
`$STACK_DIR/ZUGANGSDATEN.txt` (Standard: `/opt/elektron-net-stack/ZUGANGSDATEN.txt`),
automatisch mit `chmod 600` versehen. Enthält RPC-/DB-/Wallet-Passwörter,
JWT_SECRET, Faucet-Admin-Login, Pool-/Faucet-Wallet-Adressen, Domains/IPs
und eine Befehlsreferenz -- wird bei jedem (Re-)Lauf des Skripts neu
geschrieben, du musst also nichts bei der einmaligen Terminal-Ausgabe
abschreiben.

**Beide Wallets (Pool und Faucet) werden verschlüsselt.** Die
Pool-Wallet-Passphrase (`WALLET_PASSPHRASE` in `elektron-net-ppool/.env`)
wird -- genau wie die Faucet-Passphrase -- automatisch generiert, sofern
nicht selbst vorgegeben; `ppool` entsperrt die Wallet damit automatisch nur
für `WALLET_UNLOCK_SECONDS` bei jeder Auszahlung und sperrt sie danach
sofort wieder. Ohne das schlägt jede echte Auszahlung mit RPC-Fehler `-13`
fehl, sobald `PAYOUT_DRY_RUN=false` gesetzt wird -- das war vorher eine
Lücke in diesem Skript (die Pool-Wallet blieb unverschlüsselt), jetzt
konsistent mit der Faucet-Wallet gelöst.

Für ein **wirklich vollständiges Backup** legt das Skript zusätzlich an
(einmalig, beim ersten Anlegen der jeweiligen Wallet) -- jede Wallet bleibt
dabei bewusst ihre eigene, separat schützbare Datei statt alles in einer
einzigen riesigen Datei zu bündeln:

- `$STACK_DIR/data/elektron-net/pool-wallet-privkeys-backup.txt` und
  `.../faucet-wallet-privkeys-backup.txt` -- vollständiger Export der
  **privaten Schlüssel** von Pool- und Faucet-Wallet (`dumpwallet`, mit
  Fallback auf `listdescriptors true`, je nachdem was die Wallet
  unterstützt). Die Passphrase allein reicht im Katastrophenfall nicht --
  sie entsperrt nur eine bereits vorhandene Wallet-Datei; dieser Export ist
  die eigentliche Wiederherstellungsgrundlage.
- Alles, was du selbst in `$STACK_DIR/external-wallets/` als eigene Datei
  ablegst (z. B. eine offline mit einem eigenen Skript wie
  `generate_address.py` erzeugte Prepaid-Wallet mit Private Key/WIF) --
  dorthin bekommst du sie z. B. über `nano` + die Paste-Funktion der
  Hetzner-Console (siehe "Dateien auf den Server bringen") oder per
  SCP/WinSCP. Das Skript setzt automatisch `chmod 600` auf jede Datei dort.

Noch ein Ort, der nicht von diesem Skript verwaltet wird, aber genauso
sensibel ist: die Faucet-App generiert beim allerersten Start selbst einen
Verschlüsselungs-Key ("Secrets at rest", `FAUCET_APP_KEY`) und schreibt ihn
direkt nach `$STACK_DIR/data/faucet-config/config.php` -- steht in keiner
`.env`, wird aber genauso mitgesichert, wenn du `data/` in dein Backup
einschließt.

`ZUGANGSDATEN.txt` selbst dupliziert diese Wallet-Dateien **nicht** --
es listet nur Dateiname und Pfad als Verweis auf, damit jedes
Wallet-Geheimnis genau eine Stelle hat statt mehrfach im Klartext
herumzuliegen. RPC-/DB-/JWT-/Faucet-Admin-Passwörter stehen dagegen direkt
in `ZUGANGSDATEN.txt`, da es dafür keine separate Wallet-Datei gibt.

Trotzdem bleibt `ZUGANGSDATEN.txt` die zentrale, sensible Übersichtsdatei
im Stack. Einmalig offline sichern (WinSCP/scp) -- am besten zusammen mit
den referenzierten Wallet-Dateien -- und danach nur unter Verschluss auf
dem Server liegen lassen, nicht per
Klartext-Mail verschicken oder irgendwo hochladen.

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
ausführen. Das Skript ist idempotent: bereits vorhandene Repos, Wallets,
Secrets, RPC-Zugangsdaten und Wallet-Adressen werden erkannt und
unverändert wiederverwendet statt neu erzeugt -- ein erneuter Lauf rotiert
also nichts, was bereits läuft, kaputt. Details und schnellere Alternativen
(nur den betroffenen Container neu starten statt das ganze Skript) siehe
["Stack aktualisieren"](#stack-aktualisieren) weiter unten.

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

## Werte vorab lokal ausfüllen und per SFTP hochladen

Hast du SFTP/SCP-Zugriff (siehe oben), kannst du alles bequem lokal auf
deinem Rechner vorbereiten und dann fertig ausgefüllt hochladen, statt auf
dem Server zu tippen. Wichtig ist dabei, **welche Datei** du dafür nimmst:

**Die richtige Datei: `elektron-stack.conf`.** Das ist die einzige Datei,
die dafür gedacht ist, dass du sie vorab ausfüllst und die Werte darin
dauerhaft übernommen werden:

1. Lokal `elektron-stack.conf.example` nach `elektron-stack.conf` kopieren
   und ausfüllen (alle Felder siehe unten und in der Datei selbst
   kommentiert).
2. Per SFTP/WinSCP/`scp` **in denselben Ordner wie `install-elektron-stack.sh`**
   hochladen (z. B. `/opt/elektron-net-stack/elektron-stack.conf`, falls du
   das Skript dort ablegst -- der genaue Ordner ist egal, Hauptsache beide
   Dateien liegen zusammen).
3. `./install-elektron-stack.sh --yes` -- die Datei wird automatisch
   gefunden, alle Werte werden 1:1 übernommen, alles leer gelassene wird
   automatisch generiert. Kein Tippen auf dem Server mehr nötig.

**Nicht die richtige Wahl: die rohen `.env`-Dateien/`bitcoin.conf` selbst
vorab hochladen und erwarten, dass sie unverändert bleiben.** Das Skript
schreibt `elektron-net/bitcoin.conf`, `elektron-net-ppool/.env` und
`elektron-net-faucet/.env` bei **jedem** Lauf komplett neu (aus seinem
eigenen Template) -- eine vorab hochgeladene, handgeschriebene Version
dieser Dateien würde beim ersten Lauf größtenteils überschrieben. Die
einzige Ausnahme: ein paar konkrete Secret-Felder (`JWT_SECRET`,
`WALLET_PASSPHRASE`, `FAUCET_WALLET_PASS`, `FAUCET_DB_PASS`,
`FAUCET_DB_ROOT_PASS`, `FAUCET_ADMIN_PASS`, das RPC-Passwort über
`bitcoin.conf`s `rpcauth`-Zeile) werden erkannt und unverändert
übernommen, wenn sie in einer bereits am Zielort (`$STACK_DIR/...`)
liegenden Datei stehen -- das ist genau der Mechanismus, der Reruns
idempotent macht (siehe "Stack aktualisieren" unten), aber kein
allgemeiner Weg, um beliebige Inhalte vorzugeben. **Für alles, was du
selbst bestimmen willst, gehört der Wert nach `elektron-stack.conf`, nicht
direkt in die Zieldatei.**

Was du in `elektron-stack.conf` konkret vorab festlegen kannst -- die
komplette Liste steht in `elektron-stack.conf.example` mit Kommentaren,
kurz zusammengefasst:

| Bereich | Felder |
|---|---|
| Server/Domains | `GITHUB_USER`, `SERVER_IP`, `SERVER_IPV6`, `NODE_DOMAIN`, `POOL_DOMAIN`, `FAUCET_DOMAIN`, `CADDY_EMAIL` |
| Node/Firewall | `RPC_USER`, `FIREWALL_AUTO_CONFIGURE` |
| Repo-Updates | `AUTO_UPDATE_REPOS` (leer/`false` = nie automatisch aktualisieren, siehe "Stack aktualisieren") |
| Pool-Verhalten | `POOL_IDENTIFIER`, `POOL_FEE_PERCENT`, `PPLNS_WINDOW_MINUTES`, `MIN_PAYOUT_THRESHOLD_SATS`, `PAYOUT_INTERVAL_MINUTES`, `PAYOUT_CONFIRMATIONS_REQUIRED`, `PAYOUT_DRY_RUN`, `STRATUM_PORT`, `API_PORT` |
| Pool-Wallet | `POOL_WALLET_NAME`, `POOL_WALLET_PASSPHRASE` (leer = auto), `WALLET_UNLOCK_SECONDS` |
| Pool-Benachrichtigungen (optional) | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_BOT_USERNAME`, `DISCORD_BOT_TOKEN`, `DISCORD_BOT_CLIENTID`, `DISCORD_BOT_GUILD_ID`, `DISCORD_BOT_CHANNEL_ID` |
| Faucet-Wallet/DB | `FAUCET_WALLET_NAME`, `FAUCET_WALLET_PASSPHRASE` (leer = auto), `FAUCET_DB_NAME`, `FAUCET_DB_USER`, `FAUCET_DB_PASS`/`FAUCET_DB_ROOT_PASS` (leer = auto) |
| Faucet-Login | `FAUCET_ADMIN_USER`, `FAUCET_ADMIN_PASS` (leer = auto) |
| Faucet-Business | `FAUCET_HCAPTCHA_SITE`/`_SECRET`, `FAUCET_TITLE`, `FAUCET_MESSAGE`, `FAUCET_AMOUNT_ELEK`, `FAUCET_DAILY_BUDGET`, `FAUCET_HOURLY_BUDGET`, `FAUCET_PER_ADDR_COOLDOWN_H`, `FAUCET_PER_IP_COOLDOWN_H`, `FAUCET_DEFAULT_LANG`, `FAUCET_EXPLORER_URL` |
| Secrets (immer auto, wenn leer) | `JWT_SECRET`, RPC-Passwort (kein Feld dafür -- immer generiert) |
| Seeder (optional, Default aus) | `INSTALL_SEEDER` (Default `false`), `SEEDER_HOST`, `SEEDER_NS`, `SEEDER_MBOX`, `SEEDER_DNS_PORT`, `SEEDER_THREADS`, `SEEDER_DNS_THREADS` -- siehe [„Seeder (optional, Testphase)"](#seeder-optional-testphase) |

Felder, die das Skript automatisch nach der Wallet-Erstellung einträgt
(`POOL_WALLET_ADDRESS`, `FAUCET_SENDER_ADDR`), gehören **nicht** in
`elektron-stack.conf` -- die kannst du gar nicht vorgeben, die entstehen
erst live beim Lauf.

**Zu Telegram/Discord:** Beide sind rein optional (Miner-Benachrichtigungen
im Pool). Leer lassen deaktiviert sie sauber -- die ppool-Anwendung prüft
selbst, ob alle nötigen Felder gesetzt sind, und schaltet sich sonst ab,
ohne Fehler zu werfen. Für Discord müssen alle vier Felder zusammen gesetzt
sein (Token, Client-ID, Guild-ID, Channel-ID), sonst bleibt die Integration
inaktiv.

**Häufiger Stolperstein bei Dateien von Windows: `\r\n`-Zeilenumbrüche.**
Wurde `install-elektron-stack.sh` (oder `elektron-stack.conf`) mit einem
Windows-Editor bearbeitet oder über ein Tool hochgeladen, das Zeilenenden
umwandelt, bekommst du beim Ausführen ggf.:

```
/usr/bin/env: 'bash\r': No such file or directory
```

Das liegt daran, dass die erste Zeile dann `#!/usr/bin/env bash\r` lautet
-- `env` sucht dann nach einem Programm namens `bash\r`, das es nicht
gibt. Fix direkt auf dem Server:

```bash
sed -i 's/\r$//' install-elektron-stack.sh elektron-stack.conf
./install-elektron-stack.sh
```

(`dos2unix install-elektron-stack.sh elektron-stack.conf` funktioniert
genauso, falls installiert.) Um das beim nächsten Upload gleich zu
vermeiden: In WinSCP den Übertragungsmodus für diese Dateien auf
**Binär** stellen (Transfer Settings -> Transfer mode -> Binary) statt
"Automatisch"/"Text" -- Letzteres wandelt Zeilenenden beim Hochladen
gerne unbemerkt um.

## Stack aktualisieren

Drei unterschiedliche Situationen -- jede mit ihrem eigenen, passenden Weg.
Kurzfassung zuerst, Details darunter:

| Was hat sich geändert? | Was tun? |
|---|---|
| Eine Einstellung in `elektron-stack.conf` (Domain, hCaptcha-Key, Payout-Parameter, ...) | `nano elektron-stack.conf` -> `./install-elektron-stack.sh --yes` |
| Sourcecode eines der vier Repos (neue Version auf GitHub) | `git pull` im jeweiligen Ordner -> `docker compose up -d --build <service>` |
| Caddy- oder MariaDB-Image (Upstream-Update) | `docker compose pull caddy elektron-faucet-db` -> `docker compose up -d` |

### A) Nur eine Einstellung geändert

```bash
cd ~/elektron-net-stack-install   # oder wo elektron-stack.conf liegt
nano elektron-stack.conf          # Wert ändern, speichern
./install-elektron-stack.sh --yes
```

Das ist der einfachste Weg und seit der Idempotenz-Absicherung des Skripts
auch beim wiederholten Aufruf sicher: JWT_SECRET, alle Faucet-Passwörter,
das RPC-Passwort und die Pool-/Faucet-Wallet-Adressen werden aus dem
vorherigen Lauf **wiedererkannt und unverändert übernommen**, nicht neu
generiert -- ein Rerun rotiert also keine Zugangsdaten, die die laufenden
Container bereits verwenden, und schickt dich nicht auf eine neue,
ungefüllte Wallet-Adresse. Am Ende des Laufs siehst du in der
Zusammenfassung, welche Werte "neu generiert" vs. "wiederverwendet" wurden.

Schneller, wenn du nur eine einzelne Datei anfassen willst (ohne
DNS-/Firewall-Checks erneut durchlaufen zu lassen): direkt in der Ziel-Datei
editieren und nur den betroffenen Service neu erzeugen:

```bash
cd /opt/elektron-net-stack
nano elektron-net-faucet/.env        # oder elektron-net-ppool/.env, caddy/Caddyfile, elektron-net/bitcoin.conf
docker compose up -d --force-recreate elektron-faucet-app
```

| Geänderte Datei | Neu zu startender Service |
|---|---|
| `caddy/Caddyfile` | `caddy` |
| `elektron-net-ppool/.env` | `elektron-ppool` |
| `elektron-net-ppool-ui`-Umgebung | `elektron-ppool-ui` |
| `elektron-net-faucet/.env` | `elektron-faucet-app` |
| `elektron-net/bitcoin.conf` | `elektron-net` (kurzer Node-Neustart, P2P kurz offline) |
| `elektron-net-seeder/.env` (nur falls `INSTALL_SEEDER=true`) | `docker compose --profile seeder up -d --force-recreate elektron-net-seeder` (das `--profile seeder` nicht vergessen, sonst ignoriert Compose den Service) |

**Achtung:** `FAUCET_DB_PASS`, `FAUCET_DB_ROOT_PASS` und
`FAUCET_WALLET_PASSPHRASE` von Hand in der `.env` zu ändern bricht die
Verbindung zur bereits initialisierten MariaDB bzw. zum bereits
verschlüsselten Wallet -- diese drei nach dem Ersteinrichten nicht mehr
von Hand anfassen (das Skript selbst lässt sie beim Rerun ohnehin
automatisch unangetastet, siehe oben).

### B) Sourcecode-Update (elektron-net, -ppool, -ppool-ui, -faucet)

**Automatisch beim Skript-Lauf:** Antworte bei der Frage *"Vor dem Bauen
nach Updates in den geklonten Repos suchen ...?"* (kommt ganz am Anfang,
noch vor den anderen Prompts) mit `j`, oder setze
`AUTO_UPDATE_REPOS=true` in `elektron-stack.conf`. Das Skript holt dann
für jedes bereits geklonte Repo per `git fetch` die neuesten Commits,
zeigt sie an und spielt sie per `git pull --ff-only` ein -- niemals
force/rebase, ein lokal abgewichener Branch (z. B. weil du selbst etwas
committet hast) wird nur gemeldet und bewusst **nicht** angefasst. Der
abschließende `docker compose up -d --build` baut die aktualisierten
Repos dann automatisch mit ein. Standardmäßig (Enter/`n`) bleibt alles
wie bisher -- ein Rerun holt dann bewusst **keine** neuen Commits, damit
ein normaler Rerun (z. B. nur um eine Einstellung zu ändern) nie
unerwartet Code aktualisiert.

**Manuell, gezielt für ein Repo:** Falls du nur dieses eine Mal
aktualisieren willst, ohne die Frage im Skript zu nutzen -- selbst
`git pull`, dann nur den betroffenen Container neu bauen:

```bash
cd /opt/elektron-net-stack/elektron-net-ppool   # Repo mit der neuen Version
git pull
cd /opt/elektron-net-stack
docker compose up -d --build elektron-ppool     # baut nur dieses Image neu und ersetzt den Container
```

Service-Namen für die anderen drei Repos: `elektron-net`,
`elektron-ppool-ui`, `elektron-faucet-app`. Für alle vier auf einmal:

```bash
cd /opt/elektron-net-stack
for d in elektron-net elektron-net-ppool elektron-net-ppool-ui elektron-net-faucet; do
  (cd "$d" && git pull)
done
docker compose up -d --build
```

### C) Docker-Images aktualisieren (Caddy, MariaDB)

`caddy` und `elektron-faucet-db` sind fertige Images von Docker Hub (kein
eigener Build) -- neue Version holen und Container damit neu starten:

```bash
cd /opt/elektron-net-stack
docker compose pull caddy elektron-faucet-db
docker compose up -d
```

Die Datenbank-Daten liegen im Bind-Mount `./data/faucet-db` und bleiben
beim Image-Update erhalten (MariaDB-Minor-Updates sind abwärtskompatibel;
bei einem Major-Versionssprung vorher deren Release-Notes prüfen).

### Alles zusammen (Wartungsfenster)

```bash
cd /opt/elektron-net-stack
for d in elektron-net elektron-net-ppool elektron-net-ppool-ui elektron-net-faucet; do
  (cd "$d" && git pull)
done
docker compose pull
docker compose up -d --build
```

Kurzer Hinweis: Der `elektron-net`-Container neu zu starten unterbricht kurz
den P2P-Betrieb (Sekunden bis wenige Minuten, bis der Node wieder
synchron ist) -- für den Node am besten eine ruhige Zeit wählen, Pool und
Faucet sind davon unabhängig neu startbar.

## Externe Wallets importieren (WIF/Private Key)

Hast du eine Adresse offline erzeugt (z. B. mit
`elektron-net/mining/generate_address.py`, wie deine Datei in
`external-wallets/`) und willst den Private Key irgendwo nutzbar machen --
zum Ausgeben, zum Beobachten, oder um sie einer GUI-Wallet hinzuzufügen --
**wichtig:** `importprivkey` und `dumpwallet` gibt es in diesem Fork nicht
mehr (`error code: -32601, Method not found`, live getestet). Er nutzt wie
modernes Bitcoin Core ausschließlich Descriptor-Wallets; der Ersatz ist
`importdescriptors`. Drei Wege, je nachdem wo du den Import machen willst:

### A) Auf dem Hetzner-Server, in den laufenden Node (CLI)

Nutzt den ohnehin laufenden `elektron-net`-Container aus diesem Stack --
kein zusätzliches Programm nötig:

```bash
cd /opt/elektron-net-stack

# 1. Eigene Wallet dafür anlegen (getrennt von pool/faucet, ohne
#    automatisch generierte Keys)
docker compose exec elektron-net elektron-cli createwallet "prepaid" false true

# 2. Checksum für den Descriptor holen -- combo(...) leitet daraus alle drei
#    Standard-Adressformate ab (P2PKH, P2SH-SegWit, P2WPKH/bech32), nicht
#    nur eins:
docker compose exec elektron-net elektron-cli getdescriptorinfo "combo(<WIF>)"
# -> Feld "checksum" aus der Antwort kopieren, z. B. "7xr75u5v"

# 3. Mit WIF + Checksum importieren
docker compose exec elektron-net elektron-cli -rpcwallet=prepaid importdescriptors \
  '[{"desc": "combo(<WIF>)#<checksum>", "timestamp": 0, "label": "prepaid-import"}]'
```

`timestamp`: **`0`** durchsucht die komplette Chain nach bereits
vorhandenen UTXOs für diese Adresse -- nötig, wenn schon vor dem Import
ELEK draufgeschickt wurde (kann laut Bitcoin-Core-Doku bei einer sehr
alten Adresse über eine Stunde dauern). **`"now"`** überspringt das
Scannen komplett, nur sinnvoll bei einem brandneuen, nie benutzten Key.

Danach normal nutzbar: `docker compose exec elektron-net elektron-cli
-rpcwallet=prepaid getbalance`, `sendtoaddress`, `listunspent`, usw.

### B) Lokal auf Windows -- offizielle GUI-Wallet (elektron-qt)

Für den Fall, dass du den Key nicht auf dem Server, sondern lokal auf
deinem eigenen Windows-Rechner verwalten willst, ohne selbst etwas zu
kompilieren:

1. Offizielles Release herunterladen: [github.com/kutlusoy/elektron-net/releases](https://github.com/kutlusoy/elektron-net/releases)
   -- entweder das portable ZIP oder den Setup-Installer (`elektron-net-windows-*_portable.zip`
   bzw. `..._setup.exe`).
2. `elektron-qt.exe` starten (das ist die GUI, Pendant zu Bitcoin-Qt --
   läuft als eigener, vollständiger Node, synchronisiert selbst mit dem
   Elektron-Net-Netzwerk).
3. **Es gibt keinen eigenen "Private Key importieren"-Dialog in der GUI**
   -- das war auch in Bitcoin-Qt nie der Fall. Stattdessen: Menü
   **Hilfe -> Debug-Fenster -> Konsole** (bzw. *Help -> Debug window ->
   Console* im englischen Original) öffnen und dort exakt dieselben drei
   Befehle wie unter A) eintippen (ohne das `docker compose exec
   elektron-net`-Präfix -- die Konsole spricht schon direkt mit dem
   lokalen Node):
   ```
   createwallet "prepaid" false true
   getdescriptorinfo "combo(<WIF>)"
   importdescriptors [{"desc": "combo(<WIF>)#<checksum>", "timestamp": 0, "label": "prepaid-import"}]
   ```
4. Guthaben/Adressen erscheinen danach im normalen Wallet-Tab der GUI.

Diese lokale GUI-Wallet ist komplett unabhängig vom Hetzner-Stack -- sie
synchronisiert ihre eigene Kopie der Chain und hat nichts mit den
Pool-/Faucet-Wallets auf dem Server zu tun.

### C) Andere Methoden (kurz)

- **Reines `elektron-cli` ohne GUI**, z. B. auf einem zweiten Server oder
  lokal: dieselben drei Befehle aus A), nur direkt gegen den lokal
  laufenden `elektrond` statt über `docker compose exec`.
- **Nur beobachten, nicht ausgeben können** (watch-only, kein Private Key
  in der Zielwallet): `createwallet "beobachtung" true` (der zweite
  Parameter -- `disable_private_keys` -- macht sie watch-only), dann
  `importdescriptors` mit einem Descriptor **ohne** Private Key (nur die
  Adresse/den Public Key), z. B. `addr(<Adresse>)` statt `combo(<WIF>)`.
- Alle Wege erzeugen am Ende dieselben Adressen aus demselben Key -- welche
  Methode du nimmst, hängt nur davon ab, wo du den Key benutzen willst,
  nicht von einer technischen Einschränkung.

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

**IPv6 im Stack:** P2P (8333), Stratum (3333) und Caddy (80/443) werden im
mitgelieferten `docker-compose.yml` ganz normal nur mit der einfachen
Form (`"PORT:PORT"`, ohne Host-IP) published -- Docker legt dafür selbst
(ab Docker Engine 27, getestet mit 27.5.1) automatisch zwei
`docker-proxy`-Prozesse an, einen für `0.0.0.0` (IPv4) und einen für `[::]`
(IPv6), und leitet beide an den (intern weiterhin IPv4-basierten)
Container weiter. Das braucht keine Docker-Daemon-Konfiguration und keine
zusätzliche `"[::]:PORT:PORT"`-Zeile -- eine frühere Version dieser Datei
hatte zusätzlich genau so eine Zeile explizit gesetzt, was auf manchen
Docker-Versionen zu `Error ... bind: address already in use` führt (der
explizite Eintrag kollidiert mit der Docker-eigenen automatischen
IPv6-Bindung). Sobald die AAAA-Records oben stehen, ist alles automatisch
auch über IPv6 erreichbar -- prüfen mit `ss -tlnp | grep <port>`, sollte
sowohl eine `0.0.0.0`- als auch eine `[::]`-Zeile mit `docker-proxy`
zeigen.

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

## Seeder (optional, Testphase)

[`elektron-net-seeder`](https://github.com/kutlusoy/elektron-net-seeder) ist
ein DNS-Seed-Crawler (ein klassischer Bitcoin-`dnsseed`-Fork): er verbindet
sich laufend zu bekannten Elektron-Net-Peers, prüft ihre Erreichbarkeit und
beantwortet DNS-Anfragen mit einer Liste aktuell gut erreichbarer Nodes --
genau das, was `elektron-qt`/`elektrond` beim ersten Start abfragen, um ohne
fest einprogrammierte Adressliste ins Netzwerk zu finden.

**Ressourcenbedarf auf Hetzner:** sehr gering. Laut Upstream-README nur "a
few tens of megabytes" RAM und niedrige CPU-Last -- die vielen Crawler-Threads
(Default 96) sind I/O-gebunden (warten auf TCP-Antworten der gecrawlten
Peers), nicht CPU-intensiv. Passt problemlos neben Node/Pool/Faucet auf
denselben Server, ohne dass zusätzliche Hetzner-Ressourcen nötig wären. Es
gibt **keinen** eigenen P2P-Port zum Veröffentlichen -- der Seeder verbindet
sich nur ausgehend zu anderen Nodes, er nimmt selbst keine P2P-Verbindungen
an. Einzig offener Port: **53 (DNS, UDP + TCP)**.

**Warum vorerst optional:** Der Seeder braucht eine eigene, von den anderen
drei Domains unabhängige DNS-Konfiguration -- eine **NS-Delegation** (nicht
nur einen A/AAAA-Eintrag wie `NODE_DOMAIN`/`POOL_DOMAIN`/`FAUCET_DOMAIN`),
damit `SEEDER_HOST` überhaupt als autoritativer DNS-Seed funktioniert. Das
ist ein anderer, fehleranfälligerer DNS-Schritt als die übrigen drei Domains
und will vor dem produktiven Einsatz (z.B. Verlinken als `seednode=` in
`elektron.conf` oder öffentliches Bewerben) erst getestet sein -- daher ist
`INSTALL_SEEDER` standardmäßig `false`: ein normaler Stack-Lauf klont, baut
und startet den Seeder gar nicht (das zugehörige Docker-Compose-Profil
`seeder` bleibt inaktiv).

### Aktivieren

Entweder in `elektron-stack.conf` setzen:

```ini
INSTALL_SEEDER=true
SEEDER_HOST=seeder.elektron-net.org
SEEDER_NS=node1.elektron-net.org
SEEDER_MBOX=admin.elektron-net.org
```

oder beim interaktiven Lauf von `./install-elektron-stack.sh` die
entsprechende Frage mit `j` beantworten. `SEEDER_NS` kann derselbe Server
sein wie der Node (`NODE_DOMAIN`) -- er muss nur als autoritativer
Nameserver für `SEEDER_HOST` in DNS eingetragen sein (siehe unten).
`SEEDER_MBOX` ist eine E-Mail-Adresse für den SOA-Record, mit `@` als `.`
geschrieben (z.B. `admin.elektron-net.org` für `admin@elektron-net.org`).

Ein erneuter Lauf mit `INSTALL_SEEDER=true` klont `elektron-net-seeder`,
schreibt `elektron-net-seeder/.env`, baut das Image und startet den
Container zusätzlich zum Rest des Stacks -- alles andere (Node, Pool,
Faucet) bleibt unverändert, wie bei jedem Rerun. `docker-compose.yml` wird
bei jedem Lauf komplett neu geschrieben, aber die Service-Blöcke der
anderen Container bleiben dabei Byte-für-Byte identisch -- Compose erkennt
also keine Konfigurationsänderung an ihnen und fasst sie nicht an
(kein Neustart, kein Rebuild, kein Downtime für Node/Pool/Faucet/Caddy).
Einzige Voraussetzung: `AUTO_UPDATE_REPOS` bleibt auf `false` (Default) und
du änderst beim selben Lauf keine anderen Einstellungen -- sonst würde
natürlich genau der geänderte Service neu gebaut, wie bei jedem normalen
Rerun auch ohne Seeder.

### Wieder deaktivieren ("deinstallieren")

`INSTALL_SEEDER` wieder auf `false` setzen (in `elektron-stack.conf`, oder
bei der interaktiven Frage mit `n`/Enter antworten) und
`./install-elektron-stack.sh` erneut laufen lassen reicht aus -- das Skript
kümmert sich dabei selbst um einen sauberen Rückbau, **bevor** es
kein Compose-`up` mehr für den Seeder ausführt:

- stoppt und entfernt einen zuvor gestarteten `elektron-net-seeder`-Container
  (ein reines Deaktivieren des Compose-Profils allein würde einen bereits
  laufenden Container sonst einfach unangetastet weiterlaufen lassen --
  das Skript macht diesen Schritt explizit)
- schließt Port 53 (UDP+TCP) in `ufw` wieder, sofern `FIREWALL_AUTO_CONFIGURE=true`
  (Hetzner Cloud-Firewall-Panel bitte weiterhin manuell prüfen/anpassen)

**Bleibt bewusst erhalten**, damit ein späteres Wiederaktivieren nicht bei
null anfängt: der geklonte Quellcode in `elektron-net-seeder/`, die
`.env`-Datei darin, und vor allem `data/elektron-net-seeder/dnsseed.dat` /
`dnsseed.dump` (der bisherige Crawl-Fortschritt). Willst du auch das
vollständig entfernen: `rm -rf elektron-net-seeder data/elektron-net-seeder`
nach dem Deaktivieren.

Ganz ohne das Skript geht es genauso manuell, falls du schneller nur diesen
einen Container anfassen willst:

```bash
docker compose stop elektron-net-seeder
docker compose rm -f elektron-net-seeder
sudo ufw delete allow 53/udp
sudo ufw delete allow 53/tcp
```

### DNS-Delegation einrichten

**Wichtiger Unterschied zu den anderen drei Domains:** Ein A/AAAA-Record
(wie bei `NODE_DOMAIN`/`POOL_DOMAIN`/`FAUCET_DOMAIN`) reicht hier NICHT.
Ein A/AAAA-Record auf `SEEDER_HOST` würde nur bedeuten "diese Domain zeigt
auf diese feste IP" -- die Anfrage wird dabei direkt von deinem normalen
DNS-Anbieter (z.B. world4you) beantwortet und erreicht den Seeder-Container
**nie**, egal ob er läuft oder nicht.

Damit `SEEDER_HOST` tatsächlich als DNS-Seed funktioniert, muss die Zone
per **NS-Record** an einen bereits auflösenden Nameserver delegiert werden
-- genau der Mechanismus, den jeder "echte" DNS-Seed nutzt (z.B.
`seed.bitcoin.sipa.be`). `node1.elektron-net.org` hat bereits eigene
A/AAAA-Records (aus Schritt 1 oben) und eignet sich daher direkt als
`SEEDER_NS`:

| Subdomain | Typ | Ziel |
|---|---|---|
| `seeder.elektron-net.org` | **NS** | `node1.elektron-net.org` (bzw. dein `SEEDER_NS`) |

**Falls für `SEEDER_HOST` bereits eigene A/AAAA-Records angelegt wurden**
(z.B. weil das vor diesem Abschnitt naheliegend schien): die müssen
wieder **entfernt** werden. NS- und A/AAAA-Records für denselben Namen
gleichzeitig ergeben eine widersprüchliche ("lame") Delegation -- je nach
DNS-Anbieter gewinnt dann mal der A-Record (Anfragen erreichen den Seeder
nie), mal wird die Delegation ignoriert. Nur der NS-Record darf für
`seeder.elektron-net.org` stehen bleiben.

Prüfen, sobald propagiert:

```bash
dig -t NS seeder.elektron-net.org
```

Die Antwort sollte den NS-Eintrag zeigen, keinen A/AAAA-Eintrag mehr. Bis
die Delegation propagiert ist, kannst du trotzdem direkt gegen den
Container testen (siehe unten) -- dafür sind vorhandene A/AAAA-Records auf
`SEEDER_HOST` sogar praktisch, aber eben nur für diesen manuellen Test,
nicht für den eigentlichen Seed-Betrieb.

### Erste Tests, bevor es live geht

```bash
# Direkt gegen den laufenden Container fragen (per IP oder, falls noch
# A/AAAA-Records existieren, auch per Name) -- funktioniert auch schon VOR
# propagierter NS-Delegation, da es den Server direkt anspricht statt über
# die normale DNS-Auflösungskette zu gehen:
dig @<SERVER_IP> -p 53 seeder.elektron-net.org

# Sobald die NS-Delegation oben propagiert UND die alten A/AAAA-Records
# entfernt sind, sollte auch die ganz normale Auflösung funktionieren:
dig seeder.elektron-net.org

# Logs beobachten -- die ersten Antworten dauern etwas, der Seeder muss
# erst genug Peers erfolgreich crawlen, bevor GetIPList etwas liefert:
docker compose logs -f elektron-net-seeder

# Crawl-Status aller bekannten Peers (IP, letzter Kontakt, Erfolgsrate):
cat data/elektron-net-seeder/dnsseed.dump
```

Erst wenn `dig seeder.elektron-net.org` (die ganz normale Auflösung, nicht
nur `dig @<SERVER_IP>`) zuverlässig IP-Adressen zurückgibt und
`dnsseed.dump` plausible, aktuelle Peers zeigt, würde ich es als
`seednode=`/`dnsseed=` produktiv verlinken oder öffentlich bewerben.

### Konfigurierbare Felder (`elektron-net-seeder/.env`)

| Variable | Bedeutung | Default |
|---|---|---|
| `SEEDER_HOST` | Hostname des DNS-Seeds selbst | -- (Pflicht) |
| `SEEDER_NS` | Autoritativer Nameserver dafür | -- (Pflicht) |
| `SEEDER_MBOX` | E-Mail für SOA-Record (`@` als `.`) | -- (Pflicht) |
| `SEEDER_DNS_PORT` | UDP/TCP-Port für DNS-Antworten | `53` |
| `SEEDER_BIND_ADDRESS` | Bind-Adresse | `::` (alle) |
| `SEEDER_THREADS` | Parallele Crawler-Threads | `96` |
| `SEEDER_DNS_THREADS` | DNS-Server-Threads | `4` |
| `SEEDER_P2P_PORT` | P2P-Port der gecrawlten Peers | leer = `8333` (Elektron-Default) |
| `SEEDER_MAGIC` | Netzwerk-Magic-Bytes (hex) | leer = Elektron-Net-Default |
| `SEEDER_MIN_HEIGHT` | Mindest-Blockhöhe, ab der ein Peer als "good" gilt | `70000` (siehe unten) |
| `SEEDER_EXTRA_SEEDS` | Komma-getrennt, ersetzt die eingebaute Startliste | leer |
| `SEEDER_FILTERS` | Komma-getrennt, erlaubte Service-Flag-Kombinationen | leer (alle) |
| `SEEDER_TESTNET` / `SEEDER_WIPE_BAN` / `SEEDER_WIPE_IGNORE` | `true`/`false` | `false` |

`SEEDER_P2P_PORT` und `SEEDER_MAGIC` müssen normalerweise **nicht** gesetzt
werden -- der Seeder verwendet bereits standardmäßig Elektron Nets eigenen
P2P-Port (8333) und Netzwerk-Magic, genau wie `elektron-net` selbst.

### Wann gilt ein Peer als "good"? (wird über DNS verteilt)

Ein gecrawlter Peer muss zuerst **alle** dieser Hart-Filter bestehen:

| Prüfung | Bedingung |
|---|---|
| Port | exakt `8333` (bzw. `SEEDER_P2P_PORT`) |
| Services | bietet `NODE_NETWORK` an (voller Node) |
| Routability | öffentliche, routbare IP (keine privaten/lokalen Adressen) |
| Protokoll-Version | ≥ 70017 -- fest im Seeder-Quellcode (`db.h`, `REQUIRE_VERSION`), da Elektron Net keine älteren Versionen kennt; jeder Peer darunter gehört nicht zum Netzwerk |
| Blockhöhe | ≥ `SEEDER_MIN_HEIGHT` (Default `70000` -- bewusst niedrig gehalten, da Elektron Net noch eine junge Chain ist und Starthilfe braucht, statt des eingebauten Mainnet-Standards von 350000) |

Danach genügt **eine** von mehreren Zuverlässigkeits-Bedingungen: entweder
der allererste erfolgreiche Kontakt bei einem neuen Peer (Vertrauensvorschuss
für die ersten drei Versuche), oder eine ausreichend hohe Erfolgsquote über
eines von fünf rollierenden Zeitfenstern (2h/8h/1d/1Woche/1Monat) -- je
länger das Fenster, desto niedriger die geforderte Quote, aber desto mehr
Stichproben werden verlangt. Einmal als "good" markiert, bleibt ein Peer es,
bis ein späterer fehlgeschlagener Kontakt ihn wieder aus der Liste entfernt.

### StartOS-Variante

Es gibt zusätzlich [`elektron-seeder-startos`](https://github.com/kutlusoy/elektron-seeder-startos),
einen StartOS-Service-Wrapper für denselben Seeder (z.B. für einen
Heim-Server hinter FritzBox+DynDNS). Diese Docker-Compose-Integration hier
ist davon unabhängig und wird aktuell bevorzugt weiterentwickelt -- die
StartOS-Variante wird vorerst nicht aktiv gepflegt.

## Wichtig

- `install.php` im Faucet nach erfolgreicher Einrichtung löschen:
  `docker compose exec elektron-faucet-app rm public/install.php`
- Beide `.env`-Dateien haben reale Passwörter — nicht committen, Rechte
  einschränken (`chmod 600`).
- `node1.elektron-net.org` hat absichtlich keinen Caddy-Block — das ist der
  reine P2P-Seed, kein Webdienst.
- Nutzt du `install-elektron-stack.sh`, liegt zusätzlich eine gebündelte
  Übersicht aller Zugangsdaten in `$STACK_DIR/ZUGANGSDATEN.txt` (`chmod 600`,
  wird bei jedem Lauf aktualisiert), inklusive der vollständigen
  Private-Key-Exports von Pool-/Faucet-Wallet
  (`data/elektron-net/*-wallet-privkeys-backup.txt`) und allem, was in
  `external-wallets/` liegt — einmalig offline sichern (siehe
  ["Dateien auf den Server bringen"](#dateien-auf-den-server-bringen-nur-hetzner-console-windows)
  für WinSCP/scp), dann auf dem Server unter Verschluss lassen. Das ist die
  brisanteste Datei im Stack — Zugriff darauf = Kontrolle über alle
  Guthaben.
