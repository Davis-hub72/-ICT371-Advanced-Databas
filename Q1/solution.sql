-- ICT371 Advanced Databases — Test 3
-- Mukonta Davis | Student Number: 202401475
-- Question 1: Pharmacy Stock and Daily Sales
-- Run this question independently in PostgreSQL.

(a) Tables and sample data
  CREATE TABLE medicines (
   medicine_id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   medicine_name varchar(100) NOT NULL,
   unit_price numeric(10,2) NOT NULL CHECK (unit_price > 0),
   stock_qty integer NOT NULL CHECK (stock_qty >= 0)
  );
  CREATE TABLE sales (
   sale_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   medicine_id integer NOT NULL REFERENCES medicines,
   quantity integer NOT NULL CHECK (quantity > 0),
   unit_price numeric(10,2) NOT NULL CHECK (unit_price > 0),
   sold_on date NOT NULL
  );
  CREATE TABLE stock_audit (
   audit_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   medicine_id integer NOT NULL REFERENCES medicines,
   old_qty integer NOT NULL, new_qty integer NOT NULL,
   changed_at timestamptz NOT NULL DEFAULT now()
  );
  CREATE TABLE daily_sales (
   sales_date date PRIMARY KEY, total_qty bigint NOT NULL,
   total_amount numeric(14,2) NOT NULL
  );
  INSERT INTO medicines(medicine_name,unit_price,stock_qty)
  VALUES ('Paracetamol',2.50,100),('Amoxicillin',8.00,60),('Vitamin C',1.75,40);

(b) Price function
  CREATE OR REPLACE FUNCTION fn_sale_value(p_medicine_id int,p_quantity int)
  RETURNS numeric(14,2) LANGUAGE plpgsql AS $$
  DECLARE v_price numeric(10,2);
  BEGIN
   IF p_quantity IS NULL OR p_quantity <= 0 THEN
     RAISE EXCEPTION 'Quantity must be positive';
   END IF;
   SELECT unit_price INTO v_price FROM medicines WHERE medicine_id=p_medicine_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'Unknown medicine'; END IF;
   RETURN v_price*p_quantity;
  END; $$;

(c) Sale procedure
  CREATE OR REPLACE PROCEDURE pr_record_sale(p_medicine_id int,p_quantity int,p_sold_on date)
  LANGUAGE plpgsql AS $$
  DECLARE v_price numeric(10,2); v_stock int;
  BEGIN
   IF p_quantity IS NULL OR p_quantity<=0 OR p_sold_on IS NULL THEN
     RAISE EXCEPTION 'Invalid sale details';
   END IF;
   SELECT unit_price,stock_qty INTO v_price,v_stock
   FROM medicines WHERE medicine_id=p_medicine_id FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Unknown medicine'; END IF;
   IF v_stock<p_quantity THEN RAISE EXCEPTION 'Insufficient stock'; END IF;
   INSERT INTO sales(medicine_id,quantity,unit_price,sold_on)
   VALUES(p_medicine_id,p_quantity,v_price,p_sold_on);
   UPDATE medicines SET stock_qty=stock_qty-p_quantity
   WHERE medicine_id=p_medicine_id;
  END; $$;

(d) Stock audit trigger
  CREATE OR REPLACE FUNCTION trg_stock_audit_fn()
  RETURNS trigger LANGUAGE plpgsql AS $$
  BEGIN
   IF OLD.stock_qty IS DISTINCT FROM NEW.stock_qty THEN
     INSERT INTO stock_audit(medicine_id,old_qty,new_qty)
     VALUES(NEW.medicine_id,OLD.stock_qty,NEW.stock_qty);

<PARSED TEXT FOR PAGE: 3 / 13>
   END IF;
   RETURN NEW;
  END; $$;
  CREATE TRIGGER medicines_stock_audit
  AFTER UPDATE OF stock_qty ON medicines
  FOR EACH ROW EXECUTE FUNCTION trg_stock_audit_fn();

(e) View and sample sales
  CREATE OR REPLACE VIEW v_low_stock AS
  SELECT medicine_id,medicine_name,unit_price,stock_qty
  FROM medicines WHERE stock_qty<10;
  CALL pr_record_sale(1,5,CURRENT_DATE);
  SELECT * FROM v_low_stock;

(f) Index and EXPLAIN
  CREATE INDEX idx_sales_medicine_date ON sales(medicine_id,sold_on);
  EXPLAIN SELECT * FROM sales
  WHERE medicine_id=1 AND sold_on BETWEEN DATE '2026-01-01' AND DATE '2026-01-31';
  -- medicine_id is matched first, followed by the sold_on range.

(g) Daily refresh and schedule
  CREATE OR REPLACE PROCEDURE pr_refresh_sales(p_day date)
  LANGUAGE plpgsql AS $$
  BEGIN
   INSERT INTO daily_sales(sales_date,total_qty,total_amount)
   SELECT p_day,COALESCE(SUM(quantity),0),
           COALESCE(SUM(quantity*unit_price),0)
   FROM sales WHERE sold_on=p_day
   ON CONFLICT(sales_date) DO UPDATE SET
   total_qty=EXCLUDED.total_qty,total_amount=EXCLUDED.total_amount;
  END; $$;
  CREATE EXTENSION IF NOT EXISTS pg_cron;
  SELECT cron.schedule('refresh-pharmacy-sales','15 0 * * *',
   $$CALL pr_refresh_sales(CURRENT_DATE-1)$$);
