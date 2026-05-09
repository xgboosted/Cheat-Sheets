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
  run_cmd "Install ${label} .deb" sudo apt-get -y install "${deb_path}"
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
  msg "Checks dmesg for missing firmware, downloads if needed, updates initramfs."
  
  run_shell "Check dmesg for iwlwifi errors" "dmesg | grep -i iwlwifi | tail -10"
  
  printf "Download missing firmware files (e.g., BE201)? [y/N]: "
  read -r yn
  if [[ "${yn,,}" == "y" ]]; then
    msg "Ensure internet access (USB tethering or WiFi)."
    msg "Downloading firmware from kernel.org to /lib/firmware/"
    
    cd /lib/firmware || { msg "Cannot cd to /lib/firmware"; return; }
    
    # BE201 firmware URLs (adjust per your specific card)
    msg "Downloading BE201 firmware files..."
    sudo wget -q https://kernel.org/doc/Documentation/admin-guide/linux-firmware/iwlwifi-be.ucode
    sudo wget -q https://kernel.org/doc/Documentation/admin-guide/linux-firmware/iwlwifi-be-*.ucode 2>/dev/null
    
    msg "Firmware download complete (check /lib/firmware for .ucode files)."
    
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

step_09_battery_tlp() {
  run_cmd "Install TLP" sudo apt-get -y install tlp tlp-rdw
  run_cmd "Enable and start TLP" sudo systemctl enable --now tlp

  printf "Install ThinkPad extras (tp-smapi-dkms acpi-call-dkms)? [y/N]: "
  read -r tp
  if [[ "${tp,,}" == "y" ]]; then
    run_cmd "Install ThinkPad TLP extras" sudo apt-get -y install tp-smapi-dkms acpi-call-dkms
  fi
}

step_10_redshift() {
  run_cmd "Install Redshift" sudo apt-get -y install redshift redshift-gtk
}

step_11_preload() {
  run_cmd "Install Preload" sudo apt-get -y install preload
  run_cmd "Enable and start Preload" sudo systemctl enable --now preload
}

step_12_fractional_scaling() {
  msg "This step is GUI/manual."
  msg "Open System Settings > Display > enable fractional scaling controls, then set preferred scale."
  if command -v cinnamon-settings >/dev/null 2>&1; then
    run_cmd "Open Display settings" cinnamon-settings display
  fi
}

step_13_ldap_ad_setup() {
  msg "LDAP/Active Directory setup (domain join or LDAP authentication)."
  msg "This is optional and system-specific."
  
  printf "Install LDAP/AD packages (adcli, sssd, realmd)? [y/N]: "
  read -r yn
  if [[ "${yn,,}" == "y" ]]; then
    run_cmd "Install LDAP/AD packages" sudo apt-get -y install adcli sssd sssd-tools realmd ldap-utils
    msg "Next steps (manual):"
    msg "  1. Join domain: sudo realm join -U admin DOMAIN.COM"
    msg "  2. Or configure LDAP in: /etc/sssd/sssd.conf"
    msg "  3. Run: sudo systemctl enable --now sssd"
  fi
}

step_14_git_config() {
  msg "Configure Git global settings."
  
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

step_15_python_dev_env() {
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

step_16_basic_software() {
  run_cmd "Install basic software set" sudo apt-get -y install vlc flameshot neofetch htop

  printf "Install OnlyOffice via Flatpak? [y/N]: "
  read -r yn
  if [[ "${yn,,}" == "y" ]]; then
    run_cmd "Add Flathub repo" sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    run_cmd "Install OnlyOffice via Flatpak" sudo flatpak install -y flathub org.onlyoffice.desktopeditors
  fi
}

step_17_vscode() {
  msg "VS Code install via Flatpak (preferred) or .deb."
  msg "Reference: https://code.visualstudio.com/Download"

  printf "Install VS Code via Flatpak? [Y/n]: "
  read -r yn
  if [[ -z "${yn}" || "${yn,,}" == "y" ]]; then
    run_cmd "Add Flathub repo" sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    run_cmd "Install VS Code via Flatpak" sudo flatpak install -y flathub com.visualstudio.code
  else
    printf "Use default VS Code .deb URL? [Y/n]: "
    read -r deb_yn
    if [[ -z "${deb_yn}" || "${deb_yn,,}" == "y" ]]; then
      local default_vscode_deb_url="https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
      install_deb_from_url_prompt "vscode" "${default_vscode_deb_url}"
    else
      printf "Paste VS Code .deb URL (or press Enter to open download page): "
      read -r deb_url
      if [[ -n "${deb_url}" ]]; then
        install_deb_from_url_prompt "vscode" "$deb_url"
      else
        open_url "https://code.visualstudio.com/Download"
        msg "Download .deb from page, then re-run script and choose this step again."
      fi
    fi
  fi
}

step_18_vscode_extensions() {
  msg "VS Code extension management - install & keep specified extensions."
  
  if ! command -v code >/dev/null 2>&1; then
    msg "VS Code not found. Install it in step 17 first."
    return
  fi

  # Extensions to keep (from https://github.com/xgboosted/Cheat-Sheets/blob/main/DevOps/VSCode-setup.md)
  local keep_extensions=(
    "eamodio.gitlens"
    "github.vscode-pull-request-github"
    "ms-azuretools.vscode-containers"
    "ms-vscode.vscode-chat-customizations-evaluations"
    "bierner.markdown-mermaid"
    "codezombiech.gitignore"
    "docker.docker"
    "dorianmassoulier.repomix-runner"
    "george-alisson.html-preview-vscode"
    "github.vscode-github-actions"
    "grafana.grafana-vscode"
    "hashicorp.terraform"
    "jebbs.plantuml"
    "mechatroner.rainbow-csv"
    "mhutchie.git-graph"
    "ms-azuretools.vscode-docker"
    "ms-kubernetes-tools.vscode-kubernetes-tools"
    "ms-python.debugpy"
    "ms-python.python"
    "ms-python.vscode-pylance"
    "ms-toolsai.datawrangler"
    "ms-toolsai.jupyter-keymap"
    "ms-toolsai.jupyter-renderers"
    "ms-toolsai.jupyter"
    "ms-toolsai.vscode-jupyter-cell-tags"
    "ms-toolsai.vscode-jupyter-slideshow"
    "ms-vscode-remote.remote-ssh"
    "ms-vscode-remote.remote-wsl"
    "ms-vscode-remote.vscode-remote-extensionpack"
    "ms-vscode-remote.remote-ssh-edit"
    "ms-vscode.remote-server"
    "ms-vscode.remote-explorer"
    "ms-vscode.vscode-speech"
    "pomdtr.excalidraw-editor"
    "tomoki1207.pdf"
    "yzhang.markdown-all-in-one"
    "redhat.vscode-yaml"
    "timonwong.shellcheck"
    "ms-vscode-remote.remote-containers"
    "ms-python.vscode-python-envs"
  )

  printf "Install/update kept extensions from list? [y/N]: "
  read -r yn
  if [[ "${yn,,}" == "y" ]]; then
    msg "Installing extensions..."
    for ext in "${keep_extensions[@]}"; do
      run_cmd "Install extension: ${ext}" code --install-extension "$ext"
    done
  fi

  printf "Uninstall extensions NOT in kept list? [y/N]: "
  read -r yn
  if [[ "${yn,,}" == "y" ]]; then
    msg "Finding extensions to remove..."
    local current_exts
    current_exts=$(code --list-extensions | sort)
    local keep_sorted
    keep_sorted=$(printf '%s\n' "${keep_extensions[@]}" | sort)
    
    local to_remove
    to_remove=$(comm -23 <(echo "$current_exts") <(echo "$keep_sorted"))
    
    if [[ -n "$to_remove" ]]; then
      msg "Removing: $to_remove"
      echo "$to_remove" | xargs -I {} code --uninstall-extension {}
    else
      msg "No extensions to remove."
    fi
  fi
}

step_19_dbeaver() {
  msg "DBEaver (database client) install via Flatpak (preferred) or .deb."
  msg "Reference: https://dbeaver.io/download/"

  printf "Install DBEaver via Flatpak? [Y/n]: "
  read -r yn
  if [[ -z "${yn}" || "${yn,,}" == "y" ]]; then
    run_cmd "Add Flathub repo" sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    run_cmd "Install DBEaver via Flatpak" sudo flatpak install -y flathub io.dbeaver.DBeaverCommunity
  else
    printf "Install DBEaver via direct .deb URL? [y/N]: "
    read -r yn
    if [[ "${yn,,}" == "y" ]]; then
      printf "Paste DBEaver .deb URL (or press Enter to skip): "
      read -r deb_url
      if [[ -n "${deb_url}" ]]; then
        install_deb_from_url_prompt "dbeaver" "$deb_url"
      fi
    else
      open_url "https://dbeaver.io/download/"
      msg "Download .deb from page, then re-run script and choose this step again."
    fi
  fi
}

step_20_flatseal() {
  run_cmd "Add Flathub repo" sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  run_cmd "Install Flatseal" sudo flatpak install -y flathub com.github.tchx84.Flatseal
}

step_21_brave() {
  msg "Brave browser install via apt (preferred) or Flatpak."
  msg "Reference: https://brave.com/linux/"

  printf "Install Brave via apt repo? [Y/n]: "
  read -r yn
  if [[ -z "${yn}" || "${yn,,}" == "y" ]]; then
    run_cmd "Add Brave apt key" sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
    run_shell "Add Brave apt repo" "echo 'deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main' | sudo tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null"
    run_cmd "apt update" sudo apt-get update
    run_cmd "Install Brave" sudo apt-get -y install brave-browser
  else
    printf "Install Brave via Flatpak? [y/N]: "
    read -r yn
    if [[ "${yn,,}" == "y" ]]; then
      run_cmd "Add Flathub repo" sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
      run_cmd "Install Brave via Flatpak" sudo flatpak install -y flathub com.brave.Browser
    fi
  fi

  printf "Set Brave as default browser? [y/N]: "
  read -r yn
  if [[ "${yn,,}" == "y" ]]; then
    run_cmd "Set Brave as default" xdg-mime default com.brave.Browser.desktop x-scheme-handler/http x-scheme-handler/https x-scheme-handler/ftp
    msg "Brave set as default browser."
  fi
}

step_22_remove_unwanted() {
  msg "This step is manual by nature."
  msg "Tip: use Menu > right-click app > Uninstall, or run Software Manager."
  if command -v mintinstall >/dev/null 2>&1; then
    run_cmd "Open Software Manager" mintinstall
  fi
}

step_23_users_parental() {
  run_cmd "Install parental control helper (timekpr-next)" sudo apt-get -y install timekpr-next
  if command -v users-admin >/dev/null 2>&1; then
    run_cmd "Open Users and Groups" users-admin
  else
    msg "Open Users and Groups manually from menu."
  fi
}

step_24_fonts() {
  run_cmd "Install Microsoft core fonts" sudo apt-get -y install ttf-mscorefonts-installer
}

step_25_stacer() {
  run_cmd "Add Stacer PPA" sudo add-apt-repository -y ppa:oguzhaninan/stacer
  run_cmd "apt update" sudo apt-get update
  run_cmd "Install Stacer" sudo apt-get -y install stacer
}

step_26_ulauncher() {
  run_cmd "Add Ulauncher PPA" sudo add-apt-repository -y ppa:agornostal/ulauncher
  run_cmd "apt update" sudo apt-get update
  run_cmd "Install Ulauncher" sudo apt-get -y install ulauncher
}

step_27_clipboard_manager() {
  run_cmd "Install CopyQ" sudo apt-get -y install copyq
}

step_28_timeshift() {
  run_cmd "Install Timeshift" sudo apt-get -y install timeshift
  if command -v timeshift-gtk >/dev/null 2>&1; then
    run_cmd "Open Timeshift GUI" timeshift-gtk
  else
    msg "Timeshift installed. Open it from menu to configure snapshots."
  fi
}

step_29_backup_personal() {
  run_cmd "Install backup apps (Pika Backup, luckyBackup)" sudo apt-get -y install pika-backup luckybackup
  msg "Set 3-2-1 backup policy manually after install."
}

step_30_dropbox() {
  msg "Dropbox install via Flatpak (preferred) or apt."
  msg "Reference: https://www.dropbox.com/install-linux"

  printf "Install Dropbox via Flatpak? [Y/n]: "
  read -r yn
  if [[ -z "${yn}" || "${yn,,}" == "y" ]]; then
    run_cmd "Add Flathub repo" sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    run_cmd "Install Dropbox via Flatpak" sudo flatpak install -y flathub com.dropbox.Client
  else
    run_cmd "Install nautilus-dropbox (apt)" sudo apt-get -y install nautilus-dropbox
    printf "Also install Dropbox from direct .deb URL? [y/N]: "
    read -r yn
    if [[ "${yn,,}" == "y" ]]; then
      printf "Paste Dropbox .deb URL (or press Enter to skip): "
      read -r deb_url
      install_deb_from_url_prompt "dropbox" "$deb_url"
    fi
  fi

  open_url "https://www.dropbox.com/install-linux"
}

step_31_expandrive() {
  msg "ExpanDrive install via Flatpak (preferred) or .deb."
  msg "Reference: https://www.expandrive.com/download"

  printf "Install ExpanDrive via Flatpak? [Y/n]: "
  read -r yn
  if [[ -z "${yn}" || "${yn,,}" == "y" ]]; then
    run_cmd "Add Flathub repo" sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    run_cmd "Install ExpanDrive via Flatpak" sudo flatpak install -y flathub com.expandrive.ExpanDrive
  else
    printf "Install ExpanDrive from .deb URL? [y/N]: "
    read -r yn
    if [[ "${yn,,}" == "y" ]]; then
      printf "Paste ExpanDrive .deb URL (or press Enter for default): "
      read -r deb_url
      if [[ -z "${deb_url}" ]]; then
        deb_url="https://www.expandrive.com/api/download/expandrive?platform=linux&ext=deb"
      fi
      install_deb_from_url_prompt "expandrive" "$deb_url"
    else
      open_url "https://www.expandrive.com/download"
      msg "Download .deb from page, then re-run script and choose this step again."
    fi
  fi
}

main() {
  msg "Linux Mint post-install started. Log: ${LOG_FILE}"
  msg "Order: hardware/kernel → OS settings → dev tools → apps (+ sync/backup)"

  # Hardware & Kernel
  if ask_step "1) Change to nearby update servers"; then step_01_mirrors; fi
  if ask_step "2) Update your operating system"; then step_02_update_upgrade; fi
  if ask_step "3) Install newest microcode"; then step_03_microcode; fi
  if ask_step "4) Check and install drivers"; then step_04_drivers; fi
  if ask_step "5) WiFi firmware (iwlwifi, update-initramfs)"; then step_05_wifi_firmware; fi

  # OS System Settings
  if ask_step "6) Install multimedia codecs"; then step_06_codecs; fi
  if ask_step "7) Improve memory use (swappiness)"; then step_07_swappiness; fi
  if ask_step "8) Set up firewall"; then step_08_firewall; fi
  if ask_step "9) Improve battery life (TLP)"; then step_09_battery_tlp; fi
  if ask_step "10) Set up Redshift"; then step_10_redshift; fi
  if ask_step "11) Speed up launch times with Preload"; then step_11_preload; fi
  if ask_step "12) Fractional scaling"; then step_12_fractional_scaling; fi
  if ask_step "13) LDAP/Active Directory setup (optional)"; then step_13_ldap_ad_setup; fi

  # Dev Tools & Git
  if ask_step "14) Configure Git globally"; then step_14_git_config; fi
  if ask_step "15) Python dev environment (pip, venv)"; then step_15_python_dev_env; fi
  if ask_step "16) Install basic software"; then step_16_basic_software; fi
  if ask_step "17) Install VS Code"; then step_17_vscode; fi
  if ask_step "18) Manage VS Code extensions"; then step_18_vscode_extensions; fi
  if ask_step "19) Install DBEaver (database client)"; then step_19_dbeaver; fi
  if ask_step "20) Install Flatseal (flatpak permissions)"; then step_20_flatseal; fi

  # Apps (including Sync & Backup)
  if ask_step "21) Install Brave browser"; then step_21_brave; fi
  if ask_step "22) Remove unwanted applications"; then step_22_remove_unwanted; fi
  if ask_step "23) Additional users and parental control"; then step_23_users_parental; fi
  if ask_step "24) Install additional fonts"; then step_24_fonts; fi
  if ask_step "25) Install Stacer"; then step_25_stacer; fi
  if ask_step "26) Install Ulauncher"; then step_26_ulauncher; fi
  if ask_step "27) Install clipboard manager"; then step_27_clipboard_manager; fi
  if ask_step "28) Set up Timeshift"; then step_28_timeshift; fi
  if ask_step "29) Set backup strategy for personal files"; then step_29_backup_personal; fi
  if ask_step "30) Install Dropbox"; then step_30_dropbox; fi
  if ask_step "31) Install ExpanDrive"; then step_31_expandrive; fi

  msg "All steps processed."
}

main "$@"
