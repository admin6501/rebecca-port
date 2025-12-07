#!/bin/bash
# Rebecca Manager Script - Full version
# Version 1.3
# Author: Khalil Omidian

# ===============================
# Colors
# ===============================
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
NC="\e[0m"

# ===============================
# Confirmation Wrapper
# ===============================
confirm_and_run() {
    local desc="$1"
    shift
    local cmd=("$@")
    
    read -p "Are you sure you want to ${desc}? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo -e "${RED}${desc} canceled.${NC}"
        return
    fi

    "${cmd[@]}"
    echo -e "${YELLOW}${desc} completed successfully.${NC}"
}

# ===============================
# Functions
# ===============================

change_image_dev() {
    confirm_and_run "change image to dev" bash -c "sed -i 's|\\(image: rebeccapanel/rebecca:\\).*|\\1dev|' /opt/rebecca/docker-compose.yml && rebecca update"
}

change_image_latest() {
    confirm_and_run "change image to latest" bash -c "sed -i 's|\\(image: rebeccapanel/rebecca:\\).*|\\1latest|' /opt/rebecca/docker-compose.yml && rebecca update"
}

change_port() {
    ENV_FILE=""
    if [[ -f /opt/rebecca/.env ]]; then
        ENV_FILE="/opt/rebecca/.env"
    elif [[ -f /opt/rebecca/rebecca.env ]]; then
        ENV_FILE="/opt/rebecca/rebecca.env"
    else
        echo -e "${RED}No env file found!${NC}"
        return
    fi

    read -p "Enter new port: " new_port
    confirm_and_run "restart Rebecca after changing port" bash -c "sed -i -E 's/^(UVICORN_PORT *= *).*/\\1${new_port}/' \"$ENV_FILE\" && rebecca restart"
}

install_rebecca_sqlite() {
    confirm_and_run "install Rebecca with SQLite" sudo bash -c "$(curl -sL https://github.com/rebeccapanel/Rebecca-scripts/raw/master/rebecca.sh)" @ install
}

install_rebecca_mysql() {
    confirm_and_run "install Rebecca with MySQL" sudo bash -c "$(curl -sL https://github.com/rebeccapanel/Rebecca-scripts/raw/master/rebecca.sh)" @ install --database mysql
}

install_rebecca_mariadb() {
    confirm_and_run "install Rebecca with MariaDB" sudo bash -c "$(curl -sL https://github.com/rebeccapanel/Rebecca-scripts/raw/master/rebecca.sh)" @ install --database mariadb
}

rebecca_up() { confirm_and_run "start services" rebecca up; }
rebecca_down() { confirm_and_run "stop services" rebecca down; }
rebecca_restart() { confirm_and_run "restart services" rebecca restart; }
rebecca_status() { confirm_and_run "show status" rebecca status; }
rebecca_logs() { confirm_and_run "show logs" rebecca logs; }
rebecca_edit() { confirm_and_run "edit docker-compose.yml" rebecca edit; }
rebecca_edit_env() { confirm_and_run "edit environment file" rebecca edit-env; }
rebecca_ssl() { confirm_and_run "SSL management" rebecca ssl; }
rebecca_core_update() { confirm_and_run "update core" rebecca core-update; }
rebecca_enable_redis() { confirm_and_run "enable Redis" rebecca enable-redis; }
rebecca_backup() { confirm_and_run "manual backup" rebecca backup; }
rebecca_backup_service() { confirm_and_run "backup service" rebecca backup-service; }

# ===============================
# Main Menu
# ===============================
while true; do
    echo -e "\n${GREEN}========== Rebecca Manager ==========${NC}"
    echo -e "${GREEN}1) Change image to dev${NC}"
    echo -e "${GREEN}2) Change image to latest${NC}"
    echo -e "${GREEN}3) Change Rebecca port${NC}"
    echo -e "${GREEN}4) Install Rebecca (SQLite)${NC}"
    echo -e "${GREEN}5) Install Rebecca (MySQL)${NC}"
    echo -e "${GREEN}6) Install Rebecca (MariaDB)${NC}"
    echo -e "${GREEN}7) Start services${NC}"
    echo -e "${GREEN}8) Stop services${NC}"
    echo -e "${GREEN}9) Restart services${NC}"
    echo -e "${GREEN}10) Show status${NC}"
    echo -e "${GREEN}11) Show logs${NC}"
    echo -e "${GREEN}12) Edit docker-compose.yml${NC}"
    echo -e "${GREEN}13) Edit environment file${NC}"
    echo -e "${GREEN}14) SSL management${NC}"
    echo -e "${GREEN}15) Core update${NC}"
    echo -e "${GREEN}16) Enable Redis${NC}"
    echo -e "${GREEN}17) Backup${NC}"
    echo -e "${GREEN}18) Backup service${NC}"
    echo -e "${RED}0) Exit${NC}"

    read -p "Choose an option: " option
    case $option in
        1) change_image_dev ;;
        2) change_image_latest ;;
        3) change_port ;;
        4) install_rebecca_sqlite ;;
        5) install_rebecca_mysql ;;
        6) install_rebecca_mariadb ;;
        7) rebecca_up ;;
        8) rebecca_down ;;
        9) rebecca_restart ;;
        10) rebecca_status ;;
        11) rebecca_logs ;;
        12) rebecca_edit ;;
        13) rebecca_edit_env ;;
        14) rebecca_ssl ;;
        15) rebecca_core_update ;;
        16) rebecca_enable_redis ;;
        17) rebecca_backup ;;
        18) rebecca_backup_service ;;
        0) echo -e "${YELLOW}Exiting...${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid option!${NC}" ;;
    esac
done
