"""Static check: EN/MS key parity, and every translation key referenced in lib/ exists."""
import re, glob, sys
src=open("lib/core/strings.dart").read()
en=re.search(r"_en = \{(.*?)\n\};",src,re.S).group(1); ms=re.search(r"_ms = \{(.*?)\n\};",src,re.S).group(1)
K=lambda b:set(re.findall(r"^  '([a-z0-9_]+)':",b,re.M))
ke,km=K(en),K(ms); bad=0
if ke!=km: print("PARITY MISMATCH",ke^km); bad+=1
used=set()
for f in glob.glob("lib/**/*.dart",recursive=True):
    if f.endswith("strings.dart"): continue
    t=open(f).read()
    used|=set(re.findall(r"\bt\('([a-z0-9_]+)'\)",t))
    used|=set(re.findall(r"'((?:st_|row_|gate_)[a-z_]+)'",t))
    for m in re.findall(r"t\('(kind|cat)_\$",t): pass
# dynamic families
import itertools
used|={"kind_"+k for k in ("stock_in","stock_out","adjustment","sale_usage","void_reversal")}
used|={"cat_"+c for c in ("ingredients","packaging","utilities","labour","rent","delivery","marketing","equipment","other")}
missing=used-ke
if missing: print("MISSING KEYS",sorted(missing)); bad+=1
unused=ke-used
print(f"{len(ke)} EN keys, {len(km)} MS keys, {len(used)} referenced, {len(unused)} unused {sorted(unused)[:8]}")
sys.exit(1 if bad else 0)
