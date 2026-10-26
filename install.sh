#!/usr/bin/env bash
# pacgrab installer - no git required.
#
#   curl -fsSL https://raw.githubusercontent.com/adior-enigmac/pacgrab/main/install.sh | bash  # nosemgrep
#
# What it does:
#   1. downloads pacgrab + pacgrab-tui.sh into the base dir (default ~/pacgrab)
#   2. symlinks them into ~/.local/bin so they are on PATH
#   3. runs `pacgrab setup`: seeds the local repo db and appends the [pacgrab]
#      section to /etc/pacman.conf (idempotent; asks for sudo once)
#   4. enables the weekly autoupdate timer (best-effort; opt out with
#      `systemctl --user disable --now pacgrab-update.timer`)
#
# Env overrides:
#   PREFIX     where to symlink the scripts  (default: ~/.local/bin)
#   AUR_LOCAL  pacgrab base/repo dir         (default: ~/pacgrab)
set -euo pipefail

REPO="adior-enigmac/pacgrab"
BRANCH="main"
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH"
PREFIX="${PREFIX:-$HOME/.local/bin}"
BASE="${AUR_LOCAL:-$HOME/pacgrab}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: missing $1" >&2; exit 1; }; }
need curl

echo "installing pacgrab -> $BASE"
mkdir -p "$BASE" "$PREFIX"

# download the two scripts; -f fails on HTTP error, -L follows redirects
for f in pacgrab pacgrab-tui.sh; do
  echo "  fetching $f"
  curl -fsSL "$RAW/$f" -o "$BASE/$f"
done
chmod +x "$BASE/pacgrab" "$BASE/pacgrab-tui.sh"

# symlink into PREFIX (idempotent) so updates to $BASE are picked up immediately
for f in pacgrab pacgrab-tui.sh; do
  ln -sf "$BASE/$f" "$PREFIX/$f"
done
echo "symlinked into $PREFIX"

# seed the repo db + wire up /etc/pacman.conf
"$BASE/pacgrab" setup

# weekly autoupdates: enable the user timer (best-effort - needs a user systemd
# session, which a normal login shell has; failure only means no auto-updates)
"$BASE/pacgrab" timer-setup || echo "note: update timer not enabled - run: systemctl --user enable --now pacgrab-update.timer"

echo
echo "done. next steps:"
echo "  sudo pacman -Sy                     # sync so the [pacgrab] repo is known"
echo "  pacgrab https://github.com/.../vX.Y.Z/app-linux-x86_64.tar.gz"
echo "  pacgrab -S <pkg>                    # AUR replacement"
echo "  pacgrab-tui.sh                      # interactive menu (needs gum)"
case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *) echo; echo "note: $PREFIX is not on PATH - add it:"; echo "  export PATH=\"$PREFIX:\$PATH\"" ;;
esac
