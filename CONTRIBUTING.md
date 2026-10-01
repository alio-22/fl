# Development

این پروژه یک کلاینت Android/Flutter است. قبل از ارسال تغییرات:

```bash
flutter pub get
flutter analyze
```

برای build:

```bash
flutter create --platforms=android --org com.breeze --project-name breeze_vpn .
python3 scripts/patch_android.py
flutter build apk --release
```
