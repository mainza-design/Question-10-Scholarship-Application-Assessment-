/* #####################################################################
   QUESTION 10 - Scholarship Application Assessment
   ##################################################################### */
DROP SCHEMA IF EXISTS q10 CASCADE;
CREATE SCHEMA q10;
SET search_path TO q10, public;

-- (a) Tables ------------------------------------------------------------
CREATE TABLE students (
    student_id     SERIAL PRIMARY KEY,
    student_number VARCHAR(20) NOT NULL UNIQUE,
    full_name      VARCHAR(100) NOT NULL
);

CREATE TABLE applications (
    application_id     SERIAL PRIMARY KEY,
    student_id         INTEGER NOT NULL REFERENCES students(student_id),
    age_at_application INTEGER NOT NULL CHECK (age_at_application > 0),
    monthly_income     NUMERIC(12,2) NOT NULL CHECK (monthly_income >= 0),
    average_mark       NUMERIC(5,2) NOT NULL CHECK (average_mark BETWEEN 0 AND 100),
    submitted_on       DATE NOT NULL,
    status             VARCHAR(10) NOT NULL DEFAULT 'PENDING'
                       CHECK (status IN ('PENDING','APPROVED','REJECTED'))
);

CREATE TABLE decision_audit (
    audit_id       SERIAL PRIMARY KEY,
    application_id INTEGER NOT NULL REFERENCES applications(application_id),
    old_status     VARCHAR(10) NOT NULL,
    new_status     VARCHAR(10) NOT NULL,
    changed_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- (b) Function ----------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_scholarship_eligible(p_age INTEGER, p_income NUMERIC, p_mark NUMERIC)
RETURNS BOOLEAN LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF p_age IS NULL OR p_income IS NULL OR p_mark IS NULL THEN
        RAISE EXCEPTION 'Age, income and mark must not be NULL';
    END IF;
    IF p_age <= 0 THEN RAISE EXCEPTION 'Age must be positive, got %', p_age; END IF;
    IF p_income < 0 THEN RAISE EXCEPTION 'Income must not be negative, got %', p_income; END IF;
    IF p_mark < 0 OR p_mark > 100 THEN
        RAISE EXCEPTION 'Mark must be between 0 and 100, got %', p_mark;
    END IF;
    RETURN p_age BETWEEN 18 AND 25 AND p_income <= 3000 AND p_mark >= 70;
END $$;

-- (c) Procedure ---------------------------------------------------------
CREATE OR REPLACE PROCEDURE pr_assess_application(p_application_id INTEGER)
LANGUAGE plpgsql AS $$
DECLARE v_age INTEGER; v_income NUMERIC; v_mark NUMERIC; v_status VARCHAR(10);
BEGIN
    SELECT age_at_application, monthly_income, average_mark, status
    INTO v_age, v_income, v_mark, v_status
    FROM applications WHERE application_id = p_application_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown application_id: %', p_application_id;
    END IF;
    IF v_status <> 'PENDING' THEN
        RAISE EXCEPTION 'Application % was already assessed (status %)', p_application_id, v_status;
    END IF;
    UPDATE applications
    SET status = CASE WHEN fn_scholarship_eligible(v_age, v_income, v_mark)
                      THEN 'APPROVED' ELSE 'REJECTED' END
    WHERE application_id = p_application_id;
END $$;

-- (d) Trigger -----------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_fn_decision_audit() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO decision_audit (application_id, old_status, new_status, changed_at)
    VALUES (OLD.application_id, OLD.status, NEW.status, now());
    RETURN NULL;
END $$;

CREATE TRIGGER trg_applications_decision_audit
AFTER UPDATE ON applications
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION trg_fn_decision_audit();

-- (a) continued: seed data (six PENDING applications, 3 students) ---------
INSERT INTO students (student_number, full_name) VALUES
 ('SC001','Agnes Mbewe'), ('SC002','Bupe Kalaba'), ('SC003','Collins Mutemwa');

INSERT INTO applications (student_id, age_at_application, monthly_income, average_mark, submitted_on) VALUES
 (1, 20, 2000.00, 80.00, CURRENT_DATE - 10),  -- qualifies
 (1, 18, 3000.00, 70.00, CURRENT_DATE -  9),  -- boundary: all minimums, qualifies
 (2, 25, 3000.00, 70.00, CURRENT_DATE -  8),  -- boundary: max age, qualifies
 (2, 26, 2000.00, 85.00, CURRENT_DATE -  7),  -- too old
 (3, 22, 3001.00, 90.00, CURRENT_DATE -  6),  -- income just above limit
 (3, 21, 2500.00, 69.99, CURRENT_DATE -  5);  -- mark just below limit

SELECT fn_scholarship_eligible(20, 2000, 80) AS t, fn_scholarship_eligible(26, 2000, 85) AS f;

-- (e) View --------------------------------------------------------------
CREATE OR REPLACE VIEW v_approved_applicants AS
SELECT s.student_number, s.full_name, a.average_mark, a.status
FROM applications a JOIN students s ON s.student_id = a.student_id
WHERE a.status = 'APPROVED';                      -- household income not exposed

-- (f) Index -------------------------------------------------------------
-- Equality column (status) first, range column (submitted_on) second.
CREATE INDEX idx_applications_status_submitted ON applications (status, submitted_on);
ANALYZE applications;
SET enable_seqscan = off;
EXPLAIN
SELECT * FROM applications
WHERE status = 'PENDING' AND submitted_on BETWEEN CURRENT_DATE - 30 AND CURRENT_DATE;
RESET enable_seqscan;

-- (g) Scheduled job -----------------------------------------------------
-- Only PENDING rows are selected, and each assessed row leaves PENDING, so reruns
-- skip completed applications and the AFTER UPDATE trigger cannot create duplicates.
CREATE OR REPLACE PROCEDURE pr_assess_pending() LANGUAGE plpgsql AS $$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT application_id FROM applications
             WHERE status = 'PENDING' ORDER BY application_id
    LOOP
        CALL pr_assess_application(r.application_id);
    END LOOP;
END $$;

SELECT cron.schedule('q10_assess_pending', '0 8 * * 1',            -- Mondays 08:00
       $$CALL q10.pr_assess_pending()$$);

CALL pr_assess_pending();
CALL pr_assess_pending();                                -- rerun: nothing reassessed
SELECT application_id, status FROM applications ORDER BY 1;   -- 3 APPROVED, 3 REJECTED
SELECT * FROM decision_audit ORDER BY audit_id;               -- exactly 6 rows
SELECT * FROM v_approved_applicants;
-- Rejected: CALL pr_assess_application(1);    -- already assessed
--           CALL pr_assess_application(999);  -- unknown

-- Reset search_path
RESET search_path;
-- ======================== END OF ICT371 ANSWERS ========================
