"""Tests the TEXT EDITING done by tools/ci_android_setup.sh against realistic Flutter android/ templates
(Kotlin DSL and Groovy DSL). It does NOT run Gradle/AGP; the real proof is a real build."""
import os, re, shutil, subprocess, sys, tempfile
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# copy the project but NOT the top-level android/ (tools/android/ must be kept: it holds the override script)
IGN = lambda src, names: [n for n in names if n in ("__pycache__", ".git") or (n == "android" and os.path.abspath(src) == ROOT)]
KTS_ROOT = '''allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
'''
GROOVY_ROOT = '''allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.buildDir = "../build"
subprojects {
    project.buildDir = "${rootProject.buildDir}/${project.name}"
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register("clean", Delete) {
    delete rootProject.buildDir
}
'''
def kts_app(c): return f'''android {{
    namespace = "com.culinex.culinex"
    {c}
    defaultConfig {{
        applicationId = "com.culinex.culinex"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
    }}
}}
'''
def groovy_app(c): return f'''android {{
    namespace "com.culinex.culinex"
    {c}
    defaultConfig {{
        applicationId "com.culinex.culinex"
        minSdkVersion flutter.minSdkVersion
        targetSdkVersion flutter.targetSdkVersion
    }}
}}
'''
def project(tmp, root_name, root_txt, app_name, app_txt):
    d = os.path.join(tmp, "p"); shutil.copytree(ROOT, d, ignore=IGN)
    os.makedirs(os.path.join(d, "android/app/src/main"))
    open(os.path.join(d, "android/app/src/main/AndroidManifest.xml"), "w").write('<manifest><application android:label="culinex"/></manifest>')
    open(os.path.join(d, "android", root_name), "w").write(root_txt)
    open(os.path.join(d, "android/app", app_name), "w").write(app_txt)
    return d
def run(d):
    return subprocess.run(["bash", "tools/ci_android_setup.sh"], cwd=d, capture_output=True, text=True)
res = []
def T(name, ok, detail=""):
    res.append(ok); print(("PASS " if ok else "FAIL ") + name + ("" if ok else "  <-- " + str(detail)[:300]))
def rd(d, *p): return open(os.path.join(d, *p)).read()
def sdk_lines(txt): return [l.strip() for l in txt.split("\n") if re.search(r"minSdk|targetSdk", l)]
cases = [
 ("Kotlin DSL, compileSdk = flutter.compileSdkVersion", "build.gradle.kts", KTS_ROOT, "build.gradle.kts", kts_app("compileSdk = flutter.compileSdkVersion"), "compileSdk = maxOf(flutter.compileSdkVersion, 36)"),
 ("Groovy DSL, compileSdkVersion flutter.compileSdkVersion", "build.gradle", GROOVY_ROOT, "build.gradle", groovy_app("compileSdkVersion flutter.compileSdkVersion"), "compileSdk Math.max(flutter.compileSdkVersion, 36)"),
 ("Groovy DSL, compileSdk flutter.compileSdkVersion", "build.gradle", GROOVY_ROOT, "build.gradle", groovy_app("compileSdk flutter.compileSdkVersion"), "compileSdk Math.max(flutter.compileSdkVersion, 36)"),
 ("Kotlin DSL, literal compileSdk = 34 is raised", "build.gradle.kts", KTS_ROOT, "build.gradle.kts", kts_app("compileSdk = 34"), "compileSdk = 36"),
 ("Groovy DSL, literal compileSdkVersion 34 is raised", "build.gradle", GROOVY_ROOT, "build.gradle", groovy_app("compileSdkVersion 34"), "compileSdk 36"),
 ("Kotlin DSL, literal 37 is NOT lowered", "build.gradle.kts", KTS_ROOT, "build.gradle.kts", kts_app("compileSdk = 37"), "compileSdk = 37"),
]
for name, rn, rt, an, at, expect in cases:
    tmp = tempfile.mkdtemp(); d = project(tmp, rn, rt, an, at)
    before_sdk = sdk_lines(rd(d, "android/app", an))
    r = run(d)
    root = rd(d, "android", rn); app = rd(d, "android/app", an)
    lines = root.split("\n")
    a = next(i for i, l in enumerate(lines) if "compile-sdk-override.gradle" in l and "apply" in l); e = next(i for i, l in enumerate(lines) if "evaluationDependsOn" in l)
    exp_apply = 'apply(from = "compile-sdk-override.gradle")' if rn.endswith("kts") else "apply from: 'compile-sdk-override.gradle'"
    T(f"[{name}] script exit 0", r.returncode == 0, r.stdout[-300:] + r.stderr[-300:])
    T(f"[{name}] apply line is correct DSL syntax and BEFORE evaluationDependsOn", lines[a].strip() == exp_apply and a < e, (a, e))
    T(f"[{name}] app compileSdk -> '{expect}'", expect in app, app)
    T(f"[{name}] minSdk/targetSdk unchanged", sdk_lines(app) == before_sdk, (before_sdk, sdk_lines(app)))
    T(f"[{name}] override file installed in android/", os.path.isfile(os.path.join(d, "android/compile-sdk-override.gradle")))
    T(f"[{name}] label set to CULINEX", 'android:label="CULINEX"' in rd(d, "android/app/src/main/AndroidManifest.xml"))
    snap = (root, app); r2 = run(d)
    T(f"[{name}] second run is idempotent (files identical, exit 0)", r2.returncode == 0 and (rd(d, "android", rn), rd(d, "android/app", an)) == snap, r2.stdout[-200:])
    shutil.rmtree(tmp)
# migration: an earlier run appended the apply line at END of file (after evaluationDependsOn)
tmp = tempfile.mkdtemp(); old = KTS_ROOT + '\n// CULINEX: raise compileSdk of every module to at least 36 (see compile-sdk-override.gradle)\napply(from = "compile-sdk-override.gradle")\n'
d = project(tmp, "build.gradle.kts", old, "build.gradle.kts", kts_app("compileSdk = flutter.compileSdkVersion")); r = run(d); lines = rd(d, "android/build.gradle.kts").split("\n")
cnt = sum("compile-sdk-override.gradle" in l for l in lines); a = next(i for i, l in enumerate(lines) if "compile-sdk-override.gradle" in l and "apply" in l); e = next(i for i, l in enumerate(lines) if "evaluationDependsOn" in l)
T("[migration] old end-of-file apply is moved before evaluationDependsOn, exactly one apply remains", r.returncode == 0 and cnt == 1 and a < e and sum('apply(' in l for l in lines) == 1, (cnt, a, e))
shutil.rmtree(tmp)
# failure modes must fail loudly
tmp = tempfile.mkdtemp(); d = project(tmp, "build.gradle.kts", KTS_ROOT, "build.gradle.kts", 'android {\n    namespace = "x"\n}\n'); r = run(d)
T("[failure] app build file without any compileSdk setting -> exit 1 with message", r.returncode == 1 and "no compileSdk" in r.stdout, r.stdout[-200:]); shutil.rmtree(tmp)
tmp = tempfile.mkdtemp(); d = project(tmp, "build.gradle.kts", KTS_ROOT, "build.gradle.kts", kts_app("compileSdk = flutter.compileSdkVersion")); os.remove(os.path.join(d, "android/build.gradle.kts")); r = run(d)
T("[failure] missing root android build file -> exit 1", r.returncode == 1 and "root android/build.gradle" in r.stdout, r.stdout[-200:]); shutil.rmtree(tmp)
# generated-by-flutter-create path (stub flutter that writes the Kotlin template)
tmp = tempfile.mkdtemp(); d = os.path.join(tmp, "p"); shutil.copytree(ROOT, d, ignore=IGN)
stub = os.path.join(tmp, "bin"); os.makedirs(stub)
open(os.path.join(stub, "flutter"), "w").write('#!/bin/bash\nif [ "$1" = "create" ]; then mkdir -p android/app/src/main; echo \'<manifest><application android:label="culinex"/></manifest>\' > android/app/src/main/AndroidManifest.xml; cat > android/build.gradle.kts <<\'K\'\n' + KTS_ROOT + 'K\ncat > android/app/build.gradle.kts <<\'K\'\n' + kts_app("compileSdk = flutter.compileSdkVersion") + 'K\nfi\n')
os.chmod(os.path.join(stub, "flutter"), 0o755)
r = subprocess.run(["bash", "tools/ci_android_setup.sh"], cwd=d, capture_output=True, text=True, env={**os.environ, "PATH": stub + ":" + os.environ["PATH"]})
T("[flutter create path with stub] android/ generated then patched, exit 0", r.returncode == 0 and "maxOf(flutter.compileSdkVersion, 36)" in rd(d, "android/app/build.gradle.kts"), r.stdout[-300:] + r.stderr[-200:]); shutil.rmtree(tmp)
print(f"\n{sum(res)} passed, {len(res)-sum(res)} failed of {len(res)}"); sys.exit(0 if all(res) else 1)
