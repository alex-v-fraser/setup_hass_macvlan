# 🏠 Home Assistant on Synology with Its Own IP (macvlan)

This script automates deploying **Home Assistant** on Synology NAS with Docker using a dedicated LAN IP address via `macvlan`.  
It also sets up a **shim interface** for communication with the host and a **systemd service** for automatic startup.

---

## ✨ Features
- Runs Home Assistant in **Docker** with a static LAN IP  
- Creates and manages a **macvlan** network (`hass_macvlan`)  
- Sets up a **shim interface** (`hass-shim`) so Synology host can reach HA  
- Creates an **autoboot script** (`hass_macvlan.sh`)  
- Registers a **systemd service** (`hass_macvlan.service`) for persistence  
- Handles **first installation** and **updates** with the same script  

---

## ⚡ Quickstart

### 1. Download the script
```bash
curl -o /usr/local/bin/setup_hass_macvlan.sh \
  https://raw.githubusercontent.com/alex-v-fraser/setup_hass_macvlan/main/setup_hass_macvlan.sh
```

Or with `wget`:
```bash
wget -O /usr/local/bin/setup_hass_macvlan.sh \
  https://raw.githubusercontent.com/alex-v-fraser/setup_hass_macvlan/main/setup_hass_macvlan.sh
```

---

### 2. Make it executable
```bash
sudo chmod +x /usr/local/bin/setup_hass_macvlan.sh
```

---

### 3. Run the installer
```bash
sudo /usr/local/bin/setup_hass_macvlan.sh
```

This will:  
- Create the `hass_macvlan` Docker network  
- Set up the `hass-shim` interface  
- Deploy Home Assistant with its own LAN IP  
- Register the systemd service for automatic startup  

---

### 4. Verify installation
- Check systemd service:  
  ```bash
  systemctl status hass_macvlan.service
  ```
- Check running container:  
  ```bash
  docker ps --format '{{.Names}}'
  ```
- Open Home Assistant in your browser:  
  ```
  http://192.168.1.156:8123
  ```

---

### 5. Update Home Assistant
Re-run the script anytime to pull the latest image and restart the container:
```bash
sudo /usr/local/bin/setup_hass_macvlan.sh
```
