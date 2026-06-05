PROMPT ============================================================
PROMPT IntelliCrime System database setup
PROMPT WARNING: Running setup.sql again resets all IntelliCrime demo data.
PROMPT ============================================================

ALTER SESSION SET CONTAINER = XEPDB1;

DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM dba_users WHERE username = 'INTELLICRIME';
    IF v_count = 0 THEN
        EXECUTE IMMEDIATE 'CREATE USER intellicrime IDENTIFIED BY intellicrime123 DEFAULT TABLESPACE USERS TEMPORARY TABLESPACE TEMP';
    ELSE
        EXECUTE IMMEDIATE 'ALTER USER intellicrime IDENTIFIED BY intellicrime123 ACCOUNT UNLOCK';
    END IF;
    EXECUTE IMMEDIATE 'ALTER USER intellicrime QUOTA 100M ON USERS';
END;
/

GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE, CREATE PROCEDURE, CREATE TRIGGER TO intellicrime;

ALTER SESSION SET CURRENT_SCHEMA = INTELLICRIME;

PROMPT Dropping old IntelliCrime objects...

DECLARE
    PROCEDURE drop_object(p_sql VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE NOT IN (-942, -4043, -2289, -4080) THEN
                RAISE;
            END IF;
    END;
BEGIN
    drop_object('DROP VIEW alert_summary_view');
    drop_object('DROP VIEW smart_alerts_view');
    drop_object('DROP VIEW monthly_crime_summary_view');
    drop_object('DROP VIEW repeated_mobile_view');
    drop_object('DROP VIEW repeated_vehicle_view');
    drop_object('DROP VIEW case_evidence_summary_view');
    drop_object('DROP VIEW officer_case_load_view');
    drop_object('DROP VIEW criminal_history_view');
    drop_object('DROP VIEW crime_hotspot_view');
    drop_object('DROP VIEW active_cases_view');
    drop_object('DROP PACKAGE intellicrime_pkg');
    drop_object('DROP TABLE audit_logs CASCADE CONSTRAINTS');
    drop_object('DROP TABLE smart_alerts CASCADE CONSTRAINTS');
    drop_object('DROP TABLE case_status_history CASCADE CONSTRAINTS');
    drop_object('DROP TABLE investigation_logs CASCADE CONSTRAINTS');
    drop_object('DROP TABLE case_mobile_numbers CASCADE CONSTRAINTS');
    drop_object('DROP TABLE mobile_numbers CASCADE CONSTRAINTS');
    drop_object('DROP TABLE case_vehicles CASCADE CONSTRAINTS');
    drop_object('DROP TABLE vehicles CASCADE CONSTRAINTS');
    drop_object('DROP TABLE evidence CASCADE CONSTRAINTS');
    drop_object('DROP TABLE witnesses CASCADE CONSTRAINTS');
    drop_object('DROP TABLE victims CASCADE CONSTRAINTS');
    drop_object('DROP TABLE case_suspects CASCADE CONSTRAINTS');
    drop_object('DROP TABLE criminals CASCADE CONSTRAINTS');
    drop_object('DROP TABLE cases CASCADE CONSTRAINTS');
    drop_object('DROP TABLE firs CASCADE CONSTRAINTS');
    drop_object('DROP TABLE crime_locations CASCADE CONSTRAINTS');
    drop_object('DROP TABLE crime_types CASCADE CONSTRAINTS');
    drop_object('DROP TABLE officers CASCADE CONSTRAINTS');
    drop_object('DROP TABLE police_stations CASCADE CONSTRAINTS');
    drop_object('DROP TABLE users CASCADE CONSTRAINTS');
    drop_object('DROP TABLE roles CASCADE CONSTRAINTS');
    FOR s IN (
        SELECT 'DROP SEQUENCE ' || sequence_name AS sql_text
        FROM all_sequences
        WHERE sequence_owner = 'INTELLICRIME'
          AND sequence_name IN (
            'ROLES_SEQ','USERS_SEQ','STATIONS_SEQ','OFFICERS_SEQ','CRIME_TYPES_SEQ','LOCATIONS_SEQ',
            'FIRS_SEQ','CASES_SEQ','CRIMINALS_SEQ','VICTIMS_SEQ','WITNESSES_SEQ','EVIDENCE_SEQ',
            'VEHICLES_SEQ','MOBILE_NUMBERS_SEQ','INVESTIGATION_LOGS_SEQ','CASE_STATUS_HISTORY_SEQ',
            'SMART_ALERTS_SEQ','AUDIT_LOGS_SEQ'
        )
    ) LOOP
        drop_object(s.sql_text);
    END LOOP;
END;
/

PROMPT Creating sequences...

CREATE SEQUENCE roles_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE users_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE stations_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE officers_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE crime_types_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE locations_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE firs_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE cases_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE criminals_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE victims_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE witnesses_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE evidence_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE vehicles_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE mobile_numbers_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE investigation_logs_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE case_status_history_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE smart_alerts_seq START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE audit_logs_seq START WITH 1 INCREMENT BY 1;

PROMPT Creating tables...

CREATE TABLE roles (
    role_id NUMBER PRIMARY KEY,
    role_name VARCHAR2(50) UNIQUE NOT NULL,
    description VARCHAR2(200)
);

CREATE TABLE users (
    user_id NUMBER PRIMARY KEY,
    role_id NUMBER NOT NULL,
    username VARCHAR2(50) UNIQUE NOT NULL,
    password_hash VARCHAR2(255) NOT NULL,
    full_name VARCHAR2(100) NOT NULL,
    email VARCHAR2(100),
    phone VARCHAR2(20),
    status VARCHAR2(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE','LOCKED')),
    created_at TIMESTAMP DEFAULT SYSTIMESTAMP,
    CONSTRAINT fk_users_roles FOREIGN KEY (role_id) REFERENCES roles(role_id)
);

CREATE TABLE police_stations (
    station_id NUMBER PRIMARY KEY,
    station_name VARCHAR2(100) NOT NULL,
    city VARCHAR2(50) NOT NULL,
    district VARCHAR2(50),
    area VARCHAR2(100),
    address VARCHAR2(250),
    contact_no VARCHAR2(20),
    status VARCHAR2(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE'))
);

CREATE TABLE officers (
    officer_id NUMBER PRIMARY KEY,
    user_id NUMBER UNIQUE,
    station_id NUMBER NOT NULL,
    badge_no VARCHAR2(30) UNIQUE NOT NULL,
    officer_name VARCHAR2(100) NOT NULL,
    officer_rank VARCHAR2(50),
    phone VARCHAR2(20),
    email VARCHAR2(100),
    joining_date DATE,
    status VARCHAR2(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','INACTIVE','SUSPENDED')),
    CONSTRAINT fk_officers_users FOREIGN KEY (user_id) REFERENCES users(user_id),
    CONSTRAINT fk_officers_stations FOREIGN KEY (station_id) REFERENCES police_stations(station_id)
);

CREATE TABLE crime_types (
    crime_type_id NUMBER PRIMARY KEY,
    crime_type_name VARCHAR2(100) UNIQUE NOT NULL,
    description VARCHAR2(300),
    severity_level VARCHAR2(20) CHECK (severity_level IN ('LOW','MEDIUM','HIGH','CRITICAL'))
);

CREATE TABLE crime_locations (
    location_id NUMBER PRIMARY KEY,
    area_name VARCHAR2(100) NOT NULL,
    city VARCHAR2(50) NOT NULL,
    district VARCHAR2(50),
    hotspot_level VARCHAR2(20) DEFAULT 'LOW' CHECK (hotspot_level IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT uq_locations_area UNIQUE (area_name, city)
);

CREATE TABLE firs (
    fir_id NUMBER PRIMARY KEY,
    fir_no VARCHAR2(50) UNIQUE NOT NULL,
    station_id NUMBER NOT NULL,
    crime_type_id NUMBER NOT NULL,
    location_id NUMBER NOT NULL,
    reported_by VARCHAR2(100) NOT NULL,
    reporter_cnic VARCHAR2(20),
    reporter_phone VARCHAR2(20),
    report_date TIMESTAMP DEFAULT SYSTIMESTAMP,
    incident_at TIMESTAMP,
    description VARCHAR2(2000) NOT NULL,
    fir_status VARCHAR2(30) DEFAULT 'REGISTERED' CHECK (fir_status IN ('REGISTERED','VERIFIED','REJECTED','ARCHIVED')),
    created_by NUMBER,
    CONSTRAINT fk_firs_stations FOREIGN KEY (station_id) REFERENCES police_stations(station_id),
    CONSTRAINT fk_firs_crime_types FOREIGN KEY (crime_type_id) REFERENCES crime_types(crime_type_id),
    CONSTRAINT fk_firs_locations FOREIGN KEY (location_id) REFERENCES crime_locations(location_id),
    CONSTRAINT fk_firs_users FOREIGN KEY (created_by) REFERENCES users(user_id)
);

CREATE TABLE cases (
    case_id NUMBER PRIMARY KEY,
    fir_id NUMBER UNIQUE NOT NULL,
    officer_id NUMBER,
    case_title VARCHAR2(200) NOT NULL,
    case_description VARCHAR2(2000),
    case_status VARCHAR2(30) DEFAULT 'OPEN' CHECK (case_status IN ('OPEN','UNDER_INVESTIGATION','PENDING','SOLVED','CLOSED','ARCHIVED')),
    priority VARCHAR2(20) DEFAULT 'MEDIUM' CHECK (priority IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    opened_date TIMESTAMP DEFAULT SYSTIMESTAMP,
    closed_date TIMESTAMP,
    archived_at TIMESTAMP,
    CONSTRAINT fk_cases_firs FOREIGN KEY (fir_id) REFERENCES firs(fir_id),
    CONSTRAINT fk_cases_officers FOREIGN KEY (officer_id) REFERENCES officers(officer_id)
);

CREATE TABLE criminals (
    criminal_id NUMBER PRIMARY KEY,
    criminal_name VARCHAR2(100) NOT NULL,
    cnic VARCHAR2(20) UNIQUE,
    gender VARCHAR2(20),
    date_of_birth DATE,
    address VARCHAR2(250),
    phone VARCHAR2(20),
    criminal_status VARCHAR2(30) DEFAULT 'SUSPECT' CHECK (criminal_status IN ('SUSPECT','WANTED','ARRESTED','CONVICTED','RELEASED','CLEARED')),
    previous_record VARCHAR2(2000),
    created_at TIMESTAMP DEFAULT SYSTIMESTAMP
);

CREATE TABLE case_suspects (
    case_id NUMBER NOT NULL,
    criminal_id NUMBER NOT NULL,
    suspect_role VARCHAR2(100),
    involvement_status VARCHAR2(50),
    added_date TIMESTAMP DEFAULT SYSTIMESTAMP,
    PRIMARY KEY (case_id, criminal_id),
    CONSTRAINT fk_case_suspects_cases FOREIGN KEY (case_id) REFERENCES cases(case_id),
    CONSTRAINT fk_case_suspects_criminals FOREIGN KEY (criminal_id) REFERENCES criminals(criminal_id)
);

CREATE TABLE victims (
    victim_id NUMBER PRIMARY KEY,
    case_id NUMBER NOT NULL,
    victim_name VARCHAR2(100) NOT NULL,
    cnic VARCHAR2(20),
    gender VARCHAR2(20),
    phone VARCHAR2(20),
    address VARCHAR2(250),
    injury_details VARCHAR2(1000),
    CONSTRAINT fk_victims_cases FOREIGN KEY (case_id) REFERENCES cases(case_id)
);

CREATE TABLE witnesses (
    witness_id NUMBER PRIMARY KEY,
    case_id NUMBER NOT NULL,
    witness_name VARCHAR2(100) NOT NULL,
    cnic VARCHAR2(20),
    phone VARCHAR2(20),
    statement_summary VARCHAR2(2000),
    CONSTRAINT fk_witnesses_cases FOREIGN KEY (case_id) REFERENCES cases(case_id)
);

CREATE TABLE evidence (
    evidence_id NUMBER PRIMARY KEY,
    case_id NUMBER NOT NULL,
    evidence_code VARCHAR2(50) UNIQUE NOT NULL,
    evidence_type VARCHAR2(100) NOT NULL,
    evidence_description VARCHAR2(2000),
    collected_by NUMBER,
    collection_date TIMESTAMP DEFAULT SYSTIMESTAMP,
    storage_location VARCHAR2(150),
    verification_status VARCHAR2(30) DEFAULT 'PENDING' CHECK (verification_status IN ('PENDING','VERIFIED','REJECTED','ARCHIVED')),
    CONSTRAINT fk_evidence_cases FOREIGN KEY (case_id) REFERENCES cases(case_id),
    CONSTRAINT fk_evidence_officers FOREIGN KEY (collected_by) REFERENCES officers(officer_id)
);

CREATE TABLE vehicles (
    vehicle_id NUMBER PRIMARY KEY,
    vehicle_number VARCHAR2(30) UNIQUE NOT NULL,
    owner_name VARCHAR2(100),
    owner_cnic VARCHAR2(20),
    vehicle_type VARCHAR2(50),
    make VARCHAR2(50),
    model VARCHAR2(50),
    color VARCHAR2(30)
);

CREATE TABLE case_vehicles (
    case_id NUMBER NOT NULL,
    vehicle_id NUMBER NOT NULL,
    detected_location VARCHAR2(200),
    detection_date TIMESTAMP DEFAULT SYSTIMESTAMP,
    relation_to_case VARCHAR2(150),
    suspicious_status VARCHAR2(30) DEFAULT 'NORMAL' CHECK (suspicious_status IN ('NORMAL','SUSPICIOUS','REPEATED','CLEARED')),
    PRIMARY KEY (case_id, vehicle_id),
    CONSTRAINT fk_case_vehicles_cases FOREIGN KEY (case_id) REFERENCES cases(case_id),
    CONSTRAINT fk_case_vehicles_vehicles FOREIGN KEY (vehicle_id) REFERENCES vehicles(vehicle_id)
);

CREATE TABLE mobile_numbers (
    mobile_id NUMBER PRIMARY KEY,
    mobile_number VARCHAR2(20) UNIQUE NOT NULL,
    owner_name VARCHAR2(100),
    network VARCHAR2(50),
    registered_cnic VARCHAR2(20)
);

CREATE TABLE case_mobile_numbers (
    case_id NUMBER NOT NULL,
    mobile_id NUMBER NOT NULL,
    linked_person VARCHAR2(100),
    relation_to_case VARCHAR2(150),
    first_seen_date TIMESTAMP DEFAULT SYSTIMESTAMP,
    suspicious_status VARCHAR2(30) DEFAULT 'NORMAL' CHECK (suspicious_status IN ('NORMAL','SUSPICIOUS','REPEATED','CLEARED')),
    PRIMARY KEY (case_id, mobile_id),
    CONSTRAINT fk_case_mobiles_cases FOREIGN KEY (case_id) REFERENCES cases(case_id),
    CONSTRAINT fk_case_mobiles_mobiles FOREIGN KEY (mobile_id) REFERENCES mobile_numbers(mobile_id)
);

CREATE TABLE investigation_logs (
    log_id NUMBER PRIMARY KEY,
    case_id NUMBER NOT NULL,
    officer_id NUMBER,
    log_date TIMESTAMP DEFAULT SYSTIMESTAMP,
    progress_note VARCHAR2(2000) NOT NULL,
    next_action VARCHAR2(1000),
    CONSTRAINT fk_logs_cases FOREIGN KEY (case_id) REFERENCES cases(case_id),
    CONSTRAINT fk_logs_officers FOREIGN KEY (officer_id) REFERENCES officers(officer_id)
);

CREATE TABLE case_status_history (
    history_id NUMBER PRIMARY KEY,
    case_id NUMBER NOT NULL,
    old_status VARCHAR2(30),
    new_status VARCHAR2(30) NOT NULL,
    changed_by NUMBER,
    changed_at TIMESTAMP DEFAULT SYSTIMESTAMP,
    remarks VARCHAR2(500),
    CONSTRAINT fk_history_cases FOREIGN KEY (case_id) REFERENCES cases(case_id),
    CONSTRAINT fk_history_users FOREIGN KEY (changed_by) REFERENCES users(user_id)
);

CREATE TABLE smart_alerts (
    alert_id NUMBER PRIMARY KEY,
    case_id NUMBER,
    entity_type VARCHAR2(30),
    entity_id NUMBER,
    alert_type VARCHAR2(100) NOT NULL,
    alert_message VARCHAR2(1000) NOT NULL,
    alert_date TIMESTAMP DEFAULT SYSTIMESTAMP,
    alert_status VARCHAR2(30) DEFAULT 'NEW' CHECK (alert_status IN ('NEW','REVIEWED','RESOLVED','DISMISSED')),
    resolved_by NUMBER,
    resolved_at TIMESTAMP,
    CONSTRAINT fk_alerts_cases FOREIGN KEY (case_id) REFERENCES cases(case_id),
    CONSTRAINT fk_alerts_users FOREIGN KEY (resolved_by) REFERENCES users(user_id)
);

CREATE TABLE audit_logs (
    audit_id NUMBER PRIMARY KEY,
    user_id NUMBER,
    table_name VARCHAR2(50) NOT NULL,
    record_id VARCHAR2(100),
    operation_type VARCHAR2(20) NOT NULL,
    old_value CLOB,
    new_value CLOB,
    changed_at TIMESTAMP DEFAULT SYSTIMESTAMP,
    CONSTRAINT fk_audit_users FOREIGN KEY (user_id) REFERENCES users(user_id)
);

CREATE INDEX idx_firs_status ON firs(fir_status);
CREATE INDEX idx_firs_station ON firs(station_id);
CREATE INDEX idx_cases_status ON cases(case_status);
CREATE INDEX idx_cases_officer ON cases(officer_id);
CREATE INDEX idx_alerts_status ON smart_alerts(alert_status);
CREATE INDEX idx_evidence_case ON evidence(case_id);
CREATE INDEX idx_criminals_status ON criminals(criminal_status);

PROMPT Creating triggers...

CREATE OR REPLACE TRIGGER trg_firs_bi
BEFORE INSERT ON firs
FOR EACH ROW
BEGIN
    IF :NEW.fir_id IS NULL THEN
        :NEW.fir_id := firs_seq.NEXTVAL;
    END IF;
    IF :NEW.fir_status IS NULL THEN
        :NEW.fir_status := 'REGISTERED';
    END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_cases_bi
BEFORE INSERT ON cases
FOR EACH ROW
BEGIN
    IF :NEW.case_id IS NULL THEN
        :NEW.case_id := cases_seq.NEXTVAL;
    END IF;
    IF :NEW.case_status IS NULL THEN
        :NEW.case_status := 'OPEN';
    END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_auto_case_from_fir
AFTER INSERT ON firs
FOR EACH ROW
DECLARE
    v_priority cases.priority%TYPE;
BEGIN
    SELECT CASE severity_level
        WHEN 'CRITICAL' THEN 'CRITICAL'
        WHEN 'HIGH' THEN 'HIGH'
        WHEN 'MEDIUM' THEN 'MEDIUM'
        ELSE 'LOW'
    END INTO v_priority
    FROM crime_types
    WHERE crime_type_id = :NEW.crime_type_id;

    INSERT INTO cases (case_id, fir_id, case_title, case_description, case_status, priority, opened_date)
    VALUES (cases_seq.NEXTVAL, :NEW.fir_id, 'Case for FIR ' || :NEW.fir_no, :NEW.description, 'OPEN', v_priority, SYSTIMESTAMP);
END;
/

CREATE OR REPLACE TRIGGER trg_case_status_history
BEFORE UPDATE OF case_status ON cases
FOR EACH ROW
DECLARE
    v_user_id NUMBER;
BEGIN
    IF NVL(:OLD.case_status, 'x') <> NVL(:NEW.case_status, 'x') THEN
        BEGIN
            v_user_id := TO_NUMBER(SYS_CONTEXT('USERENV', 'CLIENT_IDENTIFIER'));
        EXCEPTION WHEN OTHERS THEN
            v_user_id := NULL;
        END;
        INSERT INTO case_status_history(history_id, case_id, old_status, new_status, changed_by, remarks)
        VALUES(case_status_history_seq.NEXTVAL, :OLD.case_id, :OLD.case_status, :NEW.case_status, v_user_id, 'Status changed by application');
        IF :NEW.case_status = 'CLOSED' THEN
            :NEW.closed_date := SYSTIMESTAMP;
        ELSIF :OLD.case_status = 'CLOSED' AND :NEW.case_status <> 'CLOSED' THEN
            :NEW.closed_date := NULL;
        END IF;
    END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_fir_location_alert
AFTER INSERT OR UPDATE ON firs
DECLARE
BEGIN
    FOR r IN (
        SELECT MIN(c.case_id) case_id, f.location_id, COUNT(*) crime_count
        FROM firs f
        JOIN cases c ON c.fir_id = f.fir_id
        WHERE f.fir_status <> 'ARCHIVED'
        GROUP BY f.location_id
        HAVING COUNT(*) >= 3
    ) LOOP
        INSERT INTO smart_alerts(alert_id, case_id, entity_type, entity_id, alert_type, alert_message)
        SELECT smart_alerts_seq.NEXTVAL, r.case_id, 'LOCATION', r.location_id, 'LOCATION_HOTSPOT',
               'Location has reached ' || r.crime_count || ' FIRs'
        FROM dual
        WHERE NOT EXISTS (
            SELECT 1 FROM smart_alerts a
            WHERE a.entity_type = 'LOCATION'
              AND a.entity_id = r.location_id
              AND a.alert_type = 'LOCATION_HOTSPOT'
              AND a.alert_status IN ('NEW','REVIEWED')
        );
    END LOOP;
END;
/

CREATE OR REPLACE TRIGGER trg_repeated_suspect_alert
AFTER INSERT OR UPDATE OR DELETE ON case_suspects
DECLARE
BEGIN
    FOR r IN (
        SELECT MIN(cs.case_id) case_id, cs.criminal_id, COUNT(DISTINCT cs.case_id) case_count
        FROM case_suspects cs
        GROUP BY cs.criminal_id
        HAVING COUNT(DISTINCT cs.case_id) >= 2
    ) LOOP
        INSERT INTO smart_alerts(alert_id, case_id, entity_type, entity_id, alert_type, alert_message)
        SELECT smart_alerts_seq.NEXTVAL, r.case_id, 'CRIMINAL', r.criminal_id, 'REPEATED_CRIMINAL',
               'Criminal appears in ' || r.case_count || ' cases'
        FROM dual
        WHERE NOT EXISTS (
            SELECT 1 FROM smart_alerts a
            WHERE a.entity_type = 'CRIMINAL'
              AND a.entity_id = r.criminal_id
              AND a.alert_type = 'REPEATED_CRIMINAL'
              AND a.alert_status IN ('NEW','REVIEWED')
        );
    END LOOP;
END;
/

CREATE OR REPLACE TRIGGER trg_repeated_vehicle_alert
AFTER INSERT OR UPDATE OR DELETE ON case_vehicles
DECLARE
BEGIN
    FOR r IN (
        SELECT MIN(cv.case_id) case_id, cv.vehicle_id, COUNT(DISTINCT cv.case_id) case_count
        FROM case_vehicles cv
        GROUP BY cv.vehicle_id
        HAVING COUNT(DISTINCT cv.case_id) >= 2
    ) LOOP
        INSERT INTO smart_alerts(alert_id, case_id, entity_type, entity_id, alert_type, alert_message)
        SELECT smart_alerts_seq.NEXTVAL, r.case_id, 'VEHICLE', r.vehicle_id, 'REPEATED_VEHICLE',
               'Vehicle appears in ' || r.case_count || ' cases'
        FROM dual
        WHERE NOT EXISTS (
            SELECT 1 FROM smart_alerts a
            WHERE a.entity_type = 'VEHICLE'
              AND a.entity_id = r.vehicle_id
              AND a.alert_type = 'REPEATED_VEHICLE'
              AND a.alert_status IN ('NEW','REVIEWED')
        );
    END LOOP;
END;
/

CREATE OR REPLACE TRIGGER trg_repeated_mobile_alert
AFTER INSERT OR UPDATE OR DELETE ON case_mobile_numbers
DECLARE
BEGIN
    FOR r IN (
        SELECT MIN(cm.case_id) case_id, cm.mobile_id, COUNT(DISTINCT cm.case_id) case_count
        FROM case_mobile_numbers cm
        GROUP BY cm.mobile_id
        HAVING COUNT(DISTINCT cm.case_id) >= 2
    ) LOOP
        INSERT INTO smart_alerts(alert_id, case_id, entity_type, entity_id, alert_type, alert_message)
        SELECT smart_alerts_seq.NEXTVAL, r.case_id, 'MOBILE', r.mobile_id, 'REPEATED_MOBILE',
               'Mobile number appears in ' || r.case_count || ' cases'
        FROM dual
        WHERE NOT EXISTS (
            SELECT 1 FROM smart_alerts a
            WHERE a.entity_type = 'MOBILE'
              AND a.entity_id = r.mobile_id
              AND a.alert_type = 'REPEATED_MOBILE'
              AND a.alert_status IN ('NEW','REVIEWED')
        );
    END LOOP;
END;
/

CREATE OR REPLACE TRIGGER trg_audit_firs
AFTER INSERT OR UPDATE OR DELETE ON firs
FOR EACH ROW
DECLARE
    v_user NUMBER;
    v_record_id VARCHAR2(100);
    v_operation VARCHAR2(20);
    v_old CLOB;
    v_new CLOB;
BEGIN
    BEGIN v_user := TO_NUMBER(SYS_CONTEXT('USERENV','CLIENT_IDENTIFIER')); EXCEPTION WHEN OTHERS THEN v_user := NULL; END;
    IF INSERTING THEN
        v_record_id := TO_CHAR(:NEW.fir_id);
        v_operation := 'INSERT';
        v_new := 'status=' || :NEW.fir_status || '; fir_no=' || :NEW.fir_no;
    ELSIF UPDATING THEN
        v_record_id := TO_CHAR(:NEW.fir_id);
        v_operation := 'UPDATE';
        v_old := 'status=' || :OLD.fir_status || '; fir_no=' || :OLD.fir_no;
        v_new := 'status=' || :NEW.fir_status || '; fir_no=' || :NEW.fir_no;
    ELSE
        v_record_id := TO_CHAR(:OLD.fir_id);
        v_operation := 'DELETE';
        v_old := 'status=' || :OLD.fir_status || '; fir_no=' || :OLD.fir_no;
    END IF;
    INSERT INTO audit_logs(audit_id, user_id, table_name, record_id, operation_type, old_value, new_value)
    VALUES(audit_logs_seq.NEXTVAL, v_user, 'FIRS', v_record_id, v_operation, v_old, v_new);
END;
/

CREATE OR REPLACE TRIGGER trg_audit_cases
AFTER INSERT OR UPDATE OR DELETE ON cases
FOR EACH ROW
DECLARE
    v_user NUMBER;
    v_record_id VARCHAR2(100);
    v_operation VARCHAR2(20);
    v_old CLOB;
    v_new CLOB;
BEGIN
    BEGIN v_user := TO_NUMBER(SYS_CONTEXT('USERENV','CLIENT_IDENTIFIER')); EXCEPTION WHEN OTHERS THEN v_user := NULL; END;
    IF INSERTING THEN
        v_record_id := TO_CHAR(:NEW.case_id);
        v_operation := 'INSERT';
        v_new := 'status=' || :NEW.case_status;
    ELSIF UPDATING THEN
        v_record_id := TO_CHAR(:NEW.case_id);
        v_operation := 'UPDATE';
        v_old := 'status=' || :OLD.case_status;
        v_new := 'status=' || :NEW.case_status;
    ELSE
        v_record_id := TO_CHAR(:OLD.case_id);
        v_operation := 'DELETE';
        v_old := 'status=' || :OLD.case_status;
    END IF;
    INSERT INTO audit_logs(audit_id, user_id, table_name, record_id, operation_type, old_value, new_value)
    VALUES(audit_logs_seq.NEXTVAL, v_user, 'CASES', v_record_id, v_operation, v_old, v_new);
END;
/

CREATE OR REPLACE TRIGGER trg_audit_criminals
AFTER INSERT OR UPDATE OR DELETE ON criminals
FOR EACH ROW
DECLARE
    v_user NUMBER;
    v_record_id VARCHAR2(100);
    v_operation VARCHAR2(20);
    v_old CLOB;
    v_new CLOB;
BEGIN
    BEGIN v_user := TO_NUMBER(SYS_CONTEXT('USERENV','CLIENT_IDENTIFIER')); EXCEPTION WHEN OTHERS THEN v_user := NULL; END;
    IF INSERTING THEN
        v_record_id := TO_CHAR(:NEW.criminal_id);
        v_operation := 'INSERT';
        v_new := :NEW.criminal_status;
    ELSIF UPDATING THEN
        v_record_id := TO_CHAR(:NEW.criminal_id);
        v_operation := 'UPDATE';
        v_old := :OLD.criminal_status;
        v_new := :NEW.criminal_status;
    ELSE
        v_record_id := TO_CHAR(:OLD.criminal_id);
        v_operation := 'DELETE';
        v_old := :OLD.criminal_status;
    END IF;
    INSERT INTO audit_logs(audit_id, user_id, table_name, record_id, operation_type, old_value, new_value)
    VALUES(audit_logs_seq.NEXTVAL, v_user, 'CRIMINALS', v_record_id, v_operation, v_old, v_new);
END;
/

CREATE OR REPLACE TRIGGER trg_audit_evidence
AFTER INSERT OR UPDATE OR DELETE ON evidence
FOR EACH ROW
DECLARE
    v_user NUMBER;
    v_record_id VARCHAR2(100);
    v_operation VARCHAR2(20);
    v_old CLOB;
    v_new CLOB;
BEGIN
    BEGIN v_user := TO_NUMBER(SYS_CONTEXT('USERENV','CLIENT_IDENTIFIER')); EXCEPTION WHEN OTHERS THEN v_user := NULL; END;
    IF INSERTING THEN
        v_record_id := TO_CHAR(:NEW.evidence_id);
        v_operation := 'INSERT';
        v_new := :NEW.verification_status;
    ELSIF UPDATING THEN
        v_record_id := TO_CHAR(:NEW.evidence_id);
        v_operation := 'UPDATE';
        v_old := :OLD.verification_status;
        v_new := :NEW.verification_status;
    ELSE
        v_record_id := TO_CHAR(:OLD.evidence_id);
        v_operation := 'DELETE';
        v_old := :OLD.verification_status;
    END IF;
    INSERT INTO audit_logs(audit_id, user_id, table_name, record_id, operation_type, old_value, new_value)
    VALUES(audit_logs_seq.NEXTVAL, v_user, 'EVIDENCE', v_record_id, v_operation, v_old, v_new);
END;
/

CREATE OR REPLACE TRIGGER trg_audit_case_vehicles
AFTER INSERT OR UPDATE OR DELETE ON case_vehicles
FOR EACH ROW
DECLARE
    v_user NUMBER;
    v_record_id VARCHAR2(100);
    v_operation VARCHAR2(20);
BEGIN
    BEGIN v_user := TO_NUMBER(SYS_CONTEXT('USERENV','CLIENT_IDENTIFIER')); EXCEPTION WHEN OTHERS THEN v_user := NULL; END;
    IF INSERTING THEN
        v_record_id := TO_CHAR(:NEW.case_id) || ':' || TO_CHAR(:NEW.vehicle_id);
        v_operation := 'INSERT';
    ELSIF UPDATING THEN
        v_record_id := TO_CHAR(:NEW.case_id) || ':' || TO_CHAR(:NEW.vehicle_id);
        v_operation := 'UPDATE';
    ELSE
        v_record_id := TO_CHAR(:OLD.case_id) || ':' || TO_CHAR(:OLD.vehicle_id);
        v_operation := 'DELETE';
    END IF;
    INSERT INTO audit_logs(audit_id, user_id, table_name, record_id, operation_type, old_value, new_value)
    VALUES(audit_logs_seq.NEXTVAL, v_user, 'CASE_VEHICLES', v_record_id, v_operation, NULL, NULL);
END;
/

CREATE OR REPLACE TRIGGER trg_audit_case_mobiles
AFTER INSERT OR UPDATE OR DELETE ON case_mobile_numbers
FOR EACH ROW
DECLARE
    v_user NUMBER;
    v_record_id VARCHAR2(100);
    v_operation VARCHAR2(20);
BEGIN
    BEGIN v_user := TO_NUMBER(SYS_CONTEXT('USERENV','CLIENT_IDENTIFIER')); EXCEPTION WHEN OTHERS THEN v_user := NULL; END;
    IF INSERTING THEN
        v_record_id := TO_CHAR(:NEW.case_id) || ':' || TO_CHAR(:NEW.mobile_id);
        v_operation := 'INSERT';
    ELSIF UPDATING THEN
        v_record_id := TO_CHAR(:NEW.case_id) || ':' || TO_CHAR(:NEW.mobile_id);
        v_operation := 'UPDATE';
    ELSE
        v_record_id := TO_CHAR(:OLD.case_id) || ':' || TO_CHAR(:OLD.mobile_id);
        v_operation := 'DELETE';
    END IF;
    INSERT INTO audit_logs(audit_id, user_id, table_name, record_id, operation_type, old_value, new_value)
    VALUES(audit_logs_seq.NEXTVAL, v_user, 'CASE_MOBILE_NUMBERS', v_record_id, v_operation, NULL, NULL);
END;
/

PROMPT Creating PL/SQL package...

CREATE OR REPLACE PACKAGE intellicrime_pkg AS
    PROCEDURE register_fir(p_fir_no IN firs.fir_no%TYPE, p_station_id IN firs.station_id%TYPE, p_crime_type_id IN firs.crime_type_id%TYPE, p_location_id IN firs.location_id%TYPE, p_reported_by IN firs.reported_by%TYPE, p_reporter_cnic IN firs.reporter_cnic%TYPE, p_reporter_phone IN firs.reporter_phone%TYPE, p_incident_at IN firs.incident_at%TYPE, p_description IN firs.description%TYPE, p_created_by IN firs.created_by%TYPE, p_new_fir_id OUT firs.fir_id%TYPE);
    PROCEDURE assign_case_to_officer(p_case_id IN cases.case_id%TYPE, p_officer_id IN cases.officer_id%TYPE);
    PROCEDURE update_case_status(p_case_id IN cases.case_id%TYPE, p_new_status IN cases.case_status%TYPE, p_remarks IN case_status_history.remarks%TYPE);
    PROCEDURE add_criminal(p_name IN criminals.criminal_name%TYPE, p_cnic IN criminals.cnic%TYPE, p_gender IN criminals.gender%TYPE, p_dob IN criminals.date_of_birth%TYPE, p_address IN criminals.address%TYPE, p_phone IN criminals.phone%TYPE, p_status IN criminals.criminal_status%TYPE, p_record IN criminals.previous_record%TYPE, p_new_id OUT criminals.criminal_id%TYPE);
    PROCEDURE link_suspect_to_case(p_case_id IN case_suspects.case_id%TYPE, p_criminal_id IN case_suspects.criminal_id%TYPE, p_role IN case_suspects.suspect_role%TYPE, p_status IN case_suspects.involvement_status%TYPE);
    PROCEDURE add_victim(p_case_id IN victims.case_id%TYPE, p_name IN victims.victim_name%TYPE, p_cnic IN victims.cnic%TYPE, p_gender IN victims.gender%TYPE, p_phone IN victims.phone%TYPE, p_address IN victims.address%TYPE, p_injury IN victims.injury_details%TYPE, p_new_id OUT victims.victim_id%TYPE);
    PROCEDURE add_witness(p_case_id IN witnesses.case_id%TYPE, p_name IN witnesses.witness_name%TYPE, p_cnic IN witnesses.cnic%TYPE, p_phone IN witnesses.phone%TYPE, p_statement IN witnesses.statement_summary%TYPE, p_new_id OUT witnesses.witness_id%TYPE);
    PROCEDURE add_evidence(p_case_id IN evidence.case_id%TYPE, p_code IN evidence.evidence_code%TYPE, p_type IN evidence.evidence_type%TYPE, p_description IN evidence.evidence_description%TYPE, p_collected_by IN evidence.collected_by%TYPE, p_storage IN evidence.storage_location%TYPE, p_new_id OUT evidence.evidence_id%TYPE);
    PROCEDURE add_vehicle(p_number IN vehicles.vehicle_number%TYPE, p_owner IN vehicles.owner_name%TYPE, p_cnic IN vehicles.owner_cnic%TYPE, p_type IN vehicles.vehicle_type%TYPE, p_make IN vehicles.make%TYPE, p_model IN vehicles.model%TYPE, p_color IN vehicles.color%TYPE, p_new_id OUT vehicles.vehicle_id%TYPE);
    PROCEDURE link_vehicle_to_case(p_case_id IN case_vehicles.case_id%TYPE, p_vehicle_id IN case_vehicles.vehicle_id%TYPE, p_location IN case_vehicles.detected_location%TYPE, p_relation IN case_vehicles.relation_to_case%TYPE, p_status IN case_vehicles.suspicious_status%TYPE);
    PROCEDURE add_mobile_number(p_number IN mobile_numbers.mobile_number%TYPE, p_owner IN mobile_numbers.owner_name%TYPE, p_network IN mobile_numbers.network%TYPE, p_cnic IN mobile_numbers.registered_cnic%TYPE, p_new_id OUT mobile_numbers.mobile_id%TYPE);
    PROCEDURE link_mobile_to_case(p_case_id IN case_mobile_numbers.case_id%TYPE, p_mobile_id IN case_mobile_numbers.mobile_id%TYPE, p_person IN case_mobile_numbers.linked_person%TYPE, p_relation IN case_mobile_numbers.relation_to_case%TYPE, p_status IN case_mobile_numbers.suspicious_status%TYPE);
    PROCEDURE add_investigation_log(p_case_id IN investigation_logs.case_id%TYPE, p_officer_id IN investigation_logs.officer_id%TYPE, p_note IN investigation_logs.progress_note%TYPE, p_next IN investigation_logs.next_action%TYPE, p_new_id OUT investigation_logs.log_id%TYPE);
    PROCEDURE resolve_alert(p_alert_id IN smart_alerts.alert_id%TYPE, p_user_id IN smart_alerts.resolved_by%TYPE, p_status IN smart_alerts.alert_status%TYPE);
    PROCEDURE archive_fir(p_fir_id IN firs.fir_id%TYPE);
    PROCEDURE archive_case(p_case_id IN cases.case_id%TYPE);
    FUNCTION get_case_age_days(p_case_id IN cases.case_id%TYPE) RETURN NUMBER;
    FUNCTION get_criminal_case_count(p_criminal_id IN criminals.criminal_id%TYPE) RETURN NUMBER;
    FUNCTION get_vehicle_case_count(p_vehicle_id IN vehicles.vehicle_id%TYPE) RETURN NUMBER;
    FUNCTION get_mobile_case_count(p_mobile_id IN mobile_numbers.mobile_id%TYPE) RETURN NUMBER;
    FUNCTION get_officer_open_case_count(p_officer_id IN officers.officer_id%TYPE) RETURN NUMBER;
    FUNCTION get_location_crime_count(p_location_id IN crime_locations.location_id%TYPE) RETURN NUMBER;
    FUNCTION get_pending_case_count RETURN NUMBER;
END intellicrime_pkg;
/

CREATE OR REPLACE PACKAGE BODY intellicrime_pkg AS
    PROCEDURE must_exist(p_count NUMBER, p_message VARCHAR2) IS
    BEGIN
        IF p_count = 0 THEN RAISE_APPLICATION_ERROR(-20001, p_message); END IF;
    END;

    PROCEDURE register_fir(p_fir_no IN firs.fir_no%TYPE, p_station_id IN firs.station_id%TYPE, p_crime_type_id IN firs.crime_type_id%TYPE, p_location_id IN firs.location_id%TYPE, p_reported_by IN firs.reported_by%TYPE, p_reporter_cnic IN firs.reporter_cnic%TYPE, p_reporter_phone IN firs.reporter_phone%TYPE, p_incident_at IN firs.incident_at%TYPE, p_description IN firs.description%TYPE, p_created_by IN firs.created_by%TYPE, p_new_fir_id OUT firs.fir_id%TYPE) IS
        v_count NUMBER;
    BEGIN
        IF p_fir_no IS NULL OR p_reported_by IS NULL OR p_description IS NULL THEN RAISE_APPLICATION_ERROR(-20002, 'FIR number, reporter and description are required'); END IF;
        SELECT COUNT(*) INTO v_count FROM police_stations WHERE station_id = p_station_id; must_exist(v_count, 'Police station not found');
        SELECT COUNT(*) INTO v_count FROM crime_types WHERE crime_type_id = p_crime_type_id; must_exist(v_count, 'Crime type not found');
        SELECT COUNT(*) INTO v_count FROM crime_locations WHERE location_id = p_location_id; must_exist(v_count, 'Location not found');
        p_new_fir_id := firs_seq.NEXTVAL;
        INSERT INTO firs(fir_id, fir_no, station_id, crime_type_id, location_id, reported_by, reporter_cnic, reporter_phone, incident_at, description, created_by)
        VALUES(p_new_fir_id, p_fir_no, p_station_id, p_crime_type_id, p_location_id, p_reported_by, p_reporter_cnic, p_reporter_phone, p_incident_at, p_description, p_created_by);
    END;

    PROCEDURE assign_case_to_officer(p_case_id IN cases.case_id%TYPE, p_officer_id IN cases.officer_id%TYPE) IS BEGIN UPDATE cases SET officer_id = p_officer_id WHERE case_id = p_case_id; IF SQL%ROWCOUNT = 0 THEN RAISE_APPLICATION_ERROR(-20003, 'Case not found'); END IF; END;
    PROCEDURE update_case_status(p_case_id IN cases.case_id%TYPE, p_new_status IN cases.case_status%TYPE, p_remarks IN case_status_history.remarks%TYPE) IS BEGIN UPDATE cases SET case_status = p_new_status WHERE case_id = p_case_id; IF SQL%ROWCOUNT = 0 THEN RAISE_APPLICATION_ERROR(-20004, 'Case not found'); END IF; UPDATE case_status_history SET remarks = NVL(p_remarks, remarks) WHERE history_id = (SELECT MAX(history_id) FROM case_status_history WHERE case_id = p_case_id); END;
    PROCEDURE add_criminal(p_name IN criminals.criminal_name%TYPE, p_cnic IN criminals.cnic%TYPE, p_gender IN criminals.gender%TYPE, p_dob IN criminals.date_of_birth%TYPE, p_address IN criminals.address%TYPE, p_phone IN criminals.phone%TYPE, p_status IN criminals.criminal_status%TYPE, p_record IN criminals.previous_record%TYPE, p_new_id OUT criminals.criminal_id%TYPE) IS BEGIN IF p_name IS NULL THEN RAISE_APPLICATION_ERROR(-20005, 'Criminal name is required'); END IF; p_new_id := criminals_seq.NEXTVAL; INSERT INTO criminals VALUES(p_new_id, p_name, p_cnic, p_gender, p_dob, p_address, p_phone, NVL(p_status,'SUSPECT'), p_record, SYSTIMESTAMP); END;
    PROCEDURE link_suspect_to_case(p_case_id IN case_suspects.case_id%TYPE, p_criminal_id IN case_suspects.criminal_id%TYPE, p_role IN case_suspects.suspect_role%TYPE, p_status IN case_suspects.involvement_status%TYPE) IS BEGIN INSERT INTO case_suspects(case_id, criminal_id, suspect_role, involvement_status) VALUES(p_case_id, p_criminal_id, p_role, p_status); EXCEPTION WHEN DUP_VAL_ON_INDEX THEN UPDATE case_suspects SET suspect_role = p_role, involvement_status = p_status WHERE case_id = p_case_id AND criminal_id = p_criminal_id; END;
    PROCEDURE add_victim(p_case_id IN victims.case_id%TYPE, p_name IN victims.victim_name%TYPE, p_cnic IN victims.cnic%TYPE, p_gender IN victims.gender%TYPE, p_phone IN victims.phone%TYPE, p_address IN victims.address%TYPE, p_injury IN victims.injury_details%TYPE, p_new_id OUT victims.victim_id%TYPE) IS BEGIN p_new_id := victims_seq.NEXTVAL; INSERT INTO victims VALUES(p_new_id, p_case_id, p_name, p_cnic, p_gender, p_phone, p_address, p_injury); END;
    PROCEDURE add_witness(p_case_id IN witnesses.case_id%TYPE, p_name IN witnesses.witness_name%TYPE, p_cnic IN witnesses.cnic%TYPE, p_phone IN witnesses.phone%TYPE, p_statement IN witnesses.statement_summary%TYPE, p_new_id OUT witnesses.witness_id%TYPE) IS BEGIN p_new_id := witnesses_seq.NEXTVAL; INSERT INTO witnesses VALUES(p_new_id, p_case_id, p_name, p_cnic, p_phone, p_statement); END;
    PROCEDURE add_evidence(p_case_id IN evidence.case_id%TYPE, p_code IN evidence.evidence_code%TYPE, p_type IN evidence.evidence_type%TYPE, p_description IN evidence.evidence_description%TYPE, p_collected_by IN evidence.collected_by%TYPE, p_storage IN evidence.storage_location%TYPE, p_new_id OUT evidence.evidence_id%TYPE) IS BEGIN p_new_id := evidence_seq.NEXTVAL; INSERT INTO evidence(evidence_id, case_id, evidence_code, evidence_type, evidence_description, collected_by, storage_location) VALUES(p_new_id, p_case_id, p_code, p_type, p_description, p_collected_by, p_storage); END;
    PROCEDURE add_vehicle(p_number IN vehicles.vehicle_number%TYPE, p_owner IN vehicles.owner_name%TYPE, p_cnic IN vehicles.owner_cnic%TYPE, p_type IN vehicles.vehicle_type%TYPE, p_make IN vehicles.make%TYPE, p_model IN vehicles.model%TYPE, p_color IN vehicles.color%TYPE, p_new_id OUT vehicles.vehicle_id%TYPE) IS BEGIN p_new_id := vehicles_seq.NEXTVAL; INSERT INTO vehicles VALUES(p_new_id, p_number, p_owner, p_cnic, p_type, p_make, p_model, p_color); END;
    PROCEDURE link_vehicle_to_case(p_case_id IN case_vehicles.case_id%TYPE, p_vehicle_id IN case_vehicles.vehicle_id%TYPE, p_location IN case_vehicles.detected_location%TYPE, p_relation IN case_vehicles.relation_to_case%TYPE, p_status IN case_vehicles.suspicious_status%TYPE) IS BEGIN INSERT INTO case_vehicles(case_id, vehicle_id, detected_location, relation_to_case, suspicious_status) VALUES(p_case_id, p_vehicle_id, p_location, p_relation, NVL(p_status,'NORMAL')); EXCEPTION WHEN DUP_VAL_ON_INDEX THEN UPDATE case_vehicles SET detected_location=p_location, relation_to_case=p_relation, suspicious_status=NVL(p_status,'NORMAL') WHERE case_id=p_case_id AND vehicle_id=p_vehicle_id; END;
    PROCEDURE add_mobile_number(p_number IN mobile_numbers.mobile_number%TYPE, p_owner IN mobile_numbers.owner_name%TYPE, p_network IN mobile_numbers.network%TYPE, p_cnic IN mobile_numbers.registered_cnic%TYPE, p_new_id OUT mobile_numbers.mobile_id%TYPE) IS BEGIN p_new_id := mobile_numbers_seq.NEXTVAL; INSERT INTO mobile_numbers VALUES(p_new_id, p_number, p_owner, p_network, p_cnic); END;
    PROCEDURE link_mobile_to_case(p_case_id IN case_mobile_numbers.case_id%TYPE, p_mobile_id IN case_mobile_numbers.mobile_id%TYPE, p_person IN case_mobile_numbers.linked_person%TYPE, p_relation IN case_mobile_numbers.relation_to_case%TYPE, p_status IN case_mobile_numbers.suspicious_status%TYPE) IS BEGIN INSERT INTO case_mobile_numbers(case_id, mobile_id, linked_person, relation_to_case, suspicious_status) VALUES(p_case_id, p_mobile_id, p_person, p_relation, NVL(p_status,'NORMAL')); EXCEPTION WHEN DUP_VAL_ON_INDEX THEN UPDATE case_mobile_numbers SET linked_person=p_person, relation_to_case=p_relation, suspicious_status=NVL(p_status,'NORMAL') WHERE case_id=p_case_id AND mobile_id=p_mobile_id; END;
    PROCEDURE add_investigation_log(p_case_id IN investigation_logs.case_id%TYPE, p_officer_id IN investigation_logs.officer_id%TYPE, p_note IN investigation_logs.progress_note%TYPE, p_next IN investigation_logs.next_action%TYPE, p_new_id OUT investigation_logs.log_id%TYPE) IS BEGIN p_new_id := investigation_logs_seq.NEXTVAL; INSERT INTO investigation_logs VALUES(p_new_id, p_case_id, p_officer_id, SYSTIMESTAMP, p_note, p_next); END;
    PROCEDURE resolve_alert(p_alert_id IN smart_alerts.alert_id%TYPE, p_user_id IN smart_alerts.resolved_by%TYPE, p_status IN smart_alerts.alert_status%TYPE) IS BEGIN UPDATE smart_alerts SET alert_status = p_status, resolved_by = CASE WHEN p_status IN ('RESOLVED','DISMISSED') THEN p_user_id ELSE resolved_by END, resolved_at = CASE WHEN p_status IN ('RESOLVED','DISMISSED') THEN SYSTIMESTAMP ELSE resolved_at END WHERE alert_id = p_alert_id; IF SQL%ROWCOUNT = 0 THEN RAISE_APPLICATION_ERROR(-20006, 'Alert not found'); END IF; END;
    PROCEDURE archive_fir(p_fir_id IN firs.fir_id%TYPE) IS BEGIN UPDATE firs SET fir_status='ARCHIVED' WHERE fir_id=p_fir_id; IF SQL%ROWCOUNT=0 THEN RAISE_APPLICATION_ERROR(-20007, 'FIR not found'); END IF; END;
    PROCEDURE archive_case(p_case_id IN cases.case_id%TYPE) IS BEGIN UPDATE cases SET case_status='ARCHIVED', archived_at=SYSTIMESTAMP WHERE case_id=p_case_id; IF SQL%ROWCOUNT=0 THEN RAISE_APPLICATION_ERROR(-20008, 'Case not found'); END IF; END;
    FUNCTION get_case_age_days(p_case_id IN cases.case_id%TYPE) RETURN NUMBER IS v_days NUMBER; BEGIN SELECT TRUNC(CAST(SYSTIMESTAMP AS DATE)) - TRUNC(CAST(opened_date AS DATE)) INTO v_days FROM cases WHERE case_id = p_case_id; RETURN v_days; END;
    FUNCTION get_criminal_case_count(p_criminal_id IN criminals.criminal_id%TYPE) RETURN NUMBER IS v_count NUMBER; BEGIN SELECT COUNT(*) INTO v_count FROM case_suspects WHERE criminal_id = p_criminal_id; RETURN v_count; END;
    FUNCTION get_vehicle_case_count(p_vehicle_id IN vehicles.vehicle_id%TYPE) RETURN NUMBER IS v_count NUMBER; BEGIN SELECT COUNT(*) INTO v_count FROM case_vehicles WHERE vehicle_id = p_vehicle_id; RETURN v_count; END;
    FUNCTION get_mobile_case_count(p_mobile_id IN mobile_numbers.mobile_id%TYPE) RETURN NUMBER IS v_count NUMBER; BEGIN SELECT COUNT(*) INTO v_count FROM case_mobile_numbers WHERE mobile_id = p_mobile_id; RETURN v_count; END;
    FUNCTION get_officer_open_case_count(p_officer_id IN officers.officer_id%TYPE) RETURN NUMBER IS v_count NUMBER; BEGIN SELECT COUNT(*) INTO v_count FROM cases WHERE officer_id = p_officer_id AND case_status IN ('OPEN','UNDER_INVESTIGATION','PENDING'); RETURN v_count; END;
    FUNCTION get_location_crime_count(p_location_id IN crime_locations.location_id%TYPE) RETURN NUMBER IS v_count NUMBER; BEGIN SELECT COUNT(*) INTO v_count FROM firs WHERE location_id = p_location_id AND fir_status <> 'ARCHIVED'; RETURN v_count; END;
    FUNCTION get_pending_case_count RETURN NUMBER IS v_count NUMBER; BEGIN SELECT COUNT(*) INTO v_count FROM cases WHERE case_status = 'PENDING'; RETURN v_count; END;
END intellicrime_pkg;
/

PROMPT Creating views...

CREATE OR REPLACE VIEW active_cases_view AS
SELECT c.case_id, c.case_title, c.case_status, c.priority, c.opened_date, f.fir_no, ct.crime_type_name, l.area_name, l.city, o.officer_name
FROM cases c
JOIN firs f ON f.fir_id = c.fir_id
JOIN crime_types ct ON ct.crime_type_id = f.crime_type_id
JOIN crime_locations l ON l.location_id = f.location_id
LEFT JOIN officers o ON o.officer_id = c.officer_id
WHERE c.case_status NOT IN ('CLOSED','ARCHIVED');

CREATE OR REPLACE VIEW crime_hotspot_view AS
SELECT l.location_id, l.area_name, l.city, l.district, COUNT(f.fir_id) crime_count, MAX(l.hotspot_level) hotspot_level
FROM crime_locations l LEFT JOIN firs f ON f.location_id = l.location_id AND f.fir_status <> 'ARCHIVED'
GROUP BY l.location_id, l.area_name, l.city, l.district;

CREATE OR REPLACE VIEW criminal_history_view AS
SELECT cr.criminal_id, cr.criminal_name, cr.cnic, cr.criminal_status, COUNT(cs.case_id) linked_case_count,
       LISTAGG(c.case_title, '; ') WITHIN GROUP (ORDER BY c.case_id) case_titles
FROM criminals cr LEFT JOIN case_suspects cs ON cs.criminal_id = cr.criminal_id LEFT JOIN cases c ON c.case_id = cs.case_id
GROUP BY cr.criminal_id, cr.criminal_name, cr.cnic, cr.criminal_status;

CREATE OR REPLACE VIEW officer_case_load_view AS
SELECT o.officer_id, o.officer_name, o.badge_no, s.station_name,
       COUNT(c.case_id) total_cases,
       SUM(CASE WHEN c.case_status IN ('OPEN','UNDER_INVESTIGATION','PENDING') THEN 1 ELSE 0 END) open_cases
FROM officers o JOIN police_stations s ON s.station_id=o.station_id LEFT JOIN cases c ON c.officer_id=o.officer_id
GROUP BY o.officer_id, o.officer_name, o.badge_no, s.station_name;

CREATE OR REPLACE VIEW case_evidence_summary_view AS
SELECT c.case_id, c.case_title, COUNT(e.evidence_id) evidence_count,
       SUM(CASE WHEN e.verification_status='VERIFIED' THEN 1 ELSE 0 END) verified_count,
       SUM(CASE WHEN e.verification_status='PENDING' THEN 1 ELSE 0 END) pending_count
FROM cases c LEFT JOIN evidence e ON e.case_id=c.case_id
GROUP BY c.case_id, c.case_title;

CREATE OR REPLACE VIEW repeated_vehicle_view AS
SELECT v.vehicle_id, v.vehicle_number, v.owner_name, COUNT(cv.case_id) linked_case_count
FROM vehicles v JOIN case_vehicles cv ON cv.vehicle_id=v.vehicle_id
GROUP BY v.vehicle_id, v.vehicle_number, v.owner_name
HAVING COUNT(cv.case_id) > 1;

CREATE OR REPLACE VIEW repeated_mobile_view AS
SELECT m.mobile_id, m.mobile_number, m.owner_name, COUNT(cm.case_id) linked_case_count
FROM mobile_numbers m JOIN case_mobile_numbers cm ON cm.mobile_id=m.mobile_id
GROUP BY m.mobile_id, m.mobile_number, m.owner_name
HAVING COUNT(cm.case_id) > 1;

CREATE OR REPLACE VIEW alert_summary_view AS
SELECT alert_type, alert_status, COUNT(*) alert_count
FROM smart_alerts
GROUP BY alert_type, alert_status;

CREATE OR REPLACE VIEW monthly_crime_summary_view AS
SELECT TO_CHAR(report_date, 'YYYY-MM') month_name, ct.crime_type_name, COUNT(*) crime_count
FROM firs f JOIN crime_types ct ON ct.crime_type_id=f.crime_type_id
GROUP BY TO_CHAR(report_date, 'YYYY-MM'), ct.crime_type_name;

PROMPT Inserting sample data...

INSERT INTO roles VALUES(roles_seq.NEXTVAL,'ADMIN','Full system administrator');
INSERT INTO roles VALUES(roles_seq.NEXTVAL,'OFFICER','Investigation officer');
INSERT INTO roles VALUES(roles_seq.NEXTVAL,'ANALYST','Crime intelligence analyst');
INSERT INTO roles VALUES(roles_seq.NEXTVAL,'ENTRY','FIR data entry user');
INSERT INTO roles VALUES(roles_seq.NEXTVAL,'SUPERVISOR','Station supervisor');
INSERT INTO roles VALUES(roles_seq.NEXTVAL,'EVIDENCE_MANAGER','Evidence room manager');
INSERT INTO roles VALUES(roles_seq.NEXTVAL,'LEGAL','Legal review user');
INSERT INTO roles VALUES(roles_seq.NEXTVAL,'DISPATCH','Dispatch operator');
INSERT INTO roles VALUES(roles_seq.NEXTVAL,'VIEWER','Read-only viewer');
INSERT INTO roles VALUES(roles_seq.NEXTVAL,'AUDITOR','Audit reviewer');

INSERT INTO users VALUES(users_seq.NEXTVAL,1,'admin','plain:admin123','System Administrator','admin@intellicrime.local','03000000001','ACTIVE',SYSTIMESTAMP);
INSERT INTO users VALUES(users_seq.NEXTVAL,2,'officer1','plain:officer123','Inspector Ali Khan','ali.khan@police.demo','03000000002','ACTIVE',SYSTIMESTAMP);
INSERT INTO users VALUES(users_seq.NEXTVAL,3,'analyst1','plain:analyst123','Sara Nadeem','sara.nadeem@police.demo','03000000003','ACTIVE',SYSTIMESTAMP);
INSERT INTO users VALUES(users_seq.NEXTVAL,4,'entry1','plain:entry123','Bilal Ahmed','bilal.ahmed@police.demo','03000000004','ACTIVE',SYSTIMESTAMP);
INSERT INTO users SELECT users_seq.NEXTVAL, MOD(LEVEL,10)+1, 'user'||LEVEL, 'plain:demo123', 'Demo User '||LEVEL, 'user'||LEVEL||'@demo.local', '03000001'||LPAD(LEVEL,3,'0'), 'ACTIVE', SYSTIMESTAMP FROM dual CONNECT BY LEVEL <= 8;

INSERT INTO police_stations SELECT stations_seq.NEXTVAL, station_name, city, district, area, address, phone, 'ACTIVE'
FROM (
    SELECT 'Wah Cantt City Police Station' station_name,'Wah Cantt' city,'Rawalpindi' district,'Lala Rukh' area,'Main GT Road Wah Cantt' address,'0514510001' phone FROM dual UNION ALL
    SELECT 'Taxila Police Station','Taxila','Rawalpindi','Museum Road','Near Taxila Museum','0514510002' FROM dual UNION ALL
    SELECT 'Attock Saddar Police Station','Attock','Attock','Saddar','Saddar Bazaar Attock','0572610003' FROM dual UNION ALL
    SELECT 'Rawalpindi Cantt Police Station','Rawalpindi','Rawalpindi','Cantt','Bank Road Rawalpindi','0515510004' FROM dual UNION ALL
    SELECT 'Islamabad Aabpara Police Station','Islamabad','Islamabad','Aabpara','Sector G-6 Islamabad','0519210005' FROM dual UNION ALL
    SELECT 'Wah Model Town Police Post','Wah Cantt','Rawalpindi','Model Town','Model Town Wah','0514510006' FROM dual UNION ALL
    SELECT 'Taxila Industrial Police Post','Taxila','Rawalpindi','Industrial Area','Hattar Road Taxila','0514510007' FROM dual UNION ALL
    SELECT 'Attock City Police Station','Attock','Attock','City','Committee Chowk Attock','0572610008' FROM dual UNION ALL
    SELECT 'Rawalpindi Airport Police Station','Rawalpindi','Rawalpindi','Airport Road','Airport Road Rawalpindi','0515510009' FROM dual UNION ALL
    SELECT 'Islamabad Sabzi Mandi Police Station','Islamabad','Islamabad','I-11','I-11 Islamabad','0519210010' FROM dual
);

INSERT INTO officers SELECT officers_seq.NEXTVAL, CASE WHEN LEVEL=1 THEN 2 WHEN LEVEL<=8 THEN LEVEL+4 ELSE NULL END, MOD(LEVEL-1,10)+1, 'ICT-'||LPAD(LEVEL,4,'0'), 'Officer '||LEVEL, CASE WHEN MOD(LEVEL,3)=0 THEN 'Sub Inspector' WHEN MOD(LEVEL,3)=1 THEN 'Inspector' ELSE 'ASI' END, '0310000'||LPAD(LEVEL,4,'0'), 'officer'||LEVEL||'@police.demo', DATE '2018-01-01' + LEVEL*90, 'ACTIVE' FROM dual CONNECT BY LEVEL <= 12;

INSERT INTO crime_types SELECT crime_types_seq.NEXTVAL, name, descr, severity FROM (
    SELECT 'Theft' name,'Property theft' descr,'MEDIUM' severity FROM dual UNION ALL SELECT 'Robbery','Robbery using force','HIGH' FROM dual UNION ALL SELECT 'Burglary','Break-in incident','HIGH' FROM dual UNION ALL SELECT 'Vehicle Theft','Vehicle stealing','HIGH' FROM dual UNION ALL SELECT 'Assault','Physical assault','HIGH' FROM dual UNION ALL SELECT 'Kidnapping','Abduction complaint','CRITICAL' FROM dual UNION ALL SELECT 'Cyber Fraud','Online fraud report','MEDIUM' FROM dual UNION ALL SELECT 'Narcotics','Drug possession or dealing','HIGH' FROM dual UNION ALL SELECT 'Homicide','Murder investigation','CRITICAL' FROM dual UNION ALL SELECT 'Harassment','Threats or harassment','LOW' FROM dual UNION ALL SELECT 'Arms Violation','Illegal weapons','HIGH' FROM dual UNION ALL SELECT 'Extortion','Demand for money by threat','CRITICAL' FROM dual
);

INSERT INTO crime_locations SELECT locations_seq.NEXTVAL, area, city, district, level_name FROM (
    SELECT 'Lala Rukh Market' area,'Wah Cantt' city,'Rawalpindi' district,'HIGH' level_name FROM dual UNION ALL SELECT 'GT Road Taxila','Taxila','Rawalpindi','HIGH' FROM dual UNION ALL SELECT 'Saddar Bazaar','Attock','Attock','MEDIUM' FROM dual UNION ALL SELECT 'Bank Road','Rawalpindi','Rawalpindi','MEDIUM' FROM dual UNION ALL SELECT 'Aabpara Market','Islamabad','Islamabad','MEDIUM' FROM dual UNION ALL SELECT 'Model Town','Wah Cantt','Rawalpindi','LOW' FROM dual UNION ALL SELECT 'HIT Road','Wah Cantt','Rawalpindi','MEDIUM' FROM dual UNION ALL SELECT 'Museum Road','Taxila','Rawalpindi','LOW' FROM dual UNION ALL SELECT 'Airport Road','Rawalpindi','Rawalpindi','HIGH' FROM dual UNION ALL SELECT 'I-11 Mandi','Islamabad','Islamabad','HIGH' FROM dual UNION ALL SELECT 'Committee Chowk','Attock','Attock','LOW' FROM dual UNION ALL SELECT 'Hassan Abdal Road','Taxila','Rawalpindi','MEDIUM' FROM dual UNION ALL SELECT 'Dhamial Road','Rawalpindi','Rawalpindi','LOW' FROM dual UNION ALL SELECT 'G-9 Markaz','Islamabad','Islamabad','MEDIUM' FROM dual UNION ALL SELECT 'Wah Garden','Wah Cantt','Rawalpindi','LOW' FROM dual
);

DECLARE
    v_new_id firs.fir_id%TYPE;
BEGIN
    FOR i IN 1..15 LOOP
        intellicrime_pkg.register_fir(
            'FIR-2026-' || LPAD(i,4,'0'), MOD(i-1,10)+1, MOD(i-1,12)+1,
            CASE WHEN i IN (1,5,9,13) THEN 1 WHEN i IN (2,6,10) THEN 2 ELSE MOD(i-1,15)+1 END,
            'Reporter ' || i, '37405-' || LPAD(i,7,'0') || '-1', '0321000' || LPAD(i,4,'0'),
            SYSTIMESTAMP - i, 'Fictional incident description for demo FIR ' || i || ' in investigation workflow.',
            CASE WHEN MOD(i,2)=0 THEN 4 ELSE 1 END, v_new_id
        );
    END LOOP;
END;
/

UPDATE cases SET officer_id = MOD(case_id-1,12)+1;
UPDATE cases SET case_status='UNDER_INVESTIGATION' WHERE case_id IN (2,3,4,5);
UPDATE cases SET case_status='PENDING' WHERE case_id IN (6,7);
UPDATE cases SET case_status='SOLVED' WHERE case_id IN (8,9);
UPDATE cases SET case_status='CLOSED' WHERE case_id IN (10,11);

INSERT INTO criminals SELECT criminals_seq.NEXTVAL, 'Demo Criminal '||LEVEL, '61101-'||LPAD(LEVEL,7,'0')||'-3', CASE WHEN MOD(LEVEL,2)=0 THEN 'Male' ELSE 'Female' END, DATE '1980-01-01'+LEVEL*430, 'Street '||LEVEL||', Rawalpindi Region', '0333000'||LPAD(LEVEL,4,'0'), CASE WHEN MOD(LEVEL,5)=0 THEN 'WANTED' WHEN MOD(LEVEL,4)=0 THEN 'ARRESTED' ELSE 'SUSPECT' END, 'Fictional previous record notes '||LEVEL, SYSTIMESTAMP FROM dual CONNECT BY LEVEL <= 15;

INSERT INTO case_suspects SELECT case_id, MOD(case_id-1,10)+1, 'Primary suspect', 'Under review', SYSTIMESTAMP FROM cases;
INSERT INTO case_suspects SELECT case_id, MOD(case_id+2,15)+1, 'Associate', 'Questioned', SYSTIMESTAMP FROM cases WHERE case_id <= 10;

INSERT INTO victims SELECT victims_seq.NEXTVAL, case_id, 'Victim '||case_id, '35202-'||LPAD(case_id,7,'0')||'-5', CASE WHEN MOD(case_id,2)=0 THEN 'Male' ELSE 'Female' END, '0344000'||LPAD(case_id,4,'0'), 'Demo victim address '||case_id, 'Minor or reported injury details' FROM cases;
INSERT INTO witnesses SELECT witnesses_seq.NEXTVAL, case_id, 'Witness '||case_id, '35201-'||LPAD(case_id,7,'0')||'-7', '0355000'||LPAD(case_id,4,'0'), 'Witness statement summary for case '||case_id FROM cases;
INSERT INTO evidence SELECT evidence_seq.NEXTVAL, MOD(LEVEL-1,15)+1, 'EV-2026-'||LPAD(LEVEL,4,'0'), CASE WHEN MOD(LEVEL,3)=0 THEN 'Digital' WHEN MOD(LEVEL,3)=1 THEN 'Physical' ELSE 'Document' END, 'Evidence demo description '||LEVEL, MOD(LEVEL-1,12)+1, SYSTIMESTAMP-LEVEL, 'Locker '||CHR(64+MOD(LEVEL,5)+1)||'-'||LEVEL, CASE WHEN MOD(LEVEL,4)=0 THEN 'VERIFIED' ELSE 'PENDING' END FROM dual CONNECT BY LEVEL <= 20;
INSERT INTO vehicles SELECT vehicles_seq.NEXTVAL, 'ICT-'||LPAD(LEVEL,4,'0'), 'Vehicle Owner '||LEVEL, '61101-'||LPAD(LEVEL+100,7,'0')||'-9', CASE WHEN MOD(LEVEL,2)=0 THEN 'Car' ELSE 'Motorcycle' END, CASE WHEN MOD(LEVEL,3)=0 THEN 'Honda' WHEN MOD(LEVEL,3)=1 THEN 'Toyota' ELSE 'Suzuki' END, 'Model '||LEVEL, CASE WHEN MOD(LEVEL,4)=0 THEN 'White' WHEN MOD(LEVEL,4)=1 THEN 'Black' WHEN MOD(LEVEL,4)=2 THEN 'Silver' ELSE 'Blue' END FROM dual CONNECT BY LEVEL <= 15;
INSERT INTO case_vehicles SELECT MOD(LEVEL-1,15)+1, MOD(LEVEL-1,9)+1, 'Checkpoint '||LEVEL, SYSTIMESTAMP-LEVEL, 'Seen near scene', CASE WHEN LEVEL <= 8 THEN 'REPEATED' ELSE 'NORMAL' END FROM dual CONNECT BY LEVEL <= 22;
INSERT INTO mobile_numbers SELECT mobile_numbers_seq.NEXTVAL, '03'||CASE WHEN MOD(LEVEL,3)=0 THEN '00' WHEN MOD(LEVEL,3)=1 THEN '21' ELSE '33' END||LPAD(LEVEL,7,'0'), 'Mobile Owner '||LEVEL, CASE WHEN MOD(LEVEL,3)=0 THEN 'Jazz' WHEN MOD(LEVEL,3)=1 THEN 'Zong' ELSE 'Ufone' END, '61101-'||LPAD(LEVEL+200,7,'0')||'-1' FROM dual CONNECT BY LEVEL <= 15;
INSERT INTO case_mobile_numbers SELECT MOD(LEVEL-1,15)+1, MOD(LEVEL-1,8)+1, 'Linked Person '||LEVEL, 'Call data relation', SYSTIMESTAMP-LEVEL, CASE WHEN LEVEL <= 8 THEN 'REPEATED' ELSE 'NORMAL' END FROM dual CONNECT BY LEVEL <= 22;
INSERT INTO investigation_logs SELECT investigation_logs_seq.NEXTVAL, MOD(LEVEL-1,15)+1, MOD(LEVEL-1,12)+1, SYSTIMESTAMP-LEVEL/24, 'Investigation progress note '||LEVEL, 'Next action '||LEVEL FROM dual CONNECT BY LEVEL <= 20;
INSERT INTO smart_alerts(alert_id, case_id, entity_type, entity_id, alert_type, alert_message, alert_status) SELECT smart_alerts_seq.NEXTVAL, MOD(LEVEL-1,15)+1, 'MANUAL', LEVEL, 'DEMO_REVIEW', 'Manual demo alert '||LEVEL, CASE WHEN MOD(LEVEL,3)=0 THEN 'REVIEWED' ELSE 'NEW' END FROM dual CONNECT BY LEVEL <= 10;
INSERT INTO audit_logs(audit_id, user_id, table_name, record_id, operation_type, old_value, new_value) SELECT audit_logs_seq.NEXTVAL, 1, 'DEMO', TO_CHAR(LEVEL), 'INSERT', NULL, 'Seed audit row '||LEVEL FROM dual CONNECT BY LEVEL <= 10;

COMMIT;

PROMPT Tables created
SELECT table_name FROM all_tables WHERE owner = 'INTELLICRIME' AND table_name IN ('ROLES','USERS','POLICE_STATIONS','OFFICERS','CRIME_TYPES','CRIME_LOCATIONS','FIRS','CASES','CRIMINALS','CASE_SUSPECTS','VICTIMS','WITNESSES','EVIDENCE','VEHICLES','CASE_VEHICLES','MOBILE_NUMBERS','CASE_MOBILE_NUMBERS','INVESTIGATION_LOGS','CASE_STATUS_HISTORY','SMART_ALERTS','AUDIT_LOGS') ORDER BY table_name;
PROMPT Views created
SELECT view_name FROM all_views WHERE owner = 'INTELLICRIME' ORDER BY view_name;
PROMPT Triggers created
SELECT trigger_name, status FROM all_triggers WHERE owner = 'INTELLICRIME' ORDER BY trigger_name;
PROMPT Package status
SELECT object_name, object_type, status FROM all_objects WHERE owner = 'INTELLICRIME' AND object_name = 'INTELLICRIME_PKG';
PROMPT Invalid objects
SELECT object_name, object_type, status FROM all_objects WHERE owner = 'INTELLICRIME' AND status <> 'VALID';
PROMPT Row counts
SELECT 'FIRS' table_name, COUNT(*) rows_count FROM firs UNION ALL SELECT 'CASES', COUNT(*) FROM cases UNION ALL SELECT 'CRIMINALS', COUNT(*) FROM criminals UNION ALL SELECT 'EVIDENCE', COUNT(*) FROM evidence UNION ALL SELECT 'SMART_ALERTS', COUNT(*) FROM smart_alerts UNION ALL SELECT 'AUDIT_LOGS', COUNT(*) FROM audit_logs;
PROMPT Sample users
SELECT username, full_name, status FROM users WHERE username IN ('admin','officer1','analyst1','entry1');
PROMPT Sample FIRs
SELECT fir_id, fir_no, reported_by, fir_status FROM firs FETCH FIRST 5 ROWS ONLY;
PROMPT Sample cases
SELECT case_id, case_title, case_status, priority FROM cases FETCH FIRST 5 ROWS ONLY;
PROMPT Sample alerts
SELECT alert_id, alert_type, alert_status, alert_message FROM smart_alerts FETCH FIRST 5 ROWS ONLY;
