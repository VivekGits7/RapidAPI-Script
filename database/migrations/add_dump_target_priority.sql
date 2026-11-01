-- Popular-first crawl order. The runner claims targets by priority (1 = most listed on
-- ContactCars), then A→Z for rows without one. Existing targets keep NULL, so their
-- order and status do not change. Safe to run more than once.

ALTER TABLE rapid_api_dump_targets ADD COLUMN IF NOT EXISTS priority INT;
