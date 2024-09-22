#!/bin/bash

# Simple script to monitor and block `port-scans` and `login brute force`

LOG_FILE="/var/log/syslog"   # Log file for port scans
AUTH_LOG="/var/log/auth.log" # Log file for SSH attempts
BLOCKLIST="/etc/iptables/blocklist.rules" # File to store block rules
# Just in case You blocked remote access from everywhere, local emergency IP
ALLOWED_ROOT_CIDR_START="10.0.0.0" # Allow root login CIDR start
ALLOWED_ROOT_CIDR_END="10.0.0.3"   # Adjust CIDR end for allowed root logins

# Function to check if IP is already in the blocklist
ip_exists_in_blocklist() {
    ip=$1
    grep -qw "$ip" $BLOCKLIST
    return $?
}

# Function to add IP to blocklist
add_to_blocklist() {
    ip=$1
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if ip_exists_in_blocklist "$ip"; then
        echo "IP ${ip} already exists in the blocklist."
    else
        echo "Blocking IP: $ip at $timestamp"
        echo "-I INPUT -s $ip -j DROP" >> $BLOCKLIST
        echo "-I FORWARD -s $ip -j DROP" >> $BLOCKLIST
        sudo iptables -I INPUT -s "$ip" -j DROP
        sudo iptables -I FORWARD -s "$ip" -j DROP
    fi
}

# Function to convert IP address to integer for comparison
ip_to_int() {
    local ip=$1
    local a b c d
    IFS=. read -r a b c d <<< "$ip"
    echo "$((a * 256 ** 3 + b * 256 ** 2 + c * 256 + d))"
}

# Function to check if IP is within allowed CIDR range
ip_in_range() {
    local ip=$1
    local ip_int=$(ip_to_int "$ip")
    local start_int=$(ip_to_int "$ALLOWED_ROOT_CIDR_START")
    local end_int=$(ip_to_int "$ALLOWED_ROOT_CIDR_END")

    if (( ip_int >= start_int && ip_int <= end_int )); then
        return 0
    else
        return 1
    fi
}

# Function to check if the user has /nologin as their shell
is_nologin_user() {
    local username=$1
    shell=$(getent passwd "$username" | cut -d: -f7)
    if [[ "$shell" == "/usr/sbin/nologin" ]]; then
        return 0
    else
        return 1
    fi
}

# Monitor for SSH unauthorized login attempts
monitor_ssh_attempts() {
    tail -Fn0 $AUTH_LOG | while read line ; do
        # Check for root login attempts
        if echo "$line" | grep -q "Failed password for root"; then
            ip=$(echo "$line" | grep -oP '(?<=from )\d+\.\d+\.\d+\.\d+')
            if ! ip_in_range "$ip"; then
                echo "Unauthorized root login attempt from $ip"
                add_to_blocklist "$ip"
            fi
        fi

        # Check for login attempts with unknown or invalid users
        if echo "$line" | grep -q "Invalid user"; then
            ip=$(echo "$line" | grep -oP '(?<=from )\d+\.\d+\.\d+\.\d+')
            username=$(echo "$line" | grep -oP '(?<=Invalid user )\S+')
            echo "Invalid user $username login attempt, from IP: $ip"
            add_to_blocklist "$ip"
        fi

        # Log failed login attempts for valid users
        if echo "$line" | grep -q "Failed password for"; then
            ip=$(echo "$line" | grep -oP '(?<=from )\d+\.\d+\.\d+\.\d+')
            username=$(echo "$line" | grep -oP '(?<=Failed password for )\S+')

            # Check if the user has /nologin shell to block remote IP
            if is_nologin_user "$username"; then
                echo "Login attempt for valid user $username with /nologin shell from IP: $ip"
                add_to_blocklist "$ip"
            else
                echo "Failed login attempt for valid user $username, from IP: $ip"
            fi
        fi
    done
}

# Monitor log file for port-scan entries and extract IPs
# To get `port-scan: ` reports on `syslog` add corresponding rules to iptables first
# e.g. `-A INPUT -p tcp -m tcp --dport 222 -j LOG --log-prefix "port-scan: "`
monitor_port_scans() {
    tail -Fn0 $LOG_FILE | while read line ; do
        echo "$line" | grep "port-scan: " | grep -oP '(?<=SRC=)\d+\.\d+\.\d+\.\d+' | while read -r ip ; do
            add_to_blocklist "$ip"
            echo "port-scan: from $ip at $timestamp"
        done
    done
}

# Run both monitors in parallel
monitor_port_scans &
monitor_ssh_attempts &
wait
