-- ICT371 Advanced Databases — Test 3
-- Mukonta Davis | Student Number: 202401475
-- Question 5: Hostel Room Allocation
-- Run this question independently in PostgreSQL.

(a) Tables and sample data
  CREATE TABLE students(student_id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   student_number varchar(30) UNIQUE NOT NULL,full_name varchar(120) NOT NULL);
  CREATE TABLE rooms(room_id int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   room_number varchar(20) UNIQUE NOT NULL,capacity int NOT NULL CHECK(capacity>0));
  CREATE TABLE allocations(
   allocation_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
   student_id int NOT NULL REFERENCES students,room_id int NOT NULL REFERENCES rooms,
   allocated_on date NOT NULL,released_on date,
   status varchar(10) NOT NULL CHECK(status IN('ACTIVE','ENDED')),
   CHECK((status='ACTIVE' AND released_on IS NULL) OR (status='ENDED' AND released_on IS NOT NULL))
  );
  CREATE UNIQUE INDEX uq_one_active_student ON allocations(student_id) WHERE status='ACTIVE';
  CREATE TABLE occupancy_snapshot(snapshot_date date NOT NULL,room_id int NOT NULL REFERENCES rooms,
   occupied_beds int NOT NULL,free_beds int NOT NULL,
   PRIMARY KEY(snapshot_date,room_id));
  INSERT INTO students(student_number,full_name) VALUES
  ('H001','Mwamba'),('H002','Chileshe'),('H003','Lungu'),('H004','Tembo');

<PARSED TEXT FOR PAGE: 7 / 13>
  INSERT INTO rooms(room_number,capacity) VALUES('R1',2),('R2',3),('R3',1);

(b) Free beds function
  CREATE OR REPLACE FUNCTION fn_free_beds(p_room_id int)
  RETURNS int LANGUAGE plpgsql AS $$
  DECLARE v_capacity int; v_occupied int;
  BEGIN
   SELECT capacity INTO v_capacity FROM rooms WHERE room_id=p_room_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'Unknown room'; END IF;
   SELECT COUNT(*) INTO v_occupied FROM allocations
   WHERE room_id=p_room_id AND status='ACTIVE';
   RETURN v_capacity-v_occupied;
  END; $$;

(c) Allocation procedure
  CREATE OR REPLACE PROCEDURE pr_allocate_room(p_student_id int,p_room_id int,p_allocated_on date)
  LANGUAGE plpgsql AS $$
  BEGIN
   IF NOT EXISTS(SELECT 1 FROM students WHERE student_id=p_student_id) OR
      NOT EXISTS(SELECT 1 FROM rooms WHERE room_id=p_room_id) THEN
    RAISE EXCEPTION 'Unknown student or room';
   END IF;
   IF EXISTS(SELECT 1 FROM allocations WHERE student_id=p_student_id AND status='ACTIVE') THEN
    RAISE EXCEPTION 'Student already has an active allocation';
   END IF;
   -- Serialize room capacity checks by locking the room row.
   PERFORM 1 FROM rooms WHERE room_id=p_room_id FOR UPDATE;
   IF fn_free_beds(p_room_id)<=0 THEN RAISE EXCEPTION 'Room is full'; END IF;
   INSERT INTO allocations(student_id,room_id,allocated_on,status)
   VALUES(p_student_id,p_room_id,p_allocated_on,'ACTIVE');
  END; $$;

(d) Direct-SQL safeguards
  -- The partial unique index enforces one ACTIVE allocation per student.
  -- Capacity must also be enforced by a trigger in deployments with direct writes:
  CREATE OR REPLACE FUNCTION trg_allocation_capacity_fn()
  RETURNS trigger LANGUAGE plpgsql AS $$
  DECLARE cap int; occupied int;
  BEGIN
   IF NEW.status='ACTIVE' THEN
    PERFORM 1 FROM rooms WHERE room_id=NEW.room_id FOR UPDATE;
    SELECT capacity INTO cap FROM rooms WHERE room_id=NEW.room_id;
    SELECT COUNT(*) INTO occupied FROM allocations
     WHERE room_id=NEW.room_id AND status='ACTIVE'
        AND allocation_id IS DISTINCT FROM NEW.allocation_id;
    IF occupied>=cap THEN RAISE EXCEPTION 'Room capacity exceeded'; END IF;
   END IF;
   RETURN NEW;
  END; $$;
  CREATE TRIGGER allocations_capacity BEFORE INSERT OR UPDATE ON allocations
  FOR EACH ROW EXECUTE FUNCTION trg_allocation_capacity_fn();

(e) Occupancy view and sample allocations
  CREATE OR REPLACE VIEW v_room_occupancy AS
  SELECT r.room_id,r.room_number,r.capacity,
   COUNT(a.allocation_id) FILTER(WHERE a.status='ACTIVE') AS occupied_beds,
   r.capacity-COUNT(a.allocation_id) FILTER(WHERE a.status='ACTIVE') AS free_beds
  FROM rooms r LEFT JOIN allocations a USING(room_id)
  GROUP BY r.room_id,r.room_number,r.capacity;
  CALL pr_allocate_room(1,1,CURRENT_DATE);
  CALL pr_allocate_room(2,1,CURRENT_DATE);
  CALL pr_allocate_room(3,2,CURRENT_DATE);
  SELECT * FROM v_room_occupancy;

(f) Active allocation index
  CREATE INDEX idx_allocations_room_active ON allocations(room_id)
  WHERE status='ACTIVE';
  EXPLAIN SELECT * FROM allocations WHERE room_id=1 AND status='ACTIVE';

(g) Occupancy snapshot job
  CREATE OR REPLACE PROCEDURE pr_refresh_occupancy()
  LANGUAGE plpgsql AS $$
  BEGIN
   INSERT INTO occupancy_snapshot(snapshot_date,room_id,occupied_beds,free_beds)
   SELECT CURRENT_DATE,room_id,occupied_beds,free_beds FROM v_room_occupancy
   ON CONFLICT(snapshot_date,room_id) DO UPDATE SET
   occupied_beds=EXCLUDED.occupied_beds,free_beds=EXCLUDED.free_beds;
  END; $$;
  SELECT cron.schedule('refresh-hostel-occupancy','55 23 * * *',
   $$CALL pr_refresh_occupancy()$$);
