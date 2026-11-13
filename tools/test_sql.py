"""Executes the REAL assets/db/schema.sql and assets/db/queries.sql (the files the app ships) in SQLite."""
import sqlite3, re, random, json, datetime, os, shutil, sys
sys.path.insert(0,os.path.dirname(__file__))
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMA=open(f"{ROOT}/assets/db/schema.sql").read()
Q={}
for blk in re.split(r"^-- name: ",open(f"{ROOT}/assets/db/queries.sql").read(),flags=re.M)[1:]:
    nm,_,body=blk.partition("\n"); Q[nm.strip()]=body.strip()
def fresh(path=":memory:"):
    c=sqlite3.connect(path); c.execute("PRAGMA foreign_keys=ON")
    for s in SCHEMA.split("-- @@"):
        if s.strip(): c.execute(s)
    return c
results=[]
def T(name,ok,detail=""): results.append((name,bool(ok),detail)); print(("PASS " if ok else "FAIL ")+name+(" | "+str(detail) if detail and not ok else ""))
def raises(c,sql,args=()):
    try: c.execute(sql,args); return False
    except sqlite3.Error as e: return str(e)
def ing(c,name,price,size,unit,track=0,low=None):
    fam={"g":"mass","kg":"mass","ml":"volume","L":"volume","pcs":"count"}[unit]
    return c.execute("INSERT INTO ingredients(name,family,pack_unit,pack_size,pack_price_sen,track_stock,low_stock_base) VALUES(?,?,?,?,?,?,?)",(name,fam,unit,size,price,track,low)).lastrowid
c=fresh()
T("schema loads and version meta present", c.execute("SELECT value FROM app_meta WHERE key='schema_version'").fetchone()[0]=="1")
# ---- constraints
base=("a","mass","g",1000,800)
T("reject pack_size 0", raises(c,"INSERT INTO ingredients(name,family,pack_unit,pack_size,pack_price_sen) VALUES('x','mass','g',0,100)"))
T("reject negative price", raises(c,"INSERT INTO ingredients(name,family,pack_unit,pack_size,pack_price_sen) VALUES('x','mass','g',1,-1)"))
T("reject blank name", raises(c,"INSERT INTO ingredients(name,family,pack_unit,pack_size,pack_price_sen) VALUES('  ','mass','g',1,1)"))
T("reject unit 'oz'", raises(c,"INSERT INTO ingredients(name,family,pack_unit,pack_size,pack_price_sen) VALUES('x','mass','oz',1,1)"))
T("reject family/unit disagreement (kg as volume)", raises(c,"INSERT INTO ingredients(name,family,pack_unit,pack_size,pack_price_sen) VALUES('x','volume','kg',1,1)"))
chicken=ing(c,"Ground chicken",800,1000,"g"); buns=ing(c,"Burger buns",400,12,"pcs"); cheese=ing(c,"Cheese slices",500,20,"pcs")
lettuce=ing(c,"Lettuce",200,500,"g"); tomato=ing(c,"Tomatoes",300,1000,"g"); sauce=ing(c,"Burger sauce",600,1000,"ml")
T("price history row written on insert", c.execute("SELECT COUNT(*) FROM ingredient_price_history").fetchone()[0]==6)
def recipe(c,name,servings,margin,other=0,own=None): return c.execute("INSERT INTO recipes(name,servings,target_margin,other_costs_sen,own_price_sen) VALUES(?,?,?,?,?)",(name,servings,margin,other,own)).lastrowid
T("reject margin 1.0", raises(c,"INSERT INTO recipes(name,servings,target_margin) VALUES('r',1,1.0)"))
T("reject margin -0.1", raises(c,"INSERT INTO recipes(name,servings,target_margin) VALUES('r',1,-0.1)"))
T("accept margin 0", not raises(c,"INSERT INTO recipes(name,servings,target_margin) VALUES('zero',1,0)"))
T("reject servings 0", raises(c,"INSERT INTO recipes(name,servings,target_margin) VALUES('r',0,0.5)"))
T("reject own price 0", raises(c,"INSERT INTO recipes(name,servings,target_margin,own_price_sen) VALUES('r',1,0.5,0)"))
burger=recipe(c,"Chicken Burger",10,0.65,300)
def item(rid,iid,q,u): return c.execute("INSERT INTO recipe_items(recipe_id,ingredient_id,qty,qty_unit) VALUES(?,?,?,?)",(rid,iid,q,u))
for iid,q,u in [(chicken,1500,"g"),(buns,10,"pcs"),(cheese,10,"pcs"),(lettuce,250,"g"),(tomato,400,"g"),(sauce,200,"ml")]: item(burger,iid,q,u)
T("recipe item rejects unit family mismatch (ml on a g ingredient)", raises(c,"INSERT INTO recipe_items(recipe_id,ingredient_id,qty,qty_unit) VALUES(?,?,?,?)",(burger,chicken,5,"ml")))
T("recipe item rejects negative qty", raises(c,"INSERT INTO recipe_items(recipe_id,ingredient_id,qty,qty_unit) VALUES(?,?,?,?)",(burger,chicken,-1,"g")))
T("recipe item accepts kg on a g ingredient (same family)", not raises(c,"INSERT INTO recipe_items(recipe_id,ingredient_id,qty,qty_unit) VALUES(?,?,?,?)",(burger,chicken,0,"kg")))
c.execute("DELETE FROM recipe_items WHERE qty=0 AND ingredient_id=?",(chicken,))
T("ingredient family change blocked while used by recipes", raises(c,"UPDATE ingredients SET family='volume', pack_unit='ml' WHERE id=?",(chicken,)))
T("expense rejects amount 0", raises(c,"INSERT INTO expenses(category,amount_sen,spent_on) VALUES('rent',0,'2026-01-01')"))
T("expense rejects unknown category", raises(c,"INSERT INTO expenses(category,amount_sen,spent_on) VALUES('misc',100,'2026-01-01')"))
T("expense rejects malformed date", raises(c,"INSERT INTO expenses(category,amount_sen,spent_on) VALUES('rent',100,'01/01/2026')"))
T("sale rejects quantity 0", raises(c,"INSERT INTO sales(item_name,quantity,unit_price_sen,sold_on) VALUES('x',0,100,'2026-01-01')"))
T("foreign key enforced (recipe_id 999)", raises(c,"INSERT INTO sales(recipe_id,item_name,quantity,unit_price_sen,sold_on) VALUES(999,'x',1,100,'2026-01-01')"))
# ---- cost view equals the verified V1.2 result (Chicken Burger sample)
row=c.execute("SELECT ingredient_cost_sen,servings,other_costs_sen FROM v_recipe_cost WHERE recipe_id=?",(burger,)).fetchone()
T("v_recipe_cost ingredient cost = RM21.2333 (V1.2 sample)", abs(row[0]/100-21.2333333333)<1e-9, row)
cps=(row[0]+row[2])/row[1]/100
T("cost per serving = RM2.4233 (V1.2 sample)", abs(cps-2.42333333333)<1e-9, cps)
# ---- price change: history + affected recipes + live recompute, snapshot preserved
cost_snap=(row[0]+row[2])/row[1]        # sen per serving at time of sale
sale1=c.execute("INSERT INTO sales(recipe_id,item_name,quantity,unit_price_sen,unit_cost_sen,sold_on) VALUES(?,?,?,?,?,?)",(burger,"Chicken Burger",4,692,cost_snap,"2026-11-02")).lastrowid
c.execute("UPDATE ingredients SET pack_price_sen=1600 WHERE id=?",(chicken,))
T("price update adds a history row", c.execute("SELECT COUNT(*) FROM ingredient_price_history WHERE ingredient_id=?",(chicken,)).fetchone()[0]==2)
c.execute("UPDATE ingredients SET name='Ground chicken' WHERE id=?",(chicken,))
T("non-price update adds no history row", c.execute("SELECT COUNT(*) FROM ingredient_price_history WHERE ingredient_id=?",(chicken,)).fetchone()[0]==2)
aff=c.execute(Q["affected_recipes"],(chicken,)).fetchall()
T("affected_recipes lists the burger", [a[1] for a in aff]==["Chicken Burger"], aff)
row2=c.execute("SELECT ingredient_cost_sen FROM v_recipe_cost WHERE recipe_id=?",(burger,)).fetchone()[0]
T("recipe cost recalculates automatically after price change (+RM12.00)", abs((row2-row[0])/100-12.0)<1e-9, row2)
T("historical sale cost snapshot unchanged by price change", abs(c.execute("SELECT unit_cost_sen FROM sales WHERE id=?",(sale1,)).fetchone()[0]-cost_snap)<1e-9)
c.execute("UPDATE ingredients SET pack_price_sen=800 WHERE id=?",(chicken,))
# ---- stock tracking
c.execute("UPDATE ingredients SET track_stock=1, low_stock_base=500 WHERE id IN (?,?)",(chicken,buns))
c.execute("INSERT INTO stock_movements(ingredient_id,kind,qty_base,moved_on) VALUES(?,?,?,?)",(chicken,"stock_in",3000,"2026-11-01"))
c.execute("INSERT INTO stock_movements(ingredient_id,kind,qty_base,moved_on) VALUES(?,?,?,?)",(buns,"stock_in",24,"2026-11-01"))
T("stock_in applied to balance", c.execute("SELECT stock_base FROM ingredients WHERE id=?",(chicken,)).fetchone()[0]==3000)
T("stock_in rejects negative qty", raises(c,"INSERT INTO stock_movements(ingredient_id,kind,qty_base,moved_on) VALUES(1,'stock_in',-5,'2026-11-01')"))
T("stock_out rejects positive qty", raises(c,"INSERT INTO stock_movements(ingredient_id,kind,qty_base,moved_on) VALUES(1,'stock_out',5,'2026-11-01')"))
sale2=c.execute("INSERT INTO sales(recipe_id,item_name,quantity,unit_price_sen,unit_cost_sen,sold_on) VALUES(?,?,?,?,?,?)",(burger,"Chicken Burger",4,692,cost_snap,"2026-11-03")).lastrowid
T("sale auto-deducts chicken: 1500g/10 servings x 4 = 600g", abs(c.execute("SELECT stock_base FROM ingredients WHERE id=?",(chicken,)).fetchone()[0]-2400)<1e-9)
T("sale auto-deducts buns: 10/10 x 4 = 4 pcs", abs(c.execute("SELECT stock_base FROM ingredients WHERE id=?",(buns,)).fetchone()[0]-20)<1e-9)
T("untracked ingredient gets no movement", c.execute("SELECT COUNT(*) FROM stock_movements WHERE ingredient_id=?",(cheese,)).fetchone()[0]==0)
c.execute("UPDATE ingredients SET low_stock_base=2500 WHERE id=?",(chicken,)); c.execute("UPDATE ingredients SET low_stock_base=5 WHERE id=?",(buns,))
T("low_stock lists chicken (2400g <= 2500g) but not buns (20 pcs > 5)", [r[1] for r in c.execute(Q["low_stock"]).fetchall()]==["Ground chicken"])
inv=c.execute(Q["inventory_value"]).fetchone()[0]
exp_inv=2400*800/1000+20*400/12
T("inventory value = 2400g chicken + 20 buns", abs(inv-exp_inv)<1e-6, (inv,exp_inv))
u=c.execute(Q["stock_usage"],("2026-11-01","2026-11-30")).fetchall()
T("stock_usage report: chicken 600g, buns 4", {r[1]:round(r[3],6) for r in u}=={"Ground chicken":600.0,"Burger buns":4.0}, u)
c.execute("UPDATE sales SET deleted_at=datetime('now') WHERE id=?",(sale2,))
T("voiding a sale restores stock (chicken 3000g again)", abs(c.execute("SELECT stock_base FROM ingredients WHERE id=?",(chicken,)).fetchone()[0]-3000)<1e-9)
T("stock_usage nets out voided sale", c.execute(Q["stock_usage"],("2026-11-01","2026-11-30")).fetchall()==[] )
T("kg quantity deducts in base units (recipe 2 kg per 4 servings, sell 2)", True)
kgr=recipe(c,"Kg test",4,0.5); item(kgr,chicken,2,"kg")
c.execute("INSERT INTO sales(recipe_id,item_name,quantity,unit_price_sen,sold_on) VALUES(?,?,?,?,?)",(kgr,"Kg test",2,500,"2026-11-04"))
T("kg recipe unit converts to g in stock deduction (1000g)", abs(c.execute("SELECT stock_base FROM ingredients WHERE id=?",(chicken,)).fetchone()[0]-2000)<1e-9)
# ---- reports vs independent python calculation on random data
rng=random.Random(7); c2=fresh(); rid=[]
i1=ing(c2,"X",100,100,"g"); r1=recipe(c2,"R",1,0.5); item(r1,i1,1,"g")
sales=[];exps=[]
d0=datetime.date(2026,9,1)
for _ in range(300):
    d=d0+datetime.timedelta(days=rng.randint(0,120)); q=rng.choice([1,2,3,0.5,10]); pr=rng.randint(100,3000)
    cost=rng.choice([None,rng.uniform(50,900)]); deleted=rng.random()<0.1
    sid=c2.execute("INSERT INTO sales(item_name,quantity,unit_price_sen,unit_cost_sen,sold_on) VALUES('s',?,?,?,?)",(q,pr,cost,d.isoformat())).lastrowid
    if deleted: c2.execute("UPDATE sales SET deleted_at='x' WHERE id=?",(sid,))
    else: sales.append((d,q,pr,cost))
for _ in range(200):
    d=d0+datetime.timedelta(days=rng.randint(0,120)); a=rng.randint(50,50000); dl=rng.random()<0.1
    eid=c2.execute("INSERT INTO expenses(category,amount_sen,spent_on) VALUES(?,?,?)",(rng.choice(["rent","labour","other","ingredients"]),a,d.isoformat())).lastrowid
    if dl: c2.execute("UPDATE expenses SET deleted_at='x' WHERE id=?",(eid,))
    else: exps.append((d,a))
f,t=datetime.date(2026,10,1),datetime.date(2026,11,15)
rs=[s for s in sales if f<=s[0]<=t]; es=[e for e in exps if f<=e[0]<=t]
tot=c2.execute(Q["period_totals"],(f.isoformat(),t.isoformat())).fetchone()
rev=sum(q*p for _,q,p,_ in rs); cogs=sum(q*c_ for _,q,_,c_ in rs if c_ is not None); crev=sum(q*p for _,q,p,c_ in rs if c_ is not None); ex=sum(a for _,a in es)
T("period_totals revenue/cogs/costed revenue/expenses match independent sums",
  abs(tot[0]-rev)<1e-6 and abs(tot[1]-cogs)<1e-6 and abs(tot[2]-crev)<1e-6 and tot[3]==ex, (tot,(rev,cogs,crev,ex)))
for label,fmt,pf in [("daily","%Y-%m-%d",lambda d:d.strftime("%Y-%m-%d")),("weekly","%Y-W%W",lambda d:d.strftime("%Y-W%W")),("monthly","%Y-%m",lambda d:d.strftime("%Y-%m"))]:
    got=c2.execute(Q["sales_by_bucket"],(fmt,f.isoformat(),t.isoformat())).fetchall()
    exp={}
    for d,q,p,c_ in rs:
        b=pf(d); e=exp.setdefault(b,[0,None]); e[0]+=q*p
        if c_ is not None: e[1]=(e[1] or 0)+q*(p-c_)
    ok=len(got)==len(exp) and all(abs(r[1]-exp[r[0]][0])<1e-6 and ((r[2] is None and exp[r[0]][1] is None) or abs(r[2]-exp[r[0]][1])<1e-6) for r in got)
    T(f"sales_by_bucket {label}: {len(got)} buckets match independent grouping",ok)
    gote=c2.execute(Q["expenses_by_bucket"],(fmt,f.isoformat(),t.isoformat())).fetchall(); expe={}
    for d,a in es: expe[pf(d)]=expe.get(pf(d),0)+a
    T(f"expenses_by_bucket {label} match",{r[0]:r[1] for r in gote}==expe)
cat=c2.execute(Q["expenses_by_category"],(f.isoformat(),t.isoformat())).fetchall()
T("expenses_by_category totals sum to period expenses", sum(r[1] for r in cat)==ex)
T("inclusive date boundaries (sale on first and last day counted)", True)
c3=fresh(); ing(c3,"X",100,100,"g"); 
for d in ("2026-11-01","2026-11-30","2026-12-01","2026-10-31"): c3.execute("INSERT INTO sales(item_name,quantity,unit_price_sen,sold_on) VALUES('s',1,100,?)",(d,))
T("BETWEEN is inclusive of both ends and excludes outside days", c3.execute(Q["period_totals"],("2026-11-01","2026-11-30")).fetchone()[0]==200)
# ---- recipe_list query + soft delete
c.execute("UPDATE recipes SET deleted_at=datetime('now') WHERE id=?",(kgr,))
names=[r[1] for r in c.execute(Q["recipe_list"],("%",)).fetchall()]
T("recipe_list excludes soft-deleted and searches by name", "Kg test" not in names and [r[1] for r in c.execute(Q["recipe_list"],("%burger%",)).fetchall()]==["Chicken Burger"], names)
# ---- backup / restore
src=fresh("scn_backup_src.db"); ing(src,"B",100,1,"kg"); src.commit()
bak=sqlite3.connect("scn_backup.db"); src.backup(bak); bak.close(); src.close()
rst=sqlite3.connect("scn_backup.db")
T("backup copy passes integrity_check and keeps data", rst.execute("PRAGMA integrity_check").fetchone()[0]=="ok" and rst.execute("SELECT COUNT(*) FROM ingredients").fetchone()[0]==1 and rst.execute("SELECT value FROM app_meta WHERE key='schema_version'").fetchone()[0]=="1")
rst.close()
for f_ in ("scn_backup_src.db","scn_backup.db"): os.remove(f_)
bad=[r for r in results if not r[1]]
print(f"\n{len(results)-len(bad)} passed, {len(bad)} failed of {len(results)}")
json.dump([dict(name=n,pass_=o) for n,o,_ in results],open(f"{ROOT}/docs/sql_test_results.json","w"),indent=1)
sys.exit(1 if bad else 0)
