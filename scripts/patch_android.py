from pathlib import Path

# flutter_v2ray_client already contributes the VPN/foreground-service
# permissions through its own AndroidManifest.xml. Do not duplicate them here;
# in particular, FOREGROUND_SERVICE_SPECIAL_USE carries a minSdkVersion=34 in
# the plugin manifest, and re-declaring it without that attribute can create a
# manifest-merger conflict.

strings = Path('android/app/src/main/res/values/strings.xml')

if strings.exists():
    text = strings.read_text(encoding='utf-8')
    text = text.replace(
        '<string name="app_name">breeze_vpn</string>',
        '<string name="app_name">Breeze VPN</string>',
    )
    strings.write_text(text, encoding='utf-8')
