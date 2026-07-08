# IntelliCrime System

IntelliCrime System is the current production-ready implementation of a crime investigation and case management platform built with Flask, Oracle Database, and a lightweight web frontend.

## 3-Tier Architecture

1. Presentation Layer
   - HTML templates in the templates folder
   - Static assets in the static folder
   - Vanilla JavaScript handles UI interaction and API calls

2. Application Layer
   - The main Flask entrypoint is app.py
   - Session-based authentication and role-based access control are implemented in the backend
   - Case management, evidence handling, and report export logic run through Flask routes

3. Data Layer
   - Oracle Database stores users, roles, FIRs, cases, criminals, evidence, vehicle and mobile information, audit logs, and historical status data
   - The schema is initialized through setup.sql
   - Automated triggers and the INTELLICRIME_PKG package provide event-driven case creation, status tracking, and audit support

## Current Core Files

- app.py: final production backend with the 5-role RBAC matrix and CSV export endpoint
- setup.sql: complete database initialization script with the 3NF schema, triggers, package, and seed data
- templates/index.html: main UI shell
- static/app.js: frontend logic for dashboard and CRUD interaction
- static/style.css: styling for the application
- requirements.txt: Python dependencies
- run.bat: Windows launcher for the Flask app

## Repository Structure

```text
IntelliCrimeSystem/
├─ app.py
├─ setup.sql
├─ requirements.txt
├─ run.bat
├─ README.md
├─ .env.example
├─ static/
│  ├─ app.js
│  ├─ style.css
│  └─ ...
├─ templates/
│  └─ index.html
└─ venv/
```

## Setup Instructions

### 1. Prerequisites
- Python 3.10+
- Oracle Database XE or a compatible local Oracle instance
- Oracle SQL Developer or any Oracle SQL client

### 2. Python Environment
```powershell
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

### 3. Database Setup
1. Connect to Oracle as SYSTEM or a DBA user.
2. Run setup.sql.
3. Ensure the schema owner and tables are created successfully.

### 4. Run the Application
```powershell
.\run.bat
```
Then open:
```text
http://127.0.0.1:5000
```

## Security and Workflow Highlights

- Five roles are supported: SUPERADMIN, ADMIN, ANALYST, OFFICER, and VIEWER
- Manual case handling and case editing are supported through the application UI and backend routes
- CSV export is available through the reporting endpoint
- The database layer includes triggers for audit logging, case spawning, and status history

## Notes

Running setup.sql resets the demo schema and seed data. Use it as the authoritative database initialization script for this repository.
