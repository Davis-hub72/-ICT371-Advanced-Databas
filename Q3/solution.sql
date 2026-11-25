-- ICT371 Advanced Databases — Test 3
-- Mukonta Davis | Student Number: 202401475
-- Question 3: Library Returns and Overdue Fines
-- Run this question independently in PostgreSQL.

(a) Tables and sample data
  CREATE TABLE books(book_id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,title varchar(150) NOT NULL);
  CREATE TABLE loans(
   loan_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   book_id int NOT NULL REFERENCES books, borrower_name varchar(120) NOT NULL,
   borrowed_on date NOT NULL,due_on date NOT NULL,returned_on date,
   fine_amount numeric(10,2) NOT NULL DEFAULT 0 CHECK(fine_amount>=0),
   CHECK(due_on>=borrowed_on),CHECK(returned_on IS NULL OR returned_on>=borrowed_on)
  );
  CREATE TABLE loan_audit(
   audit_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   loan_id bigint NOT NULL REFERENCES loans,old_returned_on date,new_returned_on date,
   changed_at timestamptz DEFAULT now()
  );
  CREATE TABLE overdue_summary(snapshot_date date PRIMARY KEY,overdue_count bigint,total_fine numeric(14,2));
  INSERT INTO books(title) VALUES('Database Systems'),('SQL Fundamentals'),('Computer Networks');

(b) Fine function
  CREATE OR REPLACE FUNCTION fn_loan_fine(p_loan_id bigint,p_as_of date)
  RETURNS numeric(10,2) LANGUAGE plpgsql AS $$
  DECLARE v_due date; v_return date; v_end date;
  BEGIN
   SELECT due_on,returned_on INTO v_due,v_return FROM loans WHERE loan_id=p_loan_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'Unknown loan'; END IF;
   v_end:=LEAST(COALESCE(v_return,p_as_of),p_as_of);
   RETURN GREATEST(v_end-v_due,0)*2.00;
  END; $$;

(c) Return procedure
  CREATE OR REPLACE PROCEDURE pr_return_loan(p_loan_id bigint,p_returned_on date)

<PARSED TEXT FOR PAGE: 5 / 13>
  LANGUAGE plpgsql AS $$
  DECLARE v_borrowed date; v_due date; v_return date;
  BEGIN
   SELECT borrowed_on,due_on,returned_on INTO v_borrowed,v_due,v_return
   FROM loans WHERE loan_id=p_loan_id FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Unknown loan'; END IF;
   IF v_return IS NOT NULL THEN RAISE EXCEPTION 'Loan already returned'; END IF;
   IF p_returned_on IS NULL OR p_returned_on<v_borrowed THEN
     RAISE EXCEPTION 'Invalid return date';
   END IF;
   UPDATE loans SET returned_on=p_returned_on,
   fine_amount=GREATEST(p_returned_on-v_due,0)*2.00 WHERE loan_id=p_loan_id;
  END; $$;

(d) Return-date audit trigger
  CREATE OR REPLACE FUNCTION trg_loan_audit_fn()
  RETURNS trigger LANGUAGE plpgsql AS $$
  BEGIN
   IF OLD.returned_on IS DISTINCT FROM NEW.returned_on THEN
    INSERT INTO loan_audit(loan_id,old_returned_on,new_returned_on)
    VALUES(NEW.loan_id,OLD.returned_on,NEW.returned_on);
   END IF;
   RETURN NEW;
  END; $$;
  CREATE TRIGGER loans_return_audit AFTER UPDATE OF returned_on ON loans
  FOR EACH ROW EXECUTE FUNCTION trg_loan_audit_fn();

(e) Overdue view and examples
  CREATE OR REPLACE VIEW v_overdue_loans AS
  SELECT b.title,l.borrower_name,l.due_on,fn_loan_fine(l.loan_id,CURRENT_DATE) AS fine_as_of_today
  FROM loans l JOIN books b USING(book_id)
  WHERE l.returned_on IS NULL AND l.due_on<CURRENT_DATE;
  -- Example six loans, including overdue, due-today/on-time, and returned cases:
  INSERT INTO loans(book_id,borrower_name,borrowed_on,due_on,returned_on,fine_amount) VALUES
  (1,'John',CURRENT_DATE-20,CURRENT_DATE-10,NULL,0),
  (2,'Mary',CURRENT_DATE-8,CURRENT_DATE,CURRENT_DATE,0),
  (3,'Peter',CURRENT_DATE-15,CURRENT_DATE-5,CURRENT_DATE-2,6),
  (1,'Ruth',CURRENT_DATE-4,CURRENT_DATE+3,NULL,0),
  (2,'James',CURRENT_DATE-12,CURRENT_DATE-2,NULL,0),
  (3,'Lydia',CURRENT_DATE-6,CURRENT_DATE+1,NULL,0);
  SELECT * FROM v_overdue_loans;

(f) Index
  CREATE INDEX idx_loans_book_returned ON loans(book_id,returned_on);
  EXPLAIN SELECT * FROM loans WHERE book_id=1 AND returned_on IS NULL;

(g) Overdue snapshot
  CREATE OR REPLACE PROCEDURE pr_refresh_overdue(p_as_of date)
  LANGUAGE plpgsql AS $$
  BEGIN
   INSERT INTO overdue_summary(snapshot_date,overdue_count,total_fine)
   SELECT p_as_of,COUNT(*),COALESCE(SUM(GREATEST(p_as_of-due_on,0)*2.00),0)
   FROM loans WHERE returned_on IS NULL AND due_on<p_as_of
   ON CONFLICT(snapshot_date) DO UPDATE SET
   overdue_count=EXCLUDED.overdue_count,total_fine=EXCLUDED.total_fine;
  END; $$;
  SELECT cron.schedule('refresh-overdue','10 0 * * *',
   $$CALL pr_refresh_overdue(CURRENT_DATE)$$);
