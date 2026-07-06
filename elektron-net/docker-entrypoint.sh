#!/bin/sh
set -e

# /data is bind-mounted from the host; fix ownership on every start in case
# it was created as root by Docker on first run.
chown -R elektron:elektron /data

# Drop root and exec the real command (elektrond by default, see Dockerfile CMD).
exec gosu elektron "$@"
