#!/usr/bin/env bash
set -u
set -e

# Linux Mint post-install helper based on:
# https://www.reallinuxuser.com/21-best-things-to-do-after-installing-linux-mint/
#
# Behavior:
# - Runs actions in logical order: hardware → OS settings → dev tools → apps → sync/backup
# - Prompts per step: run, skip, quit.
# - Aborts on first failure.

LOG_FILE="${HOME}/linux-mint-postinstall.log"
_ctrl_c_count=0

handle_sigint() {
  (( _ctrl_c_count++ )) || true
  if (( _ctrl_c_count >= 2 )); then
    msg "QUIT: Ctrl+C pressed twice. Exiting."
    exit 130
  fi
  msg "INFO: Step interrupted (Ctrl+C). Press Ctrl+C again to exit script."
}
trap handle_sigint INT

msg() { printf "\n[%s] %s\n" "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"; }

run_cmd() {
  local desc="$1"
  shift
  msg "RUN: ${desc}"
  if "$@" >>"$LOG_FILE" 2>&1; then
    msg "OK: ${desc}"
  else
    msg "FAIL: ${desc}"
    return 1
  fi
}

run_shell() {
  local desc="$1"
  local cmd="$2"
  msg "RUN: ${desc}"
  if bash -lc "$cmd" >>"$LOG_FILE" 2>&1; then
    msg "OK: ${desc}"
  else
    msg "FAIL: ${desc}"
    return 1
  fi
}

open_url() {
  local url="$1"
  if command -v xdg-open >/dev/null 2>&1; then
    run_cmd "Open ${url}" xdg-open "$url"
  else
    msg "Open manually: ${url}"
  fi
}

install_deb_from_url_prompt() {
  local label="$1"
  local url="$2"
  local deb_path="/tmp/${label}-latest.deb"

  if [[ -z "$url" ]]; then
    msg "No URL provided for ${label} .deb download."
    return 1
  fi

  run_shell "Download ${label} .deb" "wget -O '${deb_path}' '${url}'"
  run_shell "Install ${label} .deb" "sudo dpkg -i '${deb_path}'; sudo apt-get -f install -y"
}

ask_step() {
  local title="$1"
  while true; do
    printf "\n=== %s ===\n" "$title"
    printf "Choose: [r]un / [s]kip / [q]uit: "
    read -r ans
    case "${ans,,}" in
      r|run) return 0 ;;
      s|skip|"") msg "SKIP: ${title}"; return 1 ;;
      q|quit) msg "QUIT by user."; exit 0 ;;
      *) echo "Invalid input. Use r/s/q." ;;
    esac
  done
}

step_01_mirrors() {
  msg "Open Software Sources to pick nearby mirrors for Main and Base."
  if command -v mintsources >/dev/null 2>&1; then
    run_cmd "Open mintsources" mintsources
  elif command -v software-sources >/dev/null 2>&1; then
    run_cmd "Open software-sources" software-sources
  else
    msg "No mirror GUI tool found. Open Update Manager > Edit > Software Sources manually."
  fi
}

step_02_update_upgrade() {
  run_cmd "apt update" sudo apt-get update
  run_cmd "apt full upgrade" sudo apt-get -y full-upgrade
  run_cmd "Install foundational tools" sudo apt-get -y install curl wget flatpak
}

step_03_microcode() {
  local vendor
  vendor="$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')"
  case "$vendor" in
    GenuineIntel)
      run_cmd "Install Intel microcode" sudo apt-get -y install intel-microcode
      ;;
    AuthenticAMD)
      run_cmd "Install AMD microcode" sudo apt-get -y install amd64-microcode
      ;;
    *)
      msg "Unknown CPU vendor (${vendor}). Install microcode manually if needed."
      ;;
  esac
  run_shell "Check microcode in dmesg" "dmesg | grep -i microcode | tail -n 5"
}

step_04_drivers() {
  if command -v driver-manager >/dev/null 2>&1; then
    run_cmd "Open driver-manager" driver-manager
  elif command -v mintdrivers >/dev/null 2>&1; then
    run_cmd "Open mintdrivers" mintdrivers
  else
    msg "Driver manager not found. Open Driver Manager manually from menu."
  fi
}

step_05_wifi_firmware() {
  msg "WiFi firmware update (iwlwifi drivers, BE201 support)."
  msg "Checks dmesg for missing firmware, installs via apt, updates initramfs."

  run_shell "Check dmesg for iwlwifi errors" "dmesg | grep -i iwlwifi | tail -10"

  printf "Install/update iwlwifi firmware via apt (firmware-iwlwifi + linux-firmware)? [y/N]: "
  read -r yn
  if [[ "${yn,,}" == "y" ]]; then
    run_cmd "Install firmware-iwlwifi and linux-firmware" sudo apt-get -y install firmware-iwlwifi linux-firmware
    msg "Firmware packages installed."

    printf "Update kernel initramfs to include new firmware? [y/N]: "
    read -r ib
    if [[ "${ib,,}" == "y" ]]; then
      run_cmd "Update initramfs" sudo update-initramfs -u
      msg "Initramfs updated. WiFi firmware now part of boot image."

      printf "Reboot now to apply changes? [y/N]: "
      read -r rb
      if [[ "${rb,,}" == "y" ]]; then
        msg "Rebooting..."
        sudo reboot
      else
        msg "Remember to reboot later for WiFi to work."
      fi
    fi
  fi
}

step_06_codecs() {
  run_cmd "Install multimedia codecs" sudo apt-get -y install mint-meta-codecs
  run_cmd "Install Mesa utils and Intel VAAPI driver" sudo apt-get -y install mesa-utils intel-media-va-driver-non-free vainfo
  run_cmd "Install Intel VAAPI drivers (legacy i965)" sudo apt-get -y install i965-va-driver
}

step_07_swappiness() {
  run_shell "Set vm.swappiness=10" "echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf"
  run_cmd "Apply sysctl settings" sudo sysctl --system
  run_shell "Verify swappiness" "cat /proc/sys/vm/swappiness"
}

step_08_firewall() {
  run_cmd "Install ufw" sudo apt-get -y install ufw
  run_cmd "Set ufw default deny incoming" sudo ufw default deny incoming
  run_cmd "Set ufw default allow outgoing" sudo ufw default allow outgoing
  run_cmd "Enable ufw" sudo ufw --force enable
  run_cmd "Show ufw status" sudo ufw status verbose
}

step_09_fractional_scaling() {
  msg "This step is GUI/manual."
  msg "Open System Settings > Display > enable fractional scaling controls, then set preferred scale."
  if command -v cinnamon-settings >/dev/null 2>&1; then
    msg "Opening Display settings (detached from terminal)..."
    setsid cinnamon-settings display >/dev/null 2>&1 &
  elif command -v gnome-control-center >/dev/null 2>&1; then
    setsid gnome-control-center display >/dev/null 2>&1 &
  else
    msg "No display settings tool found. Open System Settings > Display manually."
  fi
}

step_10_git_config() {
  msg "Install and configure Git globally."

  run_cmd "Install git" sudo apt-get -y install git

  printf "Set git user.email (e.g., user@example.com): "
  read -r git_email
  if [[ -n "${git_email}" ]]; then
    run_shell "Set git user.email" "git config --global user.email '${git_email}'"
  fi

  printf "Set git user.name (e.g., Your Name): "
  read -r git_name
  if [[ -n "${git_name}" ]]; then
    run_shell "Set git user.name" "git config --global user.name '${git_name}'"
  fi

  printf "Set git default branch to main? [y/N]: "
  read -r yn
  if [[ "${yn,,}" == "y" ]]; then
    run_shell "Set git default branch" "git config --global init.defaultBranch main"
  fi

  run_shell "Show git config" "git config --global --list | grep -E 'user|init'"
}

step_11_python_dev_env() {
  msg "Python 3 development environment setup (Python first per GitHub cheat sheet)."
  
  # Python first requirement
  run_cmd "Install Python venv & pip" sudo apt-get install -y python3-venv python3-pip
  
  printf "Install build tools & dev packages? [y/N]: "
  read -r yn
  if [[ "${yn,,}" == "y" ]]; then
    run_cmd "Install build tools" sudo apt-get install -y build-essential python3-dev libssl-dev libffi-dev
  fi

  printf "Install Poetry package manager? [y/N]: "
  read -r yn
  if [[ "${yn,,}" == "y" ]]; then
    run_cmd "Install Poetry" sudo apt-get install -y poetry
  fi

  msg "Python environment ready. Use: python3 -m venv <env_name>"
}

step_12_basic_software() {
  run_cmd "Install basic software set" sudo apt-get -y install vlc flameshot neofetch htop

  printf "Install OnlyOffice via Flatpak? [y/N]: "
  read -r yn
  if [[ "${yn,,}" == "y" ]]; then
    run_cmd "Add Flathub repo" sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    run_cmd "Install OnlyOffice via Flatpak" sudo flatpak install -y flathub org.onlyoffice.desktopeditors
  fi
}

step_13_vscode() {
  msg "VS Code install via Microsoft apt repo."
  msg "Reference: https://code.visualstudio.com/docs/setup/linux"

  run_shell "Import Microsoft GPG key" \
    "curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft.gpg > /dev/null"
  run_shell "Add VS Code apt repo" \
    "echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main' | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null"
  run_cmd "apt update" sudo apt-get update
  run_cmd "Install VS Code" sudo apt-get -y install code
}

step_14_vscode_extensions() {
  msg "Install VSCode extensions (currently installed set)."

  if ! command -v code >/dev/null 2>&1; then
    msg "VS Code (code) not found in PATH. Install VS Code first (Step 13)."
    return 1
  fi

  local extensions=(
    bierner.markdown-mermaid
    codezombiech.gitignore
    docker.docker
    eamodio.gitlens
    fedaykindev.openchamber
    george-alisson.html-preview-vscode
    github.vscode-github-actions
    github.vscode-pull-request-github
    grafana.grafana-vscode
    hashicorp.terraform
    jebbs.plantuml
    mechatroner.rainbow-csv
    mhutchie.git-graph
    ms-azuretools.vscode-containers
    ms-azuretools.vscode-docker
    ms-kubernetes-tools.vscode-kubernetes-tools
    ms-python.debugpy
    ms-python.python
    ms-python.vscode-pylance
    ms-python.vscode-python-envs
    ms-toolsai.datawrangler
    ms-toolsai.jupyter
    ms-toolsai.jupyter-keymap
    ms-toolsai.jupyter-renderers
    ms-toolsai.vscode-jupyter-cell-tags
    ms-toolsai.vscode-jupyter-slideshow
    ms-vscode-remote.remote-containers
    ms-vscode-remote.remote-ssh
    ms-vscode-remote.remote-ssh-edit
    ms-vscode-remote.vscode-remote-extensionpack
    ms-vscode.remote-explorer
    ms-vscode.remote-server
    ms-vscode.vscode-chat-customizations-evaluations
    ms-vscode.vscode-speech
    pomdtr.excalidraw-editor
    redhat.vscode-yaml
    timonwong.shellcheck
    tomoki1207.pdf
    vizards.deepseek-v4-for-copilot
    yzhang.markdown-all-in-one
  )

  local failed=()
  for ext in "${extensions[@]}"; do
    if code --install-extension "$ext" >>"$LOG_FILE" 2>&1; then
      msg "  installed: ${ext}"
    else
      msg "  FAILED:   ${ext}"
      failed+=("$ext")
    fi
  done

  if ((${#failed[@]} > 0)); then
    msg "WARN: ${#failed[@]} extension(s) failed: ${failed[*]}"
  else
    msg "All ${#extensions[@]} extensions installed."
  fi
}

step_15_dbeaver() {
  msg "DBeaver Community install via official apt repo."
  msg "Reference: https://dbeaver.io/download/"

  run_shell "Import DBeaver GPG key" \
    "curl -fsSL https://dbeaver.io/debs/dbeaver.gpg.key | gpg --dearmor | sudo tee /usr/share/keyrings/dbeaver.gpg > /dev/null"
  run_shell "Add DBeaver apt repo" \
    "echo 'deb [signed-by=/usr/share/keyrings/dbeaver.gpg] https://dbeaver.io/debs/dbeaver/ /' | sudo tee /etc/apt/sources.list.d/dbeaver.list > /dev/null"
  run_cmd "apt update" sudo apt-get update
  run_cmd "Install DBeaver Community" sudo apt-get -y install dbeaver-ce
}

step_16_flatseal() {
  run_cmd "Add Flathub repo" sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  run_cmd "Install Flatseal" sudo flatpak install -y flathub com.github.tchx84.Flatseal
}

step_17_brave() {
  msg "Brave browser install via apt."
  msg "Reference: https://brave.com/linux/"

  if dpkg -l brave-browser 2>/dev/null | grep -q '^ii'; then
    msg "Brave already installed. Skipping."
  else
    run_cmd "Import Brave GPG key" sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
      https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
    run_shell "Add Brave apt repo" \
      "echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main' | sudo tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null"
    run_cmd "apt update" sudo apt-get update
    run_cmd "Install Brave" sudo apt-get -y install brave-browser
  fi

  printf "Set Brave as default browser? [y/N]: "
  read -r yn
  if [[ "${yn,,}" == "y" ]]; then
    run_cmd "Set Brave as default" xdg-mime default brave-browser.desktop x-scheme-handler/http x-scheme-handler/https x-scheme-handler/ftp
    msg "Brave set as default browser."
  fi
}

step_18_fonts() {
  if ! command -v debconf-set-selections >/dev/null 2>&1; then
    run_cmd "Install debconf-utils" sudo apt-get -y install debconf-utils
  fi
  run_shell "Pre-accept Microsoft fonts EULA" \
    "sudo bash -c \"echo 'ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula boolean true' | debconf-set-selections\""
  run_shell "Install Microsoft core fonts" "sudo DEBIAN_FRONTEND=noninteractive apt-get -y install ttf-mscorefonts-installer"
}

step_19_stacer() {
  msg "Stacer install via GitHub release .deb (QuentiumYT/Stacer)."
  msg "Reference: https://github.com/QuentiumYT/Stacer"

  run_cmd "Install Stacer Qt5 runtime dependencies" sudo apt-get -y install \
    libqt5widgets5 libqt5charts5 libqt5network5 libqt5dbus5

  local api_url="https://api.github.com/repos/QuentiumYT/Stacer/releases/latest"
  local deb_url
  deb_url=$(curl -fsSL "$api_url" \
    | python3 -c "import sys,json; assets=json.load(sys.stdin)['assets']; print(next((a['browser_download_url'] for a in assets if a['name'].endswith('_amd64.deb')), ''))")

  if [[ -z "$deb_url" ]]; then
    msg "Could not resolve Stacer .deb URL from GitHub API. Visit https://github.com/QuentiumYT/Stacer/releases to install manually."
    return 1
  fi

  msg "Downloading Stacer: ${deb_url}"
  install_deb_from_url_prompt "stacer" "$deb_url"
}

step_20_ulauncher() {
  run_cmd "Add Ulauncher PPA" sudo add-apt-repository -y ppa:agornostal/ulauncher
  run_cmd "apt update" sudo apt-get update
  run_cmd "Install Ulauncher" sudo apt-get -y install ulauncher
}

step_21_clipboard_manager() {
  run_cmd "Install CopyQ" sudo apt-get -y install copyq
}

step_22_timeshift() {
  run_cmd "Install Timeshift" sudo apt-get -y install timeshift
  msg "Timeshift installed. Launching GUI (requires sudo)..."
  if command -v timeshift-gtk >/dev/null 2>&1; then
    sudo timeshift-gtk &
  else
    msg "Open Timeshift from menu to configure snapshots."
  fi
}

step_23_backup_personal() {
  run_cmd "Install backup apps (Pika Backup, luckyBackup)" sudo apt-get -y install pika-backup luckybackup
  msg "Set 3-2-1 backup policy manually after install."
}

step_24_dropbox() {
  msg "Dropbox install via official apt repo."
  msg "Reference: https://www.dropbox.com/install-linux"

  run_shell "Import Dropbox GPG key" \
    "curl -fsSL https://linux.dropboxstatic.com/ubuntu/debian/apt.dropbox.com.asc | sudo gpg --dearmor -o /usr/share/keyrings/dropbox.gpg"
  run_shell "Add Dropbox apt repo" \
    "echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/dropbox.gpg] https://linux.dropboxstatic.com/ubuntu noble main' | sudo tee /etc/apt/sources.list.d/dropbox.list >/dev/null"
  run_cmd "apt update" sudo apt-get update
  run_cmd "Install Dropbox" sudo apt-get -y install dropbox
  msg "Start Dropbox: dropbox start -i"
}

step_25_expandrive() {
  msg "ExpanDrive install via .deb download."
  msg "Reference: https://www.expandrive.com/download"

  local deb_url="https://www.expandrive.com/api/download/expandrive?platform=linux&ext=deb"
  install_deb_from_url_prompt "expandrive" "$deb_url"
}

main() {
  msg "Linux Mint post-install started. Log: ${LOG_FILE}"
  msg "Order: hardware/kernel → OS settings → dev tools → apps (+ sync/backup)"
  msg "Tip: Ctrl+C once skips current step; Ctrl+C twice exits script."

  # Hardware & Kernel
  if ask_step "1) Change to nearby update servers"; then step_01_mirrors || msg "WARN: step failed, continuing."; fi
  if ask_step "2) Update your operating system"; then step_02_update_upgrade || msg "WARN: step failed, continuing."; fi
  if ask_step "3) Install newest microcode"; then step_03_microcode || msg "WARN: step failed, continuing."; fi
  if ask_step "4) Check and install drivers"; then step_04_drivers || msg "WARN: step failed, continuing."; fi
  if ask_step "5) WiFi firmware (iwlwifi, update-initramfs)"; then step_05_wifi_firmware || msg "WARN: step failed, continuing."; fi

  # OS System Settings
  if ask_step "6) Install multimedia codecs"; then step_06_codecs || msg "WARN: step failed, continuing."; fi
  if ask_step "7) Improve memory use (swappiness)"; then step_07_swappiness || msg "WARN: step failed, continuing."; fi
  if ask_step "8) Set up firewall"; then step_08_firewall || msg "WARN: step failed, continuing."; fi
  if ask_step "9) Fractional scaling"; then step_09_fractional_scaling || msg "WARN: step failed, continuing."; fi

  # Dev Tools & Git
  if ask_step "10) Install and configure Git globally"; then step_10_git_config || msg "WARN: step failed, continuing."; fi
  if ask_step "11) Python dev environment (pip, venv)"; then step_11_python_dev_env || msg "WARN: step failed, continuing."; fi
  if ask_step "12) Install basic software"; then step_12_basic_software || msg "WARN: step failed, continuing."; fi
  if ask_step "13) Install VS Code"; then step_13_vscode || msg "WARN: step failed, continuing."; fi
  if ask_step "14) Install VSCode extensions"; then step_14_vscode_extensions || msg "WARN: step failed, continuing."; fi
  if ask_step "15) Install DBeaver (database client)"; then step_15_dbeaver || msg "WARN: step failed, continuing."; fi
  if ask_step "16) Install Flatseal (flatpak permissions)"; then step_16_flatseal || msg "WARN: step failed, continuing."; fi

  # Apps (including Sync & Backup)
  if ask_step "17) Install Brave browser"; then step_17_brave || msg "WARN: step failed, continuing."; fi
  if ask_step "18) Install additional fonts"; then step_18_fonts || msg "WARN: step failed, continuing."; fi
  if ask_step "19) Install Stacer"; then step_19_stacer || msg "WARN: step failed, continuing."; fi
  if ask_step "20) Install Ulauncher"; then step_20_ulauncher || msg "WARN: step failed, continuing."; fi
  if ask_step "21) Install clipboard manager"; then step_21_clipboard_manager || msg "WARN: step failed, continuing."; fi
  if ask_step "22) Set up Timeshift"; then step_22_timeshift || msg "WARN: step failed, continuing."; fi
  if ask_step "23) Set backup strategy for personal files"; then step_23_backup_personal || msg "WARN: step failed, continuing."; fi
  if ask_step "24) Install Dropbox"; then step_24_dropbox || msg "WARN: step failed, continuing."; fi
  if ask_step "25) Install ExpanDrive"; then step_25_expandrive || msg "WARN: step failed, continuing."; fi

  msg "All steps processed."
}

main "$@"
