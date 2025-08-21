#!/bin/bash
# =============================
# Home Assistant на Synology с собственным IP (macvlan + bridge + автозагрузка + обновление)
# =============================

# ===== Настройки =====
LAN_SUBNET="192.168.1.0/24"      # Подсеть LAN
LAN_GATEWAY="192.168.1.1"        # Шлюз LAN
HASS_IP="192.168.1.156"          # IP Home Assistant
HOST_SHIM_IP="192.168.1.249"     # IP виртуального интерфейса на Synology
HASS_CONFIG="/volume1/docker/homeassistant"  # Папка конфигов HA
HASS_IMAGE="ghcr.io/home-assistant/home-assistant:stable"
HASS_NAME="homeassistant"
AUTOBOOT_SCRIPT="/usr/local/bin/hass_macvlan.sh"
SERVICE_FILE="/etc/systemd/system/hass_macvlan.service"

# ===== Определяем основной интерфейс =====
LAN_INTERFACE=$(ip route | grep "^default" | awk '{print $5}' | head -n1)
if [ -z "$LAN_INTERFACE" ]; then
  echo "❌ Не удалось определить сетевой интерфейс. Проверь команду 'ip route'."
  exit 1
fi
echo "ℹ️ Обнаружен основной интерфейс: ${LAN_INTERFACE}"

# ===== Функция настройки shim-интерфейса =====
setup_shim() {
  echo "[Shim] Настраиваю виртуальный интерфейс hass-shim..."
  ip link add hass-shim link ${LAN_INTERFACE} type macvlan mode bridge 2>/dev/null || true
  ip addr add ${HOST_SHIM_IP}/32 dev hass-shim 2>/dev/null || true
  ip link set hass-shim up
  ip route add ${HASS_IP}/32 dev hass-shim 2>/dev/null || true
}

# ===== Проверка: контейнер уже существует? =====
if docker ps -a --format '{{.Names}}' | grep -qw ${HASS_NAME}; then
  echo "🔄 Обновление Home Assistant..."

  echo "[1/3] Загружаю новый образ ${HASS_IMAGE}..."
  docker pull ${HASS_IMAGE}

  echo "[2/3] Останавливаю старый контейнер..."
  docker stop ${HASS_NAME} || true
  docker rm ${HASS_NAME} || true


  if ! docker network inspect hass_macvlan >/dev/null 2>&1; then
    echo "[0/3] Сеть hass_macvlan не найдена, создаю..."
    docker network create -d macvlan \
      --subnet=${LAN_SUBNET} \
      --gateway=${LAN_GATEWAY} \
      -o parent=${LAN_INTERFACE} \
      hass_macvlan
  fi

  echo "[3/3] Запускаю обновлённый контейнер..."
  docker run -d \
    --name=${HASS_NAME} \
    --network=hass_macvlan \
    --ip=${HASS_IP} \
    --restart=unless-stopped \
    -v ${HASS_CONFIG}:/config \
    --privileged \
    ${HASS_IMAGE}

  echo "✅ Обновление завершено! Home Assistant снова доступен: http://${HASS_IP}:8123"

else
  echo "🆕 Первый запуск: создаю сеть, shim и контейнер..."

  echo "[1/6] Создаю macvlan-сеть..."
  docker network inspect hass_macvlan >/dev/null 2>&1 || \
  docker network create -d macvlan \
    --subnet=${LAN_SUBNET} \
    --gateway=${LAN_GATEWAY} \
    -o parent=${LAN_INTERFACE} \
    hass_macvlan

  echo "[2/6] Настраиваю hass-shim..."
  setup_shim

  echo "[3/6] Создаю скрипт ${AUTOBOOT_SCRIPT}..."
  cat <<EOF | sudo tee ${AUTOBOOT_SCRIPT} >/dev/null
#!/bin/bash
case "\$1" in
  start)
    ip link add hass-shim link ${LAN_INTERFACE} type macvlan mode bridge 2>/dev/null || true
    ip addr add ${HOST_SHIM_IP}/32 dev hass-shim 2>/dev/null || true
    ip link set hass-shim up
    ip route add ${HASS_IP}/32 dev hass-shim 2>/dev/null || true
    ;;
  stop)
    ip link show hass-shim >/dev/null 2>&1 && ip link del hass-shim || true
    ;;
  restart|reload)
    \$0 stop
    \$0 start
    ;;
esac
EOF
  sudo chmod +x ${AUTOBOOT_SCRIPT}
  sudo chown root:root ${AUTOBOOT_SCRIPT}

  echo "[4/6] Создаю systemd-сервис ${SERVICE_FILE}..."
  cat <<EOF | sudo tee ${SERVICE_FILE} >/dev/null
[Unit]
Description=Home Assistant macvlan shim
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${AUTOBOOT_SCRIPT} start
ExecStop=${AUTOBOOT_SCRIPT} stop
ExecReload=${AUTOBOOT_SCRIPT} restart
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable hass_macvlan.service
  sudo systemctl start hass_macvlan.service

  echo "[5/6] Запускаю Home Assistant..."
  docker run -d \
    --name=${HASS_NAME} \
    --network=hass_macvlan \
    --ip=${HASS_IP} \
    --restart=unless-stopped \
    -v ${HASS_CONFIG}:/config \
    --privileged \
    ${HASS_IMAGE}

  echo "[6/6] ✅ Готово!"
  if ip link show hass-shim >/dev/null 2>&1; then
    echo "✅ Интерфейс hass-shim создан"
  else
    echo "❌ Интерфейс hass-shim отсутствует"
  fi

  if docker ps --format '{{.Names}}' | grep -qw ${HASS_NAME}; then
    echo "✅ Контейнер ${HASS_NAME} запущен"
    echo "Home Assistant доступен по адресу: http://${HASS_IP}:8123"
  else
    echo "❌ Контейнер ${HASS_NAME} не запущен"
  fi

  echo "Скрипт shim сохранён в ${AUTOBOOT_SCRIPT}, сервис systemd создан: hass_macvlan.service"
fi
