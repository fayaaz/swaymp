# Remaining plan

## 1. Fix waybar formatting
- Replace `waybar` module formats with plain-text labels for now:
  - `custom/keyboard` -> `K`
  - `custom/cheatsheet` -> `C`
  - `custom/notifications` -> `N`
  - `custom/euphonica` -> `E`
  - `custom/power` -> `P`
- Keep clickable actions:
  - notifications button opens/toggles `swaync`
  - Euphonica button launches/focuses Euphonica
  - power button opens `wlogout`
- Update `restore/home/pi/.config/waybar/style.css` so all right-side buttons have consistent:
  - height
  - padding
  - font size
  - background colors
  - spacing/order
- Copy waybar config and CSS to the Pi.
- Reload waybar:
  - `pkill -USR1 -x waybar`
- Apply sway config:
  - `swaymsg reload`
- Take a screenshot and verify top bar is visually stable.

## 2. Verify notification behavior end-to-end
- Confirm `swaync` is the active notification daemon.
- Confirm only Euphonica album-art notification is visible.
- Confirm `mpd-notify` text-only notifications are suppressed.
- Confirm the waybar notification button toggles the `swaync` side control-center popout.
- Test with:
  - `swaync-client -t`
  - `swaync-client -C`
  - `swaync-client -cp`

## 3. Verify default foot font behavior
- Ensure default terminal `foot` uses the larger font from:
  - `restore/home/pi/.config/foot/foot.ini`
- Avoid per-window font overrides for normal terminal use.
- Keep only the necessary explicit font override if a specific overlay still needs a smaller size, but the default terminal font should remain the user-configured default.
- Test by opening a normal `foot` window and taking a screenshot.
- Verify the cheatsheet overlay and `wiremix --peaks` overlay still remain readable.

## 4. Finish `wlogout` layout
- Add/keep button centering in:
  - `restore/home/pi/.config/wlogout/style.css`
- Restore the live `wlogout` layout from the test-safe action:
  - `touch /tmp/wlbtn`
  back to real actions, in this order:
  1. reboot
  2. logout
  3. shutdown
- Verify one harmless action first, ideally a button that opens a command or writes a marker, before any real power action.
- Confirm button centering looks right before running `wlogout` again.
- Keep the power menu usable from waybar button `P`.

## 5. Verify on the Pi
- Apply changes with `setup-pi.sh` or copy live config files directly.
- Reload services/configs:
  - `swaymsg reload`
  - `pkill -USR1 -x waybar`
- Check services:
  - `systemctl --user status mpd mympd syncthing snapclient pipewire pipewire-pulse wireplumber`
- Check playback:
  - `mpc toggle`
  - `mpc play`
- If waybar restart becomes problematic, reboot the Pi and wait for SSH to return before checking again.

## 6. Capture final visual check
After waybar, foot, notifications, and `wlogout` are stable, verify with screenshots:
- top waybar formatting
- `foot` terminal font size
- `swaync` side popout/control center
- `wlogout` centered button layout
- `wiremix --peaks` overlay readability
