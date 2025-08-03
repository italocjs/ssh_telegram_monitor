# SSH Monitor with Telegram Notifications

A simple SSH connection monitoring script that provides real-time notifications via Telegram.

## Important Note

This script is **not a security feature**, it is only a monitoring tool. It does **not** prevent unauthorized access or attacks. You should always use proper security measures such as firewalls, Fail2Ban, strong passwords, and regular system updates to protect your server.

## Features

- 🔍 **Real-time SSH connection monitoring**
- 🔐 **Login/logout detection** with user and IP tracking
- ❌ **Failed authentication alerts** (no rate limiting - logs ALL attempts)
- 🌍 **IP geolocation lookup** for external connections
- 📱 **Telegram notifications** with organized topics

## Prerequisites

- Linux system with SSH server (OpenSSH)
- Telegram bot token and chat ID

## Installation

### 1. Clone or Download the Project

```bash
git clone <repository-url>
cd ssh_telegram_monitor
```

### 2. Configure Telegram Notifications

1. **Create a Telegram Bot:**
   - Message @BotFather on Telegram
   - Send `/newbot` and follow instructions
   - Save the bot token

2. **Get your Chat ID:**
   - Message your bot
   - Visit: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
   - Find your chat ID in the response

3. **Set up Topic ID (optional):**
   - Create a group/supergroup with topics enabled
   - Send a message to your desired topic
   - Get the topic ID from the message thread and set `OPTIONAL_TOPIC_ID` in `.env`
   
### 3. Environment Configuration

Create the `.env` file with your Telegram credentials and preferences. Note that for security purposes, the .env file should NEVER be stored on GitHub - this repository already includes it in the gitignore file.

```bash
# Example .env file:
# TELEGRAM_BOT_TOKEN=1234567890:ABCdefGHIjklMNOpqrsTUVwxyz
# TELEGRAM_CHAT_ID=-1001234567890
# OPTIONAL_TOPIC_ID=2
```

### 5. Test the Setup

```bash
# Make script executable
chmod +x ssh-monitor.sh
# Test manually
sudo ./ssh-monitor.sh
```

### 6. Set up as Systemd Service (Recommended)

Create a systemd service for continuous monitoring:

```bash
sudo nano /etc/systemd/system/ssh-monitor.service
```

Replace `/path/to/ssh-monitor-directory` with your actual script path:

```ini
[Unit]
Description=SSH Connection Monitor
After=network.target sshd.service
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/home/username/folder
ExecStart=/home/username/folder/ssh-monitor.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
 
[Install]
WantedBy=multi-user.target
```

Enable and start the service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable ssh-monitor.service
sudo systemctl start ssh-monitor.service
```

### Service Management

```bash
# Start the service
sudo systemctl start ssh-monitor.service

# Stop the service
sudo systemctl stop ssh-monitor.service

# Restart the service
sudo systemctl restart ssh-monitor.service

# View logs
sudo journalctl -u ssh-monitor.service -f

# Check status
sudo systemctl status ssh-monitor.service
```

### Log Files

- **Main log:** `./logs/ssh-monitor.log` (in the same directory as the scripts)
- **System logs:** `sudo journalctl -u ssh-monitor.service`

## Version History
- **v1.0.3**: Initial release

## License

This project is open source. Feel free to modify and distribute according to your needs.