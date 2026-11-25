-- ICT371 Advanced Databases — Test 3
-- Mukonta Davis | Student Number: 202401475
-- Question 7: Water Meter Readings and Billing
-- Run this question independently in PostgreSQL.

<PARSED TEXT FOR PAGE: 9 / 13>
(a) Tables and sample data
  CREATE TABLE customers(customer_id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,full_name varchar(120) NOT NULL);
  CREATE TABLE readings(reading_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   customer_id int NOT NULL REFERENCES customers,reading_month date NOT NULL,
   previous_reading numeric(12,2) NOT NULL CHECK(previous_reading>=0),
   current_reading numeric(12,2) NOT NULL CHECK(current_reading>=0),
   UNIQUE(customer_id,reading_month),CHECK(reading_month=date_trunc('month',reading_month)::date));
  CREATE TABLE bills(bill_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   reading_id bigint UNIQUE NOT NULL REFERENCES readings,charge numeric(12,2) NOT NULL CHECK(charge>=0),
   amount_paid numeric(12,2) NOT NULL DEFAULT 0 CHECK(amount_paid>=0 AND amount_paid<=charge),
   due_on date NOT NULL);
  CREATE TABLE receivable_snapshot(snapshot_date date PRIMARY KEY,total_due numeric(14,2) NOT NULL);
  INSERT INTO customers(full_name) VALUES('Customer A'),('Customer B'),('Customer C');

(b) Tariff function
  CREATE OR REPLACE FUNCTION fn_water_charge(p_units numeric)
  RETURNS numeric(12,2) LANGUAGE plpgsql IMMUTABLE AS $$
  BEGIN
   IF p_units IS NULL OR p_units<0 THEN RAISE EXCEPTION 'Invalid consumption'; END IF;
   RETURN ROUND(LEAST(p_units,10)*5+GREATEST(p_units-10,0)*8,2);
  END; $$;

(c) Bill generation
  CREATE OR REPLACE PROCEDURE pr_generate_bill(p_reading_id bigint,p_due_on date)
  LANGUAGE plpgsql AS $$
  DECLARE prev numeric; curr numeric;
  BEGIN
   SELECT previous_reading,current_reading INTO prev,curr FROM readings
   WHERE reading_id=p_reading_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'Unknown reading'; END IF;
   IF EXISTS(SELECT 1 FROM bills WHERE reading_id=p_reading_id) THEN
    RAISE EXCEPTION 'Bill already exists';
   END IF;
   INSERT INTO bills(reading_id,charge,amount_paid,due_on)
   VALUES(p_reading_id,fn_water_charge(curr-prev),0,p_due_on);
  END; $$;

(d) Reading validation trigger
  CREATE OR REPLACE FUNCTION trg_reading_check_fn()
  RETURNS trigger LANGUAGE plpgsql AS $$
  BEGIN
   IF NEW.current_reading<NEW.previous_reading THEN
    RAISE EXCEPTION 'Current reading cannot be below previous reading';
   END IF;
   RETURN NEW;
  END; $$;
  CREATE TRIGGER readings_check BEFORE INSERT OR UPDATE ON readings
  FOR EACH ROW EXECUTE FUNCTION trg_reading_check_fn();

(e) Overdue view and sample data
  CREATE OR REPLACE VIEW v_overdue_bills AS
  SELECT c.full_name,b.due_on,b.charge-b.amount_paid AS outstanding_amount
  FROM bills b JOIN readings r USING(reading_id) JOIN customers c USING(customer_id)
  WHERE b.due_on<CURRENT_DATE AND b.amount_paid<b.charge;
  INSERT INTO readings(customer_id,reading_month,previous_reading,current_reading) VALUES
  (1,DATE '2026-09-01',0,0),(1,DATE '2026-10-01',0,10),
  (2,DATE '2026-09-01',10,25),(2,DATE '2026-10-01',25,30),
  (3,DATE '2026-09-01',5,20),(3,DATE '2026-10-01',20,20);
  CALL pr_generate_bill(1,CURRENT_DATE-5);
  CALL pr_generate_bill(2,CURRENT_DATE-5);
  CALL pr_generate_bill(3,CURRENT_DATE+10);

(f) Overdue index and query plan
  CREATE INDEX idx_bills_due_on ON bills(due_on);
  EXPLAIN SELECT * FROM bills WHERE due_on<CURRENT_DATE AND amount_paid<charge;

(g) Receivables snapshot
  CREATE OR REPLACE PROCEDURE pr_refresh_receivables()
  LANGUAGE plpgsql AS $$
  BEGIN
   INSERT INTO receivable_snapshot(snapshot_date,total_due)
   SELECT CURRENT_DATE,COALESCE(SUM(charge-amount_paid),0)
   FROM bills WHERE amount_paid<charge
   ON CONFLICT(snapshot_date) DO UPDATE SET total_due=EXCLUDED.total_due;
  END; $$;
  SELECT cron.schedule('refresh-receivables','30 0 * * *',
   $$CALL pr_refresh_receivables()$$);
