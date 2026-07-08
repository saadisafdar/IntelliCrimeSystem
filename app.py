import csv
import io
import logging
import os
from contextlib import contextmanager
from datetime import datetime
from functools import wraps

import oracledb
from dotenv import load_dotenv
from flask import Flask, Response, jsonify, render_template, request, session
from werkzeug.security import check_password_hash, generate_password_hash

load_dotenv()

app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET_KEY", "replace_this_secret")
app.config["JSON_SORT_KEYS"] = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

ORACLE_DSN = os.getenv("ORACLE_DSN", "localhost:1521/XEPDB1")
ORACLE_USER = os.getenv("ORACLE_USER", "intellicrime")
ORACLE_PASSWORD = os.getenv("ORACLE_PASSWORD", "intellicrime123")
PAGE_SIZE = int(os.getenv("PAGE_SIZE", "10"))

pool = None

# ============================================================================
# 5-ROLE RBAC MATRIX - Refactored Role-Based Access Control
# ============================================================================
ROLE_MODULES = {
    "SUPERADMIN": ["dashboard", "users", "firs", "criminals", "cases", "officers", "vehicles", "mobiles", "evidence", "reports", "alerts", "admin"],
    "ADMIN": ["dashboard", "firs", "criminals", "cases", "officers", "vehicles", "mobiles", "evidence", "reports", "alerts"],
    "ANALYST": ["dashboard", "cases", "criminals", "vehicles", "mobiles", "reports", "alerts"],
    "OFFICER": ["dashboard", "cases", "evidence", "alerts"],
    "VIEWER": ["dashboard", "firs", "criminals", "cases", "evidence", "reports", "alerts"],
}

ROLE_LABELS = {
    "SUPERADMIN": "System Master",
    "ADMIN": "Administrator",
    "ANALYST": "Crime Analyst",
    "OFFICER": "Investigation Officer",
    "VIEWER": "Read-Only Auditor",
}


def current_role():
    return session.get("role_name")


def role_modules(role=None):
    return ROLE_MODULES.get(role or current_role(), ["dashboard"])


def can_access(*roles):
    return current_role() in roles


def get_current_officer_id():
    if current_role() != "OFFICER":
        return None
    officer = fetch_one("SELECT officer_id FROM officers WHERE user_id = :user_id", {"user_id": session["user_id"]})
    return officer["officer_id"] if officer else None


def create_pool():
    global pool
    if pool is None:
        pool = oracledb.create_pool(
            user=ORACLE_USER,
            password=ORACLE_PASSWORD,
            dsn=ORACLE_DSN,
            min=1,
            max=5,
            increment=1,
        )
    return pool


@contextmanager
def get_connection():
    conn = create_pool().acquire()
    try:
        user_id = session.get("user_id")
        if user_id is not None:
            # Force conversion to clean string format for Oracle CLIENT_IDENTIFIER
            conn.client_identifier = str(user_id)
        yield conn
    finally:
        conn.close()


def rows_to_dicts(cursor):
    columns = [col[0].lower() for col in cursor.description]
    result = []
    for row in cursor.fetchall():
        item = {}
        for key, value in zip(columns, row):
            if isinstance(value, datetime):
                item[key] = value.isoformat(sep=" ", timespec="seconds")
            else:
                item[key] = value
        result.append(item)
    return result


def fetch_all(sql, params=None):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params or {})
            return rows_to_dicts(cur)


def fetch_one(sql, params=None):
    rows = fetch_all(sql, params)
    return rows[0] if rows else None


def execute(sql, params=None):
    with get_connection() as conn:
        try:
            with conn.cursor() as cur:
                cur.execute(sql, params or {})
            conn.commit()
            return True
        except Exception as e:
            conn.rollback()
            logger.error(f"Database execute error: {e}")
            raise


def call_procedure(name, params=None, out_type=oracledb.NUMBER):
    with get_connection() as conn:
        try:
            with conn.cursor() as cur:
                values = list(params or [])
                out_value = cur.var(out_type)
                values.append(out_value)
                cur.callproc(name, values)
                conn.commit()
                return out_value.getvalue()
        except Exception as e:
            conn.rollback()
            logger.error(f"Procedure call error: {e}")
            raise


def json_error(message, status=400):
    return jsonify({"ok": False, "error": message}), status


def require_login(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        if not session.get("user_id"):
            return json_error("Login required", 401)
        return fn(*args, **kwargs)
    return wrapper


def require_role(*roles):
    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            if not session.get("user_id"):
                return json_error("Login required", 401)
            if session.get("role_name") not in roles:
                return json_error("You are not allowed to perform this action", 403)
            return fn(*args, **kwargs)
        return wrapper
    return decorator


def body():
    return request.get_json(silent=True) or {}


def required(data, *fields):
    missing = [field for field in fields if data.get(field) in (None, "")]
    if missing:
        raise ValueError("Required field missing: " + ", ".join(missing))


def int_or_none(value):
    if value in (None, ""):
        return None
    return int(value)


def like(value):
    return f"%{value.strip().lower()}%"


def parse_date(value):
    if not value:
        return None
    return datetime.fromisoformat(value.replace("Z", "+00:00").replace("T", " ")).replace(tzinfo=None)


def paged_query(base_sql, params, order_by, page=None, size=None):
    page = max(int(page or request.args.get("page", 1)), 1)
    size = min(max(int(size or request.args.get("size", PAGE_SIZE)), 1), 100)
    start_row = (page - 1) * size + 1
    end_row = page * size
    sql = f"""
        SELECT * FROM (
            SELECT q.*, ROW_NUMBER() OVER (ORDER BY {order_by}) rn
            FROM ({base_sql}) q
        )
        WHERE rn BETWEEN :start_row AND :end_row
    """
    params = dict(params)
    params.update({"start_row": start_row, "end_row": end_row})
    return fetch_all(sql, params)


def safe_update(table, id_col, row_id, allowed, data):
    sets = []
    params = {"id": row_id}
    for field in allowed:
        if field in data:
            sets.append(f"{field} = :{field}")
            params[field] = data[field]
    if not sets:
        raise ValueError("No editable fields supplied")
    execute(f"UPDATE {table} SET {', '.join(sets)} WHERE {id_col} = :id", params)


@app.errorhandler(Exception)
def handle_error(exc):
    logging.exception("Application error")
    return json_error("A server error occurred. Check the Flask terminal for details.", 500)


@app.route("/")
def index():
    return render_template("index.html")


@app.post("/api/login")
def login():
    data = body()
    required(data, "username", "password")
    user = fetch_one(
        """
        SELECT u.user_id, u.username, u.password_hash, u.full_name, u.status, r.role_name
        FROM users u JOIN roles r ON r.role_id = u.role_id
        WHERE LOWER(u.username) = LOWER(:username)
        """,
        {"username": data["username"]},
    )
    if not user or user["status"] != "ACTIVE":
        return json_error("Invalid username or inactive account", 401)
    stored = user["password_hash"]
    ok = stored.startswith("plain:") and data["password"] == stored.split(":", 1)[1]
    if not ok:
        ok = check_password_hash(stored, data["password"])
    if not ok:
        return json_error("Invalid username or password", 401)
    session.clear()
    session.update(
        user_id=user["user_id"],
        username=user["username"],
        full_name=user["full_name"],
        role_name=user["role_name"],
    )
    if stored.startswith("plain:"):
        execute("UPDATE users SET password_hash = :hash WHERE user_id = :id", {"hash": generate_password_hash(data["password"]), "id": user["user_id"]})
    return jsonify({"ok": True, "user": session_user()})


@app.post("/api/register")
def signup():
    data = body()
    
    if "role" in data and "role_name" not in data:
        data["role_name"] = data["role"]

    required(data, "full_name", "username", "email", "password", "role_name")
    if len(data["password"]) < 6:
        return json_error("Password must be at least 6 characters", 400)
    
    # ========================================================================
    # CRITICAL: Block SUPERADMIN and ADMIN registration from signup screen
    # Only allow VIEWER, ANALYST, OFFICER self-registration
    # ========================================================================
    if data["role_name"] not in ("VIEWER", "ANALYST", "OFFICER"):
        return json_error("Only Viewer, Analyst, or Officer roles can be registered. Contact system admin for elevated access.", 400)
    
    role = fetch_one("SELECT role_id FROM roles WHERE role_name = :role_name", {"role_name": data["role_name"]})
    if not role:
        return json_error("Selected role does not exist in Oracle", 400)
    if fetch_one("SELECT user_id FROM users WHERE LOWER(username)=LOWER(:username)", {"username": data["username"]}):
        return json_error("Username already exists", 409)
    if fetch_one("SELECT user_id FROM users WHERE LOWER(email)=LOWER(:email)", {"email": data["email"]}):
        return json_error("Email already exists", 409)
    execute(
        """
        INSERT INTO users(user_id, role_id, username, password_hash, full_name, email, status, created_at)
        VALUES(users_seq.NEXTVAL, :role_id, :username, :password_hash, :full_name, :email, 'ACTIVE', SYSTIMESTAMP)
        """,
        {
            "role_id": role["role_id"],
            "username": data["username"],
            "password_hash": generate_password_hash(data["password"]),
            "full_name": data["full_name"],
            "email": data["email"],
        },
    )
    return jsonify(ok=True, message="Account created. You can login now.")


@app.post("/api/logout")
def logout():
    session.clear()
    return jsonify({"ok": True})


def session_user():
    if not session.get("user_id"):
        return None
    return {
        "user_id": session["user_id"],
        "username": session["username"],
        "full_name": session["full_name"],
        "role_name": session["role_name"],
        "role_label": ROLE_LABELS.get(session["role_name"], session["role_name"]),
        "modules": role_modules(session["role_name"]),
    }


@app.get("/api/session")
def current_session():
    return jsonify({"ok": True, "user": session_user()})


@app.get("/api/lookups")
@require_login
def lookups():
    return jsonify(
        ok=True,
        stations=fetch_all("SELECT station_id, station_name FROM police_stations WHERE status='ACTIVE' ORDER BY station_name"),
        crime_types=fetch_all("SELECT crime_type_id, crime_type_name, severity_level FROM crime_types ORDER BY crime_type_name"),
        locations=fetch_all("SELECT location_id, area_name, city FROM crime_locations ORDER BY city, area_name"),
        officers=fetch_all("SELECT officer_id, officer_name, badge_no FROM officers WHERE status='ACTIVE' ORDER BY officer_name"),
        criminals=fetch_all("SELECT criminal_id, criminal_name, cnic FROM criminals ORDER BY criminal_name"),
        cases=fetch_all("SELECT case_id, case_title FROM cases WHERE case_status <> 'ARCHIVED' ORDER BY case_id DESC"),
    )


@app.get("/api/dashboard")
@require_login
def dashboard():
    totals = {
        "firs": fetch_one("SELECT COUNT(*) value FROM firs WHERE fir_status <> 'ARCHIVED'")["value"],
        "active_cases": fetch_one("SELECT COUNT(*) value FROM active_cases_view")["value"],
        "criminals": fetch_one("SELECT COUNT(*) value FROM criminals WHERE criminal_status <> 'CLEARED'")["value"],
        "evidence": fetch_one("SELECT COUNT(*) value FROM evidence WHERE verification_status <> 'ARCHIVED'")["value"],
        "new_alerts": fetch_one("SELECT COUNT(*) value FROM smart_alerts WHERE alert_status='NEW'")["value"],
    }
    return jsonify(
        ok=True,
        totals=totals,
        recent_firs=fetch_all("SELECT fir_id, fir_no, reported_by, fir_status, report_date FROM firs ORDER BY report_date DESC FETCH FIRST 8 ROWS ONLY"),
        recent_alerts=fetch_all("SELECT alert_id, alert_type, alert_status, alert_message, alert_date FROM smart_alerts ORDER BY alert_date DESC FETCH FIRST 8 ROWS ONLY"),
        cases_by_status=fetch_all("SELECT case_status label, COUNT(*) value FROM cases GROUP BY case_status"),
        crimes_by_type=fetch_all("SELECT ct.crime_type_name label, COUNT(*) value FROM firs f JOIN crime_types ct ON ct.crime_type_id=f.crime_type_id GROUP BY ct.crime_type_name"),
        top_locations=fetch_all("SELECT area_name, city, crime_count FROM crime_hotspot_view ORDER BY crime_count DESC FETCH FIRST 5 ROWS ONLY"),
        officer_workload=fetch_all("SELECT officer_name, open_cases, total_cases FROM officer_case_load_view ORDER BY open_cases DESC FETCH FIRST 8 ROWS ONLY"),
    )


@app.route("/api/firs", methods=["GET", "POST"])
@require_role("SUPERADMIN", "ADMIN", "OFFICER")
def firs():
    if request.method == "GET":
        sql = """
            SELECT f.fir_id, f.fir_no, f.reported_by, f.reporter_phone, f.report_date, f.fir_status,
                   s.station_name, ct.crime_type_name, l.area_name, l.city
            FROM firs f
            JOIN police_stations s ON s.station_id=f.station_id
            JOIN crime_types ct ON ct.crime_type_id=f.crime_type_id
            JOIN crime_locations l ON l.location_id=f.location_id
            WHERE 1=1
        """
        params = {}
        if request.args.get("q"):
            sql += " AND (LOWER(f.fir_no) LIKE :q OR LOWER(f.reported_by) LIKE :q)"
            params["q"] = like(request.args["q"])
        for arg, col in [("station_id", "f.station_id"), ("crime_type_id", "f.crime_type_id")]:
            if request.args.get(arg):
                sql += f" AND {col} = :{arg}"
                params[arg] = int(request.args[arg])
        if request.args.get("status"):
            sql += " AND f.fir_status = :status"
            params["status"] = request.args["status"]
        return jsonify(ok=True, rows=paged_query(sql, params, "report_date DESC"))
    data = body()
    required(data, "fir_no", "station_id", "crime_type_id", "location_id", "reported_by", "description")
    new_id = call_procedure(
        "intellicrime_pkg.register_fir",
        [
            data["fir_no"],
            int(data["station_id"]),
            int(data["crime_type_id"]),
            int(data["location_id"]),
            data["reported_by"],
            data.get("reporter_cnic"),
            data.get("reporter_phone"),
            parse_date(data.get("incident_at")),
            data["description"],
            session["user_id"],
        ],
    )
    return jsonify(ok=True, id=new_id)


@app.route("/api/firs/<int:fir_id>", methods=["PUT", "DELETE"])
@require_role("SUPERADMIN", "ADMIN", "OFFICER")
def fir_item(fir_id):
    if request.method == "DELETE":
        execute("BEGIN intellicrime_pkg.archive_fir(:id); END;", {"id": fir_id})
        return jsonify(ok=True)
    safe_update(
        "firs",
        "fir_id",
        fir_id,
        ["reported_by", "reporter_cnic", "reporter_phone", "description", "fir_status"],
        body(),
    )
    return jsonify(ok=True)


@app.route("/api/criminals", methods=["GET", "POST"])
@require_role("SUPERADMIN", "ADMIN", "ANALYST", "OFFICER")
def criminals():
    if request.method == "GET":
        sql = """
            SELECT c.*, NVL(h.linked_case_count,0) linked_case_count
            FROM criminals c
            LEFT JOIN criminal_history_view h ON h.criminal_id=c.criminal_id
            WHERE 1=1
        """
        params = {}
        if request.args.get("q"):
            sql += " AND (LOWER(c.criminal_name) LIKE :q OR LOWER(c.cnic) LIKE :q OR LOWER(c.phone) LIKE :q)"
            params["q"] = like(request.args["q"])
        if request.args.get("status"):
            sql += " AND c.criminal_status = :status"
            params["status"] = request.args["status"]
        return jsonify(ok=True, rows=paged_query(sql, params, "criminal_id DESC"))
    data = body()
    required(data, "criminal_name")
    new_id = call_procedure(
        "intellicrime_pkg.add_criminal",
        [
            data["criminal_name"],
            data.get("cnic"),
            data.get("gender"),
            parse_date(data.get("date_of_birth")),
            data.get("address"),
            data.get("phone"),
            data.get("criminal_status", "SUSPECT"),
            data.get("previous_record"),
        ],
    )
    return jsonify(ok=True, id=new_id)


@app.route("/api/criminals/<int:criminal_id>", methods=["PUT", "DELETE"])
@require_role("SUPERADMIN", "ADMIN", "OFFICER")
def criminal_item(criminal_id):
    if request.method == "DELETE":
        execute("UPDATE criminals SET criminal_status='CLEARED' WHERE criminal_id=:id", {"id": criminal_id})
        return jsonify(ok=True)
    safe_update(
        "criminals",
        "criminal_id",
        criminal_id,
        ["criminal_name", "cnic", "gender", "date_of_birth", "address", "phone", "criminal_status", "previous_record"],
        body(),
    )
    return jsonify(ok=True)


# ============================================================================
# MANUAL CASE MANAGEMENT OVERHAUL - GET, POST, PUT Support
# ============================================================================
@app.route("/api/cases", methods=["GET", "POST", "PUT"])
@require_role("SUPERADMIN", "ADMIN", "OFFICER", "ANALYST")
def cases():
    if request.method == "GET":
        sql = """
            SELECT c.case_id, c.case_title, c.case_status, c.priority, c.opened_date, c.closed_date,
                   f.fir_no, o.officer_name, ct.crime_type_name
            FROM cases c
            JOIN firs f ON f.fir_id=c.fir_id
            JOIN crime_types ct ON ct.crime_type_id=f.crime_type_id
            LEFT JOIN officers o ON o.officer_id=c.officer_id
            WHERE 1=1
        """
        params = {}
        officer_id = get_current_officer_id()
        if officer_id:
            sql += " AND c.officer_id = :current_officer_id"
            params["current_officer_id"] = officer_id
        if request.args.get("q"):
            sql += " AND (LOWER(c.case_title) LIKE :q OR LOWER(f.fir_no) LIKE :q)"
            params["q"] = like(request.args["q"])
        if request.args.get("status"):
            sql += " AND c.case_status = :status"
            params["status"] = request.args["status"]
        return jsonify(ok=True, rows=paged_query(sql, params, "case_id DESC"))
    
    # ========================================================================
    # POST: Manually create a new case (alternative to auto-generation from FIR)
    # ========================================================================
    if request.method == "POST":
        data = body()
        required(data, "case_title", "case_description")
        fir_id = int_or_none(data.get("fir_id"))
        officer_id = int_or_none(data.get("officer_id"))
        case_status = data.get("case_status", "OPEN")
        priority = data.get("priority", "MEDIUM")
        
        execute(
            """
            INSERT INTO cases (case_id, fir_id, officer_id, case_title, case_description, case_status, priority, opened_date)
            VALUES (cases_seq.NEXTVAL, :fir_id, :officer_id, :case_title, :case_description, :case_status, :priority, SYSTIMESTAMP)
            """,
            {
                "fir_id": fir_id,
                "officer_id": officer_id,
                "case_title": data["case_title"],
                "case_description": data["case_description"],
                "case_status": case_status,
                "priority": priority,
            },
        )
        return jsonify(ok=True, message="Case created successfully")
    
    # ========================================================================
    # PUT: Update an existing case (case_id and field(s) to update required)
    # ========================================================================
    if request.method == "PUT":
        data = body()
        required(data, "case_id")
        case_id = int(data["case_id"])
        safe_update(
            "cases",
            "case_id",
            case_id,
            ["case_title", "case_description", "case_status", "priority", "officer_id"],
            data,
        )
        return jsonify(ok=True, message="Case updated successfully")


@app.get("/api/cases/<int:case_id>")
@require_role("SUPERADMIN", "ADMIN", "OFFICER", "ANALYST")
def case_detail(case_id):
    info = fetch_one(
        """
        SELECT c.*, f.fir_no, f.reported_by, f.reporter_phone, f.description fir_description,
               o.officer_name, s.station_name, ct.crime_type_name, l.area_name, l.city
        FROM cases c
        JOIN firs f ON f.fir_id=c.fir_id
        JOIN police_stations s ON s.station_id=f.station_id
        JOIN crime_types ct ON ct.crime_type_id=f.crime_type_id
        JOIN crime_locations l ON l.location_id=f.location_id
        LEFT JOIN officers o ON o.officer_id=c.officer_id
        WHERE c.case_id=:id
        """,
        {"id": case_id},
    )
    if not info:
        return json_error("Case not found", 404)
    officer_id = get_current_officer_id()
    if officer_id and info.get("officer_id") != officer_id:
        return json_error("You can only open cases assigned to you", 403)
    return jsonify(
        ok=True,
        case=info,
        suspects=fetch_all("SELECT cs.*, cr.criminal_name, cr.cnic FROM case_suspects cs JOIN criminals cr ON cr.criminal_id=cs.criminal_id WHERE cs.case_id=:id", {"id": case_id}),
        victims=fetch_all("SELECT * FROM victims WHERE case_id=:id", {"id": case_id}),
        witnesses=fetch_all("SELECT * FROM witnesses WHERE case_id=:id", {"id": case_id}),
        evidence=fetch_all("SELECT * FROM evidence WHERE case_id=:id", {"id": case_id}),
        vehicles=fetch_all("SELECT cv.*, v.vehicle_number, v.owner_name, v.make, v.model FROM case_vehicles cv JOIN vehicles v ON v.vehicle_id=cv.vehicle_id WHERE cv.case_id=:id", {"id": case_id}),
        mobiles=fetch_all("SELECT cm.*, m.mobile_number, m.owner_name, m.network FROM case_mobile_numbers cm JOIN mobile_numbers m ON m.mobile_id=cm.mobile_id WHERE cm.case_id=:id", {"id": case_id}),
        logs=fetch_all("SELECT l.*, o.officer_name FROM investigation_logs l LEFT JOIN officers o ON o.officer_id=l.officer_id WHERE l.case_id=:id ORDER BY l.log_date DESC", {"id": case_id}),
        history=fetch_all("SELECT h.*, u.username changed_by_name FROM case_status_history h LEFT JOIN users u ON u.user_id=h.changed_by WHERE h.case_id=:id ORDER BY h.changed_at DESC", {"id": case_id}),
        alerts=fetch_all("SELECT * FROM smart_alerts WHERE case_id=:id ORDER BY alert_date DESC", {"id": case_id}),
    )


@app.post("/api/cases/<int:case_id>/assign-officer")
@require_role("SUPERADMIN", "ADMIN")
def assign_case(case_id):
    data = body()
    required(data, "officer_id")
    execute("BEGIN intellicrime_pkg.assign_case_to_officer(:case_id, :officer_id); END;", {"case_id": case_id, "officer_id": int(data["officer_id"])})
    return jsonify(ok=True)


@app.post("/api/cases/<int:case_id>/status")
@require_role("SUPERADMIN", "ADMIN", "OFFICER")
def update_case_status(case_id):
    data = body()
    required(data, "case_status")
    execute("BEGIN intellicrime_pkg.update_case_status(:case_id, :status, :remarks); END;", {"case_id": case_id, "status": data["case_status"], "remarks": data.get("remarks")})
    return jsonify(ok=True)


@app.post("/api/cases/<int:case_id>/suspects")
@require_role("SUPERADMIN", "ADMIN", "ANALYST", "OFFICER")
def add_suspect(case_id):
    data = body()
    required(data, "criminal_id")
    execute("BEGIN intellicrime_pkg.link_suspect_to_case(:case_id, :criminal_id, :role, :status); END;", {"case_id": case_id, "criminal_id": int(data["criminal_id"]), "role": data.get("suspect_role"), "status": data.get("involvement_status")})
    return jsonify(ok=True)


@app.delete("/api/cases/<int:case_id>/suspects/<int:criminal_id>")
@require_role("SUPERADMIN", "ADMIN", "ANALYST", "OFFICER")
def remove_suspect(case_id, criminal_id):
    execute("DELETE FROM case_suspects WHERE case_id=:case_id AND criminal_id=:criminal_id", {"case_id": case_id, "criminal_id": criminal_id})
    return jsonify(ok=True)


@app.post("/api/cases/<int:case_id>/victims")
@require_role("SUPERADMIN", "ADMIN", "OFFICER", "ANALYST")
def add_victim(case_id):
    data = body()
    required(data, "victim_name")
    new_id = call_procedure("intellicrime_pkg.add_victim", [case_id, data["victim_name"], data.get("cnic"), data.get("gender"), data.get("phone"), data.get("address"), data.get("injury_details")])
    return jsonify(ok=True, id=new_id)


@app.post("/api/cases/<int:case_id>/witnesses")
@require_role("SUPERADMIN", "ADMIN", "OFFICER", "ANALYST")
def add_witness(case_id):
    data = body()
    required(data, "witness_name")
    new_id = call_procedure("intellicrime_pkg.add_witness", [case_id, data["witness_name"], data.get("cnic"), data.get("phone"), data.get("statement_summary")])
    return jsonify(ok=True, id=new_id)


@app.post("/api/cases/<int:case_id>/logs")
@require_role("SUPERADMIN", "ADMIN", "OFFICER", "ANALYST")
def add_log(case_id):
    data = body()
    required(data, "progress_note")
    new_id = call_procedure("intellicrime_pkg.add_investigation_log", [case_id, int_or_none(data.get("officer_id")), data["progress_note"], data.get("next_action")])
    return jsonify(ok=True, id=new_id)


@app.delete("/api/cases/<int:case_id>")
@require_role("SUPERADMIN", "ADMIN")
def archive_case(case_id):
    execute("BEGIN intellicrime_pkg.archive_case(:id); END;", {"id": case_id})
    return jsonify(ok=True)


@app.route("/api/evidence", methods=["GET", "POST"])
@require_role("SUPERADMIN", "ADMIN", "OFFICER", "ANALYST")
def evidence():
    if request.method == "GET":
        sql = "SELECT e.*, c.case_title, o.officer_name FROM evidence e JOIN cases c ON c.case_id=e.case_id LEFT JOIN officers o ON o.officer_id=e.collected_by WHERE 1=1"
        params = {}
        if request.args.get("q"):
            sql += " AND LOWER(e.evidence_code) LIKE :q"
            params["q"] = like(request.args["q"])
        for arg, col in [("case_id", "e.case_id"), ("verification_status", "e.verification_status")]:
            if request.args.get(arg):
                sql += f" AND {col} = :{arg}"
                params[arg] = int(request.args[arg]) if arg.endswith("_id") else request.args[arg]
        if request.args.get("evidence_type"):
            sql += " AND LOWER(e.evidence_type) LIKE :evidence_type"
            params["evidence_type"] = like(request.args["evidence_type"])
        return jsonify(ok=True, rows=paged_query(sql, params, "evidence_id DESC"))
    data = body()
    required(data, "case_id", "evidence_code", "evidence_type")
    new_id = call_procedure("intellicrime_pkg.add_evidence", [int(data["case_id"]), data["evidence_code"], data["evidence_type"], data.get("evidence_description"), int_or_none(data.get("collected_by")), data.get("storage_location")])
    return jsonify(ok=True, id=new_id)


@app.route("/api/evidence/<int:evidence_id>", methods=["PUT", "DELETE"])
@require_role("SUPERADMIN", "ADMIN", "OFFICER", "ANALYST")
def evidence_item(evidence_id):
    if request.method == "DELETE":
        execute("UPDATE evidence SET verification_status='ARCHIVED' WHERE evidence_id=:id", {"id": evidence_id})
        return jsonify(ok=True)
    safe_update("evidence", "evidence_id", evidence_id, ["evidence_type", "evidence_description", "storage_location", "verification_status"], body())
    return jsonify(ok=True)


@app.route("/api/vehicles", methods=["GET", "POST"])
@require_role("SUPERADMIN", "ADMIN", "ANALYST")
def vehicles():
    if request.method == "GET":
        sql = """
            SELECT v.*, COUNT(cv.case_id) linked_case_count,
                   CASE WHEN COUNT(cv.case_id)>1 THEN 'REPEATED' ELSE 'NORMAL' END suspicious_status
            FROM vehicles v LEFT JOIN case_vehicles cv ON cv.vehicle_id=v.vehicle_id
            WHERE 1=1
        """
        params = {}
        if request.args.get("q"):
            sql += " AND (LOWER(v.vehicle_number) LIKE :q OR LOWER(v.owner_name) LIKE :q OR LOWER(v.model) LIKE :q)"
            params["q"] = like(request.args["q"])
        sql += " GROUP BY v.vehicle_id, v.vehicle_number, v.owner_name, v.owner_cnic, v.vehicle_type, v.make, v.model, v.color"
        return jsonify(ok=True, rows=paged_query(sql, params, "vehicle_id DESC"))
    data = body()
    required(data, "vehicle_number")
    new_id = call_procedure("intellicrime_pkg.add_vehicle", [data["vehicle_number"], data.get("owner_name"), data.get("owner_cnic"), data.get("vehicle_type"), data.get("make"), data.get("model"), data.get("color")])
    return jsonify(ok=True, id=new_id)


@app.put("/api/vehicles/<int:vehicle_id>")
@require_role("SUPERADMIN", "ADMIN", "ANALYST")
def update_vehicle(vehicle_id):
    safe_update("vehicles", "vehicle_id", vehicle_id, ["vehicle_number", "owner_name", "owner_cnic", "vehicle_type", "make", "model", "color"], body())
    return jsonify(ok=True)


@app.post("/api/vehicles/<int:vehicle_id>/link")
@require_role("SUPERADMIN", "ADMIN", "ANALYST")
def link_vehicle(vehicle_id):
    data = body()
    required(data, "case_id")
    execute("BEGIN intellicrime_pkg.link_vehicle_to_case(:case_id, :vehicle_id, :loc, :rel, :status); END;", {"case_id": int(data["case_id"]), "vehicle_id": vehicle_id, "loc": data.get("detected_location"), "rel": data.get("relation_to_case"), "status": data.get("suspicious_status", "NORMAL")})
    return jsonify(ok=True)


@app.delete("/api/vehicles/<int:vehicle_id>/link/<int:case_id>")
@require_role("SUPERADMIN", "ADMIN", "ANALYST")
def unlink_vehicle(vehicle_id, case_id):
    execute("DELETE FROM case_vehicles WHERE vehicle_id=:vehicle_id AND case_id=:case_id", {"vehicle_id": vehicle_id, "case_id": case_id})
    return jsonify(ok=True)


@app.route("/api/mobiles", methods=["GET", "POST"])
@require_role("SUPERADMIN", "ADMIN", "ANALYST")
def mobiles():
    if request.method == "GET":
        sql = """
            SELECT m.*, COUNT(cm.case_id) linked_case_count,
                   CASE WHEN COUNT(cm.case_id)>1 THEN 'REPEATED' ELSE 'NORMAL' END suspicious_status
            FROM mobile_numbers m LEFT JOIN case_mobile_numbers cm ON cm.mobile_id=m.mobile_id
            WHERE 1=1
        """
        params = {}
        if request.args.get("q"):
            sql += " AND (LOWER(m.mobile_number) LIKE :q OR LOWER(m.owner_name) LIKE :q OR LOWER(m.registered_cnic) LIKE :q)"
            params["q"] = like(request.args["q"])
        sql += " GROUP BY m.mobile_id, m.mobile_number, m.owner_name, m.network, m.registered_cnic"
        return jsonify(ok=True, rows=paged_query(sql, params, "mobile_id DESC"))
    data = body()
    required(data, "mobile_number")
    new_id = call_procedure("intellicrime_pkg.add_mobile_number", [data["mobile_number"], data.get("owner_name"), data.get("network"), data.get("registered_cnic")])
    return jsonify(ok=True, id=new_id)


@app.put("/api/mobiles/<int:mobile_id>")
@require_role("SUPERADMIN", "ADMIN", "ANALYST")
def update_mobile(mobile_id):
    safe_update("mobile_numbers", "mobile_id", mobile_id, ["mobile_number", "owner_name", "network", "registered_cnic"], body())
    return jsonify(ok=True)


@app.post("/api/mobiles/<int:mobile_id>/link")
@require_role("SUPERADMIN", "ADMIN", "ANALYST")
def link_mobile(mobile_id):
    data = body()
    required(data, "case_id")
    execute("BEGIN intellicrime_pkg.link_mobile_to_case(:case_id, :mobile_id, :person, :rel, :status); END;", {"case_id": int(data["case_id"]), "mobile_id": mobile_id, "person": data.get("linked_person"), "rel": data.get("relation_to_case"), "status": data.get("suspicious_status", "NORMAL")})
    return jsonify(ok=True)


@app.delete("/api/mobiles/<int:mobile_id>/link/<int:case_id>")
@require_role("SUPERADMIN", "ADMIN", "ANALYST")
def unlink_mobile(mobile_id, case_id):
    execute("DELETE FROM case_mobile_numbers WHERE mobile_id=:mobile_id AND case_id=:case_id", {"mobile_id": mobile_id, "case_id": case_id})
    return jsonify(ok=True)


@app.get("/api/alerts")
@require_login
def alerts():
    sql = "SELECT a.*, c.case_title FROM smart_alerts a LEFT JOIN cases c ON c.case_id=a.case_id WHERE 1=1"
    params = {}
    if request.args.get("type"):
        sql += " AND a.alert_type = :type"
        params["type"] = request.args["type"]
    if request.args.get("status"):
        sql += " AND a.alert_status = :status"
        params["status"] = request.args["status"]
    return jsonify(ok=True, rows=paged_query(sql, params, "alert_date DESC"))


def set_alert(alert_id, status):
    execute("BEGIN intellicrime_pkg.resolve_alert(:id, :user_id, :status); END;", {"id": alert_id, "user_id": session["user_id"], "status": status})
    return jsonify(ok=True)


@app.post("/api/alerts/<int:alert_id>/review")
@require_login
def review_alert(alert_id):
    return set_alert(alert_id, "REVIEWED")


@app.post("/api/alerts/<int:alert_id>/resolve")
@require_login
def resolve_alert(alert_id):
    return set_alert(alert_id, "RESOLVED")


@app.post("/api/alerts/<int:alert_id>/dismiss")
@require_login
def dismiss_alert(alert_id):
    return set_alert(alert_id, "DISMISSED")


def report_data():
    return {
        "active_cases": fetch_all("SELECT * FROM active_cases_view"),
        "closed_cases": fetch_all("SELECT case_id, case_title, closed_date FROM cases WHERE case_status='CLOSED'"),
        "pending_cases": fetch_all("SELECT case_id, case_title, priority FROM cases WHERE case_status='PENDING'"),
        "crime_hotspots": fetch_all("SELECT * FROM crime_hotspot_view ORDER BY crime_count DESC"),
        "monthly_crime_totals": fetch_all("SELECT * FROM monthly_crime_summary_view"),
        "criminal_history": fetch_all("SELECT * FROM criminal_history_view"),
        "repeated_criminals": fetch_all("SELECT * FROM criminal_history_view WHERE linked_case_count > 1"),
        "repeated_vehicles": fetch_all("SELECT * FROM repeated_vehicle_view"),
        "repeated_mobiles": fetch_all("SELECT * FROM repeated_mobile_view"),
        "officer_workload": fetch_all("SELECT * FROM officer_case_load_view"),
        "evidence_status": fetch_all("SELECT verification_status, COUNT(*) count FROM evidence GROUP BY verification_status"),
        "alerts_by_type": fetch_all("SELECT alert_type, COUNT(*) count FROM smart_alerts GROUP BY alert_type"),
        "firs_by_station": fetch_all("SELECT s.station_name, COUNT(*) count FROM firs f JOIN police_stations s ON s.station_id=f.station_id GROUP BY s.station_name"),
        "crimes_by_severity": fetch_all("SELECT ct.severity_level, COUNT(*) count FROM firs f JOIN crime_types ct ON ct.crime_type_id=f.crime_type_id GROUP BY ct.severity_level"),
    }


@app.get("/api/reports")
@require_role("SUPERADMIN", "ADMIN", "ANALYST")
def reports():
    return jsonify(ok=True, reports=report_data())


# ============================================================================
# CSV REPORT GENERATION ENGINE - /api/reports/export
# Exportable reporting system with standard CSV format download
# ============================================================================
@app.get("/api/reports/export")
@require_role("SUPERADMIN", "ADMIN", "ANALYST")
def export_reports():
    """
    CSV Report Export Engine
    - Accepts optional 'type' query parameter (firs, cases, evidence, etc.)
    - Generates standard CSV format using Python csv module
    - Returns downloadable file response stream (text/csv)
    """
    report_type = request.args.get("type", "all").lower()
    output = io.StringIO()
    writer = csv.writer(output)
    
    reports = report_data()
    
    # If specific type requested, export only that report
    if report_type != "all" and report_type in reports:
        reports = {report_type: reports[report_type]}
    
    # Write all requested reports to CSV
    for name, rows in reports.items():
        writer.writerow([name.upper().replace("_", " ")])
        writer.writerow([])  # Blank line for readability
        
        if rows:
            # Write header row
            writer.writerow(rows[0].keys())
            # Write data rows
            for row in rows:
                writer.writerow(row.values())
        else:
            writer.writerow(["No data available"])
        
        writer.writerow([])  # Blank line between reports
    
    filename = f"intellicrime_reports_{report_type}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
    return Response(
        output.getvalue(),
        mimetype="text/csv",
        headers={"Content-Disposition": f"attachment; filename={filename}"}
    )


@app.get("/api/admin")
@require_role("SUPERADMIN")
def admin():
    return jsonify(
        ok=True,
        users=fetch_all("SELECT u.user_id, u.username, u.full_name, u.status, r.role_name FROM users u JOIN roles r ON r.role_id=u.role_id ORDER BY u.user_id"),
        stations=fetch_all("SELECT * FROM police_stations ORDER BY station_id"),
        audit_logs=fetch_all("SELECT audit_id, user_id, table_name, record_id, operation_type, changed_at FROM audit_logs ORDER BY changed_at DESC FETCH FIRST 50 ROWS ONLY"),
    )


if __name__ == "__main__":
    app.run(debug=True, host="127.0.0.1", port=5000)
