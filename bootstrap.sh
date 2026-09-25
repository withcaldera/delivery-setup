#!/usr/bin/env bash
#
# bootstrap.sh — zero-friction macOS setup for Caldera delivery leads.
#
# Installs (or verifies) everything needed to run the `delivery` Claude Code
# plugin from the private withcaldera/delivery-plugin marketplace, in both the
# Claude desktop app and the `claude` terminal command.
#
# Safe to re-run: every step checks first and only changes what is missing.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/withcaldera/delivery-setup/main/bootstrap.sh | bash
#   bash bootstrap.sh --check     # report OK / MISSING for each item, change nothing
#   bash bootstrap.sh --yes       # skip the confirmation prompt
#
# This script never runs sudo. Homebrew's own installer may ask for your Mac
# password; that is Homebrew, not this script.
#
# The whole script is wrapped in main() and only invoked on the last line, so a
# partially downloaded copy (curl | bash) can never execute half-way.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PLUGIN_REPO="withcaldera/delivery-plugin"
MARKETPLACE="caldera"
PLUGIN="delivery"
ACCESS_CONTACT="Wade Kallhoff (wade.kallhoff@withcaldera.com)"

CLAUDE_SETTINGS="$HOME/.claude/settings.json"
CLAUDE_BIN_DIR="$HOME/.local/bin"
ZPROFILE="$HOME/.zprofile"
CLT_WAIT_MAX_SECONDS=2400   # 40 minutes; the Command Line Tools download can be slow

# Make plugin clones use HTTPS (the credential path we set up with gh), not SSH.
export CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1
# Never let git sit waiting for a password in the terminal.
export GIT_TERMINAL_PROMPT=0

# ---------------------------------------------------------------------------
# Flags and output helpers
# ---------------------------------------------------------------------------
CHECK=0
YES=0
MISSING=0
SUMMARY=()

usage() {
  sed -n '2,20p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//' || true
  echo "Flags: --check   report OK / MISSING for each item and change nothing"
  echo "       --yes     do not ask for confirmation before installing"
}

if [[ -t 1 ]]; then
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
  C_GREEN=""; C_YELLOW=""; C_RED=""; C_BOLD=""; C_OFF=""
fi

ok()    { echo "${C_GREEN}✓${C_OFF} $*"; }
doing() { echo "${C_YELLOW}→${C_OFF} $*"; }
fail()  { echo "${C_RED}✗${C_OFF} $*" >&2; }
note()  { echo "  $*"; }
header(){ echo; echo "${C_BOLD}$*${C_OFF}"; }

# report <label> <0|1 present> — used by --check mode
report() {
  local label="$1" present="$2"
  if [[ "$present" == "0" ]]; then
    echo "OK       $label"
  else
    echo "MISSING  $label"
    MISSING=$((MISSING + 1))
  fi
}

die() { fail "$*"; exit 1; }

# Append a line to ~/.zprofile if no line containing the given pattern exists.
persist_zprofile() {
  local pattern="$1" line="$2"
  touch "$ZPROFILE"
  if grep -qF -- "$pattern" "$ZPROFILE"; then
    return 0
  fi
  printf '\n%s\n' "$line" >> "$ZPROFILE"
  note "Added to ~/.zprofile: $line"
}

# ---------------------------------------------------------------------------
# Detection helpers (read-only)
# ---------------------------------------------------------------------------
brew_path() {
  if [[ -x /opt/homebrew/bin/brew ]]; then echo /opt/homebrew/bin/brew
  elif [[ -x /usr/local/bin/brew ]]; then echo /usr/local/bin/brew
  else return 1
  fi
}

has_clt()   { xcode-select -p >/dev/null 2>&1; }
has_brew()  { brew_path >/dev/null; }
has_gh()    { command -v gh >/dev/null 2>&1; }
has_claude(){ command -v claude >/dev/null 2>&1 || [[ -x "$CLAUDE_BIN_DIR/claude" ]]; }
gh_logged_in() { has_gh && gh auth status --hostname github.com >/dev/null 2>&1; }

gh_helper_configured() {
  git config --get-all credential.https://github.com.helper 2>/dev/null | grep -q 'gh auth git-credential'
}

repo_accessible() {
  # Exit 0 even for an empty repo; 128 when the account cannot see it.
  git ls-remote "https://github.com/$PLUGIN_REPO" HEAD >/dev/null 2>&1
}

path_persisted() {
  grep -qsF '.local/bin' "$ZPROFILE" || grep -qsF '.local/bin' "$HOME/.zshrc"
}

python_bin() {
  if [[ -x /usr/bin/python3 ]]; then echo /usr/bin/python3
  else command -v python3
  fi
}

# Returns 0 when settings.json already has the marketplace + plugin entries.
settings_configured() {
  [[ -f "$CLAUDE_SETTINGS" ]] || return 1
  "$(python_bin)" - "$CLAUDE_SETTINGS" "$MARKETPLACE" "$PLUGIN_REPO" "$PLUGIN" <<'PY'
import json, sys
path, mk, repo, plugin = sys.argv[1:5]
try:
    with open(path) as f:
        d = json.load(f)
except Exception:
    sys.exit(1)
m = (d.get("extraKnownMarketplaces") or {}).get(mk) or {}
src = m.get("source") or {}
ok = (src.get("source") == "github" and src.get("repo") == repo
      and m.get("autoUpdate") is True
      and (d.get("enabledPlugins") or {}).get(f"{plugin}@{mk}") is True)
sys.exit(0 if ok else 1)
PY
}

known_marketplaces_json() { echo "$HOME/.claude/plugins/known_marketplaces.json"; }

cli_marketplace_registered() {
  has_claude || return 1
  local f; f="$(known_marketplaces_json)"
  [[ -f "$f" ]] || return 1
  "$(python_bin)" - "$f" "$MARKETPLACE" <<'PY'
import json, os, sys
path, mk = sys.argv[1:3]
try:
    with open(path) as f:
        d = json.load(f)
except Exception:
    sys.exit(1)
e = d.get(mk)
sys.exit(0 if e and os.path.isdir(e.get("installLocation", "")) else 1)
PY
}

cli_plugin_installed() {
  has_claude || return 1
  claude plugin list --json 2>/dev/null | grep -q "\"id\": *\"$PLUGIN@$MARKETPLACE\""
}

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------
step_clt() {
  header "1/7  Xcode Command Line Tools (gives you git)"
  if has_clt; then ok "Already installed"; SUMMARY+=("✓ Command Line Tools"); return; fi
  doing "Installing. A macOS dialog will appear — click ${C_BOLD}Install${C_OFF}, then ${C_BOLD}Agree${C_OFF}."
  xcode-select --install >/dev/null 2>&1 || true
  note "Waiting for the install to finish (this can take 5–20 minutes)..."
  local waited=0
  until has_clt; do
    if (( waited >= CLT_WAIT_MAX_SECONDS )); then
      die "Command Line Tools still not installed after 40 minutes. Finish the dialog (or open Terminal and run: xcode-select --install), then re-run this script."
    fi
    sleep 10; waited=$((waited + 10))
    printf '.'
  done
  echo
  ok "Command Line Tools installed"; SUMMARY+=("✓ Command Line Tools (installed)")
}

step_brew() {
  header "2/7  Homebrew (installs command-line apps)"
  if ! has_brew; then
    doing "Installing Homebrew. It will explain what it does and ask for your ${C_BOLD}Mac login password${C_OFF} (nothing is shown while you type)."
    if [[ "$YES" == "1" ]]; then export NONINTERACTIVE=1; fi
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || die "Homebrew install did not finish. Re-run this script to try again."
    SUMMARY+=("✓ Homebrew (installed)")
  else
    ok "Already installed"; SUMMARY+=("✓ Homebrew")
  fi
  local brew; brew="$(brew_path)"
  eval "$("$brew" shellenv)"
  persist_zprofile "brew shellenv" "eval \"\$($brew shellenv)\""
}

step_gh() {
  header "3/7  GitHub command-line tool (gh)"
  if has_gh; then ok "Already installed"; SUMMARY+=("✓ gh"); return; fi
  doing "Installing gh with Homebrew..."
  brew install gh >/dev/null || die "brew install gh failed. Run 'brew install gh' in Terminal to see why, then re-run this script."
  ok "gh installed"; SUMMARY+=("✓ gh (installed)")
}

step_github_auth() {
  header "4/7  GitHub sign-in and access to the private plugin repo"
  if gh_logged_in; then
    ok "Signed in to GitHub as $(gh api user -q .login 2>/dev/null || echo '?')"
  else
    doing "Signing in to GitHub. Your browser will open."
    note "1. Copy the one-time code shown here, 2. press Enter, 3. paste the code in the browser and approve."
    gh auth login --web --git-protocol https --hostname github.com --skip-ssh-key \
      || die "GitHub sign-in did not finish. Re-run this script to try again."
    ok "Signed in to GitHub as $(gh api user -q .login 2>/dev/null || echo '?')"
  fi

  if gh_helper_configured; then
    ok "git is set up to use your GitHub sign-in (credential helper)"
  else
    doing "Letting git use your GitHub sign-in (needed for background plugin updates)..."
    gh auth setup-git --hostname github.com || die "gh auth setup-git failed."
    ok "Credential helper configured"
  fi

  if repo_accessible; then
    ok "Your GitHub account can read $PLUGIN_REPO"
    SUMMARY+=("✓ GitHub sign-in + access to $PLUGIN_REPO")
  else
    local login; login="$(gh api user -q .login 2>/dev/null || echo 'your GitHub account')"
    fail "Your GitHub account ($login) cannot read the private repo $PLUGIN_REPO."
    note "Ask $ACCESS_CONTACT to add \"$login\" as a collaborator on"
    note "https://github.com/$PLUGIN_REPO (or to the withcaldera GitHub org)."
    note "Once that's done, re-run this script — everything else is already in place."
    SUMMARY+=("✗ Access to $PLUGIN_REPO — ask $ACCESS_CONTACT")
    exit 1
  fi
}

step_claude() {
  header "5/7  Claude Code (the 'claude' terminal command)"
  if has_claude; then
    ok "Already installed ($("$CLAUDE_BIN_DIR/claude" --version 2>/dev/null || claude --version 2>/dev/null || echo 'version unknown'))"
    SUMMARY+=("✓ Claude Code")
  else
    doing "Installing Claude Code with Anthropic's installer..."
    curl -fsSL https://claude.ai/install.sh | bash || die "Claude Code install failed. See https://code.claude.com/docs/en/setup and re-run this script."
    ok "Claude Code installed"; SUMMARY+=("✓ Claude Code (installed)")
  fi
  export PATH="$CLAUDE_BIN_DIR:$PATH"
  if ! path_persisted; then
    # shellcheck disable=SC2016  # the literal $HOME belongs in ~/.zprofile
    persist_zprofile '.local/bin' 'export PATH="$HOME/.local/bin:$PATH"'
  fi
}

step_settings() {
  header "6/7  Register the Caldera marketplace in ~/.claude/settings.json (used by the desktop app)"
  if settings_configured; then ok "Already configured"; SUMMARY+=("✓ settings.json"); return; fi
  doing "Updating settings.json (a .bak copy is kept)..."
  "$(python_bin)" - "$CLAUDE_SETTINGS" "$MARKETPLACE" "$PLUGIN_REPO" "$PLUGIN" <<'PY' || die "Could not update settings.json (see message above). Fix the file, or ask $ACCESS_CONTACT for help, then re-run."
import json, os, shutil, sys, tempfile
path, mk, repo, plugin = sys.argv[1:5]
d = {}
if os.path.exists(path) and os.path.getsize(path) > 0:
    try:
        with open(path) as f:
            d = json.load(f)
    except json.JSONDecodeError as e:
        sys.stderr.write(f"{path} is not valid JSON ({e}); leaving it untouched.\n")
        sys.exit(1)
    if not isinstance(d, dict):
        sys.stderr.write(f"{path} is not a JSON object; leaving it untouched.\n")
        sys.exit(1)
    shutil.copy2(path, path + ".bak")
os.makedirs(os.path.dirname(path), exist_ok=True)
d.setdefault("extraKnownMarketplaces", {})[mk] = {
    "source": {"source": "github", "repo": repo},
    "autoUpdate": True,
}
d.setdefault("enabledPlugins", {})[f"{plugin}@{mk}"] = True
fd, tmp = tempfile.mkstemp(prefix=".settings.", suffix=".json", dir=os.path.dirname(path))
with os.fdopen(fd, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
os.chmod(tmp, os.stat(path).st_mode & 0o777 if os.path.exists(path) else 0o600)
os.replace(tmp, path)
PY
  ok "settings.json updated"; SUMMARY+=("✓ settings.json (updated)")
}

step_cli_register() {
  header "7/7  Register the marketplace and install the plugin for the terminal too"
  if ! has_claude; then
    fail "claude is not available in this shell; skipping. Open a new Terminal window and re-run."
    SUMMARY+=("✗ CLI marketplace/plugin (claude not found)"); return
  fi
  if cli_marketplace_registered; then
    doing "Marketplace '$MARKETPLACE' already registered — refreshing it..."
    claude plugin marketplace update "$MARKETPLACE" >/dev/null 2>&1 || note "(refresh failed; it will retry in the background next session)"
    ok "Marketplace '$MARKETPLACE' up to date"
  else
    doing "Adding marketplace $PLUGIN_REPO..."
    if ! claude plugin marketplace add "$PLUGIN_REPO" >/dev/null 2>&1; then
      claude plugin marketplace update "$MARKETPLACE" >/dev/null 2>&1 \
        || die "Could not add the marketplace. Run 'claude plugin marketplace add $PLUGIN_REPO' in Terminal to see the error."
    fi
    ok "Marketplace '$MARKETPLACE' registered"
  fi
  SUMMARY+=("✓ CLI marketplace '$MARKETPLACE'")

  if cli_plugin_installed; then
    ok "Plugin $PLUGIN@$MARKETPLACE already installed"
    SUMMARY+=("✓ Plugin $PLUGIN@$MARKETPLACE")
  else
    doing "Installing plugin $PLUGIN@$MARKETPLACE..."
    local out
    if out="$(claude plugin install "$PLUGIN@$MARKETPLACE" 2>&1)" || grep -qi 'already installed' <<<"$out"; then
      ok "Plugin $PLUGIN@$MARKETPLACE installed"
      SUMMARY+=("✓ Plugin $PLUGIN@$MARKETPLACE (installed)")
    else
      fail "Plugin install failed:"; note "$out"
      SUMMARY+=("✗ Plugin $PLUGIN@$MARKETPLACE — run: claude plugin install $PLUGIN@$MARKETPLACE")
    fi
  fi
}

print_summary() {
  header "Summary"
  local line
  for line in ${SUMMARY[@]+"${SUMMARY[@]}"}; do echo "  $line"; done
  header "Next steps"
  echo "  1. Open the Claude desktop app (or type 'claude' in a NEW Terminal window)."
  echo "  2. Start a Code session in your project folder."
  echo "  3. Type  /$PLUGIN:doctor  and press Enter — it verifies everything and fixes what it can."
  echo
  echo "  Signed in to Claude yet? The app will ask you the first time; use your Caldera account."
}

# ---------------------------------------------------------------------------
# --check mode: read-only report
# ---------------------------------------------------------------------------
run_check() {
  echo "Checking delivery-lead setup (nothing will be changed)"
  echo
  report "Xcode Command Line Tools"                       "$(has_clt && echo 0 || echo 1)"
  report "Homebrew"                                       "$(has_brew && echo 0 || echo 1)"
  if has_brew; then eval "$("$(brew_path)" shellenv)"; fi
  report "Homebrew on PATH in ~/.zprofile"                "$(grep -qsF 'brew shellenv' "$ZPROFILE" && echo 0 || echo 1)"
  report "gh (GitHub CLI) installed"                      "$(has_gh && echo 0 || echo 1)"
  report "Signed in to GitHub (gh auth status)"           "$(gh_logged_in && echo 0 || echo 1)"
  report "git credential helper uses gh for github.com"   "$(gh_helper_configured && echo 0 || echo 1)"
  report "Can read https://github.com/$PLUGIN_REPO"       "$(repo_accessible && echo 0 || echo 1)"
  export PATH="$CLAUDE_BIN_DIR:$PATH"
  report "Claude Code installed (claude)"                 "$(has_claude && echo 0 || echo 1)"
  report "PATH includes ~/.local/bin (in ~/.zprofile or ~/.zshrc)" "$(path_persisted && echo 0 || echo 1)"
  report "settings.json: marketplace '$MARKETPLACE' (autoUpdate) + $PLUGIN@$MARKETPLACE enabled" "$(settings_configured && echo 0 || echo 1)"
  report "CLI marketplace '$MARKETPLACE' registered"      "$(cli_marketplace_registered && echo 0 || echo 1)"
  report "CLI plugin $PLUGIN@$MARKETPLACE installed"      "$(cli_plugin_installed && echo 0 || echo 1)"
  echo
  if (( MISSING > 0 )); then
    echo "$MISSING item(s) missing. Run this script without --check to fix them."
    exit 1
  fi
  echo "Everything is in place."
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  for arg in "$@"; do
    case "$arg" in
      --check) CHECK=1 ;;
      --yes|-y) YES=1 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown flag: $arg (use --check, --yes, or --help)" ;;
    esac
  done

  if [[ "$(uname -s)" != "Darwin" ]]; then
    die "This setup script is for macOS only. You're on $(uname -s). Ask $ACCESS_CONTACT for the setup steps for your machine."
  fi

  # When piped from curl, stdin is the script itself. Interactive tools (Homebrew,
  # gh auth login, our own prompt) need the keyboard, so point stdin at the terminal.
  if [[ ! -t 0 ]] && [[ -r /dev/tty ]] && ( : </dev/tty ) 2>/dev/null; then
    exec </dev/tty
  fi

  if [[ "$CHECK" == "1" ]]; then run_check; return; fi

  echo "${C_BOLD}Caldera delivery-lead setup${C_OFF}"
  echo "This will install or verify: Command Line Tools, Homebrew, gh, GitHub sign-in,"
  echo "Claude Code, and the '$PLUGIN' plugin from $PLUGIN_REPO."
  echo "Already-installed items are left alone. Nothing runs with sudo."
  if [[ "$YES" != "1" ]]; then
    if [[ -t 0 ]]; then
      printf 'Continue? [Y/n] '
      read -r answer
      case "${answer:-Y}" in
        y|Y|yes|YES|"") ;;
        *) echo "Cancelled."; exit 0 ;;
      esac
    else
      note "(no terminal available for confirmation; continuing — pass --yes to silence this)"
    fi
  fi

  step_clt
  step_brew
  step_gh
  step_github_auth
  step_claude
  step_settings
  step_cli_register
  print_summary
}

main "$@"; exit $?
