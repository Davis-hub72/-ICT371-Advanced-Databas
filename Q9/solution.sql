-- ICT371 Advanced Databases — Test 3
-- Mukonta Davis | Student Number: 202401475
-- Question 9: Farmer Cooperative Maize Deliveries
-- Run this question independently in PostgreSQL.

(a) Tables and sample farmers
  CREATE TABLE farmers(farmer_id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   farmer_number varchar(30) UNIQUE NOT NULL,full_name varchar(120) NOT NULL);
  CREATE TABLE deliveries(delivery_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   farmer_id int NOT NULL REFERENCES farmers,grade char(1) NOT NULL CHECK(grade IN('A','B','C')),
   weight_kg numeric(12,2) NOT NULL CHECK(weight_kg>0),
   unit_rate numeric(8,2) NOT NULL DEFAULT 0,total_value numeric(14,2) NOT NULL DEFAULT 0,
   delivered_on date NOT NULL,is_paid boolean NOT NULL DEFAULT false);
  CREATE TABLE daily_purchases(purchase_date date PRIMARY KEY,total_weight numeric(14,2),total_value numeric(14,2));
  INSERT INTO farmers(farmer_number,full_name) VALUES
  ('F001','Kabwe'),('F002','Mumba'),('F003','Sakala');

(b) Grade rate function
  CREATE OR REPLACE FUNCTION fn_maize_rate(p_grade char)
  RETURNS numeric(8,2) LANGUAGE plpgsql IMMUTABLE AS $$
  BEGIN
   IF p_grade IS NULL OR p_grade NOT IN('A','B','C') THEN
    RAISE EXCEPTION 'Unsupported maize grade';
   END IF;
   RETURN CASE p_grade WHEN 'A' THEN 5.00 WHEN 'B' THEN 4.00 ELSE 3.00 END;
  END; $$;

(c) Delivery procedure
  CREATE OR REPLACE PROCEDURE pr_receive_delivery(p_farmer_id int,p_grade char,p_weight numeric,p_date date)
  LANGUAGE plpgsql AS $$
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM farmers WHERE farmer_id=p_farmer_id) THEN
    RAISE EXCEPTION 'Unknown farmer';
   END IF;
   IF p_grade IS NULL OR p_grade NOT IN('A','B','C') OR p_weight IS NULL OR p_weight<=0 OR p_date IS NULL THEN
    RAISE EXCEPTION 'Invalid delivery details';
   END IF;
   INSERT INTO deliveries(farmer_id,grade,weight_kg,delivered_on,is_paid)
   VALUES(p_farmer_id,p_grade,p_weight,p_date,false);
  END; $$;

(d) Pricing trigger
  CREATE OR REPLACE FUNCTION trg_delivery_price_fn()
  RETURNS trigger LANGUAGE plpgsql AS $$
  BEGIN
   IF NEW.weight_kg IS NULL OR NEW.weight_kg<=0 THEN
    RAISE EXCEPTION 'Weight must be positive';
   END IF;
   NEW.unit_rate:=fn_maize_rate(NEW.grade);
   NEW.total_value:=NEW.weight_kg*NEW.unit_rate;
   RETURN NEW;
  END; $$;
  CREATE TRIGGER deliveries_price BEFORE INSERT OR UPDATE ON deliveries
  FOR EACH ROW EXECUTE FUNCTION trg_delivery_price_fn();

(e) Amount due view and six deliveries
  CREATE OR REPLACE VIEW v_farmer_amount_due AS
  SELECT f.farmer_number,f.full_name,
   COALESCE(SUM(d.total_value) FILTER(WHERE d.is_paid=false),0) AS amount_due
  FROM farmers f LEFT JOIN deliveries d USING(farmer_id)
  GROUP BY f.farmer_id,f.farmer_number,f.full_name;
  CALL pr_receive_delivery(1,'A',100,CURRENT_DATE);
  CALL pr_receive_delivery(1,'B',50,CURRENT_DATE);
  CALL pr_receive_delivery(2,'C',75,CURRENT_DATE);
  CALL pr_receive_delivery(2,'A',40,CURRENT_DATE);
  CALL pr_receive_delivery(3,'B',60,CURRENT_DATE);
  CALL pr_receive_delivery(3,'C',30,CURRENT_DATE);
  UPDATE deliveries SET is_paid=true WHERE delivery_id=2;
  SELECT * FROM v_farmer_amount_due;

(f) Farmer/date index
  CREATE INDEX idx_deliveries_farmer_date ON deliveries(farmer_id,delivered_on);
  EXPLAIN SELECT * FROM deliveries WHERE farmer_id=1
  AND delivered_on BETWEEN DATE '2026-01-01' AND DATE '2026-12-31';

(g) Daily purchases
  CREATE OR REPLACE PROCEDURE pr_refresh_purchases(p_day date)

<PARSED TEXT FOR PAGE: 12 / 13>
  LANGUAGE plpgsql AS $$
  BEGIN
   INSERT INTO daily_purchases(purchase_date,total_weight,total_value)
   SELECT p_day,COALESCE(SUM(weight_kg),0),COALESCE(SUM(total_value),0)
   FROM deliveries WHERE delivered_on=p_day
   ON CONFLICT(purchase_date) DO UPDATE SET
   total_weight=EXCLUDED.total_weight,total_value=EXCLUDED.total_value;
  END; $$;
  SELECT cron.schedule('refresh-maize-purchases','30 1 * * *',
   $$CALL pr_refresh_purchases(CURRENT_DATE-1)$$);
