#!/usr/bin/env bash
# Generates the Android platform project (android/) in CI and applies safe, minimal configuration.
# Idempotent: if android/ already exists it is not regenerated. Never overwrites lib/, pubspec.yaml, packages/ or assets/.
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

# ---------------------------------------------------------------------------------------------------------
# compileSdk alignment (target: at least 36).
# Plugins such as file_picker pin compileSdk 34 while flutter_plugin_android_lifecycle requires 36+ (AAR metadata check).
#  1) tools/android/compile-sdk-override.gradle raises compileSdk of EVERY module (app + plugins); it only raises, never lowers.
#  2) It is applied from the root android build file BEFORE the "evaluationDependsOn(':app')" block, so the hook is registered
#     before any module is evaluated (an apply at the end of the file can be too late). Re-running moves an old end-of-file apply.
#  3) The app module is made explicit: compileSdk = max(flutter.compileSdkVersion, 36). minSdk and targetSdk are NOT touched.
# ---------------------------------------------------------------------------------------------------------
OVERRIDE_NAME=compile-sdk-override.gradle
[ -f "tools/android/$OVERRIDE_NAME" ] || { echo "FAILED: tools/android/$OVERRIDE_NAME missing"; exit 1; }
cp "tools/android/$OVERRIDE_NAME" "android/$OVERRIDE_NAME"
if [ -f android/build.gradle.kts ]; then ROOT_BUILD=android/build.gradle.kts
elif [ -f android/build.gradle ]; then ROOT_BUILD=android/build.gradle
else echo "FAILED: no root android/build.gradle(.kts) found"; exit 1; fi

python3 - "$ROOT_BUILD" "$OVERRIDE_NAME" <<'PY'
import re, sys
path, name = sys.argv[1], sys.argv[2]
kts = path.endswith(".kts")
apply_line = f'apply(from = "{name}")' if kts else f"apply from: '{name}'"
comment = "// CULINEX: raise compileSdk of every module to at least 36. Keep this above the block that evaluates :app early."
lines = open(path).read().split("\n")
out, skip_blank = [], False          # drop any earlier insertion (comment, apply line and the blank line after it)
for l in lines:
    if name in l: skip_blank = True; continue
    if l.startswith("// CULINEX: raise compileSdk"): continue
    if skip_blank and l == "": skip_blank = False; continue
    skip_blank = False; out.append(l)
lines = out
idx = next((i for i, l in enumerate(lines) if "evaluationDependsOn" in l), None)
if idx is None:                       # no early evaluation in this template: end of file is safe
    while lines and lines[-1] == "": lines.pop()
    lines += ["", comment, apply_line, ""]
else:                                 # insert before the enclosing "subprojects {" line
    j = idx
    while j >= 0 and not re.match(r"\s*subprojects\s*\{", lines[j]): j -= 1
    if j < 0: j = idx
    lines[j:j] = [comment, apply_line, ""]
open(path, "w").write("\n".join(lines))
PY

python3 - <<'PY'
import os, re, sys
found = False
for p in ("android/app/build.gradle.kts", "android/app/build.gradle"):
    if not os.path.isfile(p): continue
    found = True
    kts = p.endswith(".kts")
    s = open(p).read()
    if not re.search(r"compileSdk", s):
        print(f"FAILED: no compileSdk setting found in {p}; template changed, update tools/ci_android_setup.sh"); sys.exit(1)
    if re.search(r"compileSdk\w*\s*=?\s*(?:maxOf|Math\.max)\(flutter\.compileSdkVersion,\s*36\)", s):
        print(f"{p}: compileSdk already max(flutter.compileSdkVersion, 36)"); continue
    if kts:
        s = re.sub(r"compileSdk(?:Version)?\s*=\s*flutter\.compileSdkVersion", "compileSdk = maxOf(flutter.compileSdkVersion, 36)", s)
        s = re.sub(r"compileSdk(?:Version)?\s*=\s*(\d+)", lambda m: m.group(0) if int(m.group(1)) >= 36 else "compileSdk = 36", s)
    else:
        s = re.sub(r"compileSdk(?:Version)?\s*=?\s*flutter\.compileSdkVersion", "compileSdk Math.max(flutter.compileSdkVersion, 36)", s)
        s = re.sub(r"compileSdk(?:Version)?\s*=?\s*(\d+)", lambda m: m.group(0) if int(m.group(1)) >= 36 else "compileSdk 36", s)
    open(p, "w").write(s)
if not found:
    print("FAILED: android/app/build.gradle(.kts) not found"); sys.exit(1)
PY

# verify: override applied exactly once, before evaluationDependsOn; app compileSdk >= 36 expressed explicitly
[ "$(grep -cF "$OVERRIDE_NAME" "$ROOT_BUILD")" = "1" ] || { echo "FAILED: override must be applied exactly once in $ROOT_BUILD"; exit 1; }
APPLY_LN=$(grep -nF "$OVERRIDE_NAME" "$ROOT_BUILD" | head -1 | cut -d: -f1)
EVAL_LN=$(grep -n "evaluationDependsOn" "$ROOT_BUILD" | head -1 | cut -d: -f1 || true)
if [ -n "${EVAL_LN:-}" ] && [ "$APPLY_LN" -ge "$EVAL_LN" ]; then echo "FAILED: override (line $APPLY_LN) must come before evaluationDependsOn (line $EVAL_LN)"; exit 1; fi
python3 - <<'PY' || { echo "FAILED: app compileSdk is not >= 36"; exit 1; }
import glob, re, sys
ok = False
for p in glob.glob("android/app/build.gradle*"):
    s = open(p).read()
    if re.search(r"(?:maxOf|Math\.max)\(flutter\.compileSdkVersion,\s*36\)", s): ok = True
    for m in re.finditer(r"compileSdk(?:Version)?\s*=?\s*(\d+)", s):
        if int(m.group(1)) >= 36: ok = True
sys.exit(0 if ok else 1)
PY
echo "compileSdk override applied via $ROOT_BUILD (line $APPLY_LN, evaluationDependsOn line ${EVAL_LN:-none}):"
grep -nE "CULINEX|$OVERRIDE_NAME" "$ROOT_BUILD"
echo "app module SDK lines (minSdk/targetSdk untouched by this script):"
grep -nE "compileSdk|minSdk|targetSdk" android/app/build.gradle* || true

# guards: make sure flutter create did not replace our code
grep -q "CulinexApp"       lib/main.dart  || { echo "FAILED: lib/main.dart was overwritten"; exit 1; }
grep -q "culinex_engine"   pubspec.yaml   || { echo "FAILED: pubspec.yaml was overwritten"; exit 1; }
grep -q "assets/db/schema.sql" pubspec.yaml || { echo "FAILED: pubspec.yaml assets missing"; exit 1; }
if grep -q "const MyApp" test/widget_test.dart; then echo "FAILED: template widget_test.dart present"; exit 1; fi
echo "Android project ready. applicationId:"
grep -rn "applicationId" android/app/build.gradle* 2>/dev/null || true
