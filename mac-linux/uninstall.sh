#!/usr/bin/env bash
# CRT-mpv uninstaller for macOS and Linux (no root needed). Undoes install.sh:
#   mac-linux/uninstall.sh                  remove the Open With entry, everything the installer downloaded,
#                                           and the player's saved state (settings, resume positions, shader cache, logs)
#   mac-linux/uninstall.sh --remove-folder  also delete the whole CRT-mpv folder
# Without --remove-folder the folder is left as a fresh copy: run mac-linux/install.sh again to reinstall.
# TV pictures you added yourself to config/overlays are kept (unless --remove-folder).
# mpv itself came from your package manager and is left alone.
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"

echo "[1/3] Open With entry"
case "$(uname -s)" in
Darwin)
    rm -rf "$HOME/Applications/CRT-mpv.app"
    ;;
*)
    d="$HOME/.local/share/applications"
    rm -f "$d/crt-mpv.desktop"
    # drop CRT-mpv from any default-app choices made in the file manager
    for m in "$HOME/.config/mimeapps.list" "$d/mimeapps.list"; do
        [ -f "$m" ] && sed -i -e 's/crt-mpv\.desktop;\{0,1\}//g' -e '/^[^[#][^=]*=$/d' "$m"
    done
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$d" || true
    ;;
esac

if [ "${1:-}" = "--remove-folder" ]; then
    echo "[2/3] deleting $root"
    cd ..
    rm -rf "$root"
    echo "[3/3] done"
    echo
    echo "Uninstalled. CRT-mpv is gone from this computer (mpv itself is still installed)."
    exit 0
fi

echo "[2/3] downloaded files"
rm -rf .cache config/scripts/modernz.lua config/scripts/autoload.lua config/fonts/modernz-icons.ttf config/yt-dlp config/deno
rmdir config/fonts 2>/dev/null || true      # created by the installer; kept if you put fonts of your own there
for tv in G02_Generic_TV Generic_CRT_Monitor Generic_Flat_TV Generic_Gray_TV Generic_White_TV \
          Nintendo_Famicom Nintendo_N64 Nintendo_NES Nintendo_SNES SNK_NeoGeo Sega_Dreamcast \
          Sega_Genesis Sega_MasterSystem Sony_PS2 Sony_PlayStation \
          Atari_2600 Duimon_9519 Duimon_9519_3DS Duimon_9519_NDS Duimon_Ambassador_26 Duimon_Ambassador_26_XL \
          Duimon_GJR641PR Duimon_TH20B8 Duimon_TH20B8_Alt Duimon_TV7 Duimon_TV7_Wood Generic_CRT_Monitor_2 \
          NEC_PCEngine NEC_PCEngine_CD NEC_PCEngine_CD_v2 NEC_PCEngine_Duo NEC_PCEngine_v2 NEC_PCFX \
          NEC_SuperGrafx NEC_TurboDuo NEC_TurboGrafx16 NEC_TurboGrafx_CD Nintendo_Famicom_Black \
          Nintendo_Famicom_Disk_System Nintendo_Famicom_Red Nintendo_GameCube Nintendo_NES_Black \
          Nintendo_SNES_v2 Nintendo_SNES_v3 Nintendo_SuperFamicom Nintendo_SuperFamicom_v2 \
          Nintendo_SuperGameBoy Nintendo_Wii Nintendo_Wii_16x9 Panasonic_3DO Sega_CD Sega_MarkIII Sega_SG1000 \
          Sega_Saturn; do
    rm -f "config/overlays/$tv.png"
done

echo "[3/3] saved settings, resume positions, shader cache and logs"
rm -rf config/settings.json config/open-locations.json config/update.json config/watch_later config/cache config/*.log ./*.log backup .update-manifest

echo
echo "Uninstalled. Delete this folder to remove CRT-mpv completely, or run mac-linux/install.sh to reinstall."
