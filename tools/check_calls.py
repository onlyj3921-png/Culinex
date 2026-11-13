"""Static check: named arguments at call sites of PROJECT-defined constructors/functions/methods exist in the definition,
and required named parameters are supplied. Not a compiler; regex based."""
import re, glob, sys
files=sorted(glob.glob("lib/**/*.dart",recursive=True))+sorted(glob.glob("packages/culinex_engine/lib/**/*.dart",recursive=True))
def strip(s):  # drop comments and string contents
    s=re.sub(r"//[^\n]*","",s); s=re.sub(r"/\*.*?\*/","",s,flags=re.S)
    s=re.sub(r"'(?:\\.|[^'\\\n])*'","''",s); s=re.sub(r'"(?:\\.|[^"\\\n])*"','""',s); return s
src={f:strip(open(f).read()) for f in files}
def balanced(s,i):  # s[i]=='(' -> index of matching ')'
    d=0
    for j in range(i,len(s)):
        if s[j]=="(": d+=1
        elif s[j]==")":
            d-=1
            if d==0: return j
    return -1
def top_level_split(a):
    parts=[];d=0;cur=""
    for ch in a:
        if ch in "([{<": d+=1 if ch!="<" else 0
        if ch in ")]}": d-=1
        if ch=="," and d==0: parts.append(cur); cur=""
        else: cur+=ch
    parts.append(cur); return parts
defs={}   # name -> list of (file, named:set, required:set, npos)
def parse_params(p):
    named=set();req=set();npos=0
    m=re.search(r"\{(.*)\}",p,re.S)
    if m:
        for part in top_level_split(m.group(1)):
            part=part.strip()
            if not part: continue
            nm=re.search(r"(?:this\.|super\.)?(\w+)\s*(?:=.*)?$",part.split("=")[0].strip())
            if nm: named.add(nm.group(1)); 
            if part.startswith("required"): req.add(nm.group(1))
        pos=p[:m.start()]
    else: pos=p
    opt=re.search(r"\[(.*?)\]",pos,re.S); nopt=len([x for x in top_level_split(opt.group(1)) if x.strip()]) if opt else 0
    pos=re.sub(r"\[.*?\]","",pos,flags=re.S); npos=len([x for x in top_level_split(pos) if x.strip()])
    return named,req,(npos,npos+nopt)
for f,s in src.items():
    # constructors:  const? ClassName({...});  or ClassName(this.a, ...)
    for cm in re.finditer(r"\bclass\s+(\w+)",s):
        cls=cm.group(1)
        for m in re.finditer(r"\b(?:const\s+)?(?:factory\s+)?"+cls+r"(?:\.\w+)?\s*\(",s):
            i=m.end()-1; j=balanced(s,i)
            if j<0: continue
            after=s[j+1:j+4].lstrip()
            if not (after.startswith(";") or after.startswith(":") or after.startswith("{") or after.startswith("=")): continue
            if s[max(0,m.start()-6):m.start()].strip().endswith(("new","return")): continue
            if re.match(r"(?:const\s+)?(?:factory\s+)?"+cls+r"\.fromMap",s[m.start():]) : continue
            defs.setdefault(cls,[]).append((f,)+parse_params(s[i+1:j]))
    # methods / functions with a return type
    for m in re.finditer(r"^\s*(?:static\s+)?(?:Future<[^\n=;{]*?>|[A-Za-z_][\w<>?,\s\(\)\{\}\.]*?)\s+(\w+)\s*\(",s,re.M):
        name=m.group(1)
        if name in("if","for","while","switch","catch","return","build","initState","dispose","paint","shouldRepaint") or name[0].isupper(): continue
        i=m.end()-1; j=balanced(s,i)
        if j<0: continue
        after=s[j+1:j+8].lstrip()
        if not (after.startswith("{") or after.startswith("=>") or after.startswith("async")): continue
        defs.setdefault(name,[]).append((f,)+parse_params(s[i+1:j]))
errs=[]; checked=0
for f,s in src.items():
    for name,dl in defs.items():
        if len(name)<3: continue
        for m in re.finditer(r"(?<![\w$])"+re.escape(name)+r"\s*\(",s):
            # skip declarations
            pre=s[max(0,m.start()-40):m.start()]
            if re.search(r"(class|Future<[^\n]*>|void|String|bool|int|double|Widget|Object\?)\s*$",pre) and not re.search(r"(await|return|=>|=|\()\s*$",pre): continue
            i=m.end()-1; j=balanced(s,i)
            if j<0: continue
            args=s[i+1:j]
            if 'required' in args or 'this.' in args or 'super.' in args: continue  # a declaration, not a call
            if re.search(r"\b[A-Z]\w*\??\s+[a-z]\w*\s*(?:,|\)|=|$)",args): continue  # typed parameter => declaration
            given=set(re.findall(r"(?:^|,)\s*(\w+)\s*:",re.sub(r"[\(\[\{][^\(\)\[\]\{\}]*[\)\]\}]","",args) if False else "".join(args_part+"," for args_part in [x for x in top_level_split(args)]))) 
            parts=[p.strip() for p in top_level_split(args) if p.strip()]
            givenames={re.match(r"(\w+)\s*:",p).group(1) for p in parts if re.match(r"(\w+)\s*:(?!:)",p)}
            ok=False;why=[]
            for (df,named,req,npos) in dl:
                miss=None
                miss=givenames-named; need=req-givenames
                ngiven=len([p for p in parts if not re.match(r"\w+\s*:(?!:)",p)])
                arity_ok=npos[0]<=ngiven<=npos[1]
                if not miss and not need and arity_ok: ok=True;break
                if not arity_ok: miss=miss+[f"arity {ngiven} vs {npos}"] if isinstance(miss,list) else sorted(miss)+[f"arity {ngiven} vs {npos}"]
                why.append((sorted(miss),sorted(need)))
            checked+=1
            if not ok:
                errs.append(f"{f}:{s[:m.start()].count(chr(10))+1}: {name}(...) bad named args {why[0]}")
print(f"{checked} call sites checked against {len(defs)} project definitions")
for e in sorted(set(errs)): print("ISSUE",e)
sys.exit(1 if errs else 0)
