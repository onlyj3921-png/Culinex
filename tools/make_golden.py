"""Export golden test vectors from the VERIFIED V1.2 workbook scenarios.
Inputs and expected outputs are read straight from workbooks that were recalculated
by LibreOffice during the V1.2 QA run (not produced by the Dart engine)."""
import json, sys, os
from openpyxl import load_workbook
SCN = sys.argv[1]; OUT = sys.argv[2]
tags = ["t1","t2a","t2b","t3","t4","t5","t6","t7","t8","x1","x2","x3","x4","x5","x6","x8","b1","b2",
        "c1","c2","c3","c4","c5","c6","c7","m1","m2","m3","m4","m5","m6","h1","h2","h3","h4",
        "r0","r1","r2","r3","r4","r5","bt1"]
KEY = [("negative","negative"),("unit mismatch","unitMismatch"),("not recognised","checkUnit"),("incomplete","incomplete"),
       ("invalid number","invalidRow"),("servings above zero","noServings"),("target margin","badMargin"),
       ("own selling price","badOwnPrice"),("OK:","ok")]
def code(a5):
    for k,v in KEY:
        if k in a5: return v
    raise ValueError(a5)
def n(v):  # sheet blank -> None
    return None if v in (None,"") else v
vectors=[]
for t in tags:
    sheet="Blank Template" if t=="bt1" else "Sample Calculator"
    wi=load_workbook(f"{SCN}/{t}.xlsx")[sheet]; wv=load_workbook(f"{SCN}/{t}.xlsx",data_only=True)[sheet]
    rows=[];rt=[];rc=[]
    for r in range(24,49):
        vals=[wi.cell(r,c).value for c in range(1,7)]
        if all(v in (None,"") for v in vals): continue
        assert all(isinstance(vals[i],(int,float)) or vals[i] is None for i in (1,2,4)), (t,r,vals)  # numeric-only vectors
        rows.append(dict(name=vals[0],price=vals[1],size=vals[2],packUnit=vals[3],used=vals[4],usedUnit=vals[5]))
        g=wv.cell(r,7).value
        if isinstance(g,str): rt.append(g); rc.append(None)
        else: rt.append(""); rc.append(g)
    exp={c:n(wv[c].value) for c in ("E6","E7","E8","E9","E10","E11","E12","E13")}
    exp["statusCode"]=code(wv["A5"].value); exp["rowText"]=rt; exp["rowCost"]=rc
    vectors.append(dict(id=t+("_blank_template" if t=="bt1" else ""),
        input=dict(servings=n(wi["E18"].value),margin=n(wi["E19"].value),other=n(wi["E20"].value),own=n(wi["E21"].value),rows=rows),expected=exp))
json.dump(dict(source="AutoFood_Profit_Calculator_V1.2.xlsx scenarios recalculated in LibreOffice during V1.2 QA",count=len(vectors),vectors=vectors),open(OUT,"w"),indent=1)
print(len(vectors),"vectors written")
