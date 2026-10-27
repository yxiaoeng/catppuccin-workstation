#!/usr/bin/env bash
# Catppuccin Workstation — customized installer.
#
# Based on:
#   https://github.com/barrychen38/catppuccin-workstation
#
# Personal fork:
#   https://github.com/yxiaoeng/catppuccin-workstation
#
# Installation:
#   git clone https://github.com/yxiaoeng/catppuccin-workstation.git
#   cd catppuccin-workstation
#   ./install.sh
#
# Zsh configuration is sourced directly from this Git repository.
# Existing ~/.zshrc content is preserved outside the managed block.
# Fully managed configuration files are backed up before replacement.
#
# This installer runs from a local clone of the repository.
set -euo pipefail

REPO_URL="https://github.com/yxiaoeng/catppuccin-workstation"
CLONE_DIR="$HOME/Workspace/catppuccin-workstation"
MANAGED="catppuccin-workstation"

NO_BREW=0
[[ "${1:-}" == "--no-brew" ]] && NO_BREW=1


info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWarning:\033[0m %s\n' "$*"; }

# --- 0. Platform check -------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This setup targets macOS only (lazygit/ghostty paths, osxkeychain). Aborting." >&2
  exit 1
fi

# --- 1. Locate the repo --------------------------------------------------------
# When piped from curl, this script runs without the repo next to it:
# clone to ~/.catppuccin-workstation and re-exec from there.
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [[ -z "$SCRIPT_DIR" || ! -f "$SCRIPT_DIR/Brewfile" || ! -f "$SCRIPT_DIR/config/zsh/zshrc" ]]; then
  info "Fetching the repository..."
  if [[ -d "$CLONE_DIR/.git" ]]; then
    git -C "$CLONE_DIR" pull --ff-only
  else
    if [[ -e "$CLONE_DIR" || -L "$CLONE_DIR" ]]; then
      echo "Cannot clone into existing non-repository path: $CLONE_DIR" >&2
      exit 1
    fi
    git clone --depth 1 "$REPO_URL" "$CLONE_DIR"
  fi
  exec bash "$CLONE_DIR/install.sh" "$@"
fi
REPO_DIR="$SCRIPT_DIR"

# --- 2. Dependencies via Homebrew ----------------------------------------------
if [[ $NO_BREW -eq 1 ]]; then
  info "Skipping Homebrew dependencies (--no-brew)"
else
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is not installed. Visit https://brew.sh first, or rerun with --no-brew." >&2
    exit 1
  fi
  info "Installing dependencies (this can take a while on first run)..."
  brew bundle install --file="$REPO_DIR/Brewfile"
fi

# --- 3. Backup helpers -----------------------------------------------------------
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
BACKED_UP=0

backup() {
  if [[ -e "$1" || -L "$1" ]]; then
    mkdir -p "$BACKUP_DIR/$(dirname "${1#"$HOME"/}")"
    mv "$1" "$BACKUP_DIR/${1#"$HOME"/}"
    BACKED_UP=1
  fi
}

# Install a file we fully own: skip if identical, back up the old one if not.
install_owned_file() {
  local src=$1 dst=$2
  mkdir -p "$(dirname "$dst")"
  if [[ -e "$dst" ]] && diff -q "$src" "$dst" >/dev/null 2>&1; then
    return 0
  fi
  backup "$dst"
  cp "$src" "$dst"
}

# Replace (or insert) a managed block in a config file we do NOT own.
# Re-running always refreshes the block in place; the rest of the file is kept.
# $2 is either a file path or a literal string.
set_managed_block() {
  local file=$1 content=$2 target=$1 link
  mkdir -p "$(dirname "$file")"
  touch "$file"
  # Replace the target atomically without detaching a user's dotfiles symlink.
  while [[ -L "$target" ]]; do
    link="$(readlink "$target")"
    if [[ "$link" == /* ]]; then
      target="$link"
    else
      target="$(dirname "$target")/$link"
    fi
  done
  local tmp
  tmp="$(mktemp "$(dirname "$target")/.catppuccin-workstation.XXXXXX")"
  cp -p "$target" "$tmp"
  if ! awk '
    /^# >>> catppuccin-workstation >>>$/ { if (managed) exit 1; managed=1; next }
    /^# <<< catppuccin-workstation <<<$/{ if (!managed) exit 1; managed=0; next }
    !managed { print }
    END { if (managed) exit 1 }
  ' "$target" > "$tmp"; then
    rm -f "$tmp"
    echo "Malformed managed block in $file; leaving it unchanged." >&2
    return 1
  fi
  {
    echo "# >>> $MANAGED >>>"
    if [[ -f "$content" ]]; then cat "$content"; else printf '%s\n' "$content"; fi
    echo "# <<< $MANAGED <<<"
  } >> "$tmp"
  mv "$tmp" "$target"
}


# --- 4. Zsh: source configuration directly from Git repo ------------------------
info "Linking Zsh configuration directly to Git repository..."

ZSH_CONFIG="$REPO_DIR/config/zsh/zshrc"

set_managed_block "$HOME/.zshrc" "source \"$ZSH_CONFIG\""

USER_SHELL="$(dscl . -read "$HOME" UserShell 2>/dev/null | awk '{print $2}' || true)"

# --- 5. Ghostty: managed block in the config --------------------------------------
info "Installing Ghostty settings (incremental)..."
GHOSTTY_CONFIG_DIR="${XDG_CONFIG_HOME:-"$HOME/.config"}/ghostty"
GHOSTTY_CFG="$GHOSTTY_CONFIG_DIR/config"
# macOS configs load after XDG configs; config.ghostty takes precedence over
# the legacy filename within each location. Keep the user's files in place.
for config_file in \
  "$GHOSTTY_CONFIG_DIR/config.ghostty" \
  "$HOME/Library/Application Support/com.mitchellh.ghostty/config" \
  "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"; do
  if [[ -e "$config_file" || -L "$config_file" ]]; then
    GHOSTTY_CFG="$config_file"
  fi
done
set_managed_block "$GHOSTTY_CFG" "$REPO_DIR/config/ghostty/config"

# --- 6. Font -----------------------------------------------------------------------
info "Installing Source Han Sans SC font..."
if [[ ! -e "$HOME/Library/Fonts/SourceHanSansSC-VF.ttf" ]]; then
  mkdir -p "$HOME/Library/Fonts"
  cp "$REPO_DIR/fonts/SourceHanSansSC-VF.ttf" "$HOME/Library/Fonts/"
fi

# --- 7. starship / bat -------------------------------------------------------------
info "Installing starship config..."
install_owned_file "$REPO_DIR/config/starship.toml" "$HOME/.config/starship.toml"

info "Installing bat config (incremental)..."
BAT_CFG="$HOME/.config/bat/config"
mkdir -p "$(dirname "$BAT_CFG")"
touch "$BAT_CFG"
grep -Eq '^[[:space:]]*--theme([=[:space:]]|$)' "$BAT_CFG" || echo '--theme="Catppuccin Macchiato"' >> "$BAT_CFG"
grep -Eq '^[[:space:]]*--style([=[:space:]]|$)' "$BAT_CFG" || echo '--style="numbers,changes,header"' >> "$BAT_CFG"

# --- 8. git + delta (incremental via `git config`) ----------------------------------
info "Installing delta settings into ~/.gitconfig (incremental)..."
GIT_THEME_CFG="$HOME/.config/git/catppuccin.gitconfig"
install_owned_file "$REPO_DIR/config/git/catppuccin.gitconfig" "$GIT_THEME_CFG"
if ! git config --global --get-all include.path | grep -Fx -- "$GIT_THEME_CFG" >/dev/null; then
  git config --global --add include.path "$GIT_THEME_CFG"
fi
git config --global core.pager delta
git config --global interactive.diffFilter 'delta --color-only'
git config --global delta.navigate true
git config --global delta.features catppuccin-macchiato
git config --global delta.line-numbers true
git config --global delta.decorations 'commit-style box'
git config --global delta.hide-plus-minus-markers false

# --- 9. lazygit ----------------------------------------------------------------------
info "Installing lazygit config..."
install_owned_file "$REPO_DIR/config/lazygit/config.yml" "$HOME/Library/Application Support/lazygit/config.yml"

# --- 12. bat themes ------------------------------------------------------------------------
info "Installing Catppuccin themes for bat..."
if command -v bat >/dev/null 2>&1; then
  bash "$REPO_DIR/scripts/bat-themes.sh"
else
  warn "bat not found; run scripts/bat-themes.sh after dependencies are installed."
fi

# --- 14. Done -----------------------------------------------------------------------------------
cat <<'EOF'

Done. Next steps:

  1. Set your git identity (if you haven't already):
       git config --global user.name  "Your Name"
       git config --global user.email "you@example.com"
  2. Restart your terminal (or open a new Ghostty window).
EOF

if [[ "$USER_SHELL" != */zsh && -n "$USER_SHELL" ]]; then
  echo "  3. Your login shell is $USER_SHELL — these configs target zsh."
  echo "     Switch with: chsh -s /bin/zsh"
fi

if [[ $BACKED_UP -eq 1 ]]; then
  echo
  echo "Replaced files were backed up under:"
  echo "  $BACKUP_DIR"
fi
