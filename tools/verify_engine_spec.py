"""Line-by-line Python mirror of packages/culinex_engine/lib/src/calc.dart, run against the golden vectors.
This checks the SPECIFICATION encoded in the Dart engine. It does NOT execute the Dart code."""
import json, math, sys
U={"g":("m",1),"kg":("m",1000),"ml":("v",1),"l":("v",1000),"pcs":("c",1)}
blank=lambda s: s is None or str(s).strip()==""
def row(l):
    if blank(l["name"]) and l["price"] is None and l["size"] is None and blank(l["packUnit"]) and l["used"] is None and blank(l["usedUnit"]): return "blank",None
    if l["price"] is None or l["size"] is None or blank(l["packUnit"]) or l["used"] is None or blank(l["usedUnit"]): return "incomplete",None
    p,s,u=l["price"],l["size"],l["used"]
    if p<0 or s<=0 or u<0: return "checkNumbers",None
    pu=U.get(l["packUnit"].lower()); uu=U.get(l["usedUnit"].lower())
    if not pu or not uu: return "checkUnit",None
    if pu[0]!=uu[0]: return "unitMismatch",None
    return "ok",p*u*uu[1]/(s*pu[1])
TXT={"blank":"","ok":"","incomplete":"Incomplete","checkNumbers":"Check numbers","checkUnit":"Check unit","unitMismatch":"Unit mismatch"}
def calc(i):
    rows=[row(l) for l in i["rows"]]; blocked=any(s not in("blank","ok") for s,_ in rows)
    ing=None if blocked else sum(c for s,c in rows if c is not None)
    other=i["other"] or 0; total=None if ing is None else ing+other
    serv=i["servings"] or 0; cps=total/serv if total is not None and serv>0 else None
    m=i["margin"]; sug=cps/(1-m) if cps is not None and m is not None and 0<=m<1 else None
    own=i["own"]; used=own if own is not None else sug
    prof=used-cps if used is not None and cps is not None else None
    mar=prof/used if prof is not None and used>0 else None
    batch=prof*i["servings"] if prof is not None and i["servings"] is not None else None
    neg=other<0 or any((l["price"] or 0)<0 or (l["size"] or 0)<0 or (l["used"] or 0)<0 for l in i["rows"])
    st=[s for s,_ in rows]
    if neg: code="negative"
    elif "unitMismatch" in st: code="unitMismatch"
    elif "checkUnit" in st: code="checkUnit"
    elif "incomplete" in st: code="incomplete"
    elif "checkNumbers" in st: code="invalidRow"
    elif serv<=0: code="noServings"
    elif m is None or m<0 or m>=1: code="badMargin"
    elif own is not None and own<=0: code="badOwnPrice"
    else: code="ok"
    cells={"E12":"Fix inputs" if blocked else ing,"E13":total if total is not None else "Fix inputs",
      "E6":"Fix inputs" if total is None else (cps if cps is not None else "Enter servings"),
      "E7":sug if sug is not None else "Check inputs","E11":own if own is not None else (sug if sug is not None else "Check inputs"),
      "E8":prof,"E9":mar,"E10":batch}
    return rows,cells,code
V=json.load(open(sys.argv[1]))["vectors"]; bad=0; checks=0
for v in V:
    rows,cells,code=calc(v["input"]); e=v["expected"]; errs=[]
    for k,c in cells.items():
        x=e[k]; checks+=1
        if x is None or isinstance(x,str) or c is None or isinstance(c,str):
            if x!=c: errs.append((k,c,x))
        elif abs(c-x)>1e-9*max(1,abs(x)): errs.append((k,c,x))
    checks+=1
    if code!=e["statusCode"]: errs.append(("status",code,e["statusCode"]))
    for (s,c),t,x in zip(rows,e["rowText"],e["rowCost"]):
        checks+=1
        if TXT[s]!=t or (x is not None and abs(c-x)>1e-9*max(1,abs(x))): errs.append(("row",s,t))
    if errs: bad+=1; print("MISMATCH",v["id"],errs[:3])
print(f"{len(V)} vectors, {checks} cell checks, {bad} vectors with mismatches")
sys.exit(1 if bad else 0)
