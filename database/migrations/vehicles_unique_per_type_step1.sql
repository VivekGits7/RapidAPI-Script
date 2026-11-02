-- Step 1 of 2: add the per-type rule next to the old one. Nothing is dropped and no rows change.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'rapid_api_vehicles_external_id_type_key'
    ) THEN
        ALTER TABLE rapid_api_vehicles
            ADD CONSTRAINT rapid_api_vehicles_external_id_type_key UNIQUE (vehicles_external_id, vehicle_type_id);
    END IF;
END $$;
