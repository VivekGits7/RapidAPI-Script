-- Step 2 of 2: run only after the backend with the new ON CONFLICT is deployed on this server.
ALTER TABLE rapid_api_vehicles DROP CONSTRAINT IF EXISTS rapid_api_vehicles_vehicles_external_id_key;
