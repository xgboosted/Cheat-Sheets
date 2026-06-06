#!/usr/bin/env bash
set -u

# Recreate the Bottles "winapps" bottle with all dependencies and programs.
# Run on fresh Linux Mint install to restore Windows app environment.
#
# Usage: ./setup-bottles-winapps.sh
#
# Idempotent — safe to re-run. Steps skip if already done.

BOTTLE_NAME="winapps"
BOTTLES_BASE="${HOME}/.var/app/com.usebottles.bottles/data/bottles/bottles"
BOTTLE_PATH="${BOTTLES_BASE}/${BOTTLE_NAME}"
LOG_FILE="$(dirname "$(readlink -f "$0")")/setup-bottles-winapps.log"
> "$LOG_FILE"  # truncate on each run

# Programs: name, wine_path (C:\...), linux_relative_path (drive_c/...)
PROGRAMS=(
  "sync-taskbar|C:\\Program Files (x86)\\Sync\\sync-taskbar.exe|drive_c/Program Files (x86)/Sync/sync-taskbar.exe"
  "notepad++|C:\\Program Files\\Notepad++\\notepad++.exe|drive_c/Program Files/Notepad++/notepad++.exe"
  "TDSEE_Studio|C:\\Program Files\\TDSEE_Studio\\TDSEE_Studio.exe|drive_c/Program Files/TDSEE_Studio/TDSEE_Studio.exe"
)

# Source bottle to copy from (if different from target). Set empty to skip copy.
COPY_SRC=""

msg() { printf "\n[%s] %s\n" "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"; }
warn() { msg "WARN: $*"; }

bottles() {
  flatpak run --command=bottles-cli com.usebottles.bottles "$@"
}

msg "Bottles winapps bottle setup started. Log: ${LOG_FILE}"

# ─── Step 0: Grant Flatpak filesystem access ───
msg "Granting Flatpak filesystem access to /Z (Sync storage)..."
flatpak override --user --filesystem=/Z com.usebottles.bottles 2>/dev/null \
  && msg "  ✓ /Z access granted" \
  || warn "  Could not grant /Z access"

# ─── Step 1: Install Bottles ───
if ! flatpak list 2>/dev/null | grep -q com.usebottles.bottles; then
  msg "Installing Bottles..."
  flatpak install -y flathub com.usebottles.bottles >>"$LOG_FILE" 2>&1 || {
    msg "FAIL: Bottles install failed."; exit 1;
  }
else
  msg "Bottles already installed."
fi

# ─── Step 2: Create bottle ───
if bottles list bottles 2>/dev/null | grep -q "$BOTTLE_NAME"; then
  msg "Bottle '${BOTTLE_NAME}' already exists. Skipping creation."
else
  msg "Creating bottle '${BOTTLE_NAME}' (win64, application, sys-wine-11.0)..."
  bottles new \
    --bottle-name "$BOTTLE_NAME" \
    --environment application \
    --arch win64 \
    --runner sys-wine-11.0 >>"$LOG_FILE" 2>&1 || {
      msg "FAIL: bottle creation failed."; exit 1;
    }
  msg "Bottle created."

  msg "Setting Windows version to win10..."
  bottles edit -b "$BOTTLE_NAME" --win win10 >>"$LOG_FILE" 2>&1 || true
fi

# ─── Step 3: Install dependencies ───
msg "Installing Wine dependencies..."
msg "(Dependencies cannot be installed via CLI. Install manually in Bottles GUI if needed.)"

deps=( arial32 times32 courie32 mono gecko vcredist2022 )

# Check which deps are already in bottle.yml
installed=$(grep -A50 'Installed_Dependencies:' "${BOTTLE_PATH}/bottle.yml" 2>/dev/null | grep '^- ' | sed 's/^- //')
missing=()
for d in "${deps[@]}"; do
  if echo "$installed" | grep -qx "$d"; then
    msg "  ✓ ${d}"
  else
    msg "  ✗ ${d} — install via Bottles GUI: Dependencies → ${d}"
    missing+=("$d")
  fi
done

if (( ${#missing[@]} == 0 )); then
  msg "All dependencies present."
else
  msg "${#missing[@]} dependencies missing. Install in Bottles GUI."
fi

# ─── Step 4: Configure bottle parameters ───
# --params only accepts ONE key:value per call (comma-list hangs)
msg "Configuring bottle parameters..."

declare -A params=(
  [dxvk]="true"
  [vkd3d]="true"
  [sync]="wine"
  [renderer]="gl"
  [virtual_desktop]="false"
  [sandbox]="false"
  [wayland]="false"
)

for k in "${!params[@]}"; do
  want="${params[$k]}"

  # Check if already set in current bottle
  if [[ -f "${BOTTLE_PATH}/bottle.yml" ]]; then
    if grep -q "    ${k}: ${want}\$" "${BOTTLE_PATH}/bottle.yml" 2>/dev/null; then
      msg "  ✓ ${k}=${want} (already set)"
      continue
    fi
  fi

  msg "  Setting ${k}=${want}..."
  if timeout 8 bottles edit -b "$BOTTLE_NAME" --params "${k}:${want}" >>"$LOG_FILE" 2>&1; then
    msg "  OK: ${k}=${want}"
  else
    rc=$?
    if (( rc == 124 )); then
      warn "  TIMEOUT: ${k}=${want}"
    else
      warn "  FAIL: ${k}=${want} (exit ${rc})"
    fi
  fi
done

# Set Windows version if not win10
if ! grep -q '^Windows: win10' "${BOTTLE_PATH}/bottle.yml" 2>/dev/null; then
  timeout 5 bottles edit -b "$BOTTLE_NAME" --win win10 >>"$LOG_FILE" 2>&1 || true
  msg "  Windows: win10"
fi

msg "Bottle configured."

# ─── Step 5: Copy programs from source (only if src != dst) ───
if [[ -n "$COPY_SRC" ]] && [[ "$COPY_SRC" != "$BOTTLE_PATH" ]] && [[ -d "$COPY_SRC/drive_c" ]]; then
  msg "Copying Windows programs from ${COPY_SRC}..."

  mkdir -p "${BOTTLE_PATH}/drive_c/Program Files" \
           "${BOTTLE_PATH}/drive_c/Program Files (x86)"

  for entry in "${PROGRAMS[@]}"; do
    IFS='|' read -r prog_name prog_wine prog_linux <<< "$entry"
    name="${prog_linux##*/}"
    src_dir="$(dirname "${COPY_SRC}/${prog_linux}")"
    dst_dir="$(dirname "${BOTTLE_PATH}/${prog_linux}")"
    if [[ -d "$src_dir" ]]; then
      mkdir -p "$(dirname "$dst_dir")"
      cp -r "$src_dir" "$dst_dir" 2>/dev/null \
        && msg "  ✓ ${prog_name}" || warn "  Could not copy ${prog_name}"
    else
      msg "  ✗ ${prog_name} not found at source"
    fi
  done

  # Copy registry
  if [[ -f "${COPY_SRC}/user.reg" ]]; then
    cp "${COPY_SRC}/user.reg" "${BOTTLE_PATH}/user.reg" 2>/dev/null \
      && msg "  ✓ registry" || warn "  Could not copy registry"
  fi

  # Copy Sync.com config
  SYNC_CFG_SRC="${COPY_SRC}/drive_c/users/${USER}/AppData/Local/Sync.Config"
  if [[ -d "$SYNC_CFG_SRC" ]]; then
    mkdir -p "${BOTTLE_PATH}/drive_c/users/${USER}/AppData/Local"
    cp -r "$SYNC_CFG_SRC" "${BOTTLE_PATH}/drive_c/users/${USER}/AppData/Local/Sync.Config" 2>/dev/null \
      && msg "  ✓ Sync.com config" || warn "  Could not copy Sync.com config"
  fi
else
  msg "Skipping program copy (no external source, or source == target)."
fi

# ─── Step 6: Register programs ───
msg "Registering programs..."

register_program() {
  local name="$1" path="$2"
  # Strip C:\ and convert all backslashes to forward slashes
  local fs_path="${BOTTLE_PATH}/drive_c/$(echo "$path" | sed 's/^C:\\//; s/\\/\//g')"
  if [[ -f "$fs_path" ]]; then
    if bottles programs -b "$BOTTLE_NAME" 2>/dev/null | grep -q "$name"; then
      msg "  ✓ ${name} (already registered)"
    else
      bottles add -b "$BOTTLE_NAME" -n "$name" -p "$path" >>"$LOG_FILE" 2>&1 \
        && msg "  ✓ ${name} registered" \
        || warn "  ${name} registration failed"
    fi
  else
    msg "  ✗ ${name} — .exe not found at ${path}"
  fi
}

for entry in "${PROGRAMS[@]}"; do
  IFS='|' read -r prog_name prog_wine prog_linux <<< "$entry"
  register_program "$prog_name" "$prog_wine"
done

# ─── Done ───
msg ""
msg "═══════════════════════════════════════"
msg "Setup complete."
msg "  Bottle: ${BOTTLE_NAME}"
msg "  Path:   ${BOTTLE_PATH}"

for entry in "${PROGRAMS[@]}"; do
  IFS='|' read -r prog_name prog_wine prog_linux <<< "$entry"
  if [[ -f "${BOTTLE_PATH}/${prog_linux}" ]]; then
    msg "  ✓ ${prog_linux##*/}"
  else
    msg "  ✗ ${prog_linux##*/} — install manually"
  fi
done

msg ""
msg "Missing deps?  Open Bottles GUI → ${BOTTLE_NAME} → Dependencies"
msg "Sync folder?   Update cfg.db prefs: sharedfolder = Z:/Z/Sync"
msg "Launch:        bottles run -p <name> -b ${BOTTLE_NAME}"
msg "Log:           ${LOG_FILE}"
msg "═══════════════════════════════════════"
echo ""
read -r -p "Press Enter to exit..." _
