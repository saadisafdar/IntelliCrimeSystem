# IntelliCrime System

IntelliCrime System is a university ADBMS semester project for smart crime investigation and criminal record management.

The workflow is simple: HTML, CSS, and vanilla JavaScript render the interface, JavaScript sends JSON requests to Flask, Flask validates input and runs parameterized Oracle SQL or PL/SQL, Oracle stores the data, and Flask commits or rolls back before returning JSON.

## Required Software

- Python 3.10 or newer
- Oracle Database XE with XEPDB1
- Oracle SQL Developer

## Database Setup

1. Open Oracle SQL Developer.
2. Connect as `SYSTEM` to `localhost:1521/XEPDB1`.
3. Open `setup.sql`.
4. Press `F5` / Run Script.
5. Wait for the verification row counts.

Running `setup.sql` again resets all IntelliCrime demo data.

## Start Application

Double-click `run.bat`, then open:

```text
http://127.0.0.1:5000
```

## Demo Logins

```text
admin / admin123
officer1 / officer123
analyst1 / analyst123
entry1 / entry123
```

## Main Modules

Dashboard, FIRs, Criminals, Cases, Evidence, Vehicles, Mobile Numbers, Alerts, Reports, and Administration.

## Database Features

The project includes primary and foreign keys, check constraints, unique constraints, indexes, views, sequences, triggers, PL/SQL procedures, PL/SQL functions, one package, audit logs, status history, automatic case creation, and smart repeated-entity alerts.
