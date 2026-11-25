-- ICT371 Advanced Databases — Test 3
-- Mukonta Davis | Student Number: 202401475
-- Question 2: University Fee Payments
-- Run this question independently in PostgreSQL.

(a) Tables and seed records
  CREATE TABLE students(
   student_id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   student_number varchar(30) UNIQUE NOT NULL,
   full_name varchar(120) NOT NULL,
   fee_due numeric(12,2) NOT NULL CHECK(fee_due>=0)
  );
  CREATE TABLE payments(
   payment_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   student_id int NOT NULL REFERENCES students,
   amount numeric(12,2) NOT NULL CHECK(amount>0), paid_on date NOT NULL
  );
  CREATE TABLE payment_audit(
   audit_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   payment_id bigint NOT NULL REFERENCES payments,
   student_id int NOT NULL REFERENCES students,
   amount numeric(12,2) NOT NULL, logged_at timestamptz DEFAULT now()
  );
  CREATE TABLE daily_collections(
   collection_date date PRIMARY KEY,payment_count bigint NOT NULL,
   total_amount numeric(14,2) NOT NULL
  );
  INSERT INTO students(student_number,full_name,fee_due) VALUES
  ('ST001','Amina Phiri',5000),('ST002','Brian Zulu',3500),('ST003','Chipo Banda',4200);

(b) Balance function
  CREATE OR REPLACE FUNCTION fn_fee_balance(p_student_id int)
  RETURNS numeric(12,2) LANGUAGE plpgsql AS $$
  DECLARE v_due numeric(12,2); v_paid numeric(12,2);
  BEGIN
   SELECT fee_due INTO v_due FROM students WHERE student_id=p_student_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'Unknown student'; END IF;
   SELECT COALESCE(SUM(amount),0) INTO v_paid FROM payments WHERE student_id=p_student_id;
   RETURN v_due-v_paid;
  END; $$;

(c) Payment procedure
  CREATE OR REPLACE PROCEDURE pr_receive_payment(p_student_id int,p_amount numeric,p_paid_on date)
  LANGUAGE plpgsql AS $$
  DECLARE v_balance numeric(12,2);
  BEGIN
   IF p_amount IS NULL OR p_amount<=0 OR p_paid_on IS NULL THEN
     RAISE EXCEPTION 'Payment amount and date must be valid';
   END IF;
   SELECT fn_fee_balance(p_student_id) INTO v_balance;

<PARSED TEXT FOR PAGE: 4 / 13>
   IF p_amount>v_balance THEN RAISE EXCEPTION 'Payment exceeds outstanding balance'; END IF;
   INSERT INTO payments(student_id,amount,paid_on) VALUES(p_student_id,p_amount,p_paid_on);
  END; $$;

(d) Automatic audit trigger
  CREATE OR REPLACE FUNCTION trg_payment_audit_fn()
  RETURNS trigger LANGUAGE plpgsql AS $$
  BEGIN
   INSERT INTO payment_audit(payment_id,student_id,amount)
   VALUES(NEW.payment_id,NEW.student_id,NEW.amount);
   RETURN NEW;
  END; $$;
  CREATE TRIGGER payments_audit AFTER INSERT ON payments
  FOR EACH ROW EXECUTE FUNCTION trg_payment_audit_fn();

(e) Fee balance view and sample payments
  CREATE OR REPLACE VIEW v_fee_balances AS
  SELECT s.student_number,s.full_name,
         s.fee_due-COALESCE(SUM(p.amount),0) AS outstanding_balance
  FROM students s LEFT JOIN payments p ON p.student_id=s.student_id
  GROUP BY s.student_id,s.student_number,s.full_name,s.fee_due
  HAVING s.fee_due-COALESCE(SUM(p.amount),0)>0;
  -- Student 3 intentionally starts with no payments.
  CALL pr_receive_payment(1,500,CURRENT_DATE);
  CALL pr_receive_payment(1,250,CURRENT_DATE);
  CALL pr_receive_payment(2,300,CURRENT_DATE);
  CALL pr_receive_payment(2,200,CURRENT_DATE);
  CALL pr_receive_payment(1,150,CURRENT_DATE);
  CALL pr_receive_payment(2,100,CURRENT_DATE);
  SELECT * FROM v_fee_balances;

(f) Composite index
  CREATE INDEX idx_payments_student_date ON payments(student_id,paid_on);
  EXPLAIN SELECT * FROM payments WHERE student_id=1
  AND paid_on BETWEEN DATE '2026-01-01' AND DATE '2026-01-31';

(g) Daily collections job
  CREATE OR REPLACE PROCEDURE pr_refresh_collections(p_day date)
  LANGUAGE plpgsql AS $$
  BEGIN
   INSERT INTO daily_collections(collection_date,payment_count,total_amount)
   SELECT p_day,COUNT(*),COALESCE(SUM(amount),0)
   FROM payments WHERE paid_on=p_day
   ON CONFLICT(collection_date) DO UPDATE SET
   payment_count=EXCLUDED.payment_count,total_amount=EXCLUDED.total_amount;
  END; $$;
  SELECT cron.schedule('refresh-fees','0 1 * * *',
   $$CALL pr_refresh_collections(CURRENT_DATE-1)$$);
