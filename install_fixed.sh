#!/bin/bash

# ---------------- COLORS ----------------
GREEN='\33[0;32m'
YELLOW='\33[1;33m'
MAGENTA='\33[0;35m'
RED='\33[0;31m'
NC='\33[0m'

# ---------------- CHECK ROOT ----------------
if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}[!] This script must be run as root.${NC}"
    echo -e "${YELLOW}[!] Please use 'sudo' or switch to root user.${NC}"
    exit 1
fi

# ---------------- FAST DEPENDENCY CHECK ----------------
DEPS_MARKER="/etc/.lena_deps_installed"
if [[ ! -f "$DEPS_MARKER" ]]; then
    echo -e "${YELLOW}[*] Checking and installing dependencies (first run only)...${NC}"
    apt-get update -y -qq
    for pkg in iproute2 net-tools grep awk iputils-ping jq curl iptables; do
        if ! command -v $pkg &> /dev/null; then
            echo -e "${YELLOW}[*] Installing $pkg...${NC}"
            apt-get install -y -qq $pkg
        fi
    done
    touch "$DEPS_MARKER"
else
    echo -e "${GREEN}[✓] Dependencies already installed. Skipping check.${NC}"
fi


# ---------------- FUNCTIONS ----------------

check_core_status() {
    ip link show | grep -q 'vxlan' && echo "Active" || echo "Inactive"
}

Lena_menu() {
    clear
    SERVER_IP=$(hostname -I | awk '{print $1}')
    SERVER_COUNTRY=$(curl -sS "http://ip-api.com/json/$SERVER_IP" | jq -r '.country')
    SERVER_ISP=$(curl -sS "http://ip-api.com/json/$SERVER_IP" | jq -r '.isp')

    echo "+-------------------------------------------------------------------------+"
    echo "| _                      							|"
    echo "|| |                     							|"
    echo "|| |     ___ _ __   __ _ 							|"
    echo "|| |    / _ \\ '_ \\ / _  |							|"
    echo "|| |___|  __/ | | | (_| |							|"
    echo "|\\_____/\\___|_| |_|\\__,_|	V2.0.0 (Multi-Tunnel)	            |"
    echo "+-------------------------------------------------------------------------+"
    echo -e "| Telegram Channel : ${MAGENTA}@AminiDev ${NC}| Version : ${GREEN} 2.0.0 ${NC} "
    echo "+-------------------------------------------------------------------------+"
    echo -e "|${GREEN}Server Country    |${NC} $SERVER_COUNTRY"
    echo -e "|${GREEN}Server IP         |${NC} $SERVER_IP"
    echo -e "|${GREEN}Server ISP        |${NC} $SERVER_ISP"
    echo "+-------------------------------------------------------------------------+"
    echo -e "|${YELLOW}Please choose an option:${NC}"
    echo "+-------------------------------------------------------------------------+"
    echo -e "1- Install new tunnel"
    echo -e "2- Uninstall tunnel(s)"
    echo -e "3- Edit tunnel"
    echo -e "4- Install BBR"
    echo -e "5- Cronjob settings"
    echo -e "6- Show active tunnels"
    echo -e "0- Exit"
    echo "+-------------------------------------------------------------------------+"
    echo -e "\33[0m"
}

# ---------------- SHOW ACTIVE TUNNELS ----------------
show_active_tunnels() {
    echo -e "${GREEN}=== Active VXLAN Tunnels ===${NC}"
    local tunnels=$(ip -d link show | grep -oP 'vxlan\d+' | sort -u)
    if [[ -z "$tunnels" ]]; then
        echo -e "${YELLOW}No active tunnels found.${NC}"
    else
        for tunnel in $tunnels; do
            echo -e "${GREEN}Interface: $tunnel${NC}"
            ip addr show $tunnel 2>/dev/null | grep -E 'inet |vxlan' | head -2
            echo "---"
        done
    fi
    read -p "Press Enter to return to menu..."
}

# ---------------- EDIT VXLAN TUNNEL ----------------
edit_vxlan_tunnel() {
    local BRIDGE_FILE="/usr/local/bin/vxlan_bridge.sh"
    local HAPROXY_CFG="/etc/haproxy/haproxy.cfg"

    # --- Retrieve current settings ---
    local VXLAN_IF VNI CUR_REMOTE CUR_LOCAL CUR_PORT
    if [[ -f "$BRIDGE_FILE" ]]; then
        CUR_REMOTE=$(grep -oP 'remote \K[^ ]+' "$BRIDGE_FILE")
        CUR_LOCAL=$(grep -oP 'ip addr add \K[^ ]+' "$BRIDGE_FILE")
        CUR_PORT=$(grep -oP 'dstport \K[^ ]+' "$BRIDGE_FILE")
        VXLAN_IF=$(grep -oP 'dev \K[^ ]+' "$BRIDGE_FILE" | head -n1)
        VNI=$(grep -oP 'vxlan id \K[^ ]+' "$BRIDGE_FILE")
    fi

    echo "=== Edit VXLAN Tunnel ==="
    # --- Prompt for new values (default to current) ---
    read -p "Remote IP [$CUR_REMOTE]: " NEW_REMOTE
    NEW_REMOTE=${NEW_REMOTE:-$CUR_REMOTE}
    read -p "Local VXLAN IP (e.g. 10.0.1.15/24) [$CUR_LOCAL]: " NEW_LOCAL
    NEW_LOCAL=${NEW_LOCAL:-$CUR_LOCAL}
    [[ "$NEW_LOCAL" != */* ]] && NEW_LOCAL="$NEW_LOCAL/24"
    read -p "VXLAN Port [$CUR_PORT]: " NEW_PORT
    NEW_PORT=${NEW_PORT:-$CUR_PORT}

    # --- Validate inputs ---
    if [[ -z "$NEW_REMOTE" || -z "$NEW_LOCAL" || -z "$NEW_PORT" ]]; then
        echo "[x] Error: All fields are required."
        return
    fi

    # --- Remove existing interface and any lingering IPs ---
    if ip link show "$VXLAN_IF" &>/dev/null; then
        echo "[*] Deleting existing interface $VXLAN_IF"
        ip link del "$VXLAN_IF"
    else
        # flush any old IPs if interface exists in namespace
        ip addr flush dev "$VXLAN_IF" 2>/dev/null || true
    fi

    # --- Create and configure new VXLAN ---
    local IFACE=$(ip route get 1.1.1.1 | awk '{print $5}' | head -n1)
    local HOST_IP=$(hostname -I | awk '{print $1}')
    echo "[*] Creating VXLAN interface $VXLAN_IF with ID $VNI"
    ip link add "$VXLAN_IF" type vxlan id "$VNI" \
        local "$HOST_IP" remote "$NEW_REMOTE" \
        dev "$IFACE" dstport "$NEW_PORT" nolearning
    echo "[*] Assigning IP $NEW_LOCAL to $VXLAN_IF"
    ip addr add "$NEW_LOCAL" dev "$VXLAN_IF"
    ip link set "$VXLAN_IF" up

    # --- Update bridge script for persistence ---
    if [[ -f "$BRIDGE_FILE" ]]; then
        sed -i "s|remote [^ ]\+|remote $NEW_REMOTE|" "$BRIDGE_FILE"
        sed -i "s|ip addr add [^ ]\+|ip addr add $NEW_LOCAL|" "$BRIDGE_FILE"
        sed -i "s|dstport [^ ]\+|dstport $NEW_PORT|" "$BRIDGE_FILE"
    fi

    # --- Update HAProxy backend IP if configured ---
    if [[ -f "$HAPROXY_CFG" ]]; then
        local OLD_IP="${CUR_LOCAL%%/*}"
        local NEW_IP="${NEW_LOCAL%%/*}"
        if [[ "$OLD_IP" != "$NEW_IP" ]]; then
            echo "[*] Replacing HAProxy IP: $OLD_IP -> $NEW_IP"
            sed -i "s/$OLD_IP/$NEW_IP/g" "$HAPROXY_CFG"
            systemctl restart haproxy
        fi
    fi

    # --- Restart VXLAN service ---
    echo "[*] Restarting VXLAN tunnel service"
    systemctl restart vxlan-tunnel.service

    echo -e "${GREEN}[✓] VXLAN tunnel updated and all services restarted.${NC}"
}


uninstall_all_vxlan() {
    echo "[!] Deleting all VXLAN interfaces and cleaning up..."
    for i in $(ip -d link show | grep -o 'vxlan[0-9]\+'); do
        ip link del $i 2>/dev/null
    done

    systemctl stop haproxy vxlan-tunnel 2>/dev/null
    systemctl disable haproxy vxlan-tunnel 2>/dev/null

    # Stop all multi-tunnel services
    for service in /etc/systemd/system/vxlan-tunnel-*.service; do
        if [[ -f "$service" ]]; then
            svc_name=$(basename "$service")
            systemctl stop "$svc_name" 2>/dev/null
            systemctl disable "$svc_name" 2>/dev/null
        fi
    done

    rm -f /usr/local/bin/vxlan_bridge.sh /usr/local/bin/vxlan_bridge_*.sh /etc/ping_vxlan.sh
    rm -f /etc/systemd/system/vxlan-tunnel.service /etc/systemd/system/vxlan-tunnel-*.service

    systemctl daemon-reload

    # Remove HAProxy package
    apt remove -y haproxy -qq
    apt purge -y haproxy -qq
    apt autoremove -y 2>/dev/null

    # Remove related cronjobs
    crontab -l 2>/dev/null | grep -v 'systemctl restart haproxy' | grep -v 'systemctl restart vxlan-tunnel' | grep -v '/etc/ping_vxlan.sh' > /tmp/cron_tmp || true
    crontab /tmp/cron_tmp
    rm /tmp/cron_tmp
    echo "[+] All VXLAN tunnels and related cronjobs deleted."
}

install_bbr() {
    echo "Running BBR script..."
    curl -fsSLk https://raw.githubusercontent.com/MrAminiDev/NetOptix/main/scripts/bbr.sh | bash
}

install_haproxy_and_configure() {
    local backend_ips=("$@")
    
    echo "[*] Configuring HAProxy..."

    # Ensure haproxy is installed
    if ! command -v haproxy >/dev/null 2>&1; then
        echo "[x] HAProxy is not installed. Installing..."
        apt update -qq && apt install -y haproxy -qq
    fi

    # Ensure config directory exists
    mkdir -p /etc/haproxy

    # Default HAProxy config file
    local CONFIG_FILE="/etc/haproxy/haproxy.cfg"
    local BACKUP_FILE="/etc/haproxy/haproxy.cfg.bak"

    # Backup old config
    [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$BACKUP_FILE"

    # Write base config
    cat <<EOL > "$CONFIG_FILE"
global
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    maxconn 4096

defaults
    mode    tcp
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms
    retries 3
    option  tcpka
EOL

    read -p "Enter ports (comma-separated): " user_ports

    IFS=',' read -ra ports <<< "$user_ports"

    for port in "${ports[@]}"; do
        cat <<EOL >> "$CONFIG_FILE"

frontend frontend_$port
    bind *:$port
    default_backend backend_$port
    option tcpka

backend backend_$port
    option tcpka
EOL
        # Add all backend IPs
        local server_num=1
        for backend_ip in "${backend_ips[@]}"; do
            cat <<EOL >> "$CONFIG_FILE"
    server server$server_num $backend_ip:$port check maxconn 2048
EOL
            ((server_num++))
        done
    done

    # Validate haproxy config
    if haproxy -c -f "$CONFIG_FILE"; then
        echo "[*] Restarting HAProxy service..."
        systemctl enable haproxy && systemctl restart haproxy
        echo -e "${GREEN}HAProxy configured and restarted successfully.${NC}"
    else
        echo -e "${YELLOW}Warning: HAProxy configuration is invalid!${NC}"
    fi
}

# ---------------- CREATE MULTI-TUNNEL FUNCTION ----------------
# This version accepts arrays: remote_ips and ports (one port per tunnel)
create_multi_tunnel() {
    local role=$1           # iran or kharej
    local local_ip=$2       # this server IP
    local base_vni=$3       # starting VNI
    shift 3
    
    # Parse the remaining arguments: first half are IPs, second half are ports
    local total_args=$#
    local num_tunnels=$((total_args / 2))
    
    local remote_ips=()
    local ports=()
    
    for i in $(seq 1 $num_tunnels); do
        remote_ips+=("$1")
        shift
    done
    for i in $(seq 1 $num_tunnels); do
        ports+=("$1")
        shift
    done
    
    local INTERFACE=$(ip route get 1.1.1.1 | awk '{print $5}' | head -n1)
    local HOST_IP=$(hostname -I | awk '{print $1}')
    local vxlan_ips=()
    
    echo -e "${GREEN}[*] Creating ${#remote_ips[@]} VXLAN tunnels...${NC}"
    
    local tunnel_num=1
    for idx in "${!remote_ips[@]}"; do
        local remote_ip="${remote_ips[$idx]}"
        local dstport="${ports[$idx]}"
        local VNI=$((base_vni + tunnel_num - 1))
        local VXLAN_IF="vxlan${VNI}"
        
        # Calculate VXLAN IPs based on role
        if [[ "$role" == "iran" ]]; then
            # Iran server: .1 for each tunnel
            local VXLAN_IP="30.0.${tunnel_num}.1/24"
            local REMOTE_VXLAN_IP="30.0.${tunnel_num}.2"
        else
            # Kharej server: .2 for each tunnel
            local VXLAN_IP="30.0.${tunnel_num}.2/24"
            local REMOTE_VXLAN_IP="30.0.${tunnel_num}.1"
        fi
        
        vxlan_ips+=("${VXLAN_IP%/*}")
        
        echo -e "${YELLOW}[+] Creating tunnel $tunnel_num to $remote_ip (VNI: $VNI, Port: $dstport)${NC}"
        
        # Delete if exists
        ip link del "$VXLAN_IF" 2>/dev/null || true
        
        # Create VXLAN interface
        ip link add "$VXLAN_IF" type vxlan id "$VNI" \
            local "$HOST_IP" remote "$remote_ip" \
            dev "$INTERFACE" dstport "$dstport" nolearning
        
        # Assign IP
        ip addr add "$VXLAN_IP" dev "$VXLAN_IF"
        ip link set "$VXLAN_IF" up
        
        # Add iptables rules
        iptables -I INPUT 1 -p udp --dport "$dstport" -j ACCEPT 2>/dev/null || true
        iptables -I INPUT 1 -s "$remote_ip" -j ACCEPT 2>/dev/null || true
        iptables -I INPUT 1 -s "${VXLAN_IP%/*}" -j ACCEPT 2>/dev/null || true
        
        # Create bridge script for this tunnel
        cat <<EOF > "/usr/local/bin/vxlan_bridge_${tunnel_num}.sh"
#!/bin/bash
ip link del $VXLAN_IF 2>/dev/null || true
ip link add $VXLAN_IF type vxlan id $VNI local $HOST_IP remote $remote_ip dev $INTERFACE dstport $dstport nolearning
ip addr add $VXLAN_IP dev $VXLAN_IF
ip link set $VXLAN_IF up
# Persistent keepalive: ping remote every 30s in background
( while true; do ping -c 1 $remote_ip >/dev/null 2>&1; sleep 30; done ) &
EOF
        chmod +x "/usr/local/bin/vxlan_bridge_${tunnel_num}.sh"
        
        # Create systemd service for this tunnel
        cat <<EOF > "/etc/systemd/system/vxlan-tunnel-${tunnel_num}.service"
[Unit]
Description=VXLAN Tunnel $tunnel_num to $remote_ip (Port: $dstport)
After=network.target

[Service]
ExecStart=/usr/local/bin/vxlan_bridge_${tunnel_num}.sh
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        
        chmod 644 "/etc/systemd/system/vxlan-tunnel-${tunnel_num}.service"
        
        echo -e "${GREEN}[✓] Tunnel $tunnel_num created: $VXLAN_IF -> $remote_ip (IP: ${VXLAN_IP%/*}, Port: $dstport)${NC}"
        
        ((tunnel_num++))
    done
    
    # Reload and enable all services
    systemctl daemon-reexec
    systemctl daemon-reload
    
    for i in $(seq 1 ${#remote_ips[@]}); do
        systemctl enable "vxlan-tunnel-${i}.service" 2>/dev/null
        systemctl start "vxlan-tunnel-${i}.service" 2>/dev/null
    done
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}[✓] All ${#remote_ips[@]} tunnels created successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Your VXLAN IPs:${NC}"
    for i in "${!vxlan_ips[@]}"; do
        echo -e "  Tunnel $((i+1)): ${vxlan_ips[$i]} (Port: ${ports[$i]})"
    done
    echo ""
    
    # Return vxlan_ips for HAProxy
    printf '%s\n' "${vxlan_ips[@]}"
}

# ---------------- MAIN ----------------
while true; do
    Lena_menu
    read -p "Enter your choice [0-6]: " main_action
    case $main_action in
        0)
            echo "Exiting..."
            exit 0
            ;;
        1)
            break
            ;;
        2)
            uninstall_all_vxlan
            read -p "Press Enter to return to menu..."
            ;;
        3)
            edit_vxlan_tunnel
            ;;
        4)
            install_bbr
            read -p "Press Enter to return to menu..."
            ;;
        5)
            while true; do
                clear
                echo "+-----------------------------+"
                echo "|      Cronjob settings       |"
                echo "+-----------------------------+"
                echo "1- Install cronjob"
                echo "2- Edit cronjob"
                echo "3- Delete cronjob"
                echo "4- Back to main menu"
                read -p "Enter your choice [1-4]: " cron_action
                case $cron_action in
                    1)
                        while true; do
                            read -p "How many hours between each restart? (1-24, b=Back): " cron_hours
                            if [[ "$cron_hours" == "b" || "$cron_hours" == "B" ]]; then
                                break
                            elif [[ $cron_hours =~ ^[0-9]+$ ]] && (( cron_hours >= 1 && cron_hours <= 24 )); then
                                crontab -l 2>/dev/null | grep -v 'systemctl restart haproxy' | grep -v 'systemctl restart vxlan-tunnel' > /tmp/cron_tmp || true
                                echo "0 */$cron_hours * * * systemctl restart haproxy >/dev/null 2>&1" >> /tmp/cron_tmp
                                # Restart all tunnel services
                                echo "0 */$cron_hours * * * for svc in \$(systemctl list-units --type=service --all | grep vxlan-tunnel | awk '{print \$1}'); do systemctl restart \$svc; done >/dev/null 2>&1" >> /tmp/cron_tmp
                                crontab /tmp/cron_tmp
                                rm /tmp/cron_tmp
                                echo -e "${GREEN}Cronjob set successfully to restart haproxy and all vxlan-tunnels every $cron_hours hour(s).${NC}"
                                read -p "Press Enter to return to Cronjob settings..."
                                break
                            else
                                echo "Invalid input. Please enter a number between 1 and 24 or 'b' to go back."
                            fi
                        done
                        ;;
                    2)
                        if crontab -l 2>/dev/null | grep -q 'systemctl restart haproxy'; then
                            while true; do
                                read -p "Enter new hours for cronjob (1-24, b=Back): " new_cron_hours
                                if [[ "$new_cron_hours" == "b" || "$new_cron_hours" == "B" ]]; then
                                    break
                                elif [[ $new_cron_hours =~ ^[0-9]+$ ]] && (( new_cron_hours >= 1 && new_cron_hours <= 24 )); then
                                    crontab -l 2>/dev/null | grep -v 'systemctl restart haproxy' | grep -v 'systemctl restart vxlan-tunnel' > /tmp/cron_tmp || true
                                    echo "0 */$new_cron_hours * * * systemctl restart haproxy >/dev/null 2>&1" >> /tmp/cron_tmp
                                    echo "0 */$new_cron_hours * * * for svc in \$(systemctl list-units --type=service --all | grep vxlan-tunnel | awk '{print \$1}'); do systemctl restart \$svc; done >/dev/null 2>&1" >> /tmp/cron_tmp
                                    crontab /tmp/cron_tmp
                                    rm /tmp/cron_tmp
                                    echo -e "${GREEN}Cronjob updated successfully to every $new_cron_hours hour(s).${NC}"
                                    read -p "Press Enter to return to Cronjob settings..."
                                    break
                                else
                                    echo "Invalid input. Please enter a number between 1 and 24 or 'b' to go back."
                                fi
                            done
                        else
                            echo -e "${YELLOW}No cronjob found to edit. Please install first.${NC}"
                            read -p "Press Enter to return to Cronjob settings..."
                        fi
                        ;;
                    3)
                        if crontab -l 2>/dev/null | grep -q 'systemctl restart haproxy'; then
                            crontab -l 2>/dev/null | grep -v 'systemctl restart haproxy' | grep -v 'systemctl restart vxlan-tunnel' > /tmp/cron_tmp || true
                            crontab /tmp/cron_tmp
                            rm /tmp/cron_tmp
                            echo -e "${GREEN}Cronjob deleted successfully.${NC}"
                        else
                            echo -e "${YELLOW}No cronjob found to delete.${NC}"
                        fi
                        read -p "Press Enter to return to Cronjob settings..."
                        ;;
                    4)
                        break
                        ;;
                    *)
                        echo "[x] Invalid option. Try again."
                        sleep 1
                        ;;
                esac
            done
            ;;
        6)
            show_active_tunnels
            ;;
        *)
            echo "[x] Invalid option. Try again."
            sleep 1
            ;;
    esac

done

# Check if ip command is available
if ! command -v ip >/dev/null 2>&1; then
    echo "[x] iproute2 is not installed. Aborting."
    exit 1
fi

# ------------- VARIABLES --------------
BASE_VNI=88

# --------- Choose Server Role ----------
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}      Multi-Tunnel Configuration       ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Choose server role:"
echo "1- Iran (Receive tunnels from multiple Kharej servers)"
echo "2- Kharej (Connect to multiple Iran servers)"
echo "3- Single tunnel (Legacy mode)"
read -p "Enter choice (1/2/3): " role_choice

if [[ "$role_choice" == "1" ]]; then
    # ========== IRAN SERVER - Multiple Kharej to One Iran ==========
    echo ""
    echo -e "${YELLOW}=== Iran Server Setup (Multi-Kharej to One Iran) ===${NC}"
    echo ""
    
    read -p "Enter this server's (IRAN) IP: " IRAN_IP
    
    echo ""
    echo -e "${YELLOW}How many Kharej servers do you want to connect?${NC}"
    read -p "Enter number of Kharej servers: " num_kharej
    
    if ! [[ "$num_kharej" =~ ^[0-9]+$ ]] || [[ "$num_kharej" -lt 1 ]]; then
        echo -e "${RED}[x] Invalid number. Must be at least 1.${NC}"
        exit 1
    fi
    
    declare -a KHAREJ_IPS
    declare -a TUNNEL_PORTS
    echo ""
    for i in $(seq 1 $num_kharej); do
        read -p "Enter Kharej server $i IP: " kharej_ip
        KHAREJ_IPS+=("$kharej_ip")
        
        # Port validation loop for each server
        while true; do
            read -p "Enter tunnel port for Kharej $i (1 ~ 64435): " port
            if [[ $port =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 64435 )); then
                TUNNEL_PORTS+=("$port")
                break
            else
                echo "Invalid port. Try again."
            fi
        done
        echo ""
    done
    
    # Create all tunnels with individual ports
    vxlan_result=$(create_multi_tunnel "iran" "$IRAN_IP" "$BASE_VNI" "${KHAREJ_IPS[@]}" "${TUNNEL_PORTS[@]}")
    
    # Parse VXLAN IPs for HAProxy
    readarray -t VXLAN_IPS <<< "$vxlan_result"
    
    # Ask about HAProxy
    while true; do
        read -p "Should port forwarding be done automatically with HAProxy? [1-yes, 2-no]: " haproxy_choice
        if [[ "$haproxy_choice" == "1" || "$haproxy_choice" == "2" ]]; then
            break
        else
            echo "Please enter 1 (yes) or 2 (no)."
        fi
    done
    
    if [[ "$haproxy_choice" == "1" ]]; then
        # Get the remote VXLAN IPs (Kharej side IPs: 30.0.X.2)
        declare -a backend_ips
        for i in $(seq 1 $num_kharej); do
            backend_ips+=("30.0.${i}.2")
        done
        install_haproxy_and_configure "${backend_ips[@]}"
    fi
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}     IRAN Server Setup Complete!       ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Your VXLAN IPs (use these in your panels):${NC}"
    for i in $(seq 1 $num_kharej); do
        echo -e "  Tunnel to Kharej $i: 30.0.${i}.1 (Port: ${TUNNEL_PORTS[$((i-1))]})"
    done
    echo ""
    echo -e "${YELLOW}Remote Kharej VXLAN IPs:${NC}"
    for i in $(seq 1 $num_kharej); do
        echo -e "  Kharej $i: 30.0.${i}.2 (Port: ${TUNNEL_PORTS[$((i-1))]})"
    done

elif [[ "$role_choice" == "2" ]]; then
    # ========== KHAREJ SERVER - Multiple Iran to One Kharej ==========
    echo ""
    echo -e "${YELLOW}=== Kharej Server Setup (Multi-Iran to One Kharej) ===${NC}"
    echo ""
    
    read -p "Enter this server's (Kharej) IP: " KHAREJ_IP
    
    echo ""
    echo -e "${YELLOW}How many Iran servers do you want to connect?${NC}"
    read -p "Enter number of Iran servers: " num_iran
    
    if ! [[ "$num_iran" =~ ^[0-9]+$ ]] || [[ "$num_iran" -lt 1 ]]; then
        echo -e "${RED}[x] Invalid number. Must be at least 1.${NC}"
        exit 1
    fi
    
    declare -a IRAN_IPS
    declare -a TUNNEL_PORTS
    echo ""
    for i in $(seq 1 $num_iran); do
        read -p "Enter Iran server $i IP: " iran_ip
        IRAN_IPS+=("$iran_ip")
        
        # Port validation loop for each server
        while true; do
            read -p "Enter tunnel port for Iran $i (1 ~ 64435): " port
            if [[ $port =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 64435 )); then
                TUNNEL_PORTS+=("$port")
                break
            else
                echo "Invalid port. Try again."
            fi
        done
        echo ""
    done
    
    # Create all tunnels with individual ports
    create_multi_tunnel "kharej" "$KHAREJ_IP" "$BASE_VNI" "${IRAN_IPS[@]}" "${TUNNEL_PORTS[@]}"
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}    KHAREJ Server Setup Complete!      ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Your VXLAN IPs (use these in your panels):${NC}"
    for i in $(seq 1 $num_iran); do
        echo -e "  Tunnel to Iran $i: 30.0.${i}.2 (Port: ${TUNNEL_PORTS[$((i-1))]})"
    done
    echo ""
    echo -e "${YELLOW}Remote Iran VXLAN IPs:${NC}"
    for i in $(seq 1 $num_iran); do
        echo -e "  Iran $i: 30.0.${i}.1 (Port: ${TUNNEL_PORTS[$((i-1))]})"
    done

elif [[ "$role_choice" == "3" ]]; then
    # ========== LEGACY SINGLE TUNNEL MODE ==========
    echo ""
    echo -e "${YELLOW}=== Single Tunnel Mode (Legacy) ===${NC}"
    echo ""
    echo "Choose server type:"
    echo "1- Iran"
    echo "2- Kharej"
    read -p "Enter choice (1/2): " single_role
    
    VNI=88
    VXLAN_IF="vxlan${VNI}"
    
    if [[ "$single_role" == "1" ]]; then
        read -p "Enter IRAN IP: " IRAN_IP
        read -p "Enter Kharej IP: " KHAREJ_IP

        while true; do
            read -p "Tunnel port (1 ~ 64435): " DSTPORT
            if [[ $DSTPORT =~ ^[0-9]+$ ]] && (( DSTPORT >= 1 && DSTPORT <= 64435 )); then
                break
            else
                echo "Invalid port. Try again."
            fi
        done

        while true; do
            read -p "Should port forwarding be done automatically? (HAProxy) [1-yes, 2-no]: " haproxy_choice
            if [[ "$haproxy_choice" == "1" || "$haproxy_choice" == "2" ]]; then
                break
            else
                echo "Please enter 1 (yes) or 2 (no)."
            fi
        done
        
        VXLAN_IP="30.0.0.1/24"
        REMOTE_IP=$KHAREJ_IP
        
        if [[ "$haproxy_choice" == "1" ]]; then
            install_haproxy_and_configure "30.0.0.2"
        else
            echo -e "${GREEN}IRAN Server setup complete.${NC}"
            echo -e "####################################"
            echo -e "# Your IPv4: 30.0.0.1              #"
            echo -e "####################################"
        fi

    elif [[ "$single_role" == "2" ]]; then
        read -p "Enter IRAN IP: " IRAN_IP
        read -p "Enter Kharej IP: " KHAREJ_IP

        while true; do
            read -p "Tunnel port (1 ~ 64435): " DSTPORT
            if [[ $DSTPORT =~ ^[0-9]+$ ]] && (( DSTPORT >= 1 && DSTPORT <= 64435 )); then
                break
            else
                echo "Invalid port. Try again."
            fi
        done

        echo -e "${GREEN}Kharej Server setup complete.${NC}"
        echo -e "####################################"
        echo -e "# Your IPv4: 30.0.0.2              #"
        echo -e "####################################"

        VXLAN_IP="30.0.0.2/24"
        REMOTE_IP=$IRAN_IP
    else
        echo "[x] Invalid role selected."
        exit 1
    fi

    # Detect default interface
    INTERFACE=$(ip route get 1.1.1.1 | awk '{print $5}' | head -n1)
    echo "Detected main interface: $INTERFACE"

    # Setup VXLAN
    echo "[+] Creating VXLAN interface..."
    ip link del $VXLAN_IF 2>/dev/null || true
    ip link add $VXLAN_IF type vxlan id $VNI local $(hostname -I | awk '{print $1}') remote $REMOTE_IP dev $INTERFACE dstport $DSTPORT nolearning

    echo "[+] Assigning IP $VXLAN_IP to $VXLAN_IF"
    ip addr add $VXLAN_IP dev $VXLAN_IF
    ip link set $VXLAN_IF up

    echo "[+] Adding iptables rules"
    iptables -I INPUT 1 -p udp --dport $DSTPORT -j ACCEPT
    iptables -I INPUT 1 -s $REMOTE_IP -j ACCEPT
    iptables -I INPUT 1 -s ${VXLAN_IP%/*} -j ACCEPT

    # Create systemd service
    echo "[+] Creating systemd service for VXLAN..."

    cat <<EOF > /usr/local/bin/vxlan_bridge.sh
#!/bin/bash
ip link del $VXLAN_IF 2>/dev/null || true
ip link add $VXLAN_IF type vxlan id $VNI local $(hostname -I | awk '{print $1}') remote $REMOTE_IP dev $INTERFACE dstport $DSTPORT nolearning
ip addr add $VXLAN_IP dev $VXLAN_IF
ip link set $VXLAN_IF up
( while true; do ping -c 1 $REMOTE_IP >/dev/null 2>&1; sleep 30; done ) &
EOF

    chmod +x /usr/local/bin/vxlan_bridge.sh

    cat <<EOF > /etc/systemd/system/vxlan-tunnel.service
[Unit]
Description=VXLAN Tunnel Interface
After=network.target

[Service]
ExecStart=/usr/local/bin/vxlan_bridge.sh
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 /etc/systemd/system/vxlan-tunnel.service
    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl enable vxlan-tunnel.service
    systemctl start vxlan-tunnel.service

    echo -e "\n${GREEN}[✓] VXLAN tunnel service enabled to run on boot.${NC}"
    echo "[✓] VXLAN tunnel setup completed successfully."

else
    echo "[x] Invalid role selected."
    exit 1
fi

echo ""
echo -e "${GREEN}[✓] Setup completed successfully!${NC}"
echo -e "${YELLOW}Use option 6 in menu to view active tunnels.${NC}"
