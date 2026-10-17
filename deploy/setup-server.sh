#!/usr/bin/env bash
# One-time server setup for deploying the landing (whobook.ru) from GitHub Actions:
#   - installs rsync: the deploy copies the built site with it
#   - creates user "landing": no password, no sudo, no docker, SSH key login only
#   - gives the landing folder /var/www/whobook.ru to that user (nginx already serves this folder)
#   - lets the deploy key do one thing only: rsync into that folder (rrsync)
# It only adds its own things: nginx configs, other users and the app are not touched.
# Safe to run again; with a new key file it replaces the previous landing deploy key.
#
# Usage (as root), with the public deploy key in landing-deploy.pub next to this script:
#   sudo bash setup-server.sh
set -Eeuo pipefail

DEPLOY_USER="landing"
# Marks the user as created by this script, so an unrelated user with the same name is never taken over.
DEPLOY_USER_GECOS="personal-crm-landing deploy"
SITE_DIR="/var/www/whobook.ru"

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUB_KEY_FILE="$SRC_DIR/landing-deploy.pub"
LOG_FILE="$SRC_DIR/setup.log"
APT="apt-get -y -q -o DPkg::Lock::Timeout=300"

export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
trap 'printf "\nERROR: command failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

[ "$(id -u)" -eq 0 ] || die "run as root: sudo bash $0"
exec > >(tee "$LOG_FILE") 2>&1

# ---------------------------------------------------------------- key file
log "Deploy key"
[ -f "$PUB_KEY_FILE" ] || die "no $PUB_KEY_FILE: put the public deploy key there"
read -r key_type key_body key_comment < "$PUB_KEY_FILE" || true
[ "${key_type:-}" = "ssh-ed25519" ] && [ -n "${key_body:-}" ] || die "$PUB_KEY_FILE is not an ed25519 public key"
ssh-keygen -lf "$PUB_KEY_FILE" >/dev/null || die "$PUB_KEY_FILE is not a valid public key"
info "$(ssh-keygen -lf "$PUB_KEY_FILE")"

# ---------------------------------------------------------------- rsync
log "rsync"
if command -v rsync >/dev/null 2>&1; then
  info "already installed"
else
  $APT update
  $APT install rsync
  info "installed"
fi
RRSYNC="$(command -v rrsync || true)"
[ -n "$RRSYNC" ] || die "rrsync not found (it comes with the rsync package)"
command -v python3 >/dev/null 2>&1 || die "python3 not found: rrsync needs it"
# sed reads the whole output: "head" would close the pipe early and trip the ERR trap.
info "$(rsync --version | sed -n 1p)"
info "rrsync: $RRSYNC"

# ---------------------------------------------------------------- user
log "User $DEPLOY_USER"
if id "$DEPLOY_USER" >/dev/null 2>&1; then
  gecos="$(getent passwd "$DEPLOY_USER" | cut -d: -f5)"
  [ "$gecos" = "$DEPLOY_USER_GECOS" ] || die "user $DEPLOY_USER exists but was not created by this script"
  info "already exists"
else
  useradd --create-home --user-group --shell /bin/bash --comment "$DEPLOY_USER_GECOS" "$DEPLOY_USER"
  info "created (no password: SSH key login only)"
fi
groups="$(id -nG "$DEPLOY_USER")"
[ "$groups" = "$DEPLOY_USER" ] || die "$DEPLOY_USER must have no extra groups, has: $groups"
info "groups: $groups (no sudo, no docker)"
DEPLOY_HOME="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)"

# ---------------------------------------------------------------- site folder
log "Site folder $SITE_DIR"
# nginx (whobook.ru.conf) already serves this folder; the deploy user becomes its owner.
install -d -m 0755 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$SITE_DIR"
info "$(stat -c '%U:%G %a %n' "$SITE_DIR")"

# ---------------------------------------------------------------- authorized key
log "SSH access for $DEPLOY_USER"
# restrict: no shell, no port/agent/X11 forwarding; rrsync: only rsync, only inside SITE_DIR.
install -d -m 0700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$DEPLOY_HOME/.ssh"
tmp="$(mktemp)"
printf 'restrict,command="%s %s" %s %s %s\n' "$RRSYNC" "$SITE_DIR" "$key_type" "$key_body" "${key_comment:-}" > "$tmp"
install -m 0600 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$tmp" "$DEPLOY_HOME/.ssh/authorized_keys"
rm -f "$tmp"
info "$DEPLOY_HOME/.ssh/authorized_keys:"
ssh-keygen -lf "$DEPLOY_HOME/.ssh/authorized_keys" | sed 's/^/      /'
info "allowed command: $RRSYNC $SITE_DIR"

echo
echo "DONE"
