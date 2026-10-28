# pacgrab

> Paste a URL, get the app. A "Gear Lever"-style manager for local PKGBUILDs on Arch Linux.

`pacgrab` turns a GitHub release URL (or any direct download link) into a proper
local Arch package. It generates a PKGBUILD, builds it with `makepkg`, serves the
result from a local pacman repository, and keeps it up to date — so apps you
install from a URL install, update, and uninstall like any other package.

- **`pacgrab`** — the CLI (pure Bash, no runtime deps beyond `pacman`/`makepkg`).
- **`pacgrab-tui.sh`** — an optional [gum](https://github.com/charmbracelet/gum)-based TUI front-end.

## Why

Many desktop apps are only published as a GitHub release tarball, an AppImage,
a `.deb`, or a bare binary — there is no Arch package for them. `pacgrab`
bridges that gap: it wraps any of those into a real package backed by a local
repo, so you get version tracking, dependency handling, clean upgrades and
uninstalls — without hand-writing a PKGBUILD. It is just a local database of
URL-fetched apps: every recipe lives in `~/pacgrab` and comes from a link you
paste.

## How it works

Everything lives in a base directory (default `~/pacgrab`, override with
`AUR_LOCAL`):

```
~/pacgrab/
├── pacgrab                 # this tool
├── pacgrab-tui.sh          # optional TUI
├── <pkgname>/              # one recipe dir per app (generated)
│   ├── PKGBUILD
│   ├── .SRCINFO
│   └── <pkgname>.desktop   # generated when the app ships none
└── *.pkg.tar.zst           # the flat package "pool" served to pacman
```

`pacgrab repo` indexes the pool into a local database (`pacgrab.db`) that you add
to `/etc/pacman.conf`. From then on the apps are ordinary packages: `pacman -Syu`
upgrades them, `pacman -R` removes them.

```
[pacgrab]
SigLevel = Optional TrustAll
Server = file:///home/YOU/pacgrab
```

## Install

One line, no git needed:

```sh
curl -fsSL https://raw.githubusercontent.com/adior-enigmac/pacgrab/main/install.sh | bash
```

This downloads `pacgrab` and `pacgrab-tui.sh` into `~/pacgrab`, symlinks them
into `~/.local/bin`, then runs **`pacgrab setup`**, which:

- creates the local package pool + an empty `pacgrab.db`, and
- appends the `[pacgrab]` section to `/etc/pacman.conf` (asks for `sudo` once).

Both steps are **idempotent** — re-running `pacgrab setup` is safe and won't
duplicate the config block. When it finishes, sync so pacman picks the repo up:

```sh
sudo pacman -Sy
```

### Manual install

Prefer to do it by hand? Copy the scripts wherever you like, then run setup:

```sh
install -Dm755 pacgrab        ~/.local/bin/pacgrab
install -Dm755 pacgrab-tui.sh ~/.local/bin/pacgrab-tui.sh
pacgrab setup                 # seeds the db + writes /etc/pacman.conf
sudo pacman -Sy
```

If you'd rather edit `/etc/pacman.conf` yourself, `pacgrab repo` prints the
exact block to paste.

## Usage

```
pacgrab <url>             install app from a link (GitHub release or direct download)
pacgrab list              show managed packages and install status
pacgrab recipe [p ...]    look inside recipes: one line each, or print full PKGBUILD(s)
pacgrab check             show which GitHub packages have updates
pacgrab sync [name ...]   install recipe desktops+icons directly, no rebuild
pacgrab refresh <name>    regenerate recipe from its URL with current code
pacgrab bump <p> [ver]    bump version: GitHub API or explicit version
pacgrab edit <name>       open the PKGBUILD in $EDITOR
pacgrab new <name> O/R    scaffold a recipe by hand from GitHub owner/repo
pacgrab fix-conflicts     delete unowned files that would block pacgrab package installs
pacgrab prune [--yes]     delete recipes for apps that are not installed
pacgrab clean             delete build leftovers and partial downloads
pacgrab repo              regenerate the local pacman repo database
pacgrab setup             one-time: create repo db + add [pacgrab] to /etc/pacman.conf
```

Run `pacgrab help` for the same list. A bare URL short-circuits to install:

```sh
pacgrab https://github.com/owner/repo/releases/download/v1.2.3/app-linux-x86_64.tar.gz
```

### Autoupdates

GitHub-backed recipes self-update: `install.sh` enables a daily systemd user
timer that checks GitHub, rebuilds what's outdated and publishes it to the
local `[pacgrab]` repo (a timer session has no sudo, so it prints the
`sudo pacman -U ...` line for you to run instead), and updates the pacgrab
scripts themselves to the latest version from this repo. Logs land in
`~/.local/share/pacgrab/update.log`. To opt out:

```sh
systemctl --user disable --now pacgrab-update.timer
```

### The TUI

```sh
pacgrab-tui.sh          # interactive menu (requires gum)
pacgrab-tui.sh status   # plain-text status dump
```

## What it understands

`pacgrab install` inspects the download and picks a packaging strategy
automatically:

| Layout            | Detected from                                   | Result                          |
| ----------------- | ----------------------------------------------- | ------------------------------- |
| Structured tree   | `bin/` + `share/`                               | binaries → `/usr/bin`, data → `/usr/share` |
| AppImage          | `*.AppImage`                                     | → `/opt/<pkg>`, symlinked into `/usr/bin` |
| Debian package    | `*.deb`                                          | repacked from `data.tar.*`      |
| Opt tree          | launcher script / app binary deep in the tree    | whole tree → `/opt`             |
| Raw binary        | a bare ELF with no archive                       | straight to `/usr/bin`          |
| Cursor/icon theme | `index.theme`/`cursor.theme` + `cursors/`       | → `/usr/share/icons`            |

It also detects a `.desktop` and icon (falling back to the repo's own assets),
and probes whether the app is terminal vs GUI so the generated `.desktop` sets
`Terminal=` correctly.

### Supported formats

`pacgrab install` (and a bare URL) accept any of these, as a GitHub release URL
or a direct download link:

| Category          | Extensions                                                     | Handling                                          |
| ----------------- | -------------------------------------------------------------- | ------------------------------------------------- |
| Tarballs          | `.tar.gz` `.tgz` `.tar.xz` `.tar.bz2` `.tar.zst` `.tar.lzma`   | unpacked; layout auto-detected (see above)        |
| Zip               | `.zip`                                                         | unpacked; layout auto-detected                    |
| Other archives    | `.7z` `.cpio` `.rar` `.xz` `.bz2` `.zst` `.run`                | anything `bsdtar -tf` can list                    |
| AppImage          | `.AppImage`                                                    | `.desktop`/icons extracted → `/opt/<pkg>`         |
| Debian            | `.deb`                                                         | repacked from `data.tar.*`                        |
| RPM               | `.rpm`                                                         | read as a generic archive via `bsdtar`            |
| Bare binary       | *(no / unknown extension)*                                     | ELF magic (`\x7fELF`) detected → straight to `/usr/bin` |

Two things worth calling out:

- **GitHub auto-pick** — when resolving the latest release, pacgrab **prefers**
  `.tar.gz` `.tgz` `.tar.xz` `.AppImage` `.deb` `.zip`, and skips ARM/aarch64,
  macOS, Windows, `.exe`, source-only, and `.rpm` assets.
- **Sniffing** — a file with no recognized extension isn't rejected: if `bsdtar`
  can list it, it's treated as a tarball; if the first bytes are `\x7fELF`, it's
  installed as a single binary (this is how `sonora-bin` and other bare-binary
  releases work).

## Requirements

- Arch Linux with `pacman` + `makepkg` (`base-devel`)
- `curl`, `bsdtar`; `gum` for the TUI

## Notes

- The repo section **must not** be named `local` — libalpm reserves that name for
  the installed-packages database. `pacgrab` uses `[pacgrab]`.
- GitHub links autoupdate; other links install fine but you bump them manually.

## License

MIT.
