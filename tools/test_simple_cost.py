"""Regression tests for the Simple-calculator fix ("incomplete row" shown with no visible row).
Python mirror of lib/core/simple_cost.dart + the results-card guard, run against the V1.2 golden vectors, plus static
assertions on the real source files. It does NOT execute the Dart code (no Dart SDK here)."""
import json, os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.argv = [sys.argv[0], os.path.join(ROOT, "packages/culinex_engine/test/golden/calc_vectors.json")]
ns = {}; exec(open(os.path.join(ROOT, "tools/verify_engine_spec.py")).read().split("V=json.load")[0], ns)
calc = ns["calc"]
res = []
def T(name, ok, detail=""): res.append(bool(ok)); print(("PASS " if ok else "FAIL ") + name + ("" if ok else "  <-- " + str(detail)[:200]))
# ---- mirror of parseNum / classifySimpleCost (Dart semantics for the unambiguous cases used here)
NUM = re.compile(r"^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$")
def parse_num(s):
    t = s.strip().replace(",", "")
    if not t: return None
    if not NUM.match(t): return None          # also rejects Infinity / NaN (parseNum rejects non-finite)
    return float(t)
def classify(s):
    if s.strip() == "": return "empty"
    return "invalid" if parse_num(s) is None else "valid"
for s, want in [("", "empty"), (" ", "empty"), ("   ", "empty"), ("abc", "invalid"), ("RM5", "invalid"), ("5RM", "invalid"), ("1.2.3", "invalid"),
                ("-", "invalid"), ("Infinity", "invalid"), ("NaN", "invalid"), ("5", "valid"), ("24.50", "valid"), ("1,234.50", "valid"),
                (" 8 ", "valid"), ("0", "valid"), ("0.5", "valid"), ("-5", "valid")]:
    T(f"classify({s!r}) == {want}", classify(s) == want, classify(s))
# ---- screen model: what the Simple tab shows
LABELS = ["cost_per_serving", "suggested_price", "ingredient_cost", "total_recipe_cost", "price_used", "profit_per_serving", "profit_margin", "profit_per_batch"]
def simple_screen(cost_text, servings=None, margin=None, other=None, own=None):
    state = classify(cost_text)
    line = dict(name="ingredients", price=parse_num(cost_text), size=1, packUnit="pcs", used=1, usedUnit="pcs")
    rows, cells, code = calc(dict(rows=[line], servings=servings, margin=margin, other=other, own=own))
    if state != "valid":
        banner = "simple_enter_cost" if state == "empty" else "simple_cost_invalid"
        return dict(banner=banner, values=["—"] * 8, engine_status_shown=False)
    vals = [cells["E6"], cells["E7"], cells["E12"], cells["E13"], cells["E11"], cells["E8"], cells["E10" if False else "E9"], cells["E10"]]
    return dict(banner="st_" + code, values=vals, engine_status_shown=True, cells=cells, code=code)
for label, txt in [("EMPTY cost -> neutral message", ""), ("blank spaces -> neutral message", "   ")]:
    r = simple_screen(txt, 10, 0.65, 3)
    T(f"{label}: banner simple_enter_cost, all 8 results '—', no engine status", r["banner"] == "simple_enter_cost" and r["values"] == ["—"] * 8 and not r["engine_status_shown"], r)
    T(f"{label}: never shows 'Fix inputs' / incomplete (even with servings and margin filled)", "Fix inputs" not in r["values"] and "incomplete" not in r["banner"])
for txt in ["abc", "RM5", "1.2.3", "-", "Infinity", "NaN"]:
    r = simple_screen(txt, 10, 0.65, 3)
    T(f"INVALID cost {txt!r} -> red message, all 8 results '—'", r["banner"] == "simple_cost_invalid" and r["values"] == ["—"] * 8 and not r["engine_status_shown"], r)
# ---- valid path uses the unchanged engine: compare with the V1.2 golden vectors
V = {v["id"]: v for v in json.load(open(sys.argv[1]))["vectors"]}
g = V["t1"]["expected"]; inp = V["t1"]["input"]
r = simple_screen(repr(g["E12"]), inp["servings"], inp["margin"], inp["other"], inp["own"])
c = r["cells"]
def close(a, b): return abs(a - b) <= 1e-9 * max(1, abs(b))
T("VALID cost (golden sample ingredient cost) -> banner OK", r["banner"] == "st_ok", r["banner"])
T("VALID cost: E6 cost/serving, E7 suggested price, E8, E9, E10, E11, E13 equal V1.2 golden (t1)", all(close(c[k], g[k]) for k in ("E6", "E7", "E8", "E9", "E10", "E11", "E13")), {k: (c[k], g[k]) for k in ("E6", "E7", "E8")})
T("VALID cost: ingredient cost shown equals the typed value", close(c["E12"], g["E12"]))
T("VALID cost, servings empty -> engine still reports 'enter servings' (unchanged behaviour)", simple_screen("5", None, 0.65, 3)["banner"] == "st_noServings")
T("VALID cost 0 -> engine result shown (no prompt)", simple_screen("0", 1, 0.5, 0)["engine_status_shown"] and simple_screen("0", 1, 0.5, 0)["banner"] == "st_ok")
T("VALID negative cost -> engine reports the negative value (no prompt)", simple_screen("-5", 1, 0.5, 0)["banner"] == "st_negative")
# ---- strings exist in both languages
S = open(os.path.join(ROOT, "lib/core/strings.dart")).read()
en = re.search(r"_en = \{(.*?)\n\};", S, re.S).group(1); ms = re.search(r"_ms = \{(.*?)\n\};", S, re.S).group(1)
for k in ("simple_enter_cost", "simple_cost_invalid"):
    T(f"string '{k}' exists in English and Bahasa Melayu", f"  '{k}':" in en and f"  '{k}':" in ms)
# ---- static assertions on the real source
C = open(os.path.join(ROOT, "lib/ui/calculator_screen.dart")).read()
T("source: results card classifies the Simple cost field", "classifySimpleCost(_simpleIng.text)" in C)
T("source: guard applies to the Simple tab only (Advanced is never blocked)", "final costState = simple ? classifySimpleCost(_simpleIng.text) : SimpleCostState.valid;" in C)
T("source: blocked state returns '—' for every result", "costBlocked ? '—'" in C)
T("source: blocked state shows the prompt banner, otherwise the engine status banner", "costBlocked ? _simpleCostBanner(t, costState) : StatusBanner(r.status)" in C)
T("source: engine call and Simple hidden-row construction are unchanged", "name: 'ingredients'," in C and "final r = calculate(_input(simple));" in C)
T("source: Dart unit test file exists with all cases", os.path.isfile(os.path.join(ROOT, "test/simple_cost_test.dart")) and "SimpleCostState.invalid" in open(os.path.join(ROOT, "test/simple_cost_test.dart")).read())
print(f"\n{sum(res)} passed, {len(res)-sum(res)} failed of {len(res)}"); sys.exit(0 if all(res) else 1)
