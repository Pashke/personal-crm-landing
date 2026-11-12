#!/usr/bin/env bash
# Installs the nginx config of the landing (whobook.ru) on the server and reloads nginx:
#   - copies nginx/whobook.ru.conf (next to this script) to /etc/nginx/sites-available/whobook.ru.conf
#     and makes sure sites-enabled links to it
#   - checks the whole nginx setup with "nginx -t"; if the check fails, puts the previous file back and stops,
#     so nginx keeps running with the old config
#   - reloads nginx only after a successful check: open connections are not dropped
# Touches only the landing's own file and its link. Other sites, snippets and nginx.conf are not changed.
# The first run replaces the stub that the app's server setup put there; that stub expects to be replaced.
# Safe to run again.
#
# Usage (as root), with nginx/whobook.ru.conf next to this script:
#   sudo bash install-nginx.sh
set -Eeuo pipefail

SITE="whobook.ru"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_CONF="$SRC_DIR/nginx/$SITE.conf"
DST_CONF="/etc/nginx/sites-available/$SITE.conf"
DST_LINK="/etc/nginx/sites-enabled/$SITE.conf"
# Our own files start with this line.
OWN_MARKER="# owner: personal-crm-landing"
# Files of the app's server setup carry this; its setup.sh overwrites only such files.
APP_MARKER="managed-by: personal-crm deploy/server-setup"

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
trap 'printf "\nERROR: command failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

[ "$(id -u)" -eq 0 ] || die "run as root: sudo bash $0"

# ---------------------------------------------------------------- new config
log "New config $SRC_CONF"
[ -f "$SRC_CONF" ] || die "no $SRC_CONF: copy deploy/nginx/$SITE.conf there"
[ "$(head -n 1 "$SRC_CONF")" = "$OWN_MARKER (deploy/nginx/$SITE.conf)" ] || die "$SRC_CONF does not start with the line \"$OWN_MARKER ...\""
! grep -qF "$APP_MARKER" "$SRC_CONF" || die "$SRC_CONF carries the app's marker: the app's setup.sh would overwrite it"
! grep -q $'\r' "$SRC_CONF" || die "$SRC_CONF has Windows line endings (CRLF)"
info "ok"

# ---------------------------------------------------------------- current config
log "Current config $DST_CONF"
if [ ! -e "$DST_CONF" ]; then
  info "absent"
elif [[ "$(head -n 1 "$DST_CONF")" == "$OWN_MARKER"* ]]; then
  info "the landing's own"
elif grep -qF "$APP_MARKER" "$DST_CONF"; then
  info "the stub of the app's server setup: replacing it"
else
  die "$DST_CONF was created neither by the landing nor by the app's setup: not touching it"
fi
if [ -L "$DST_LINK" ] && [ "$(readlink -f "$DST_LINK")" = "$DST_CONF" ]; then
  info "enabled: $DST_LINK -> $DST_CONF"
elif [ -e "$DST_LINK" ] || [ -L "$DST_LINK" ]; then
  die "$DST_LINK exists but is not a link to $DST_CONF: not touching it"
else
  info "not enabled yet"
fi

if [ -f "$DST_CONF" ] && cmp -s "$SRC_CONF" "$DST_CONF" && [ -L "$DST_LINK" ]; then
  log "Nothing to do"
  info "$DST_CONF is already the same as $SRC_CONF"
  exit 0
fi

# ---------------------------------------------------------------- install with rollback
log "Installing"
backup=""
if [ -f "$DST_CONF" ]; then
  backup="$(mktemp)"
  cp -p "$DST_CONF" "$backup"
fi
link_created=0
committed=0

# Until nginx is reloaded with the new config, any failure puts the previous state back.
rollback() {
  if [ -n "$backup" ]; then
    install -m 0644 -o root -g root "$backup" "$DST_CONF"
  else
    rm -f "$DST_CONF"
  fi
  [ "$link_created" -eq 0 ] || rm -f "$DST_LINK"
  printf '    rolled back: %s is as it was before, nginx keeps working with it\n' "$DST_CONF" >&2
}
trap '[ "$committed" -eq 1 ] || rollback; [ -z "$backup" ] || rm -f "$backup"' EXIT

install -m 0644 -o root -g root "$SRC_CONF" "$DST_CONF"
info "installed $DST_CONF"
if [ ! -L "$DST_LINK" ]; then
  ln -s "$DST_CONF" "$DST_LINK"
  link_created=1
  info "enabled: $DST_LINK -> $DST_CONF"
fi

log "Checking the nginx setup (nginx -t)"
nginx -t || die "nginx -t failed: the new config is not used"

log "Reloading nginx"
systemctl reload nginx
committed=1
info "done"

# ---------------------------------------------------------------- check
log "Response headers of https://$SITE/ (asked from the server itself)"
sleep 1
curl -sS -o /dev/null -D - --resolve "$SITE:443:127.0.0.1" "https://$SITE/" | sed 's/^/    /' \
  || info "could not ask https://$SITE/ from the server: check it from a browser"

echo
echo "DONE"
