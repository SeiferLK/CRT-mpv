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

echo "[3/4] TV pictures (54)"
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
# More TVs, from the artists' own repositories (pinned commits): Soqueroeu's TV Backgrounds V2.0, and Duimon's
# Mega Bezel 'Potato' and Vintage TV pictures (complete pictures with the screen already cut out; CC BY-NC-ND 4.0).
soq=https://raw.githubusercontent.com/soqueroeu/Soqueroeu-TV-Backgrounds_V2.0/52bc4588d88c7bd319f922659d3ba74ed81ce959/img
duiP=https://raw.githubusercontent.com/Duimon/Duimon-Mega-Bezel-Potato/9b9b3d781c077bbce6ced712565e96155d1063cd/Graphics/_Potato
duiV=https://raw.githubusercontent.com/Duimon/Duimon-Vintage-TV/28478a2bcb21416c619dd2fa2d67d70d91c715dc/Graphics/_Potato
fetch "$soq/Atari_2600/Atari_2600.png" 436c59535627c9009259e2cc9e375c8548589412d439d0348552d6e0ba4c7ef4 config/overlays/Atari_2600.png
fetch "$duiV/9519/9519.png" 5c19a8aa56166d433edb86db93bc73faec87163ad6778ae62e9774897fabb880 config/overlays/Duimon_9519.png
fetch "$duiV/9519/9519_3DS.png" a09fa8977f44bdfe33249132176cc00c201a5b464b403b786d8342a7c8eeca92 config/overlays/Duimon_9519_3DS.png
fetch "$duiV/9519/9519_NDS.png" 304c23934f75247dfa06f8b44d90087faaedf638e625b56e03d21ef04fabc34c config/overlays/Duimon_9519_NDS.png
fetch "$duiV/Ambassador_26/Ambassador_26.png" c5a9f84153aaf11733781e45de26f87887064bf2afde9a245bf51bb04f8acb84 config/overlays/Duimon_Ambassador_26.png
fetch "$duiV/Ambassador_26/Ambassador_26_Scaled.png" 259f18d3e9afd7e0d326285c088f69e3d9eafd7d6bdbf7582c3e90c9c18422dc config/overlays/Duimon_Ambassador_26_XL.png
fetch "$duiV/GJR641PR/GJR641PR.png" 47acd2ade90953534790a9f250855841de79d6d4fe6b768e05b4e19d0ee1eea5 config/overlays/Duimon_GJR641PR.png
fetch "$duiV/TH20-B8/TH20-B8.png" 7c1032f54ad98f624fad5e06eabdb2db1cacacbc42b111fe7a03d4ed62ce8525 config/overlays/Duimon_TH20B8.png
fetch "$duiV/TH20-B8/TH20-B8_Alt.png" 8b5fa6c657f9e9622f150cb4a57a76050480dfb276e3a74d42b27c39bab5147b config/overlays/Duimon_TH20B8_Alt.png
fetch "$duiP/TV/TV7_16x9.png" 36744713d4b1a5236e8eb87400f863a27917f18a607ff7a2fb0fdaa8effe53d5 config/overlays/Duimon_TV7.png
fetch "$duiP/TV/TV7_Wood_16x9.png" 3a52ee1d8c62a6534019030280fad9149666ad4e90cfa044b35c81a2ec32b0a8 config/overlays/Duimon_TV7_Wood.png
fetch "$soq/_Generic/G03B.png" 52d41bed1f05effe548b199f0d4c1d1795489841bab60057f58ab4779d4fd6e0 config/overlays/Generic_CRT_Monitor_2.png
fetch "$soq/NEC_PCEngine/PCE.png" 4185af4d7edce7a2f228087e6b0ec90d5fe5b6b5486d76bf2ece79f07437d0e8 config/overlays/NEC_PCEngine.png
fetch "$soq/NEC_PCEngine-CD/PCECD.png" 1afa8e7c5d319a07791390675177c9bf16e8cc0ffa1124d5661048882a660cdd config/overlays/NEC_PCEngine_CD.png
fetch "$soq/NEC_PCEngine-CD/PCECD_v2.png" 1298f95ca5544cac58207f74cc5593f18208fe26d37aab9ea7f941ed870ea8b1 config/overlays/NEC_PCEngine_CD_v2.png
fetch "$soq/NEC_PCEngine-Duo/PCEDuo.png" 55798df9e0851bded1fed1e1ab0928049b667ca65443970a88cb44f907ef0e1b config/overlays/NEC_PCEngine_Duo.png
fetch "$soq/NEC_PCEngine/PCE_v2.png" 0d8c9bec8be4d83ef6a69ba8c963440e5806b80ca5f9afeb9f49372561d5f3bd config/overlays/NEC_PCEngine_v2.png
fetch "$soq/NEC_PCFX/PCFX.png" ee9a96eabd492a400f553d6e3e32a12930fc6b9707e3293798bb307f3726a416 config/overlays/NEC_PCFX.png
fetch "$soq/NEC_SuperGrafx/SuperGFX.png" 58b90eeb819d00978f0fe40af96a9d7e988821c330cf036a2c5700e192a9991d config/overlays/NEC_SuperGrafx.png
fetch "$soq/NEC_TurboDuo/TurboDuo.png" 5a252b48a8ea538d3bdbceb2570428c18c19c645d6fa565145e5a950d0d4e273 config/overlays/NEC_TurboDuo.png
fetch "$soq/NEC_TurboGrafx16/TG16.png" af1d286e716637c3f3e3e0b52bcd01384dc955aa2214b826528855e2705f7041 config/overlays/NEC_TurboGrafx16.png
fetch "$soq/NEC_TurboGrafx-CD/TGFX16CD.png" 87970257667f34f892c6295d0a802c1f636864bf419122a481bffd4f2a739743 config/overlays/NEC_TurboGrafx_CD.png
fetch "$soq/Nintendo_Famicom/Famicom_Black_Edition.png" d8f084c05f4763ee47e17a31e86f600a5268194c173393ecfac826b223117504 config/overlays/Nintendo_Famicom_Black.png
fetch "$soq/Nintendo_Famicom/Famicom_Disk_System.png" 027d007f3ebab0901cb8a4d93dc0adba19b41645a73f4647681114656aff8ce6 config/overlays/Nintendo_Famicom_Disk_System.png
fetch "$soq/Nintendo_Famicom/Famicom_Red_Edition.png" e439be3ba396ae98da0c0c7bdd3cd54295ac414c90bf09b830cbaf6511c44ec3 config/overlays/Nintendo_Famicom_Red.png
fetch "$soq/Nintendo_GameCube/GameCube.png" 523ee9e99ed56f88fe850f728dcd4d2a25e6b17b4f769314034c7166e5cbeffd config/overlays/Nintendo_GameCube.png
fetch "$soq/Nintendo_NES/NES_Black_Edition.png" 23fc86483b5ca74da163b1e35f798a7259fdbfe3958e47d6ae8b31e4373f40b5 config/overlays/Nintendo_NES_Black.png
fetch "$soq/Nintendo_SuperNintendo/SuperNES_V2.png" b4335065f98140c2f3faf0d6ee8ec8d8881fd26958a87aa9f04f20c5aa4ea249 config/overlays/Nintendo_SNES_v2.png
fetch "$soq/Nintendo_SuperNintendo/SuperNES_V3.png" 85bcf79694b73da2dc87d89341cd9c985f4270f1ef5d9131f85504604857654f config/overlays/Nintendo_SNES_v3.png
fetch "$soq/Nintendo_SuperFamicom/SuperFamicom.png" b61324925746dd408c2257dfc12ea703c0c24fde4e12bd4b3b0157babcc9ffd2 config/overlays/Nintendo_SuperFamicom.png
fetch "$soq/Nintendo_SuperFamicom/SuperFamicom_v2.png" 4038b23b9089a163da3a69421ef8de1161c9e1b9d2e0f2f460d33f6ceea05845 config/overlays/Nintendo_SuperFamicom_v2.png
fetch "$soq/Nintendo_SuperGameBoy/SuperGameBoy.png" dcd86c48324c6a3ead0bf3a9ed5d1c2a62bf7bbabd0a99c33a10d6167ce7f647 config/overlays/Nintendo_SuperGameBoy.png
fetch "$soq/Nintendo_Wii/Wii_4x3.png" 4021acdc0e896feae1f10fed0d403fb6ec70e4347d5b3df0de07416794479441 config/overlays/Nintendo_Wii.png
fetch "$soq/Nintendo_Wii/Wii_16x9.png" 82f7581bb04157232b6164c35c3ef8c29babe1ad38f69bbe8945ae84966f5c1b config/overlays/Nintendo_Wii_16x9.png
fetch "$soq/3DO/3DO.png" 0d624722e284f80dd015a36eaea7d8a8df04893df564aceb481a4d19927cca10 config/overlays/Panasonic_3DO.png
fetch "$soq/Sega_CD/Sega_CD.png" f143c31c42dfbf910a1818ee64e1c08fe83900ce50edfd2654c20980155936fd config/overlays/Sega_CD.png
fetch "$soq/Sega_MarkIII/MarkIII.png" 2187d592f303682aa47b36042d9f7c5659361b683f758fc8e86d79281a5eafc5 config/overlays/Sega_MarkIII.png
fetch "$soq/Sega_SG-1000/SG-1000.png" cbe76481dc853d364f983b6b9db9c3bda7e3b2b5e80a04004acec44c1deb9457 config/overlays/Sega_SG1000.png
fetch "$soq/Sega_Saturn/Sega_SaturnJP.png" a3da1e6f16ba32e1ba832542fa338d8c519c48e4fb98565d77cd3d5a81d3d3e2 config/overlays/Sega_Saturn.png

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
