#!/usr/bin/env bash
# Installs the PX13 power tools. Run as your user; system parts use sudo.
set -euo pipefail
sudo() { command sudo ${SUDO_ASKPASS:+-A} "$@"; }
cd "$(dirname "$0")"

USER_BIN="${HOME}/.local/bin"
PLASMOID_DIR="${HOME}/.local/share/plasma/plasmoids/org.madhan.px13power"
PRESENCE_UI_DIR="${HOME}/.local/share/plasma/plasmoids/org.madhan.px13presence"
USER_UNITS="${HOME}/.config/systemd/user"

python3 -c 'import dbus' 2>/dev/null || { echo "python3-dbus is required: sudo apt install python3-dbus" >&2; exit 1; }

echo "==> System files"
sudo install -o root -g root -m 755 bin/px13 /usr/local/bin/px13
sudo install -o root -g root -m 755 bin/px13-envycontrol /usr/local/bin/px13-envycontrol
# Validate before installing: a broken sudoers file can lock sudo out.
visudo -cf system/sudoers-px13-power >/dev/null
sudo install -o root -g root -m 440 system/sudoers-px13-power /etc/sudoers.d/px13-power
sudo install -o root -g root -m 755 bin/px13-presence /usr/local/bin/px13-presence
sudo install -o root -g root -m 644 system/px13-watch.service system/px13-reapply.service system/px13-presence.service /etc/systemd/system/
sudo install -o root -g root -m 755 system/px13-sleep /usr/lib/systemd/system-sleep/px13
# The presence state is private: readable only by root and your group.
PRESENCE_DROPIN=/etc/systemd/system/px13-presence.service.d
sudo install -d -o root -g root -m 755 "${PRESENCE_DROPIN}"
printf '[Service]\n# Group that may read /run/px13/presence.json (written by install.sh).\nGroup=%s\n' "$(id -gn)" \
  | sudo tee "${PRESENCE_DROPIN}/reader-group.conf" >/dev/null
sudo chmod 644 "${PRESENCE_DROPIN}/reader-group.conf"
# px13-watch now tracks AC changes itself; remove the old udev trigger.
sudo rm -f /etc/udev/rules.d/90-px13-ac.rules
sudo systemctl daemon-reload
sudo udevadm control --reload
sudo systemctl reenable px13-watch.service
sudo systemctl restart px13-watch.service
# Presence is opt-in (px13 presence on); only restart it if already running.
sudo systemctl try-restart px13-presence.service

echo "==> User files"
install -d "${USER_BIN}" "${PLASMOID_DIR}"
install -m 755 bin/px13-panel-run bin/px13-panel-battery bin/px13-panel-status bin/px13-open-status bin/px13-cycle "${USER_BIN}/"
cp -r plasmoid/. "${PLASMOID_DIR}/"
install -m 755 bin/px13-presence-agent bin/px13-presence-ctl "${USER_BIN}/"
install -d "${USER_UNITS}" "${PRESENCE_UI_DIR}" "${HOME}/.config/px13" "${HOME}/.local/share/applications"
install -m 644 system/px13-presence-agent.service "${USER_UNITS}/"
[ -f "${HOME}/.config/px13/presence.conf" ] || install -m 644 system/presence.conf.default "${HOME}/.config/px13/presence.conf"
cp -r presence-ui/metadata.json presence-ui/contents "${PRESENCE_UI_DIR}/"
install -m 644 presence-ui/px13-presence.desktop "${HOME}/.local/share/applications/"
systemctl --user daemon-reload
systemctl --user try-restart px13-presence-agent.service

echo "==> Done. Restart plasmashell to load the widget changes:"
echo "    systemctl --user restart plasma-plasmashell"
