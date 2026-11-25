-- ICT371 Advanced Databases — Test 3
-- Mukonta Davis | Student Number: 202401475
-- Question 8: Transport Fleet Maintenance
-- Run this question independently in PostgreSQL.

<PARSED TEXT FOR PAGE: 10 / 13>
(a) Tables and sample data
  CREATE TABLE vehicles(vehicle_id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   registration varchar(30) UNIQUE NOT NULL,current_odometer numeric(12,2) NOT NULL CHECK(current_odometer>=0),
   last_service_odometer numeric(12,2) NOT NULL CHECK(last_service_odometer>=0 AND last_service_odometer<=current_odometer));
  CREATE TABLE trips(trip_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   vehicle_id int NOT NULL REFERENCES vehicles,trip_on date NOT NULL,
   start_odometer numeric(12,2) NOT NULL,end_odometer numeric(12,2) NOT NULL,
   CHECK(start_odometer>=0 AND end_odometer>start_odometer));
  CREATE TABLE service_alerts(vehicle_id int PRIMARY KEY REFERENCES vehicles,
   km_since_service numeric(12,2) NOT NULL,flagged_on date NOT NULL);
  INSERT INTO vehicles(registration,current_odometer,last_service_odometer) VALUES
  ('ABC001',10000,6000),('ABC002',25000,22000),('ABC003',50000,44000);

(b) Service due function
  CREATE OR REPLACE FUNCTION fn_service_due(p_vehicle_id int)
  RETURNS boolean LANGUAGE plpgsql AS $$
  DECLARE cur numeric; last numeric;
  BEGIN
   SELECT current_odometer,last_service_odometer INTO cur,last
   FROM vehicles WHERE vehicle_id=p_vehicle_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'Unknown vehicle'; END IF;
   RETURN cur-last>=5000;
  END; $$;

(c) Trip procedure
  CREATE OR REPLACE PROCEDURE pr_record_trip(p_vehicle_id int,p_trip_on date,p_start numeric,p_end numeric)
  LANGUAGE plpgsql AS $$
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM vehicles WHERE vehicle_id=p_vehicle_id) THEN
    RAISE EXCEPTION 'Unknown vehicle';
   END IF;
   IF p_start IS NULL OR p_end IS NULL OR p_end<=p_start THEN
    RAISE EXCEPTION 'End odometer must exceed start odometer';
   END IF;
   INSERT INTO trips(vehicle_id,trip_on,start_odometer,end_odometer)
   VALUES(p_vehicle_id,p_trip_on,p_start,p_end);
  END; $$;

(d) Trip trigger updates odometer once
  CREATE OR REPLACE FUNCTION trg_trip_odometer_fn()
  RETURNS trigger LANGUAGE plpgsql AS $$
  DECLARE v_current numeric;
  BEGIN
   SELECT current_odometer INTO v_current FROM vehicles
   WHERE vehicle_id=NEW.vehicle_id FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Unknown vehicle'; END IF;
   IF NEW.start_odometer<>v_current OR NEW.end_odometer<=NEW.start_odometer THEN
    RAISE EXCEPTION 'Trip must start at current odometer and have positive mileage';
   END IF;
   UPDATE vehicles SET current_odometer=NEW.end_odometer WHERE vehicle_id=NEW.vehicle_id;
   RETURN NEW;
  END; $$;
  CREATE TRIGGER trips_odometer BEFORE INSERT ON trips
  FOR EACH ROW EXECUTE FUNCTION trg_trip_odometer_fn();

(e) Service view and six trips
  CREATE OR REPLACE VIEW v_service_due AS
  SELECT registration,current_odometer-last_service_odometer AS km_since_service
  FROM vehicles WHERE current_odometer-last_service_odometer>=5000;
  -- Each trip starts at the vehicle's current value; procedure does not update it.
  CALL pr_record_trip(1,CURRENT_DATE,10000,11000);
  CALL pr_record_trip(1,CURRENT_DATE,11000,12000);
  CALL pr_record_trip(2,CURRENT_DATE,25000,26000);
  CALL pr_record_trip(2,CURRENT_DATE,26000,27000);
  CALL pr_record_trip(3,CURRENT_DATE,50000,51000);
  CALL pr_record_trip(3,CURRENT_DATE,51000,52000);
  SELECT * FROM v_service_due;

(f) Vehicle/date index
  CREATE INDEX idx_trips_vehicle_date ON trips(vehicle_id,trip_on);
  EXPLAIN SELECT * FROM trips WHERE vehicle_id=1
  AND trip_on BETWEEN CURRENT_DATE-30 AND CURRENT_DATE;

(g) Service alerts schedule
  CREATE OR REPLACE PROCEDURE pr_refresh_service_alerts()
  LANGUAGE plpgsql AS $$
  BEGIN
   INSERT INTO service_alerts(vehicle_id,km_since_service,flagged_on)
   SELECT vehicle_id,current_odometer-last_service_odometer,CURRENT_DATE
   FROM vehicles WHERE current_odometer-last_service_odometer>=5000
   ON CONFLICT(vehicle_id) DO UPDATE SET
   km_since_service=EXCLUDED.km_since_service,flagged_on=EXCLUDED.flagged_on;

<PARSED TEXT FOR PAGE: 11 / 13>
   DELETE FROM service_alerts a USING vehicles v
   WHERE a.vehicle_id=v.vehicle_id
   AND v.current_odometer-v.last_service_odometer<5000;
  END; $$;
  SELECT cron.schedule('refresh-service-alerts','0 6 * * 1',
   $$CALL pr_refresh_service_alerts()$$);
