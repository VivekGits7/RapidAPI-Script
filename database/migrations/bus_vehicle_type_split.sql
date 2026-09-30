-- Give buses their own vehicle type.
-- RapidAPI answers bus vehicles and categories only under the CV type, so every bus model
-- dumped so far was stored as CV. This retypes those models and vehicles to BUS in place, so
-- every model_id and vehicle_id stays the same, moves their category links onto a BUS copy of
-- the category tree, and removes the CV targets that are really buses so a CV run never
-- crawls them again. Data only, no schema change.
--
-- Expected on kalaaxdb, 2026-09-30:
--   134 models and 1174 vehicles retyped to BUS
--   up to 307 BUS categories created, fewer once a bus dump has already made some
--   21110 vehicle category links and 21643 article links repointed
--   3474 browse links added for the BUS categories
--   at most 1 seller listing moved onto its BUS category
--   2175 articles queued for a search key refresh
--   234 CV targets deleted, 6 CV make junctions deleted

\set ON_ERROR_STOP on

-- This server's shared memory segment is too small for parallel plans, they fail with "No space left on device"
SET max_parallel_workers_per_gather = 0;

BEGIN;

-- CV model rows whose make and model are on the bus target list
CREATE TEMP TABLE bus_models ON COMMIT DROP AS
SELECT m.model_id, m.manufacturer_id
FROM rapid_api_dump_targets b
JOIN rapid_api_manufacturers mf ON mf.manufacturers_external_id = b.tec_manufacturer_id
JOIN rapid_api_models m ON m.models_external_id = b.tec_model_id
                       AND m.manufacturer_id = mf.manufacturer_id
JOIN rapid_api_vehicle_types vt ON vt.vehicle_type_id = m.vehicle_type_id
WHERE b.vehicle_type_id = 8
  AND vt.type_code = 'CV';

CREATE TEMP TABLE bus_vehicles ON COMMIT DROP AS
SELECT v.vehicle_id
FROM rapid_api_vehicles v
JOIN bus_models USING (model_id);

-- Every CV category those vehicles link to, plus its ancestors
CREATE TEMP TABLE bus_cat_map ON COMMIT DROP AS
WITH RECURSIVE used AS (
    SELECT x.category_id FROM rapid_api_vehicle_categories x JOIN bus_vehicles USING (vehicle_id)
    UNION
    SELECT x.category_id FROM rapid_api_category_articles x JOIN bus_vehicles USING (vehicle_id)
), tree AS (
    SELECT c.category_id, c.parent_category_id, c.root_category_id
    FROM rapid_api_categories c
    JOIN used USING (category_id)
    UNION
    SELECT p.category_id, p.parent_category_id, p.root_category_id
    FROM tree t
    JOIN rapid_api_categories p ON p.category_id IN (t.parent_category_id, t.root_category_id)
)
SELECT c.category_id AS cv_category_id, c.categories_external_id, c.lang_id,
       NULL::uuid AS bus_category_id
FROM rapid_api_categories c
JOIN tree USING (category_id);

-- The (category, article) pairs those vehicles hold today, kept for the browse links and search queue
CREATE TEMP TABLE moved_pairs ON COMMIT DROP AS
SELECT DISTINCT x.category_id AS cv_category_id, x.article_id
FROM rapid_api_category_articles x
JOIN bus_vehicles USING (vehicle_id);

-- 1) BUS copy of those categories, parent and root wired in the next statement
INSERT INTO rapid_api_categories
    (category_id, categories_external_id, category_name_en, category_name_ar, level, path_en, path_ar,
     node_type, product_external_id, is_leaf, sort_order, vehicle_type_id, lang_id)
SELECT gen_random_uuid(), c.categories_external_id, c.category_name_en, c.category_name_ar, c.level,
       c.path_en, c.path_ar, c.node_type, c.product_external_id, c.is_leaf, c.sort_order,
       bus.vehicle_type_id, c.lang_id
FROM bus_cat_map m
JOIN rapid_api_categories c ON c.category_id = m.cv_category_id
CROSS JOIN (SELECT vehicle_type_id FROM rapid_api_vehicle_types WHERE type_code = 'BUS') bus
ON CONFLICT (categories_external_id, vehicle_type_id, lang_id) DO NOTHING;

UPDATE bus_cat_map m
SET bus_category_id = c.category_id
FROM rapid_api_categories c
JOIN rapid_api_vehicle_types vt ON vt.vehicle_type_id = c.vehicle_type_id AND vt.type_code = 'BUS'
WHERE c.categories_external_id = m.categories_external_id
  AND c.lang_id = m.lang_id;

-- Same rule the dumper uses: only wire a node that has no root yet
UPDATE rapid_api_categories b
SET parent_category_id = pm.bus_category_id,
    root_category_id   = rm.bus_category_id,
    updated_at         = NOW()
FROM bus_cat_map m
JOIN rapid_api_categories cv ON cv.category_id = m.cv_category_id
LEFT JOIN bus_cat_map pm ON pm.cv_category_id = cv.parent_category_id
LEFT JOIN bus_cat_map rm ON rm.cv_category_id = cv.root_category_id
WHERE b.category_id = m.bus_category_id
  AND b.root_category_id IS NULL;

-- 2) Retype the models and vehicles in place
UPDATE rapid_api_models m
SET vehicle_type_id = bus.vehicle_type_id, updated_at = NOW()
FROM (SELECT vehicle_type_id FROM rapid_api_vehicle_types WHERE type_code = 'BUS') bus
WHERE m.model_id IN (SELECT model_id FROM bus_models);

UPDATE rapid_api_vehicles v
SET vehicle_type_id = bus.vehicle_type_id, updated_at = NOW()
FROM (SELECT vehicle_type_id FROM rapid_api_vehicle_types WHERE type_code = 'BUS') bus
WHERE v.vehicle_id IN (SELECT vehicle_id FROM bus_vehicles);

-- 3) Make junctions: add BUS, drop CV where the make has no CV model left
INSERT INTO rapid_api_manufacturer_vehicle_types (mvt_id, manufacturer_id, vehicle_type_id, models_fetched_at)
SELECT gen_random_uuid(), d.manufacturer_id, bus.vehicle_type_id, NOW()
FROM (SELECT DISTINCT manufacturer_id FROM bus_models) d
CROSS JOIN (SELECT vehicle_type_id FROM rapid_api_vehicle_types WHERE type_code = 'BUS') bus
ON CONFLICT (manufacturer_id, vehicle_type_id) DO NOTHING;

DELETE FROM rapid_api_manufacturer_vehicle_types j
USING rapid_api_vehicle_types vt
WHERE vt.vehicle_type_id = j.vehicle_type_id
  AND vt.type_code = 'CV'
  AND j.manufacturer_id IN (SELECT manufacturer_id FROM bus_models)
  AND NOT EXISTS (SELECT 1 FROM rapid_api_models m
                  WHERE m.manufacturer_id = j.manufacturer_id
                    AND m.vehicle_type_id = j.vehicle_type_id);

-- 4) Repoint the vehicle links onto the BUS categories
UPDATE rapid_api_vehicle_categories x
SET category_id = m.bus_category_id
FROM bus_cat_map m
WHERE x.category_id = m.cv_category_id
  AND x.vehicle_id IN (SELECT vehicle_id FROM bus_vehicles);

UPDATE rapid_api_category_articles x
SET category_id = m.bus_category_id
FROM bus_cat_map m
WHERE x.category_id = m.cv_category_id
  AND x.vehicle_id IN (SELECT vehicle_id FROM bus_vehicles);

-- 5) Browse link table. Its triggers fire on insert and delete only, so an update needs this by hand
INSERT INTO rapid_api_category_article_links (category_id, article_id, dump_state, article_no)
SELECT DISTINCT m.bus_category_id, p.article_id, a.dump_state, a.article_no
FROM moved_pairs p
JOIN bus_cat_map m USING (cv_category_id)
JOIN rapid_api_articles a ON a.article_id = p.article_id
ON CONFLICT (category_id, article_id) DO NOTHING;

DELETE FROM rapid_api_category_article_links l
USING moved_pairs p
WHERE l.category_id = p.cv_category_id
  AND l.article_id = p.article_id
  AND NOT EXISTS (SELECT 1 FROM rapid_api_category_articles ca
                  WHERE ca.category_id = l.category_id
                    AND ca.article_id = l.article_id);

-- 6) Listings on a moved bus keep pointing at a category of the same type
UPDATE seller_products s
SET category_id = m.bus_category_id
FROM bus_cat_map m
WHERE s.category_id = m.cv_category_id
  AND (s.model_id IN (SELECT model_id FROM bus_models)
       OR s.vehicle_id IN (SELECT vehicle_id FROM bus_vehicles));

-- 7) Search keys store category ids per article, so queue the touched articles for a refresh
DO $$
BEGIN
    IF to_regclass('search_key_refresh_queue') IS NOT NULL THEN
        INSERT INTO search_key_refresh_queue (article_id, reason)
        SELECT DISTINCT article_id, 'rapid_api_category_articles' FROM moved_pairs
        ON CONFLICT (article_id) DO UPDATE SET queued_at = now(), reason = EXCLUDED.reason;
    END IF;
END $$;

-- 8) The same make and model must not stay a CV target, a CV run would crawl the bus again as a truck
DELETE FROM rapid_api_dump_targets c
USING rapid_api_dump_targets b
WHERE c.vehicle_type_id = 2
  AND b.vehicle_type_id = 8
  AND b.tec_manufacturer_id = c.tec_manufacturer_id
  AND b.tec_model_id = c.tec_model_id;

COMMIT;

-- Post checks. Expect BUS up by 134 models and 1174 vehicles, CV down to 386 models and 21025 vehicles,
-- type 8 targets unchanged at 234 in total, type 2 = 355 complete, 31 resumable, 221 pending,
-- and both leftover counts 0.
SELECT vt.type_code, COUNT(DISTINCT m.model_id) AS models, COUNT(v.vehicle_id) AS vehicles
FROM rapid_api_models m
JOIN rapid_api_vehicle_types vt ON vt.vehicle_type_id = m.vehicle_type_id
LEFT JOIN rapid_api_vehicles v ON v.model_id = m.model_id
GROUP BY 1 ORDER BY 1;

SELECT vehicle_type_id, status, COUNT(*) AS n
FROM rapid_api_dump_targets GROUP BY 1, 2 ORDER BY 1, 2;

SELECT COUNT(*) AS bus_vehicle_links_still_on_cv_categories
FROM rapid_api_vehicle_categories x
JOIN rapid_api_vehicles v ON v.vehicle_id = x.vehicle_id
JOIN rapid_api_categories c ON c.category_id = x.category_id
JOIN rapid_api_vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id AND vt.type_code = 'BUS'
WHERE v.vehicle_type_id <> c.vehicle_type_id;

SELECT COUNT(*) AS bus_article_links_still_on_cv_categories
FROM rapid_api_category_articles x
JOIN rapid_api_vehicles v ON v.vehicle_id = x.vehicle_id
JOIN rapid_api_categories c ON c.category_id = x.category_id
JOIN rapid_api_vehicle_types vt ON vt.vehicle_type_id = v.vehicle_type_id AND vt.type_code = 'BUS'
WHERE v.vehicle_type_id <> c.vehicle_type_id;
