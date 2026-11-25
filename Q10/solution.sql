-- ICT371 Advanced Databases — Test 3
-- Mukonta Davis | Student Number: 202401475
-- Question 10: Scholarship Application Assessment
-- Run this question independently in PostgreSQL.

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



Question 10: Scholarship Application Assessment
(a) Tables and sample data
  CREATE TABLE students(student_id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   student_number varchar(30) UNIQUE NOT NULL,full_name varchar(120) NOT NULL);
  CREATE TABLE applications(application_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   student_id int NOT NULL REFERENCES students,age_at_application int NOT NULL CHECK(age_at_application>0),
   monthly_income numeric(12,2) NOT NULL CHECK(monthly_income>=0),
   average_mark numeric(5,2) NOT NULL CHECK(average_mark BETWEEN 0 AND 100),
   submitted_on date NOT NULL,status varchar(10) NOT NULL DEFAULT 'PENDING'
   CHECK(status IN('PENDING','APPROVED','REJECTED')));
  CREATE TABLE decision_audit(audit_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   application_id bigint NOT NULL REFERENCES applications,old_status varchar(10),
   new_status varchar(10),changed_at timestamptz DEFAULT now());
  INSERT INTO students(student_number,full_name) VALUES
  ('S001','Nalia'),('S002','Peter'),('S003','Grace');


(b) Eligibility function
  CREATE OR REPLACE FUNCTION fn_scholarship_eligible(p_age int,p_income numeric,p_mark numeric)
  RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
  BEGIN
   IF p_age IS NULL OR p_income IS NULL OR p_mark IS NULL OR p_age<=0
   OR p_income<0 OR p_mark<0 OR p_mark>100 THEN
    RAISE EXCEPTION 'Invalid eligibility input';
   END IF;
   RETURN p_age BETWEEN 18 AND 25 AND p_income<=3000 AND p_mark>=70;
  END; $$;


(c) Assessment procedure
  CREATE OR REPLACE PROCEDURE pr_assess_application(p_application_id bigint)
  LANGUAGE plpgsql AS $$
  DECLARE a record; v_status varchar(10);
  BEGIN
   SELECT * INTO a FROM applications WHERE application_id=p_application_id FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'Unknown application'; END IF;
   IF a.status<>'PENDING' THEN RAISE EXCEPTION 'Application already assessed'; END IF;
   IF fn_scholarship_eligible(a.age_at_application,a.monthly_income,a.average_mark) THEN
    v_status:='APPROVED';
   ELSE v_status:='REJECTED'; END IF;
   UPDATE applications SET status=v_status WHERE application_id=p_application_id;
  END; $$;


(d) Status audit trigger
  CREATE OR REPLACE FUNCTION trg_decision_audit_fn()
  RETURNS trigger LANGUAGE plpgsql AS $$
  BEGIN
   IF OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO decision_audit(application_id,old_status,new_status)
    VALUES(NEW.application_id,OLD.status,NEW.status);
   END IF;
   RETURN NEW;
  END; $$;
  CREATE TRIGGER applications_status_audit AFTER UPDATE OF status ON applications
  FOR EACH ROW EXECUTE FUNCTION trg_decision_audit_fn();


(e) Approved applicants and seed applications
  CREATE OR REPLACE VIEW v_approved_applicants AS
  SELECT s.student_number,s.full_name,a.average_mark,a.status
  FROM applications a JOIN students s USING(student_id)
  WHERE a.status='APPROVED';
  INSERT INTO applications(student_id,age_at_application,monthly_income,average_mark,submitted_on)
  VALUES
  (1,18,3000,70,CURRENT_DATE),(1,25,2500,85,CURRENT_DATE),
  (2,17,2000,90,CURRENT_DATE),(2,24,3001,80,CURRENT_DATE),
  (3,22,1800,69.99,CURRENT_DATE),(3,26,1000,95,CURRENT_DATE);
  CALL pr_assess_application(1); CALL pr_assess_application(2);
  CALL pr_assess_application(3); CALL pr_assess_application(4);
  CALL pr_assess_application(5); CALL pr_assess_application(6);
  SELECT * FROM v_approved_applicants;


(f) Status/date index
