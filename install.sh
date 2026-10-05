#!/usr/bin/env bash
# Installs the PX13 power tools. Run as your user; system parts use sudo.
set -euo pipefail
sudo() { command sudo ${SUDO_ASKPASS:+-A} "$@"; }
cd "$(dirname "$0")"

USER_BIN="${HOME}/.local/bin"
PLASMOID_DIR="${HOME}/.local/share/plasma/plasmoids/org.madhan.px13power"

echo "==> System files"
sudo install -o root -g root -m 755 bin/px13 /usr/local/bin/px13
sudo install -o root -g root -m 755 bin/px13-envycontrol /usr/local/bin/px13-envycontrol
# Validate before installing: a broken sudoers file can lock sudo out.
visudo -cf system/sudoers-px13-power >/dev/null
sudo install -o root -g root -m 440 system/sudoers-px13-power /etc/sudoers.d/px13-power
sudo install -o root -g root -m 644 system/px13-watch.service system/px13-reapply.service /etc/systemd/system/
sudo install -o root -g root -m 755 system/px13-sleep /usr/lib/systemd/system-sleep/px13
# px13-watch now tracks AC changes itself; remove the old udev trigger.
sudo rm -f /etc/udev/rules.d/90-px13-ac.rules
sudo systemctl daemon-reload
sudo udevadm control --reload
sudo systemctl reenable px13-watch.service
sudo systemctl restart px13-watch.service

echo "==> User files"
install -d "${USER_BIN}" "${PLASMOID_DIR}"
install -m 755 bin/px13-panel-run bin/px13-panel-battery bin/px13-panel-status bin/px13-open-status bin/px13-cycle "${USER_BIN}/"
cp -r plasmoid/. "${PLASMOID_DIR}/"

echo "==> Done. Restart plasmashell to load the widget changes:"
echo "    systemctl --user restart plasma-plasmashell"
