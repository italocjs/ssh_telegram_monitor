#!/bin/bash

############################################################
# SSH Connection Monitor Script
#
# Monitors SSH connections in real-time and sends Telegram 
# notifications for security monitoring.
#
# Features:
# - Real-time SSH connection monitoring
# - Login/logout detection
# - Failed authentication alerts
# - IP geolocation lookup
# - Rate limiting to prevent spam
# - Comprehensive logging
############################################################

# Version
VERSION="1.0.3"

# Load environment configuration
if [ -f "./.env" ]; then
    source ./.env
fi

# Color codes for logging
GREEN="\033[0;32m"
BLUE="\033[0;34m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
PURPLE="\033[0;35m"
NC="\033[0m" # No Color

# Configuration
LOG_FILE="./logs/ssh-monitor.log"
STATE_FILE="/tmp/ssh-monitor-state"
RATE_LIMIT_FILE="/tmp/ssh-monitor-rate"

# Rate limiting (seconds between notifications for same IP)
RATE_LIMIT_LOGIN_SECONDS=10    # 10 seconds for successful logins
RATE_LIMIT_FAILED_SECONDS=0    # No rate limit for failed attempts (log ALL)
RATE_LIMIT_LOGOUT_SECONDS=60   # 1 minute for logouts

# Notification settings
NOTIFY_SUCCESSFUL_LOGINS=true
NOTIFY_FAILED_LOGINS=true
NOTIFY_LOGOUTS=true
NOTIFY_ROOT_LOGINS=true  # Always notify for root logins regardless of rate limit

# =====================
# FUNCTION DEFINITIONS
# =====================

log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local colored_message=""
    
    case "$level" in
        "INFO")
            colored_message="${BLUE}[INFO]${NC} $message"
            ;;
        "SUCCESS")
            colored_message="${GREEN}[SUCCESS]${NC} $message"
            ;;
        "WARNING")
            colored_message="${YELLOW}[WARNING]${NC} $message"
            ;;
        "ERROR")
            colored_message="${RED}[ERROR]${NC} $message"
            ;;
        "SECURITY")
            colored_message="${PURPLE}[SECURITY]${NC} $message"
            ;;
        *)
            colored_message="[$level] $message"
            ;;
    esac
    
    echo -e "$colored_message"
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Send Telegram notification
telegram_send() {
    local message="$1"
    
    if [ -z "$message" ]; then
        echo "Usage: telegram_send <message>"
        return 1
    fi
    
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        local url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
        local curl_args=("--data-urlencode" "chat_id=${TELEGRAM_CHAT_ID}" "--data-urlencode" "text=${message}")
        
        # Add topic ID if specified
        if [ -n "$OPTIONAL_TOPIC_ID" ]; then
            curl_args+=("--data-urlencode" "message_thread_id=${OPTIONAL_TOPIC_ID}")
        fi
        
        if curl -s -X POST "$url" "${curl_args[@]}" | grep -q '"ok":true'; then
            return 0  # Success
        else
            return 1  # Failed
        fi
    else
        echo "Telegram credentials not configured"
        return 1
    fi
}

# Get IP geolocation info (with timeout and error handling)
get_ip_info() {
    local ip="$1"
    
    # Skip private IPs
    if [[ "$ip" =~ ^10\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.|^192\.168\.|^127\.|^::1$|^localhost$ ]]; then
        echo "🏠 Local Network"
        return
    fi
    
    # Try to get location info with timeout
    local location=""
    if command -v curl &> /dev/null; then
        location=$(timeout 5 curl -s "http://ip-api.com/line/${ip}?fields=country,regionName,city,isp" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    fi
    
    if [ -n "$location" ] && [ "$location" != "fail" ]; then
        echo "🌍 $location"
    else
        echo "🌐 External IP: $ip"
    fi
}

# Check rate limiting
should_notify() {
    local ip="$1"
    local event_type="$2"
    local current_time=$(date +%s)
    
    # Always notify for root logins
    if [ "$NOTIFY_ROOT_LOGINS" = true ] && [[ "$event_type" =~ root ]]; then
        return 0
    fi
    
    # Determine rate limit based on event type
    local rate_limit_seconds=0
    if [[ "$event_type" =~ ^login_ ]]; then
        rate_limit_seconds=$RATE_LIMIT_LOGIN_SECONDS
    elif [[ "$event_type" =~ ^failed_ ]]; then
        rate_limit_seconds=$RATE_LIMIT_FAILED_SECONDS
    elif [[ "$event_type" =~ ^logout_ ]]; then
        rate_limit_seconds=$RATE_LIMIT_LOGOUT_SECONDS
    fi
    
    # No rate limiting if set to 0 (for failed attempts)
    if [ $rate_limit_seconds -eq 0 ]; then
        return 0
    fi
    
    # Check rate limit file
    local rate_key="${ip}_${event_type}"
    local last_notification=0
    
    if [ -f "$RATE_LIMIT_FILE" ]; then
        last_notification=$(grep "^${rate_key}:" "$RATE_LIMIT_FILE" 2>/dev/null | cut -d: -f2 || echo 0)
    fi
    
    local time_diff=$((current_time - last_notification))
    
    if [ $time_diff -ge $rate_limit_seconds ]; then
        # Update rate limit file
        mkdir -p "$(dirname "$RATE_LIMIT_FILE")"
        grep -v "^${rate_key}:" "$RATE_LIMIT_FILE" 2>/dev/null > "${RATE_LIMIT_FILE}.tmp" || true
        echo "${rate_key}:${current_time}" >> "${RATE_LIMIT_FILE}.tmp"
        mv "${RATE_LIMIT_FILE}.tmp" "$RATE_LIMIT_FILE"
        return 0
    else
        return 1
    fi
}

# Process SSH log entry
process_ssh_event() {
    local log_line="$1"
    
    # Extract timestamp and hostname - handle different log formats
    local timestamp=""
    local hostname=""
    
    # For journalctl format (ISO timestamp)
    if echo "$log_line" | grep -q "T.*Z\|T.*[+-][0-9]"; then
        timestamp=$(echo "$log_line" | awk '{print $1}' | sed 's/T/ /')
        hostname=$(echo "$log_line" | awk '{print $2}')
    else
        # For traditional syslog format
        timestamp=$(echo "$log_line" | awk '{print $1, $2, $3}')
        hostname=$(echo "$log_line" | awk '{print $4}')
    fi
    
    # Clean up hostname (remove trailing colon)
    hostname=$(echo "$hostname" | sed 's/:$//')
    
    # Extract different types of SSH events
    if echo "$log_line" | grep -q "Accepted password\|Accepted publickey"; then
        # Successful login
        local user=$(echo "$log_line" | grep -o "for [^ ]*" | cut -d' ' -f2)
        local ip=$(echo "$log_line" | grep -o "from [0-9.]*\|from [0-9a-f:]*" | cut -d' ' -f2)
        local auth_method="password"
        
        if echo "$log_line" | grep -q "publickey"; then
            auth_method="SSH key"
        fi
        
        log_message "SECURITY" "SSH login: $user from $ip using $auth_method"
        
        if [ "$NOTIFY_SUCCESSFUL_LOGINS" = true ] && should_notify "$ip" "login_$user"; then
            local ip_info=$(get_ip_info "$ip")
            local alert_icon="🔐"
            
            # Use different icon for root
            if [ "$user" = "root" ]; then
                alert_icon="⚠️"
            fi
            
            local message="$alert_icon SSH Login Detected

👤 User: $user
🖥️ Server: $hostname
📍 From: $ip
$ip_info
🔑 Method: $auth_method
⏰ Time: $timestamp

$([ "$user" = "root" ] && echo "🚨 ROOT LOGIN - High Priority!" || echo "ℹ️ Regular user login")"
            
            telegram_send "$message"
        fi
        
    elif echo "$log_line" | grep -q "Failed password\|Failed publickey\|Invalid user"; then
        # Failed login attempt
        local user=$(echo "$log_line" | grep -o "for [^ ]*\|user [^ ]*" | cut -d' ' -f2)
        local ip=$(echo "$log_line" | grep -o "from [0-9.]*\|from [0-9a-f:]*" | cut -d' ' -f2)
        
        log_message "SECURITY" "SSH failed login: $user from $ip"
        
        if [ "$NOTIFY_FAILED_LOGINS" = true ] && should_notify "$ip" "failed_$user"; then
            local ip_info=$(get_ip_info "$ip")
            
            local message="🚨 SSH Failed Login Attempt

👤 User: $user
🖥️ Server: $hostname  
📍 From: $ip
$ip_info
⏰ Time: $timestamp

⚠️ Potential security threat detected!"
            
            telegram_send "$message"
        fi
        
    elif echo "$log_line" | grep -q "session closed\|Disconnected from user"; then
        # User logout
        local user=$(echo "$log_line" | grep -o "user [^ ]*" | cut -d' ' -f2 || echo "unknown")
        local ip=$(echo "$log_line" | grep -o "from [0-9.]*\|from [0-9a-f:]*" | cut -d' ' -f2 || echo "unknown")
        
        log_message "INFO" "SSH logout: $user from $ip"
        
        if [ "$NOTIFY_LOGOUTS" = true ] && should_notify "$ip" "logout_$user"; then
            local message="🔓 SSH Session Ended

👤 User: $user
🖥️ Server: $hostname
📍 From: $ip  
⏰ Time: $timestamp"
            
            telegram_send "$message"
        fi
    fi
}

# Initialize logging
setup_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    
    # Rotate log if it gets too large (>10MB)
    if [ -f "$LOG_FILE" ] && [ $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt 10485760 ]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        touch "$LOG_FILE"
        log_message "INFO" "Log file rotated"
    fi
}

# Cleanup function
cleanup() {
    log_message "INFO" "SSH monitor stopped"
    rm -f "$STATE_FILE"
    exit 0
}

# =============
# MAIN EXECUTION
# =============

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} This script requires root privileges to read SSH logs!"
    echo -e "${RED}[ERROR]${NC} Please run as root: sudo $0"
    exit 1
fi

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Initialize
setup_logging
echo $$ > "$STATE_FILE"

log_message "INFO" "SSH Monitor v$VERSION started"
log_message "INFO" "Monitoring SSH connections... (PID: $$)"

# Send startup notification
telegram_send "🔍 SSH Monitor v$VERSION started

🛡️ Now monitoring SSH connections
🔔 Notifications enabled for:
$([ "$NOTIFY_SUCCESSFUL_LOGINS" = true ] && echo "• ✅ Successful logins")
$([ "$NOTIFY_FAILED_LOGINS" = true ] && echo "• ❌ Failed login attempts (NO rate limit)") 
$([ "$NOTIFY_LOGOUTS" = true ] && echo "• 🔓 Session logouts")
$([ "$NOTIFY_ROOT_LOGINS" = true ] && echo "• ⚠️ Root logins (high priority)")

📊 Rate limits:
• ✅ Successful logins: ${RATE_LIMIT_LOGIN_SECONDS}s
• ❌ Failed attempts: No limit (all logged)
• 🔓 Logouts: ${RATE_LIMIT_LOGOUT_SECONDS}s
📝 Logs: $LOG_FILE"

# Monitor SSH logs in real-time using journalctl
log_message "INFO" "Starting real-time SSH log monitoring..."

# Try journalctl first (preferred method)
if command -v journalctl &> /dev/null && journalctl -u ssh.service -u sshd.service --no-pager -n 1 &>/dev/null; then
    log_message "INFO" "Using journalctl for SSH log monitoring"
    # Use journalctl to follow SSH logs in real-time (only new events from now on)
    journalctl -u ssh.service -u sshd.service -f --no-pager -o short-iso --since "now" 2>/dev/null | while read -r line; do
        # Process each SSH-related log line
        if echo "$line" | grep -E "(sshd|ssh)" | grep -E "(Accepted|Failed|session closed|Disconnected|Invalid user)" >/dev/null 2>&1; then
            process_ssh_event "$line"
        fi
    done
else
    # Fallback: Monitor auth.log if journalctl is not available or fails
    if [ -f "/var/log/auth.log" ]; then
        log_message "INFO" "Fallback: Using /var/log/auth.log for SSH log monitoring"
        # For auth.log, tail -F only shows new lines by default
        tail -F /var/log/auth.log 2>/dev/null | while read -r line; do
            if echo "$line" | grep -E "sshd.*Accepted|sshd.*Failed|sshd.*session closed|sshd.*Disconnected|sshd.*Invalid user" >/dev/null 2>&1; then
                process_ssh_event "$line"
            fi
        done
    else
        log_message "ERROR" "Neither journalctl nor /var/log/auth.log are available for monitoring!"
        exit 1
    fi
fi
