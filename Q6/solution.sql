-- ICT371 Advanced Databases — Test 3
-- Mukonta Davis | Student Number: 202401475
-- Question 6: Monthly Payroll Processing
-- Run this question independently in PostgreSQL.

<PARSED TEXT FOR PAGE: 8 / 13>
(a) Tables and sample data
  CREATE TABLE employees(employee_id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   full_name varchar(120) NOT NULL,basic_salary numeric(12,2) NOT NULL CHECK(basic_salary>=0),
   allowance numeric(12,2) NOT NULL CHECK(allowance>=0),
   deduction numeric(12,2) NOT NULL CHECK(deduction>=0),active boolean NOT NULL DEFAULT true);
  CREATE TABLE payroll(payroll_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   employee_id int NOT NULL REFERENCES employees,pay_month date NOT NULL,
   gross_pay numeric(12,2) NOT NULL,net_pay numeric(12,2) NOT NULL,
   UNIQUE(employee_id,pay_month),CHECK(pay_month=date_trunc('month',pay_month)::date));
  CREATE TABLE salary_audit(audit_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   employee_id int NOT NULL REFERENCES employees,old_salary numeric(12,2),
   new_salary numeric(12,2),changed_at timestamptz DEFAULT now());
  INSERT INTO employees(full_name,basic_salary,allowance,deduction,active) VALUES
  ('Moses',5000,500,300,true),('Rita',6000,700,400,true),('Paul',4500,300,200,false);

(b) Net pay function
  CREATE OR REPLACE FUNCTION fn_net_pay(p_employee_id int)
  RETURNS numeric(12,2) LANGUAGE plpgsql AS $$
  DECLARE b numeric; a numeric; d numeric; n numeric;
  BEGIN
   SELECT basic_salary,allowance,deduction INTO b,a,d FROM employees
   WHERE employee_id=p_employee_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'Unknown employee'; END IF;
   n:=b+a-d;
   IF n<0 THEN RAISE EXCEPTION 'Computed net pay is negative'; END IF;
   RETURN n;
  END; $$;

(c) Payroll procedure
  CREATE OR REPLACE PROCEDURE pr_process_payroll(p_month date)
  LANGUAGE plpgsql AS $$
  DECLARE e record; v_gross numeric(12,2); v_net numeric(12,2);
  BEGIN
   IF p_month IS NULL OR p_month<>date_trunc('month',p_month)::date THEN
    RAISE EXCEPTION 'Pay month must be the first day of a month';
   END IF;
   FOR e IN SELECT * FROM employees WHERE active LOOP
    v_gross:=e.basic_salary+e.allowance;
    v_net:=fn_net_pay(e.employee_id);
    INSERT INTO payroll(employee_id,pay_month,gross_pay,net_pay)
    VALUES(e.employee_id,p_month,v_gross,v_net)
    ON CONFLICT(employee_id,pay_month) DO NOTHING;
   END LOOP;
  END; $$;

(d) Salary audit trigger
  CREATE OR REPLACE FUNCTION trg_salary_audit_fn()
  RETURNS trigger LANGUAGE plpgsql AS $$
  BEGIN
   IF OLD.basic_salary IS DISTINCT FROM NEW.basic_salary THEN
    INSERT INTO salary_audit(employee_id,old_salary,new_salary)
    VALUES(NEW.employee_id,OLD.basic_salary,NEW.basic_salary);
   END IF;
   RETURN NEW;
  END; $$;
  CREATE TRIGGER employees_salary_audit AFTER UPDATE OF basic_salary ON employees
  FOR EACH ROW EXECUTE FUNCTION trg_salary_audit_fn();

(e) Report view and example runs
  CREATE OR REPLACE VIEW v_payroll_report AS
  SELECT e.full_name,p.pay_month,p.gross_pay,p.net_pay
  FROM payroll p JOIN employees e USING(employee_id);
  CALL pr_process_payroll(DATE '2026-10-01');
  CALL pr_process_payroll(DATE '2026-11-01');
  SELECT * FROM v_payroll_report;

(f) Month index
  CREATE INDEX idx_payroll_month ON payroll(pay_month);
  EXPLAIN SELECT * FROM payroll WHERE pay_month=DATE '2026-10-01';

(g) Monthly schedule and job history
  -- At 02:00 on day 1, process the previous month's first date.
  SELECT cron.schedule('monthly-payroll','0 2 1 * *',
   $$CALL pr_process_payroll((date_trunc('month',CURRENT_DATE)-interval '1 month')::date)$$);
  -- Inspect configured jobs and execution history:
  SELECT * FROM cron.job;
  SELECT * FROM cron.job_run_details ORDER BY start_time DESC;
