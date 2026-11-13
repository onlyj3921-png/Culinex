-- CULINEX local database, schema version 1. Statements are split on separator lines (see database.dart).
-- Money is stored as integer sen (RM x 100). Quantities of stock are in base units (g, ml, pcs).
CREATE TABLE app_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)
-- @@
INSERT INTO app_meta(key,value) VALUES('schema_version','1')
-- @@
CREATE TABLE ingredients (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL CHECK (length(trim(name)) > 0),
  family TEXT NOT NULL CHECK (family IN ('mass','volume','count')),
  pack_unit TEXT NOT NULL CHECK (pack_unit IN ('g','kg','ml','L','pcs')),
  pack_size REAL NOT NULL CHECK (pack_size > 0),
  pack_price_sen INTEGER NOT NULL CHECK (pack_price_sen >= 0),
  track_stock INTEGER NOT NULL DEFAULT 0 CHECK (track_stock IN (0,1)),
  stock_base REAL NOT NULL DEFAULT 0,
  low_stock_base REAL CHECK (low_stock_base IS NULL OR low_stock_base >= 0),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  deleted_at TEXT,
  CHECK ((pack_unit IN ('g','kg') AND family = 'mass')
      OR (pack_unit IN ('ml','L') AND family = 'volume')
      OR (pack_unit = 'pcs' AND family = 'count'))
)
-- @@
CREATE INDEX idx_ingredients_name ON ingredients(name COLLATE NOCASE)
-- @@
CREATE TABLE ingredient_price_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ingredient_id INTEGER NOT NULL REFERENCES ingredients(id),
  pack_price_sen INTEGER NOT NULL,
  pack_size REAL NOT NULL,
  pack_unit TEXT NOT NULL,
  changed_at TEXT NOT NULL DEFAULT (datetime('now'))
)
-- @@
CREATE TABLE recipes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL CHECK (length(trim(name)) > 0),
  servings REAL NOT NULL CHECK (servings > 0),
  target_margin REAL NOT NULL CHECK (target_margin >= 0 AND target_margin < 1),
  other_costs_sen INTEGER NOT NULL DEFAULT 0 CHECK (other_costs_sen >= 0),
  own_price_sen INTEGER CHECK (own_price_sen IS NULL OR own_price_sen > 0),
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  deleted_at TEXT
)
-- @@
CREATE TABLE recipe_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  recipe_id INTEGER NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
  ingredient_id INTEGER NOT NULL REFERENCES ingredients(id),
  qty REAL NOT NULL CHECK (qty >= 0),
  qty_unit TEXT NOT NULL CHECK (qty_unit IN ('g','kg','ml','L','pcs'))
)
-- @@
CREATE INDEX idx_recipe_items_recipe ON recipe_items(recipe_id)
-- @@
CREATE INDEX idx_recipe_items_ingredient ON recipe_items(ingredient_id)
-- @@
CREATE TABLE sales (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  recipe_id INTEGER REFERENCES recipes(id),
  item_name TEXT NOT NULL CHECK (length(trim(item_name)) > 0),
  quantity REAL NOT NULL CHECK (quantity > 0),
  unit_price_sen INTEGER NOT NULL CHECK (unit_price_sen >= 0),
  unit_cost_sen REAL CHECK (unit_cost_sen IS NULL OR unit_cost_sen >= 0),
  sold_on TEXT NOT NULL CHECK (sold_on GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  deleted_at TEXT
)
-- @@
CREATE INDEX idx_sales_date ON sales(sold_on)
-- @@
CREATE TABLE expenses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  category TEXT NOT NULL CHECK (category IN ('ingredients','packaging','utilities','labour','rent','delivery','marketing','equipment','other')),
  amount_sen INTEGER NOT NULL CHECK (amount_sen > 0),
  spent_on TEXT NOT NULL CHECK (spent_on GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  note TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  deleted_at TEXT
)
-- @@
CREATE INDEX idx_expenses_date ON expenses(spent_on)
-- @@
CREATE TABLE stock_movements (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ingredient_id INTEGER NOT NULL REFERENCES ingredients(id),
  kind TEXT NOT NULL CHECK (kind IN ('stock_in','stock_out','adjustment','sale_usage','void_reversal')),
  qty_base REAL NOT NULL,
  sale_id INTEGER REFERENCES sales(id),
  note TEXT,
  moved_on TEXT NOT NULL CHECK (moved_on GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  CHECK ((kind = 'stock_in' AND qty_base > 0)
      OR (kind IN ('stock_out','sale_usage') AND qty_base <= 0)
      OR (kind = 'adjustment' AND qty_base <> 0)
      OR (kind = 'void_reversal' AND qty_base >= 0))
)
-- @@
CREATE INDEX idx_stock_mov_ing ON stock_movements(ingredient_id)
-- @@
CREATE TRIGGER trg_ingredient_hist_ins AFTER INSERT ON ingredients
BEGIN
  INSERT INTO ingredient_price_history(ingredient_id,pack_price_sen,pack_size,pack_unit)
  VALUES (NEW.id, NEW.pack_price_sen, NEW.pack_size, NEW.pack_unit);
END
-- @@
CREATE TRIGGER trg_ingredient_hist_upd AFTER UPDATE ON ingredients
WHEN NEW.pack_price_sen IS NOT OLD.pack_price_sen OR NEW.pack_size IS NOT OLD.pack_size OR NEW.pack_unit IS NOT OLD.pack_unit
BEGIN
  INSERT INTO ingredient_price_history(ingredient_id,pack_price_sen,pack_size,pack_unit)
  VALUES (NEW.id, NEW.pack_price_sen, NEW.pack_size, NEW.pack_unit);
END
-- @@
CREATE TRIGGER trg_ingredient_family_lock BEFORE UPDATE OF family ON ingredients
WHEN NEW.family IS NOT OLD.family AND EXISTS (SELECT 1 FROM recipe_items WHERE ingredient_id = OLD.id)
BEGIN
  SELECT RAISE(ABORT, 'ingredient is used in recipes; unit type cannot change');
END
-- @@
CREATE TRIGGER trg_recipe_item_family_ins BEFORE INSERT ON recipe_items
BEGIN
  SELECT RAISE(ABORT, 'unit type does not match ingredient')
  WHERE (SELECT family FROM ingredients WHERE id = NEW.ingredient_id) IS NOT
        (CASE NEW.qty_unit WHEN 'g' THEN 'mass' WHEN 'kg' THEN 'mass' WHEN 'ml' THEN 'volume' WHEN 'L' THEN 'volume' WHEN 'pcs' THEN 'count' END);
END
-- @@
CREATE TRIGGER trg_recipe_item_family_upd BEFORE UPDATE ON recipe_items
BEGIN
  SELECT RAISE(ABORT, 'unit type does not match ingredient')
  WHERE (SELECT family FROM ingredients WHERE id = NEW.ingredient_id) IS NOT
        (CASE NEW.qty_unit WHEN 'g' THEN 'mass' WHEN 'kg' THEN 'mass' WHEN 'ml' THEN 'volume' WHEN 'L' THEN 'volume' WHEN 'pcs' THEN 'count' END);
END
-- @@
CREATE TRIGGER trg_stock_apply AFTER INSERT ON stock_movements
BEGIN
  UPDATE ingredients SET stock_base = stock_base + NEW.qty_base, updated_at = datetime('now') WHERE id = NEW.ingredient_id;
END
-- @@
CREATE TRIGGER trg_sale_stock AFTER INSERT ON sales
WHEN NEW.recipe_id IS NOT NULL
BEGIN
  INSERT INTO stock_movements(ingredient_id, kind, qty_base, sale_id, note, moved_on)
  SELECT ri.ingredient_id, 'sale_usage',
         -(ri.qty * (CASE ri.qty_unit WHEN 'kg' THEN 1000.0 WHEN 'L' THEN 1000.0 ELSE 1.0 END) / r.servings * NEW.quantity),
         NEW.id, 'sale: ' || NEW.item_name, NEW.sold_on
  FROM recipe_items ri
  JOIN recipes r ON r.id = ri.recipe_id
  JOIN ingredients i ON i.id = ri.ingredient_id
  WHERE ri.recipe_id = NEW.recipe_id AND i.track_stock = 1;
END
-- @@
CREATE TRIGGER trg_sale_void AFTER UPDATE OF deleted_at ON sales
WHEN OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL
BEGIN
  INSERT INTO stock_movements(ingredient_id, kind, qty_base, sale_id, note, moved_on)
  SELECT ingredient_id, 'void_reversal', -SUM(qty_base), NEW.id, 'sale voided', NEW.sold_on
  FROM stock_movements WHERE sale_id = NEW.id AND kind = 'sale_usage'
  GROUP BY ingredient_id HAVING SUM(qty_base) <> 0;
END
-- @@
CREATE VIEW v_recipe_cost AS
SELECT r.id AS recipe_id, r.name, r.servings, r.target_margin, r.other_costs_sen, r.own_price_sen,
       COALESCE(SUM(ri.qty * (CASE ri.qty_unit WHEN 'kg' THEN 1000.0 WHEN 'L' THEN 1000.0 ELSE 1.0 END)
                    * i.pack_price_sen
                    / (i.pack_size * (CASE i.pack_unit WHEN 'kg' THEN 1000.0 WHEN 'L' THEN 1000.0 ELSE 1.0 END))), 0) AS ingredient_cost_sen
FROM recipes r
LEFT JOIN recipe_items ri ON ri.recipe_id = r.id
LEFT JOIN ingredients i ON i.id = ri.ingredient_id
WHERE r.deleted_at IS NULL
GROUP BY r.id
