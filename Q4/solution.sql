-- ICT371 Advanced Databases — Test 3
-- Mukonta Davis | Student Number: 202401475
-- Question 4: Clinic Appointment Scheduling
-- Run this question independently in PostgreSQL.

(a) Tables and sample data
  CREATE TABLE patients(patient_id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,full_name varchar(120) NOT NULL);
  CREATE TABLE doctors(doctor_id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,full_name varchar(120) NOT NULL);
  CREATE TABLE appointments(
   appointment_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   patient_id int NOT NULL REFERENCES patients,doctor_id int NOT NULL REFERENCES doctors,
   appointment_day date NOT NULL,slot_time time NOT NULL,
   status varchar(10) NOT NULL CHECK(status IN('BOOKED','ATTENDED','CANCELLED')),
   CHECK(slot_time IN(TIME '09:00',TIME '10:00',TIME '11:00',TIME '12:00'))
  );
  CREATE UNIQUE INDEX uq_doctor_day_slot_active ON appointments(doctor_id,appointment_day,slot_time)
  WHERE status<>'CANCELLED';
  CREATE TABLE clinic_summary(summary_date date PRIMARY KEY,booked_count bigint,attended_count bigint,cancelled_count bigint);
  INSERT INTO patients(full_name) VALUES('Alice'),('Benson'),('Chanda');
  INSERT INTO doctors(full_name) VALUES('Dr Banda'),('Dr Phiri'),('Dr Zulu');

(b) Daily load function
  CREATE OR REPLACE FUNCTION fn_daily_load(p_doctor_id int,p_day date)
  RETURNS bigint LANGUAGE plpgsql AS $$
  DECLARE n bigint;
  BEGIN

<PARSED TEXT FOR PAGE: 6 / 13>
   IF NOT EXISTS(SELECT 1 FROM doctors WHERE doctor_id=p_doctor_id) THEN
    RAISE EXCEPTION 'Unknown doctor';
   END IF;
   SELECT COUNT(*) INTO n FROM appointments
   WHERE doctor_id=p_doctor_id AND appointment_day=p_day AND status<>'CANCELLED';
   RETURN n;
  END; $$;

(c) Booking procedure
  CREATE OR REPLACE PROCEDURE pr_book_appointment(p_patient_id int,p_doctor_id int,p_day date,p_slot time)
  LANGUAGE plpgsql AS $$
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM patients WHERE patient_id=p_patient_id) OR
      NOT EXISTS(SELECT 1 FROM doctors WHERE doctor_id=p_doctor_id) THEN
    RAISE EXCEPTION 'Unknown patient or doctor';
   END IF;
   IF p_day<CURRENT_DATE OR p_slot NOT IN(TIME '09:00',TIME '10:00',TIME '11:00',TIME '12:00') THEN
    RAISE EXCEPTION 'Past date or unsupported slot';
   END IF;
   INSERT INTO appointments(patient_id,doctor_id,appointment_day,slot_time,status)
   VALUES(p_patient_id,p_doctor_id,p_day,p_slot,'BOOKED');
  END; $$;

(d) Clash enforcement
  -- The partial unique index above enforces the rule even for direct SQL and concurrent inserts.
  -- It also allows multiple CANCELLED appointments in the same slot.

(e) Today's view and six appointments
  CREATE OR REPLACE VIEW v_today_appointments AS
  SELECT a.appointment_day,a.slot_time,p.full_name AS patient_name,d.full_name AS doctor_name
  FROM appointments a JOIN patients p USING(patient_id) JOIN doctors d USING(doctor_id)
  WHERE a.appointment_day=CURRENT_DATE AND a.status='BOOKED';
  CALL pr_book_appointment(1,1,CURRENT_DATE,TIME '09:00');
  CALL pr_book_appointment(2,1,CURRENT_DATE,TIME '10:00');
  CALL pr_book_appointment(3,2,CURRENT_DATE,TIME '09:00');
  CALL pr_book_appointment(1,2,CURRENT_DATE,TIME '11:00');
  CALL pr_book_appointment(2,3,CURRENT_DATE,TIME '12:00');
  CALL pr_book_appointment(3,3,CURRENT_DATE,TIME '10:00');
  SELECT * FROM v_today_appointments;

(f) Index and query plan
  CREATE INDEX idx_appointments_day_doctor ON appointments(appointment_day,doctor_id);
  EXPLAIN SELECT * FROM appointments
  WHERE appointment_day=CURRENT_DATE AND doctor_id=1;

(g) Daily clinic summary
  CREATE OR REPLACE PROCEDURE pr_refresh_clinic_summary(p_day date)
  LANGUAGE plpgsql AS $$
  BEGIN
   INSERT INTO clinic_summary
   SELECT p_day,
    COUNT(*) FILTER(WHERE status='BOOKED'),
    COUNT(*) FILTER(WHERE status='ATTENDED'),
    COUNT(*) FILTER(WHERE status='CANCELLED')
   FROM appointments WHERE appointment_day=p_day
   ON CONFLICT(summary_date) DO UPDATE SET
   booked_count=EXCLUDED.booked_count,attended_count=EXCLUDED.attended_count,
   cancelled_count=EXCLUDED.cancelled_count;
  END; $$;
  SELECT cron.schedule('refresh-clinic','0 1 * * *',
   $$CALL pr_refresh_clinic_summary(CURRENT_DATE-1)$$);
