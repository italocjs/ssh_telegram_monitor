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

### 2. Setup Files

The scripts use relative paths, so they'll work from wherever you place them:

```bash
# Create logs directory
mkdir -p logs

# Copy environment template
cp .env.template .env

# Make script executable
chmod +x ssh-monitor.sh

# Secure the environment file
chmod 600 .env
```

### 3. Configure Telegram Notifications

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

### 4. Environment Configuration

Configure your Telegram credentials:

```bash
# Edit the environment file
nano .env
```

Edit the `.env` file with your Telegram credentials and preferences. Note that for security purposes, the .env file should NEVER be stored on GitHub - this repository already includes it in the gitignore file.

### 5. Test the Setup

```bash
# Test manually (requires root)
sudo ./ssh-monitor.sh
```

### 6. Set up as Systemd Service (Recommended)

Create a systemd service for continuous monitoring:

```bash
sudo nano /etc/systemd/system/ssh-monitor.service
```

Replace `/path/to/ssh-monitor-directory` with your actual installation path:

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

## Telegram Notification Topics

The script supports organized notifications using Telegram topics:

- **server_info**: SSH login/logout events, system information
- **uptime**: Uptime monitoring (if integrated)
- **backup**: Backup and timeshift operations
- **jellyfin**: Media server notifications
- **general**: General notifications

## Security Considerations

1. **Root Privileges**: The script requires root access to read SSH logs
2. **Environment File**: Keep `.env` file secure with `chmod 600`
3. **Rate Limiting**: Configured to prevent notification spam while ensuring security alerts
4. **Root Login Alerts**: Always notified regardless of rate limiting
5. **Failed Attempts**: No rate limiting on failed attempts to catch brute force attacks

## Troubleshooting

### Common Issues

1. **Permission Denied:**
   ```bash
   sudo chmod +x ssh-monitor.sh
   sudo chown root:root ssh-monitor.sh
   ```

2. **Telegram Not Working:**
   - Verify bot token and chat ID in `.env`
   - Test with: `curl "https://api.telegram.org/bot<TOKEN>/getMe"`

3. **No SSH Events Detected:**
   - Check if `journalctl` is available: `sudo journalctl -u ssh.service --no-pager -n 1`
   - Verify `/var/log/auth.log` exists: `ls -la /var/log/auth.log`

4. **Service Won't Start:**
   ```bash
   sudo systemctl status ssh-monitor.service
   sudo journalctl -u ssh-monitor.service
   ```

### Log Analysis

```bash
# View recent SSH monitor logs (adjust path to your installation)
tail -f /path/to/ssh-monitor-directory/logs/ssh-monitor.log

# View service logs
sudo journalctl -u ssh-monitor.service -f

# Check for errors
sudo journalctl -u ssh-monitor.service | grep ERROR
```

## Version History

- **v1.0.2**: Current version with integrated Telegram functionality and simplified configuration
- **v1.0.1**: Enhanced logging and geolocation
- **v1.0.0**: Initial release

## License

This project is open source. Feel free to modify and distribute according to your needs.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review the logs for error messages
3. Ensure all prerequisites are met
4. Test individual components (Telegram notifications, log access)
