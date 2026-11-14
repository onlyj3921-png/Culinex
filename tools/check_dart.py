"""Static sanity checks for Dart sources WITHOUT a Dart compiler. This is NOT a substitute for `flutter analyze`.
Checks: balanced brackets, imports resolve, symbols declared in this project are imported where used,
Repo methods called from UI exist, provider names used are declared."""
import re, glob, os, sys
ROOT=os.getcwd(); files=sorted(glob.glob("lib/**/*.dart",recursive=True))+sorted(glob.glob("packages/*/lib/**/*.dart",recursive=True))+sorted(glob.glob("packages/*/test/*.dart"))
def strip(s):
    out=[];i=0;n=len(s)
    while i<n:
        c=s[i]
        if s.startswith("//",i):
            j=s.find("\n",i); i=n if j<0 else j; continue
        if s.startswith("/*",i):
            j=s.find("*/",i); i=n if j<0 else j+2; continue
        if c in "'\"":
            q=c; triple=s.startswith(q*3,i); i+= 3 if triple else 1; end=q*3 if triple else q; depth=0
            while i<n:
                if s[i]=="\\": i+=2; continue
                if s[i]=="$" and i+1<n and s[i+1]=="{":
                    # keep interpolated code balanced: skip to matching }
                    d=1;i+=2
                    while i<n and d:
                        if s[i]=="{": d+=1
                        elif s[i]=="}": d-=1
                        i+=1
                    continue
                if s.startswith(end,i): i+=len(end); break
                i+=1
            out.append('""'); continue
        out.append(c); i+=1
    return "".join(out)
errs=[]
pub=open("pubspec.yaml").read(); deps=set(re.findall(r"^  ([a-z_]+):",pub,re.M))|{"flutter","flutter_test","dart"}
declared={}   # symbol -> file
texts={}
for f in files:
    raw=open(f).read(); s=strip(raw); texts[f]=s
    # brackets
    st=[];pairs={")":"(","]":"[","}":"{"}
    for ln,line in enumerate(s.split("\n"),1):
        for ch in line:
            if ch in "([{": st.append((ch,ln))
            elif ch in ")]}":
                if not st or st[-1][0]!=pairs[ch]: errs.append(f"{f}:{ln}: unbalanced '{ch}'"); st=[]; break
                st.pop()
    if st: errs.append(f"{f}: unclosed '{st[-1][0]}' opened line {st[-1][1]}")
    for m in re.finditer(r"^(?:abstract\s+)?(?:class|enum|typedef|mixin|extension)\s+([A-Za-z_]\w*)",s,re.M): declared[m.group(1)]=f
    for m in re.finditer(r"^(?:final|const)\s+(?:[\w<>?,\s\(\)\{\}]+?\s+)?([a-z]\w*)\s*=",s,re.M): declared[m.group(1)]=f
    for m in re.finditer(r"^(?:[A-Za-z_][\w<>?,\s\(\)\{\}\.]*?\s)?([a-z]\w*)\s*\([^;{]*\)\s*(?:async\s*)?(?:\{|=>)",s,re.M):
        if m.group(1) not in ("if","for","while","switch","catch","return"): declared.setdefault(m.group(1),f)
# imports
for f in files:
    raw=open(f).read()
    for imp in re.findall(r"^import\s+'([^']+)'",raw,re.M):
        if imp.startswith("package:"):
            pk=imp.split(":")[1].split("/")[0]
            if pk not in deps and pk not in ("test","culinex_engine"): errs.append(f"{f}: package '{pk}' not in pubspec")
        elif imp.startswith("dart:"): pass
        else:
            tgt=os.path.normpath(os.path.join(os.path.dirname(f),imp))
            if not os.path.exists(tgt): errs.append(f"{f}: import '{imp}' not found")
# symbol import check (project symbols only; engine symbols by package import)
engine_syms={s for s,f in declared.items() if f.startswith("packages/culinex_engine/lib")}
lib_syms={s:f for s,f in declared.items() if f.startswith("lib/") and len(s)>2}
for f in files:
    if not f.startswith("lib/"): continue
    s=texts[f]; raw=open(f).read()
    imports={os.path.normpath(os.path.join(os.path.dirname(f),i)) for i in re.findall(r"^import\s+'([^'\.][^']*|\.[^']*)'",raw,re.M) if not i.startswith(("package:","dart:"))}
    idents=set(re.findall(r"\b[A-Za-z_]\w*\b",s))
    for sym,src in lib_syms.items():
        if src==f or sym not in idents: continue
        if os.path.normpath(src) not in imports and not sym.startswith("_"): errs.append(f"{f}: uses '{sym}' declared in {src} but does not import it")
    used=[sym for sym in engine_syms if len(sym)>3 and not sym.startswith("_") and re.search(r"(?<![\w.])"+re.escape(sym)+r"\b",s) and sym not in ("Brand",)]  # not preceded by "." (e.g. Icons.calculate)
    if used and "package:culinex_engine/culinex_engine.dart" not in raw:
        errs.append(f"{f}: uses engine symbols {used[:4]} without importing culinex_engine")
    for sym in ("SystemNavigator","Clipboard","HapticFeedback","SystemChrome"):
        if sym in idents and "package:flutter/services.dart" not in raw: errs.append(f"{f}: uses {sym} without importing flutter/services.dart")
    if re.search(r"\b(Text|Scaffold|Column|Row|Icon)\(",s) and "package:flutter/material.dart" not in raw: errs.append(f"{f}: uses Flutter widgets without material import")
    if "../core/strings.dart" in raw and not re.search(r"\bT\b",s): errs.append(f"{f}: strings.dart import is unused")
# Repo methods used from UI exist
repo=texts["lib/data/repository.dart"]; methods=set(re.findall(r"^\s+(?:Future<[^\n]*?>|Future<void>|[A-Za-z<>?,\{\}\(\)\s]+?)\s+([a-z]\w*)\(",repo,re.M))|set(re.findall(r"^\s+Future<[^\n]*?>\s+([a-z]\w*)\(",repo,re.M))
for f in files:
    for m in re.finditer(r"(?:repoProvider\)|\brepo)\.([a-z]\w*)\(",texts[f]):
        if m.group(1) not in methods and m.group(1) not in ("meta","setMeta"): errs.append(f"{f}: Repo.{m.group(1)}() does not exist")
# providers used are declared
for f in files:
    for m in re.finditer(r"\b([a-z]\w*Provider)\b",texts[f]):
        if m.group(1) not in declared and m.group(1) not in ("overrideWithValue",): errs.append(f"{f}: provider '{m.group(1)}' not declared")
print(f"{len(files)} files checked")
for e in sorted(set(errs)): print("ISSUE",e)
sys.exit(1 if errs else 0)
