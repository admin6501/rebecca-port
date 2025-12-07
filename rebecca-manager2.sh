#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

COMPOSE_FILE="/opt/rebecca/docker-compose.yml"
ENV1="/opt/rebecca/.env"
ENV2="/opt/rebecca/rebecca.env"

update_rebecca() {
    read -p "Are you sure you want to run 'rebecca update'? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo -e "${RED}Update canceled.${NC}"
        return
    fi
    rebecca update
}

restart_rebecca() {
    read -p "Are you sure you want to run 'rebecca restart'? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo -e "${RED}Restart canceled.${NC}"
        return
    fi
    rebecca restart
}

change_image() {
    TAG=$1
    sed -i "s|image: rebeccapanel/rebecca:.*|image: rebeccapanel/rebecca:${TAG}|g" "$COMPOSE_FILE"
    echo -e "${GREEN}Image successfully changed to ${TAG}.${NC}"
    update_rebecca
}

change_port() {
    # Select the correct env file
    if [[ -f "$ENV1" ]]; then
        ENV_FILE="$ENV1"
    elif [[ -f "$ENV2" ]]; then
        ENV_FILE="$ENV2"
    else
        echo -e "${RED}No env file found!${NC}"
        return
    fi

    read -p "Enter the new port number: " NEW_PORT

    # Replace only the number after UVICORN_PORT =
    sed -i "s|\(UVICORN_PORT *= *\).*|\1${NEW_PORT}|" "$ENV_FILE"

    echo -e "${GREEN}Port successfully updated.${NC}"
    restart_rebecca
}

while true; do
    clear
    echo -e "${BLUE}==============================${NC}"
    echo -e "${YELLOW}     Rebecca Control Panel Menu${NC}"
    echo -e "${BLUE}==============================${NC}"
    echo -e "${GREEN}1) Change image to dev${NC}"
    echo -e "${GREEN}2) Change image to latest${NC}"
    echo -e "${GREEN}3) Change Rebecca port${NC}"
    echo -e "${RED}0) Exit${NC}"
    echo -e "${BLUE}==============================${NC}"

    read -p "Select an option: " CHOICE

    case $CHOICE in
        1)
            echo -e "${YELLOW}Changing image to dev...${NC}"
            change_image "dev"
            ;;
        2)
            echo -e "${YELLOW}Changing image to latest...${NC}"
            change_image "latest"
            ;;
        3)
            echo -e "${YELLOW}Changing port...${NC}"
            change_port
            ;;
        0)
            echo -e "${GREEN}Exiting script...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option!${NC}"
            ;;
    esac

    echo
    read -p "Press Enter to continue..."
done
