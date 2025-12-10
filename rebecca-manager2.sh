#!/bin/bash

# ============================================================
#   Rebecca & Marzban Manager Script
#   Author: Khalil Omidian
#   Version: 2.2 (Final)
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear

# ============================
#   Pretty Header
# ============================

echo -e "${CYAN}"
echo "=============================================================="
echo "              Rebecca & Marzban Manager Script"
echo "=============================================================="
echo -e "${YELLOW}                 Author: Khalil Omidian ${NC}"
echo -e "${CYAN}==============================================================${NC}"
echo ""

# ============================
#   FILE PATHS
# ============================

REBECCA_COMPOSE="/opt/rebecca/docker-compose.yml"
MARZBAN_COMPOSE="/opt/marzban/docker-compose.yml"

REBECCA_ENV1="/opt/rebecca/.env"
REBECCA_ENV2="/opt/rebecca/rebecca.env"

# ============================
#   Confirm Function
# ============================

confirm() {
    read -p "Are you sure? (y/n): " CONFIRM
    if [[ "$CONFIRM" != "y" ]]; then
        echo -e "${RED}Cancelled.${NC}"
        return 1
    fi
    return 0
}

# ============================
#   Function: Change Image Tag
# ============================

change_image_tag() {
    local TARGET_TAG=$1

    if [[ -f "$REBECCA_COMPOSE" ]]; then
        TARGET_FILE="$REBECCA_COMPOSE"
        MAIN_IMAGE="rebeccapanel/rebecca"
        PANEL="rebecca"
    elif [[ -f "$MARZBAN_COMPOSE" ]]; then
        TARGET_FILE="$MARZBAN_COMPOSE"
        MAIN_IMAGE="gozargah/marzban"
        PANEL="marzban"
    else
        echo -e "${RED}docker-compose.yml not found!${NC}"
        return
    fi

    echo -e "${BLUE}Detected panel: $PANEL${NC}"
    echo -e "${YELLOW}Changing ONLY main panel image to: ${MAIN_IMAGE}:${TARGET_TAG}${NC}"

    confirm || return

    sed -i "s|image: *${MAIN_IMAGE}:.*|image: ${MAIN_IMAGE}:${TARGET_TAG}|" "$TARGET_FILE"

    if [[ "$PANEL" == "rebecca" ]]; then
        rebecca update
    else
        marzban update
    fi

    echo -e "${GREEN}Main panel image updated successfully.${NC}"
}

# ============================
#   Function: Change Port
# ============================

change_port() {
    ENV_FILE=""

    if [[ -f "$REBECCA_ENV1" ]]; then
        ENV_FILE="$REBECCA_ENV1"
    elif [[ -f "$REBECCA_ENV2" ]]; then
        ENV_FILE="$REBECCA_ENV2"
    else
        echo -e "${RED}No .env file found!${NC}"
        return
    fi

    echo -e "${BLUE}Using env file: $ENV_FILE${NC}"

    read -p "Enter new Rebecca port: " NEW_PORT

    confirm || return

    sed -i "s/^UVICORN_PORT *= *.*/UVICORN_PORT=$NEW_PORT/" "$ENV_FILE"

    echo -e "${YELLOW}Restarting Rebecca...${NC}"

    rebecca restart

    echo -e "${GREEN}Port changed and Rebecca restarted successfully.${NC}"
}

# ============================
#   Install Functions
# ============================

install_rebecca_sqlite() {
    confirm || return
    sudo bash -c "$(curl -sL https://github.com/rebeccapanel/Rebecca-scripts/raw/master/rebecca.sh)" @ install
}

install_rebecca_mysql() {
    confirm || return
    sudo bash -c "$(curl -sL https://github.com/rebeccapanel/Rebecca-scripts/raw/master/rebecca.sh)" @ install --database mysql
}

install_rebecca_mariadb() {
    confirm || return
    sudo bash -c "$(curl -sL https://github.com/rebeccapanel/Rebecca-scripts/raw/master/rebecca.sh)" @ install --database mariadb
}

install_rebecca_node() {
    confirm || return
    sudo bash -c "$(curl -sL https://github.com/rebeccapanel/Rebecca-scripts/raw/master/rebecca-node.sh)" @ install
}

# ============================
#   Generic Rebecca Command
# ============================

run_rebecca_cmd() {
    local CMD=$1
    confirm || return
    rebecca $CMD
}

# ============================
#   MENU
# ============================

while true; do
echo -e "${CYAN}"
echo "====================== MENU ======================"
echo -e "${NC}"
echo "0) Exit"
echo "1) Change image to dev"
echo "2) Change image to latest"
echo "3) Change Rebecca port"
echo "4) Rebecca up"
echo "5) Rebecca down"
echo "6) Rebecca restart"
echo "7) Rebecca status"
echo "8) Rebecca logs"
echo "9) Rebecca install (SQLite)"
echo "10) Rebecca install (MySQL)"
echo "11) Rebecca install (MariaDB)"
echo "12) Rebecca service-install"
echo "13) Rebecca service-update"
echo "14) Rebecca service-status"
echo "15) Rebecca service-logs"
echo "16) Rebecca service-uninstall"
echo "17) Rebecca backup"
echo "18) Rebecca backup-service"
echo "19) Rebecca update"
echo "20) Install Rebecca Node"
echo "21) Rebecca core-update"
echo "22) Rebecca uninstall"
echo "=================================================="
echo ""
read -p "Select an option: " OPT

case $OPT in

    0) exit ;;

    1) change_image_tag "dev" ;;
    2) change_image_tag "latest" ;;
    3) change_port ;;

    4) run_rebecca_cmd "up" ;;
    5) run_rebecca_cmd "down" ;;
    6) run_rebecca_cmd "restart" ;;
    7) run_rebecca_cmd "status" ;;
    8) run_rebecca_cmd "logs" ;;

    9) install_rebecca_sqlite ;;
    10) install_rebecca_mysql ;;
    11) install_rebecca_mariadb ;;

    12) run_rebecca_cmd "service-install" ;;
    13) run_rebecca_cmd "service-update" ;;
    14) run_rebecca_cmd "service-status" ;;
    15) run_rebecca_cmd "service-logs" ;;
    16) run_rebecca_cmd "service-uninstall" ;;

    17) run_rebecca_cmd "backup" ;;
    18) run_rebecca_cmd "backup-service" ;;

    19) run_rebecca_cmd "update" ;;

    20) install_rebecca_node ;;

    21) run_rebecca_cmd "core-update" ;;

    22) run_rebecca_cmd "uninstall" ;;

    *) echo -e "${RED}Invalid option!${NC}" ;;
esac

echo ""

done
