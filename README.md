# Breeze VPN

کلاینت اندرویدی Xray/V2Ray با ظاهر تیره و مینیمال، الهام‌گرفته از چیدمان اپ‌های VPN مدرن. این پروژه برای این ساخته شده که کانفیگ‌هایی مثل `vless://`، `vmess://`، `trojan://` و `ss://` را وارد کنی، چند سرور را ذخیره کنی، پینگ را تست کنی و با VPN Mode به کل ترافیک دستگاه وصل شوی.

## قابلیت‌ها

- دکمه بزرگ اتصال/قطع اتصال شبیه اپ‌های VPN مدرن
- افزودن لینک‌های VLESS / VMess / Trojan / Shadowsocks / SOCKS / Hysteria از کلیپ‌بورد
- وارد کردن مستقیم JSON
- ذخیره چند سرور در حافظه محلی
- انتخاب سرور و تغییر نام یا حذف آن
- تست Ping سرور؛ موفق = سبز + عدد میلی‌ثانیه، ناموفق = قرمز + OFFLINE
- VPN Mode با `flutter_v2ray_client` و Xray-core
- نمایش وضعیت اتصال و مدت اتصال

## ساخت APK با GitHub Actions

1. این پوشه را داخل یک repository جدید GitHub قرار بده و روی `main` یا `master` push کن.
2. در GitHub به **Actions** برو.
3. workflow با نام **Build Breeze VPN APK** را اجرا کن.
4. بعد از اتمام build، artifact با نام **breeze-vpn-release-apk** را از صفحه workflow بگیر.

Workflow خودش Android platform files را با Flutter stable می‌سازد؛ بنابراین لازم نیست پوشه `android/` را دستی نگه داری.
در Workflow ابتدا Android platform ساخته می‌شود و سپس Gradle cache فعال می‌شود تا خطای نبودن فایل‌های Gradle رخ ندهد. تست نمونهٔ خودکار Flutter نیز حذف می‌شود چون اپ کلاس `BreezeVpnApp` دارد، نه `MyApp`.

## اجرای محلی

```bash
flutter pub get
flutter create --platforms=android --org com.breeze --project-name breeze_vpn .
flutter run
```

## محدودیت مهم

این نسخه برای کانفیگ‌های Xray/V2Ray طراحی شده است. کانفیگ‌های Cloudflare Warp/WireGuard از این نسخه پشتیبانی نمی‌شوند و لینک Subscription URL نیز هنوز واردکنندهٔ مستقیم ندارد؛ برای این موارد باید کانفیگ خروجی Xray/لینک‌های تکی را وارد کنی.

## نکته فنی

هسته شبکه از پکیج `flutter_v2ray_client` نسخه 3.5.0 استفاده می‌کند که در زمان ساخت این پروژه، Xray-core 26.9.9 را برای Android ارائه می‌کند و API لازم برای VPN/TUN و تست delay دارد.

برای استفاده واقعی، کانفیگ تولیدشده در پنل خودت را وارد کن. بدون کانفیگ معتبر، دکمه اتصال چیزی برای اتصال ندارد.


## Build note
The GitHub Actions workflow runs `flutter analyze --no-fatal-infos` so analyzer info-level lints do not prevent the release APK build.
