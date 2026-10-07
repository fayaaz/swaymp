#!/bin/bash
# HyperPixel4 panel setup for a fresh Raspberry Pi OS install.
# Run ON THE Pi as the target non-root user BEFORE setup-pi.sh: it edits /boot/firmware/config.txt
# so the 720x720 DPI panel is the active display (sway output "DPI-1").
# Idempotent: re-running is safe. A reboot is required before the panel comes up.
set -eu

# Square 720x720 panel (this build). Use OVERLAY=vc4-kms-dpi-hyperpixel4 for the
# rectangular HyperPixel4. OVERLAY_PARAMS accepts the overlay's own params, e.g.
# OVERLAY_PARAMS="rotate=90" or "touchscreen-swapped-x-y=1" or "disable-touch=1".
OVERLAY=${OVERLAY:-vc4-kms-dpi-hyperpixel4sq}
OVERLAY_PARAMS=${OVERLAY_PARAMS:-}
CONFIG=/boot/firmware/config.txt
OVERLAYS_DIR=/boot/firmware/overlays
MARKER="# --- hackpi: HyperPixel4 (KMS DPI overlay) ---"

# --- sanity: only touch boot firmware on a real Pi ---
compatible=""
if [ -r /proc/device-tree/compatible ]; then
    compatible=$(tr '\0' ' ' < /proc/device-tree/compatible)
fi
case "$compatible" in
    *raspberrypi*) ;;
    *)
        echo "not a Raspberry Pi (device-tree compatible: '${compatible:-unknown}') - refusing to edit $CONFIG" >&2
        exit 1
        ;;
esac

# --- sanity: the panel needs the rp1 KMS DPI overlays (recent kernel + firmware) ---
if [ ! -e "$OVERLAYS_DIR/$OVERLAY.dtbo" ]; then
    echo "missing $OVERLAYS_DIR/$OVERLAY.dtbo" >&2
    echo "the HyperPixel4 needs the KMS DPI overlays (Raspberry Pi OS trixie, kernel >= 6.6)." >&2
    echo "update first: sudo apt-get update && sudo apt-get full-upgrade && sudo reboot" >&2
    exit 1
fi

# --- idempotent: already configured? ---
if grep -q "dtoverlay=$OVERLAY" "$CONFIG"; then
    echo "already configured: dtoverlay=$OVERLAY present in $CONFIG"
    echo "edit $CONFIG by hand for overlay params (rotate/touch); reboot to apply."
    exit 0
fi

# --- backup once ---
if [ ! -e "$CONFIG.hackpi.bak" ]; then
    sudo cp -a "$CONFIG" "$CONFIG.hackpi.bak"
    echo "backed up $CONFIG -> $CONFIG.hackpi.bak"
fi

# --- append the panel block (vc4-kms-v3d is required by the overlay) ---
block="$MARKER
[all]"
if ! grep -qE '^[[:space:]]*dtoverlay=vc4-kms-v3d' "$CONFIG"; then
    block="$block
dtoverlay=vc4-kms-v3d"
fi
block="$block
dtoverlay=$OVERLAY${OVERLAY_PARAMS:+,$OVERLAY_PARAMS}"

printf '\n%s\n' "$block" | sudo tee -a "$CONFIG" >/dev/null
echo "added to $CONFIG:"
printf '%s\n' "$block"

echo
echo "reboot now (sudo reboot), then verify the panel is the display:"
echo "  swaymsg -t get_outputs   # expect DPI-1 at 720x720"
echo "then run setup-pi.sh."
