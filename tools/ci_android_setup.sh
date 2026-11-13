#!/usr/bin/env bash
# Generates the Android platform project (android/) in CI and applies safe, minimal configuration.
# Idempotent: if android/ already exists it is left untouched. Never overwrites lib/, pubspec.yaml, packages/ or assets/.
set -euo pipefail
cd "$(dirname "$0")/.."

for f in pubspec.yaml lib/main.dart lib/app.dart assets/db/schema.sql assets/db/queries.sql \
         packages/culinex_engine/pubspec.yaml packages/culinex_engine/test/golden/calc_vectors.json test/widget_test.dart; do
  [ -f "$f" ] || { echo "PRE-FLIGHT FAILED: missing $f"; exit 1; }
done

if [ ! -d android ]; then
  echo "android/ missing -> generating with flutter create"
  flutter create --platforms=android --org com.culinex --project-name culinex .
else
  echo "android/ already exists -> leaving it untouched"
fi

MANIFEST=android/app/src/main/AndroidManifest.xml
[ -f "$MANIFEST" ] || { echo "FAILED: $MANIFEST not generated"; exit 1; }
# app name shown on the phone
sed -i 's/android:label="[^"]*"/android:label="CULINEX"/' "$MANIFEST"
grep -n 'android:label' "$MANIFEST"

# guards: make sure flutter create did not replace our code
grep -q "CulinexApp"       lib/main.dart  || { echo "FAILED: lib/main.dart was overwritten"; exit 1; }
grep -q "culinex_engine"   pubspec.yaml   || { echo "FAILED: pubspec.yaml was overwritten"; exit 1; }
grep -q "assets/db/schema.sql" pubspec.yaml || { echo "FAILED: pubspec.yaml assets missing"; exit 1; }
if grep -q "const MyApp" test/widget_test.dart; then echo "FAILED: template widget_test.dart present"; exit 1; fi
echo "Android project ready. applicationId:"
grep -rn "applicationId" android/app/build.gradle* 2>/dev/null || true
