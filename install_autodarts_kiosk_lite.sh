#!/bin/bash
set -e

DEFAULT_URL="https://play.autodarts.io/boards/3cc49fd3-d7e9-480b-898e-0338f7df6f71/follow"

# Script darf NICHT als root laufen
if [ "$EUID" -eq 0 ]; then
  echo "Bitte nicht als root ausführen. Starte es als normaler Benutzer."
  exit 1
fi

USER_HOME="$HOME"
URL_FILE="$USER_HOME/.autodarts-url"

echo "=== Autodarts Kiosk Installer (Lite) ==="
echo "Home: $USER_HOME"

echo "=== URL speichern ==="
echo "$DEFAULT_URL" > "$URL_FILE"

echo "=== System aktualisieren ==="
sudo apt update
sudo apt upgrade -y

echo "=== X11 + Openbox installieren ==="
sudo apt install --no-install-recommends -y xserver-xorg x11-xserver-utils xinit openbox

echo "=== Chromium + Tools installieren ==="
sudo apt install -y chromium xdotool unclutter curl xbindkeys

echo "=== kiosk.sh erstellen ==="
cat << 'EOF' > "$USER_HOME/kiosk.sh"
#!/bin/bash

CONFIG="$HOME/.autodarts-url"
URL=$(cat "$CONFIG")

sleep 5

while true; do
  chromium \
    --kiosk "$URL" \
    --start-fullscreen \
    --disable-infobars \
    --noerrdialogs \
    --disable-session-crashed-bubble \
    --enable-low-end-device-mode \
    --disable-pinch \
    --overscroll-history-navigation=0 \
    --password-store=basic \
    --use-gl=angle \
    --use-angle=egl \
    --high-dpi-support=1 \
    --force-device-scale-factor=2

  echo "Chromium wurde beendet – Neustart in 5 Sekunden..."
  sleep 5
done
EOF
chmod +x "$USER_HOME/kiosk.sh"

echo "=== Watchdog erstellen ==="
cat << 'EOF' > "$USER_HOME/autodarts-watchdog.sh"
#!/bin/bash

CONFIG="$HOME/.autodarts-url"
URL=$(cat "$CONFIG")
export DISPLAY=:0

while true; do
  if ! curl -sSf --max-time 5 "$URL" > /dev/null; then
    xdotool search --onlyvisible --class "Chromium" key F5
  fi
  sleep 30
done
EOF
chmod +x "$USER_HOME/autodarts-watchdog.sh"

echo "=== Openbox Autostart konfigurieren ==="
mkdir -p "$USER_HOME/.config/openbox"

cat << 'EOF' > "$USER_HOME/.config/openbox/autostart"
xset s off
xset -dpms
xset s noblank
unclutter &
xbindkeys &
$HOME/kiosk.sh &
$HOME/autodarts-watchdog.sh &
EOF

echo "=== .xinitrc erstellen ==="
cat << 'EOF' > "$USER_HOME/.xinitrc"
exec openbox-session
EOF
chmod +x "$USER_HOME/.xinitrc"

echo "=== Hotkey Strg+Alt+Q einrichten ==="
cat << 'EOF' > "$USER_HOME/stop-autodarts.sh"
#!/bin/bash
pkill -f kiosk.sh
pkill -f autodarts-watchdog.sh
pkill -f chromium
EOF
chmod +x "$USER_HOME/stop-autodarts.sh"

cat << EOF > "$USER_HOME/.xbindkeysrc"
"bash $USER_HOME/stop-autodarts.sh"
  Control+Alt + q
EOF

echo "=== .bash_profile anpassen (Auto-GUI Start) ==="
if ! grep -q "startx" "$USER_HOME/.bash_profile" 2>/dev/null; then
cat << 'EOF' >> "$USER_HOME/.bash_profile"

if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
  startx -- -nocursor
fi
EOF
fi

echo "=== Installation abgeschlossen! ==="
echo "Bitte führe jetzt aus:"
echo "sudo raspi-config → Boot / Auto Login → Console Autologin"
echo "Dann: sudo reboot"