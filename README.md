# CULINEX — Know Your Cost. Control Your Business.

Flutter (Android first) food-business app: Dashboard, Food Cost Calculator (Simple/Advanced), Recipes, Ingredients,
Stock (Premium), Sales, Expenses, Reports. English + Bahasa Melayu. Currency RM. Fully offline (local SQLite).

## STATUS (honest)
* Source code is complete for the modules above. It has **never been compiled or run**: the build sandbox had no Flutter/Dart/Android SDK and no internet.
* **No APK exists.** See `docs/QA_REPORT.txt` for what was and was not verified.
* No accounts/cloud sync (needs a Supabase project + keys). No payments. Premium is locked in release builds.

## Build (on a machine with Flutter stable + Android SDK)
```
unzip culinex_source.zip && cd culinex
flutter create --platforms=android --org com.culinex --project-name culinex .   # generates android/ ; keeps lib/, pubspec.yaml
# if flutter create added test/widget_test.dart (template MyApp test), delete it: it does not match this app
flutter pub get
(cd packages/culinex_engine && dart test)       # engine vs 42 golden vectors from the V1.2 workbook
flutter analyze                                  # expect to fix a few compile/lint issues: code was never compiled
flutter test                                     # money, period ranges, schema split
flutter run                                      # real device / emulator
flutter build apk --release                      # build/app/outputs/flutter-apk/app-release.apk
```
Release signing: create a keystore and configure `android/app/build.gradle` (without it the APK is signed with debug keys: fine for testing, not for the Play Store). Play Store needs an app bundle: `flutter build appbundle`.
Install APK on a phone: enable "Install unknown apps", copy `app-release.apk`, tap it (or `adb install app-release.apk`).
Dependency versions in `pubspec.yaml` are caret ranges written without network access; `pub get` may need adjustments for current releases.

## Verification tools (run here, Python 3)
```
python tools/verify_engine_spec.py packages/culinex_engine/test/golden/calc_vectors.json
python tools/test_sql.py        # executes assets/db/schema.sql + queries.sql (the shipped files) in SQLite
python tools/check_strings.py   # EN/MS key parity
python tools/check_dart.py      # static sanity only (NOT flutter analyze)
```

## Cloud build (Codemagic)
`codemagic.yaml` has two workflows: `culinex-android` (strict, APK only if every step passes) and `culinex-diagnose` (runs every step and uploads logs).
`tools/ci_android_setup.sh` generates `android/` with `flutter create` (only if missing), sets the app name CULINEX and guards against overwriting our code.
Neither workflow has been executed yet. Release APK is debug-signed unless you add a keystore in Codemagic.
