#!/bin/bash

set -e

REPO_URL="https://github.com/rebeccapanel/rebecca"
ENV_FILE=".env"

# Check command existence
require_command() {
  command -v "$1" >/dev/null 2>&1 || { echo "$1 command not found. Please install it."; exit 1; }
}

# Confirm action
confirm() {
  if [[ "$AUTO_YES" == "true" ]]; then
    return 0
  fi
  read -p "$1 [y/N]: " -r
  [[ $REPLY =~ ^[Yy]$ ]]
}

# Change port number
change_port() {
  read -p "Enter new port number: " NEW_PORT
  [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || { echo "Invalid port."; return 1; }
  if grep -q '^PORT=' "$ENV_FILE"; then
    sed -i "s/^PORT=.*/PORT=$NEW_PORT/" "$ENV_FILE"
  else
    echo "PORT=$NEW_PORT" >> "$ENV_FILE"
  fi
  echo "Port changed to $NEW_PORT"
}

# Change image tag
change_image_tag() {
  read -p "Enter new image tag: " NEW_TAG
  if ! sed -i "s|image: rebeccapanel/rebecca:.*|image: rebeccapanel/rebecca:$NEW_TAG|" docker-compose.yml; then
    echo "Failed to change image tag"; return 1
  fi
  echo "Image tag updated to $NEW_TAG"
}

# Install Rebecca
install_rebecca() {
  require_command curl
  require_command sudo
  local TMP_SCRIPT="/tmp/install_rebecca.sh"
  curl -fsSL "$REPO_URL/raw/main/install.sh" -o "$TMP_SCRIPT" || { echo "Download failed."; return 1; }
  if confirm "Execute downloaded script with sudo?"; then
    sudo bash "$TMP_SCRIPT"
  fi
  rm -f "$TMP_SCRIPT"
}

# Update Rebecca
update_rebecca() {
  require_command rebecca
  if ! rebecca update; then
    echo "Rebecca update failed."; return 1
  fi
  echo "Rebecca updated successfully."
}

# Main menu
main_menu() {
  PS3='Choose an option: '
  options=("Change Port" "Change Image Tag" "Install Rebecca" "Update Rebecca" "Quit")
  select opt in "${options[@]}"; do
    case $REPLY in
      1) change_port;;
      2) change_image_tag;;
      3) install_rebecca;;
      4) update_rebecca;;
      5) break;;
      *) echo "Invalid option";;
    esac
  done
}

# Parse args
AUTO_YES=false
for arg in "$@"; do
  if [[ "$arg" == "--yes" ]]; then
    AUTO_YES=true
  fi
  if [[ "$arg" == "--help" ]]; then
    echo "Usage: $0 [--yes]"
    exit 0
  fi

  # Allow calling a single function directly for CI/CD use
  if declare -f "$arg" > /dev/null; then
    "$arg"
    exit $?
  fi

done

main_menu