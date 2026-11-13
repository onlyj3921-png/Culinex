-- Named queries shared by the app and tools/test_sql.py. Parameters are positional (?).
-- name: period_totals
WITH p AS (SELECT ? AS d1, ? AS d2)
SELECT
  COALESCE((SELECT SUM(s.quantity * s.unit_price_sen) FROM sales s, p WHERE s.deleted_at IS NULL AND s.sold_on BETWEEN p.d1 AND p.d2), 0) AS revenue_sen,
  COALESCE((SELECT SUM(s.quantity * s.unit_cost_sen) FROM sales s, p WHERE s.deleted_at IS NULL AND s.unit_cost_sen IS NOT NULL AND s.sold_on BETWEEN p.d1 AND p.d2), 0) AS cogs_sen,
  COALESCE((SELECT SUM(s.quantity * s.unit_price_sen) FROM sales s, p WHERE s.deleted_at IS NULL AND s.unit_cost_sen IS NOT NULL AND s.sold_on BETWEEN p.d1 AND p.d2), 0) AS costed_revenue_sen,
  COALESCE((SELECT SUM(e.amount_sen) FROM expenses e, p WHERE e.deleted_at IS NULL AND e.spent_on BETWEEN p.d1 AND p.d2), 0) AS expenses_sen
-- name: sales_by_bucket
WITH p AS (SELECT ? AS f, ? AS d1, ? AS d2)
SELECT strftime(p.f, s.sold_on) AS bucket,
       SUM(s.quantity * s.unit_price_sen) AS revenue_sen,
       SUM(CASE WHEN s.unit_cost_sen IS NOT NULL THEN s.quantity * (s.unit_price_sen - s.unit_cost_sen) END) AS gross_profit_sen
FROM sales s, p
WHERE s.deleted_at IS NULL AND s.sold_on BETWEEN p.d1 AND p.d2
GROUP BY bucket ORDER BY bucket
-- name: expenses_by_bucket
WITH p AS (SELECT ? AS f, ? AS d1, ? AS d2)
SELECT strftime(p.f, e.spent_on) AS bucket, SUM(e.amount_sen) AS expenses_sen
FROM expenses e, p
WHERE e.deleted_at IS NULL AND e.spent_on BETWEEN p.d1 AND p.d2
GROUP BY bucket ORDER BY bucket
-- name: expenses_by_category
WITH p AS (SELECT ? AS d1, ? AS d2)
SELECT e.category, SUM(e.amount_sen) AS total_sen
FROM expenses e, p
WHERE e.deleted_at IS NULL AND e.spent_on BETWEEN p.d1 AND p.d2
GROUP BY e.category ORDER BY total_sen DESC
-- name: stock_usage
WITH p AS (SELECT ? AS d1, ? AS d2)
SELECT i.id AS ingredient_id, i.name, i.pack_unit, -SUM(m.qty_base) AS used_base
FROM stock_movements m JOIN ingredients i ON i.id = m.ingredient_id, p
WHERE m.kind IN ('sale_usage','void_reversal') AND m.moved_on BETWEEN p.d1 AND p.d2
GROUP BY i.id HAVING -SUM(m.qty_base) > 0 ORDER BY used_base DESC
-- name: inventory_value
SELECT COALESCE(SUM(i.stock_base * i.pack_price_sen /
       (i.pack_size * (CASE i.pack_unit WHEN 'kg' THEN 1000.0 WHEN 'L' THEN 1000.0 ELSE 1.0 END))), 0) AS value_sen
FROM ingredients i WHERE i.deleted_at IS NULL AND i.track_stock = 1 AND i.stock_base > 0
-- name: low_stock
SELECT id, name, pack_unit, stock_base, low_stock_base
FROM ingredients
WHERE deleted_at IS NULL AND track_stock = 1 AND low_stock_base IS NOT NULL AND stock_base <= low_stock_base
ORDER BY name COLLATE NOCASE
-- name: affected_recipes
SELECT DISTINCT r.id, r.name FROM recipes r JOIN recipe_items ri ON ri.recipe_id = r.id
WHERE ri.ingredient_id = ? AND r.deleted_at IS NULL ORDER BY r.name COLLATE NOCASE
-- name: recipe_items_detail
SELECT ri.id, ri.ingredient_id, ri.qty, ri.qty_unit, i.name AS ing_name, i.pack_price_sen, i.pack_size, i.pack_unit
FROM recipe_items ri JOIN ingredients i ON i.id = ri.ingredient_id
WHERE ri.recipe_id = ? ORDER BY ri.id
-- name: recipe_list
SELECT recipe_id, name, servings, target_margin, other_costs_sen, own_price_sen, ingredient_cost_sen
FROM v_recipe_cost WHERE name LIKE ? ORDER BY name COLLATE NOCASE
