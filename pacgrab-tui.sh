#!/usr/bin/env bash
# pacgrab-tui.sh - Gum-based TUI for pacgrab (paste-URL installer)
# Usage: pacgrab-tui.sh [status|menu]
set -euo pipefail
BASE="${AUR_LOCAL:-$HOME/pacgrab}"
PACGRAB="$BASE/pacgrab"
# repo section name in /etc/pacman.conf + db file prefix (never "local" -
# libalpm reserves that name; see the REPO_NAME comment in the pacgrab script)
REPO_NAME="pacgrab"

pkg_info() {
  bash -c 'source "$1/PKGBUILD" 2>/dev/null || exit 1
    if declare -p pkgname 2>/dev/null | grep -q "declare -a"; then echo "${pkgname[*]}|$pkgver-$pkgrel"
    else echo "$pkgname|$pkgver-$pkgrel"; fi' _ "$1" || echo "?|?"
}

repo_state() {
  # count the pool (flat links in $BASE), not the recipe-dir copies
  if [ -f "$BASE/$REPO_NAME.db.tar.gz" ]; then
    echo "ready ($(compgen -G "$BASE/*.pkg.tar.zst" | wc -l) pkgs)"
  else
    echo "not built"
  fi
}
conf_state() {
  grep -q "^\[$REPO_NAME\]" /etc/pacman.conf 2>/dev/null && echo "enabled" || echo "missing"
}

cmd_status() {
  echo "== pacgrab status =="
  echo "bases: $(find "$BASE" -maxdepth 2 -name PKGBUILD | wc -l)  repo: $(repo_state)  pacman.conf [$REPO_NAME]: $(conf_state)"
  printf "%-24s %-12s %-30s\n" "BASE" "VERSION" "INSTALLED"
  for d in "$BASE"/*/; do
    [ -f "$d/PKGBUILD" ] || continue
    base=$(basename "$d"); info=$(pkg_info "$d")
    pns=${info%%|*}; pv=${info##*|}
    first=${pns%% *}
    inst=$(pacman -Q "$first" 2>/dev/null | cut -d' ' -f2 || echo "-")
    flag=""; [ "$inst" != "-" ] && [ "$inst" != "${pv%-*}" ] && [ "$inst" != "$pv" ] && flag=" (!)"
    printf "%-24s %-12s %-30s\n" "$base" "$pv" "$inst$flag"
  done
  echo ""
  echo "artifacts: $(du -sh "$BASE" 2>/dev/null | cut -f1)  repo pkgs: $(compgen -G "$BASE/*.pkg.tar.zst" | wc -l)"
  echo "peaclock dir: $(ls "$BASE/peaclock" 2>/dev/null | tr '\n' ' ')"
}

recipe_names() {
  for d in "$BASE"/*/; do [ -f "$d/PKGBUILD" ] && basename "$d"; done
}

# overview (all recipes) or one recipe's full PKGBUILD dump
cmd_recipes() {
  mapfile -t bases < <(recipe_names)
  [ ${#bases[@]} -gt 0 ] || { gum style --foreground 1 "no PKGBUILDs in $BASE"; return; }
  local pick
  pick=$(printf '%s\n' "[overview]" "${bases[@]}" | gum choose --header "Recipe (type to filter)") || return
  if [ "$pick" = "[overview]" ]; then
    "$PACGRAB" recipe 2>&1 | gum pager
  else
    "$PACGRAB" recipe "$pick" 2>&1 | gum pager
  fi
}

cmd_menu() {
  command -v gum >/dev/null || { echo "gum missing, falling back to status"; cmd_status; return; }
  while true; do
    gum style --foreground 5 --bold "pacgrab :: $(find "$BASE" -maxdepth 2 -name PKGBUILD | wc -l) pkgs · repo: $(repo_state) · [$REPO_NAME]: $(conf_state)"
    choice=$(gum choose --header "What to do?" \
      "Status" "Recipes" "Install from URL" "Check GH updates" \
      "Repo setup" "Clean artifacts" "View last log" "Quit") || break
    case "$choice" in
      Status) gum pager <<< "$(cmd_status)" ;;
      "Recipes") cmd_recipes ;;
      "Install from URL")
        url=$(gum input --placeholder "Paste GitHub release URL...") || continue
        [ -n "$url" ] && "$PACGRAB" install "$url" 2>&1 | gum pager ;;
      "Check GH updates") "$PACGRAB" check 2>&1 | gum pager ;;
      "Repo setup") "$PACGRAB" repo 2>&1 | gum pager ;;
      "Clean artifacts") "$PACGRAB" clean; gum style --foreground 2 "cleaned" ;;
      "View last log") log=$(ls -t /tmp/pacgrab-*.log 2>/dev/null | head -1); [ -n "${log:-}" ] && gum pager < "$log" || echo "no logs yet" ;;
      Quit) break ;;
    esac
  done
}

case "${1:-menu}" in
  status) cmd_status ;;
  menu) cmd_menu ;;
  *) echo "usage: $0 [status|menu]" ;;
esac
