#!/bin/bash

ENV_FILE="/opt/rebecca/.env"

# Get new port from user
read -p "Enter the new port: " NEW_PORT

# Check if file exists
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: $ENV_FILE not found!"
    exit 1
fi

# Update only the UVICORN_PORT value
sed -i "s/^UVICORN_PORT *= *.*/UVICORN_PORT = $NEW_PORT/" "$ENV_FILE"

echo "Port successfully changed to: $NEW_PORT"

# Ask for restart confirmation
read -p "Do you want to restart Rebecca? (y/n): " confirm

if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    rebecca restart
    echo "Rebecca has been restarted."
else
    echo "Restart canceled."
fi
