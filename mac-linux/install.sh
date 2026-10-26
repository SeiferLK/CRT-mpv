#!/usr/bin/env bash
# CRT-mpv installer for macOS and Linux (no root needed; mpv itself comes from your package manager).
#   mac-linux/install.sh               download the dependencies into the CRT-mpv folder
#   mac-linux/install.sh --open-with   also add "CRT-mpv" to your file manager's Open With menu
# Every download is pinned to an exact version and verified with SHA-256.
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"

sha_ok() {   # file expected-hash
    if command -v sha256sum >/dev/null 2>&1; then echo "$2  $1" | sha256sum -c - >/dev/null 2>&1
    else echo "$2  $1" | shasum -a 256 -c - >/dev/null 2>&1; fi
}
fetch() {    # url sha256 dest
    local url=$1 sha=$2 dest=$3
    if [ -f "$dest" ] && sha_ok "$dest" "$sha"; then return; fi
    mkdir -p "$(dirname "$dest")"
    echo "  downloading $(basename "$dest")"
    curl -fsSL "$url" -o "$dest"
    if ! sha_ok "$dest" "$sha"; then rm -f "$dest"; echo "Checksum mismatch for $url - refusing to use it." >&2; exit 1; fi
}

echo "[1/4] mpv"
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/snap/bin:/var/lib/flatpak/exports/bin"
if ! command -v mpv >/dev/null 2>&1; then
    echo "  mpv is not installed. Install it, then re-run this script:"
    case "$(uname -s)" in
        Darwin) echo "    brew install mpv" ;;
        *)      echo "    Debian/Ubuntu: sudo apt install mpv     Fedora: sudo dnf install mpv     Arch: sudo pacman -S mpv" ;;
    esac
    exit 1
fi
echo "  found $(command -v mpv)  ($(mpv --version | head -1))"

echo "[2/4] hover controls + folder playlist"
fetch https://github.com/Samillion/ModernZ/releases/download/v0.3.3/modernz.lua \
      c36aef0152d3fdb0c769cefe7074648b457ed50ea4ddcc402b778bec23ca32c8 .cache/modernz.lua
# Two-string patch of the verified file: the bar's "i" button becomes the CRT remote button.
for needle in 'ne.content = icons.info' 'ne.tooltipF = locale.stats_info'; do
    grep -qF "$needle" .cache/modernz.lua || { echo "ModernZ patch failed: '$needle' not found." >&2; exit 1; }
done
mkdir -p config/scripts
sed -e 's/ne\.content = icons\.info/ne.content = icons.menu/' \
    -e 's/ne\.tooltipF = locale\.stats_info/ne.tooltipF = "CRT remote"/' .cache/modernz.lua > config/scripts/modernz.lua
grep -qF 'local function osc_init()' .cache/modernz.lua || { echo 'ModernZ seek hook: osc_init not found.' >&2; exit 1; }
cat >> config/scripts/modernz.lua <<'LUA'

local crt_seek = dofile(mp.command_native({"expand-path", "~~/script-modules/crt_seek.lua"}))
local upstream_osc_init = osc_init
osc_init = function()
    upstream_osc_init()
    crt_seek.attach(state.seekbar_element, get_slider_value, request_tick, state, user_opts)
end
LUA
fetch https://github.com/Samillion/ModernZ/releases/download/v0.3.3/modernz-icons.ttf \
      5033b84d569502538968c6f23b0859bda790eed85c10e419b0759537ec60a016 config/fonts/modernz-icons.ttf
fetch https://raw.githubusercontent.com/mpv-player/mpv/867990d949e9ad99406e0f26e5528e95046b30a7/TOOLS/lua/autoload.lua \
      5d2f5491edf1c9857932a4fd816413651d110345e7e57b5ad915f74fb4d516ca config/scripts/autoload.lua

echo "[3/4] TV pictures"
ovl=https://raw.githubusercontent.com/itsdunintime104/VLC-CRT-emulator-plugin/603a77752cd78d091389072e6ad61f86086cd31f/overlays
fetch "$ovl/G02_Generic_TV.png" 9402db8d7fd2824496885244f7e1c163db168a40da3ff2821d110764fb85150d config/overlays/G02_Generic_TV.png
fetch "$ovl/Generic_CRT_Monitor.png" 42d6b67dc85229e0f9f7f468acad49a13fd156d599ec7b21cabdb193b7c7633d config/overlays/Generic_CRT_Monitor.png
fetch "$ovl/Generic_Flat_TV.png" 3265ce23975385d0e0f5e6381fb47b2112110b1019032bf74821e86dd65e0758 config/overlays/Generic_Flat_TV.png
fetch "$ovl/Generic_Gray_TV.png" c4f0a100084fde578af12be600cf0d8e5d6e63dc6b91b615aeedfa380f1d8e33 config/overlays/Generic_Gray_TV.png
fetch "$ovl/Generic_White_TV.png" c81a41f23a778f4cb9b8f22ed4a0e9e64c23a1db41143b4ec220984cfc92d340 config/overlays/Generic_White_TV.png
fetch "$ovl/Nintendo_Famicom.png" e12af654b3ca7c7d22720dcfa5c6b50293fb85dd6d3d9573de74347598a9f325 config/overlays/Nintendo_Famicom.png
fetch "$ovl/Nintendo_N64.png" 997bd3923eb6bc9c1c0d11fbe98daa1f7a901b40fb204d6bfd6710caaee948de config/overlays/Nintendo_N64.png
fetch "$ovl/Nintendo_NES.png" 4b806f0a9ff18ba59d6261dc810472d42025d60991b613e4d3de7f552ffab89b config/overlays/Nintendo_NES.png
fetch "$ovl/Nintendo_SNES.png" 898c5273c0a70bf10207de66c6dd42d2400d51ce2cd85fb69028dba3c6631006 config/overlays/Nintendo_SNES.png
fetch "$ovl/SNK_NeoGeo.png" 6a72a6e7b7708c9fb43869c06e47ad0390efeb9937697fd39dd9d19eab0e0139 config/overlays/SNK_NeoGeo.png
fetch "$ovl/Sega_Dreamcast.png" e5888e01245081a8c64014341c05845276efb1253b4bb51b64b241f0769f98c4 config/overlays/Sega_Dreamcast.png
fetch "$ovl/Sega_Genesis.png" 77d150ca4b6360c89f8ccf1863b6b28d5c479774a5f912e49838c369b291e60e config/overlays/Sega_Genesis.png
fetch "$ovl/Sega_MasterSystem.png" c91d779cffce543ffbc157d67f2d2c436247bfa0fcbe9135dc265cdd5de40e0f config/overlays/Sega_MasterSystem.png
fetch "$ovl/Sony_PS2.png" 521956983f30bded9566ffec3deeb7242ce20f1fcfd52b777b81598c60f0421e config/overlays/Sony_PS2.png
fetch "$ovl/Sony_PlayStation.png" febbba2594cf1732709188ebc7d932be574358a80f441336d5e75e6d04532ee4 config/overlays/Sony_PlayStation.png

chmod +x mac-linux/crt-mpv
echo "[4/4] done"

if [ "${1:-}" = "--open-with" ]; then
    case "$(uname -s)" in
    Darwin)
        app="$HOME/Applications/CRT-mpv.app"
        mkdir -p "$HOME/Applications"; rm -rf "$app"
        osacompile -o "$app" -e "on open theFiles
    repeat with f in theFiles
        do shell script \"nohup \" & quoted form of \"$root/mac-linux/crt-mpv\" & \" \" & quoted form of POSIX path of f & \" >/dev/null 2>&1 &\"
    end repeat
end open
on run
    do shell script \"nohup \" & quoted form of \"$root/mac-linux/crt-mpv\" & \" >/dev/null 2>&1 &\"
end run"
        [ -f "$root/assets/crt-mpv.icns" ] && cp "$root/assets/crt-mpv.icns" "$app/Contents/Resources/applet.icns" && touch "$app"
        echo "Created $app - right-click a video > Open With > CRT-mpv."
        ;;
    *)
        d="$HOME/.local/share/applications"; mkdir -p "$d"
        cat > "$d/crt-mpv.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=CRT-mpv
Comment=Play video with a CRT TV look
Exec="$root/mac-linux/crt-mpv" %F
Icon=$root/assets/icon.png
Terminal=false
Categories=AudioVideo;Video;Player;
MimeType=video/x-matroska;video/mp4;video/x-msvideo;video/quicktime;video/webm;video/mpeg;video/x-flv;video/x-ms-wmv;video/ogg;video/3gpp;video/mp2t;
DESK
        command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$d" || true
        echo "Added $d/crt-mpv.desktop - right-click a video > Open With > CRT-mpv."
        ;;
    esac
fi
echo
echo "Installed. Try:  $root/mac-linux/crt-mpv /path/to/video.mkv"
echo "To uninstall:    $root/mac-linux/uninstall.sh --remove-folder"
