const state = {
    user: null,
    lookups: { stations: [], crime_types: [], locations: [], officers: [], criminals: [], cases: [] },
    currentSection: "dashboard",
    modalAction: null,
};

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];

// Streamlined 5-Role Module Meta Matrix Maps
const sectionMeta = {
    dashboard: { title: "🏠 Dashboard Overview" },
    firs: { title: "📄 First Information Reports (FIR)" },
    criminals: { title: "👤 Criminal Dossiers" },
    cases: { title: "📁 Case Management Records" },
    evidence: { title: "🔍 Evidence Locker Records" },
    vehicles: { title: "🚗 Vehicle Tracking List" },
    mobiles: { title: "📱 Cellular Intelligence Logs" },
    alerts: { title: "🚨 Smart System Anomalies" },
    reports: { title: "📊 Analytical Hotspots & Reports" },
    admin: { title: "⚙️ Core System Governance" },
};

const metricIcons = {
    "Total FIRs": "📄",
    "Active Cases": "📁",
    Criminals: "👤",
    Evidence: "🔍",
    "New Alerts": "🚨",
};

const statusIcons = {
    ACTIVE: "✅",
    VERIFIED: "✅",
    SOLVED: "✅",
    RESOLVED: "✅",
    CLEARED: "✅",
    CLOSED: "✅",
    PENDING: "⏳",
    OPEN: "⏳",
    REGISTERED: "⏳",
    UNDER_INVESTIGATION: "🔍",
    REVIEWED: "🔎",
    NEW: "🚨",
    HIGH: "⚠️",
    CRITICAL: "⚠️",
    WANTED: "⚠️",
    REJECTED: "⚠️",
    ARCHIVED: "🗄️",
    DISMISSED: "🗑️",
};

function showLoading(show) {
    $("#loading").classList.toggle("hidden", !show);
}

function toast(message, type = "ok") {
    const node = document.createElement("div");
    node.className = `toast ${type === "error" ? "error" : "success"}`;
    node.textContent = `${type === "error" ? "⚠️" : "✅"} ${message}`;
    $("#toastHost").appendChild(node);
    setTimeout(() => node.remove(), 3800);
}

async function api(path, options = {}) {
    showLoading(true);
    try {
        const config = {
            headers: { "Content-Type": "application/json" },
            ...options,
        };
        if (config.body && typeof config.body !== "string") {
            config.body = JSON.stringify(config.body);
        }
        const response = await fetch(path, config);
        const data = await response.json();
        if (!response.ok || data.ok === false) {
            throw new Error(data.error || "Operation rejected by Oracle engine");
        }
        return data;
    } finally {
        showLoading(false);
    }
}

function escapeHtml(value) {
    return String(value ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#039;");
}

function badge(value) {
    const text = String(value ?? "");
    const icon = statusIcons[text] || "";
    return `<span class="badge ${escapeHtml(text)}">${icon ? `${icon} ` : ""}${escapeHtml(text)}</span>`;
}

function renderTable(target, rows, columns, actions) {
    if (!rows || rows.length === 0) {
        $(target).innerHTML = `<div class="empty">🔎 No matching data subsets found inside current schema view.</div>`;
        return;
    }
    const head = columns.map((col) => `<th>${escapeHtml(col.label)}</th>`).join("") + (actions ? "<th>Actions</th>" : "");
    const body = rows.map((row) => {
        const cells = columns.map((col) => {
            const value = typeof col.render === "function" ? col.render(row) : escapeHtml(row[col.key]);
            return `<td>${value}</td>`;
        }).join("");
        const actionCell = actions ? `<td><div class="row-actions">${actions(row)}</div></td>` : "";
        return `<tr>${cells}${actionCell}</tr>`;
    }).join("");
    $(target).innerHTML = `<table><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table>`;
}

function optionList(items, valueKey, labelKey, selected = "") {
    return items.map((item) => `<option value="${escapeHtml(item[valueKey])}" ${String(item[valueKey]) === String(selected) ? "selected" : ""}>${escapeHtml(item[labelKey])}</option>`).join("");
}

function formData(form) {
    return Object.fromEntries(new FormData(form).entries());
}

function fieldHtml(field) {
    const required = field.required ? "required" : "";
    const value = field.value ?? "";
    if (field.type === "select") {
        return `<label class="${field.wide ? "wide" : ""}">${field.label}<select name="${field.name}" ${required}><option value="">Select</option>${field.options || ""}</select></label>`;
    }
    if (field.type === "textarea") {
        return `<label class="wide">${field.label}<textarea name="${field.name}" ${required}>${escapeHtml(value)}</textarea></label>`;
    }
    return `<label class="${field.wide ? "wide" : ""}">${field.label}<input name="${field.name}" type="${field.type || "text"}" value="${escapeHtml(value)}" ${required}></label>`;
}

function openModal(title, fields, submit) {
    $("#modalTitle").textContent = title;
    $("#modalFields").innerHTML = fields.map(fieldHtml).join("");
    state.modalAction = submit;
    $("#modal").classList.remove("hidden");
    const firstField = $("#modalFields input, #modalFields select, #modalFields textarea");
    if (firstField) firstField.focus();
}

function closeModal() {
    $("#modal").classList.add("hidden");
    $("#modalForm").reset();
    state.modalAction = null;
}

function confirmAction(text, action) {
    $("#confirmText").textContent = text;
    $("#confirmModal").classList.remove("hidden");
    $("#okConfirm").onclick = async () => {
        $("#confirmModal").classList.add("hidden");
        try {
            await action();
        } catch (err) {
            toast(err.message, "error");
        }
    };
}

function showApp(user) {
    state.user = user;
    $("#loginView").classList.add("hidden");
    $("#appView").classList.remove("hidden");
    $("#userBadge").textContent = `${user.full_name} · ${user.username}`;
    $("#rolePill").textContent = user.role_label || user.role_name;

    // Dynamically filter sidebar modules according to the 5-role privilege matrix
    $$(".nav-btn").forEach(btn => {
        const isAllowed = user.modules.includes(btn.dataset.section);
        btn.classList.toggle("hidden", !isAllowed);
    });
}

async function loadLookups() {
    const data = await api("/api/lookups");
    state.lookups = data;
}

async function loadDashboard() {
    const data = await api("/api/dashboard");
    const labels = [
        ["Total FIRs", data.totals.firs],
        ["Active Cases", data.totals.active_cases],
        ["Criminals", data.totals.criminals],
        ["Evidence", data.totals.evidence],
        ["New Alerts", data.totals.new_alerts],
    ];
    $("#dashboardCards").innerHTML = labels.map(([label, value]) => `
        <div class="metric">
            <div class="metric-icon">${metricIcons[label] || "📊"}</div>
            <span>${label}</span>
            <strong>${value}</strong>
        </div>
    `).join("");
    renderTable("#recentFirs", data.recent_firs, [
        { key: "fir_no", label: "FIR" },
        { key: "reported_by", label: "Reporter" },
        { key: "fir_status", label: "Status", render: (r) => badge(r.fir_status) },
    ]);
    renderTable("#recentAlerts", data.recent_alerts, [
        { key: "alert_type", label: "Type" },
        { key: "alert_status", label: "Status", render: (r) => badge(r.alert_status) },
        { key: "alert_message", label: "Message" },
    ]);
    renderTable("#topLocations", data.top_locations, [
        { key: "area_name", label: "Area" },
        { key: "city", label: "City" },
        { key: "crime_count", label: "Crimes" },
    ]);
    renderTable("#officerWorkload", data.officer_workload, [
        { key: "officer_name", label: "Officer" },
        { key: "open_cases", label: "Open" },
        { key: "total_cases", label: "Total" },
    ]);
}

async function loadFirs() {
    const q = encodeURIComponent($("#firSearch").value);
    const status = encodeURIComponent($("#firStatus").value);
    const data = await api(`/api/firs?q=${q}&status=${status}`);
    
    // Hide administrative action utilities completely if user is a read-only VIEWER
    const hasEditRights = state.user.role_name !== "VIEWER";

    renderTable("#firsTable", data.rows, [
        { key: "fir_no", label: "FIR No" },
        { key: "reported_by", label: "Reporter" },
        { key: "station_name", label: "Station" },
        { key: "crime_type_name", label: "Crime" },
        { key: "area_name", label: "Location" },
        { key: "fir_status", label: "Status", render: (r) => badge(r.fir_status) },
    ], hasEditRights ? (r) => `
        <button class="mini" onclick="editFir(${r.fir_id})">✏️ Edit</button>
        <button class="mini danger" onclick="archiveFir(${r.fir_id})">🗑️ Archive</button>
    ` : null);
}

async function loadCriminals() {
    const q = encodeURIComponent($("#criminalSearch").value);
    const status = encodeURIComponent($("#criminalStatus").value);
    const data = await api(`/api/criminals?q=${q}&status=${status}`);
    const hasEditRights = state.user.role_name !== "VIEWER";

    renderTable("#criminalsTable", data.rows, [
        { key: "criminal_name", label: "Name" },
        { key: "cnic", label: "CNIC" },
        { key: "phone", label: "Phone" },
        { key: "criminal_status", label: "Status", render: (r) => badge(r.criminal_status) },
        { key: "linked_case_count", label: "Cases" },
    ], hasEditRights ? (r) => `
        <button class="mini" onclick="editCriminal(${r.criminal_id})">✏️ Edit</button>
        <button class="mini danger" onclick="clearCriminal(${r.criminal_id})">✅ Clear</button>
    ` : null);
}

async function loadCases() {
    const q = encodeURIComponent($("#caseSearch").value);
    const status = encodeURIComponent($("#caseStatus").value);
    const data = await api(`/api/cases?q=${q}&status=${status}`);
    const hasEditRights = state.user.role_name !== "VIEWER";

    renderTable("#casesTable", data.rows, [
        { key: "case_title", label: "Case" },
        { key: "fir_no", label: "FIR" },
        { key: "crime_type_name", label: "Crime" },
        { key: "officer_name", label: "Officer" },
        { key: "priority", label: "Priority", render: (r) => badge(r.priority) },
        { key: "case_status", label: "Status", render: (r) => badge(r.case_status) },
    ], (r) => {
        let actionButtons = `<button class="mini" onclick="loadCaseDetail(${r.case_id})">📁 Details</button>`;
        if (hasEditRights) {
            actionButtons += `
                <button class="mini" onclick="editManualCaseModal(${r.case_id}, '${encodeURIComponent(r.case_title)}', '${r.priority}', '${r.case_status}', '${r.fir_id || ''}', '${r.officer_id || ''}')">✏️ Edit</button>
                <button class="mini" onclick="openCaseStatus(${r.case_id})">⏳ Status</button>
                <button class="mini danger" onclick="archiveCase(${r.case_id})">🗑️ Archive</button>
            `;
        }
        return actionButtons;
    });
}

// Intercepts and formats manual case parameters for structural PUT revisions
window.editManualCaseModal = function(id, title, priority, status, firId, officerId) {
    openModal("✏️ Update Primary Case Record", [
        { name: "case_title", label: "Case Title", required: true, value: decodeURIComponent(title) },
        { name: "fir_id", label: "FIR Sequence ID", type: "select", required: true, options: optionList(state.lookups.cases, "case_id", "case_title", firId) },
        { name: "officer_id", label: "Investigation Lead", type: "select", options: optionList(state.lookups.officers, "officer_id", "officer_name", officerId) },
        { name: "priority", label: "Priority Allocation", type: "select", options: ["LOW", "MEDIUM", "HIGH", "CRITICAL"].map(s => `<option ${s === priority ? "selected" : ""}>${s}</option>`).join("") },
        { name: "case_status", label: "Operational State", type: "select", options: ["OPEN", "UNDER_INVESTIGATION", "PENDING", "SOLVED", "CLOSED", "ARCHIVED"].map(s => `<option ${s === status ? "selected" : ""}>${s}</option>`).join("") }
    ], async (data) => {
        const payload = { case_id: parseInt(id), ...data };
        await api("/api/cases", { method: "PUT", body: payload });
        toast("Oracle session case changes committed successfully");
        closeModal();
        await loadCases();
    });
};

async function loadCaseDetail(caseId) {
    const data = await api(`/api/cases/${caseId}`);
    const c = data.case;
    $("#caseDetail").classList.remove("hidden");
    
    const isViewer = state.user.role_name === "VIEWER";
    const toolbarHtml = isViewer ? "" : `
        <div class="toolbar">
            <button class="primary" onclick="openAssignOfficer(${caseId})">👮 Assign Officer</button>
            <button class="ghost" onclick="openSuspect(${caseId})">👤 Link Suspect</button>
            <button class="ghost" onclick="openVictim(${caseId})">➕ Add Victim</button>
            <button class="ghost" onclick="openWitness(${caseId})">➕ Add Witness</button>
            <button class="ghost" onclick="openCaseEvidence(${caseId})">🔍 Add Evidence</button>
            <button class="ghost" onclick="openCaseLog(${caseId})">📝 Add Log</button>
        </div>`;

    $("#caseDetail").innerHTML = `
        <h3>${escapeHtml(c.case_title)} ${badge(c.case_status)}</h3>
        <p style="margin-top: 6px; margin-bottom: 12px;">${escapeHtml(c.fir_description || c.case_description)}</p>
        ${toolbarHtml}
        <div class="detail-grid">
            ${detailList("👤 Suspects", data.suspects, ["criminal_name", "suspect_role", "involvement_status"])}
            ${detailList("🧾 Victims", data.victims, ["victim_name", "phone", "injury_details"])}
            ${detailList("👁️ Witnesses", data.witnesses, ["witness_name", "phone", "statement_summary"])}
            ${detailList("🔍 Evidence Locker", data.evidence, ["evidence_code", "evidence_type", "verification_status"])}
            ${detailList("🚗 Linked Vehicles", data.vehicles, ["vehicle_number", "relation_to_case", "suspicious_status"])}
            ${detailList("📱 Intercept Mobile Logs", data.mobiles, ["mobile_number", "relation_to_case", "suspicious_status"])}
            ${detailList("📝 Progress Timelines", data.logs, ["officer_name", "progress_note", "next_action"])}
            ${detailList("⏳ Status Logs", data.history, ["old_status", "new_status", "remarks"])}
        </div>
    `;
}

function detailList(title, rows, keys) {
    const content = rows && rows.length ? rows.map((row) => `<li>${keys.map((key) => escapeHtml(row[key])).filter(Boolean).join(" · ")}</li>`).join("") : "<li>🔎 No related entity maps found.</li>";
    return `<div class="detail-card"><h3>${title}</h3><ul>${content}</ul></div>`;
}

async function loadEvidence() {
    const q = encodeURIComponent($("#evidenceSearch").value);
    const status = encodeURIComponent($("#evidenceStatus").value);
    const data = await api(`/api/evidence?q=${q}&verification_status=${status}`);
    const hasEditRights = state.user.role_name !== "VIEWER";

    renderTable("#evidenceTable", data.rows, [
        { key: "evidence_code", label: "Code" },
        { key: "case_title", label: "Case" },
        { key: "evidence_type", label: "Type" },
        { key: "storage_location", label: "Storage" },
        { key: "verification_status", label: "Status", render: (r) => badge(r.verification_status) },
    ], hasEditRights ? (r) => `
        <button class="mini" onclick="verifyEvidence(${r.evidence_id}, 'VERIFIED')">✅ Verify</button>
        <button class="mini danger" onclick="archiveEvidence(${r.evidence_id})">🗑️ Archive</button>
    ` : null);
}

async function loadVehicles() {
    const q = encodeURIComponent($("#vehicleSearch").value);
    const data = await api(`/api/vehicles?q=${q}`);
    const hasEditRights = state.user.role_name !== "VIEWER";

    renderTable("#vehiclesTable", data.rows, [
        { key: "vehicle_number", label: "Number" },
        { key: "owner_name", label: "Owner" },
        { key: "make", label: "Make" },
        { key: "model", label: "Model" },
        { key: "linked_case_count", label: "Cases" },
        { key: "suspicious_status", label: "Status", render: (r) => badge(r.suspicious_status) },
    ], hasEditRights ? (r) => `<button class="mini" onclick="openVehicleLink(${r.vehicle_id})">🔗 Link</button>` : null);
}

async function loadMobiles() {
    const q = encodeURIComponent($("#mobileSearch").value);
    const data = await api(`/api/mobiles?q=${q}`);
    const hasEditRights = state.user.role_name !== "VIEWER";

    renderTable("#mobilesTable", data.rows, [
        { key: "mobile_number", label: "Number" },
        { key: "owner_name", label: "Owner" },
        { key: "network", label: "Network" },
        { key: "registered_cnic", label: "CNIC" },
        { key: "linked_case_count", label: "Cases" },
        { key: "suspicious_status", label: "Status", render: (r) => badge(r.suspicious_status) },
    ], hasEditRights ? (r) => `<button class="mini" onclick="openMobileLink(${r.mobile_id})">🔗 Link</button>` : null);
}

async function loadAlerts() {
    const status = encodeURIComponent($("#alertStatus").value);
    const data = await api(`/api/alerts?status=${status}`);
    const hasEditRights = state.user.role_name !== "VIEWER";

    renderTable("#alertsTable", data.rows, [
        { key: "alert_type", label: "Type" },
        { key: "alert_message", label: "Message" },
        { key: "case_title", label: "Case" },
        { key: "alert_status", label: "Status", render: (r) => badge(r.alert_status) },
    ], hasEditRights ? (r) => `
        <button class="mini" onclick="alertAction(${r.alert_id}, 'review')">🔎 Review</button>
        <button class="mini" onclick="alertAction(${r.alert_id}, 'resolve')">✅ Resolve</button>
        <button class="mini danger" onclick="alertAction(${r.alert_id}, 'dismiss')">🗑️ Dismiss</button>
    ` : null);
}

async function loadReports() {
    const data = await api("/api/reports");
    $("#reportsGrid").innerHTML = Object.entries(data.reports).map(([name, rows]) => `
        <article class="panel">
            <h3>📊 ${name.replaceAll("_", " ").toUpperCase()}</h3>
            <div>${reportPreview(rows)}</div>
        </article>
    `).join("");
}

function reportPreview(rows) {
    if (!rows || rows.length === 0) return `<div class="empty">🔎 No operational matrix profiles loaded.</div>`;
    const keys = Object.keys(rows[0]).slice(0, 4);
    return `<table><thead><tr>${keys.map((key) => `<th>${key}</th>`).join("")}</tr></thead><tbody>${rows.slice(0, 6).map((row) => `<tr>${keys.map((key) => `<td>${escapeHtml(row[key])}</td>`).join("")}</tr>`).join("")}</tbody></table>`;
}

async function loadAdmin() {
    const data = await api("/api/admin");
    $("#adminPanel").innerHTML = `
        <article class="panel"><h3>👥 System User Roster</h3>${smallTable(data.users, ["username", "full_name", "role_name", "status"])}</article>
        <article class="panel"><h3>🏢 Station Configuration Grid</h3>${smallTable(data.stations, ["station_name", "city", "status"])}</article>
        <article class="panel"><h3>🧾 Oracle Security Audit Logs</h3>${smallTable(data.audit_logs, ["table_name", "record_id", "operation_type", "changed_at"])}</article>
    `;
}

function smallTable(rows, keys) {
    if (!rows || rows.length === 0) return `<div class="empty">🔎 No log indices registered.</div>`;
    return `<table><thead><tr>${keys.map((key) => `<th>${key}</th>`).join("")}</tr></thead><tbody>${rows.slice(0, 10).map((row) => `<tr>${keys.map((key) => `<td>${escapeHtml(row[key])}</td>`).join("")}</tr>`).join("")}</tbody></table>`;
}

const sectionLoaders = {
    dashboard: loadDashboard,
    firs: loadFirs,
    criminals: loadCriminals,
    cases: loadCases,
    evidence: loadEvidence,
    vehicles: loadVehicles,
    mobiles: loadMobiles,
    alerts: loadAlerts,
    reports: loadReports,
    admin: loadAdmin,
};

async function showSection(name) {
    state.currentSection = name;
    $$(".section").forEach((section) => section.classList.toggle("active", section.id === name));
    $$(".nav-btn").forEach((btn) => btn.classList.toggle("active", btn.dataset.section === name));
    $("#sectionTitle").textContent = sectionMeta[name]?.title || name.replace(/\b\w/g, (c) => c.toUpperCase());
    $("#sidebar").classList.remove("open");
    
    // Clear details if leaving the cases frame view
    if (name !== 'cases') $("#caseDetail").classList.add("hidden");

    await sectionLoaders[name]();
}

function openFirForm() {
    openModal("📄 Register Core Complaint File (FIR)", [
        { name: "fir_no", label: "FIR Number", required: true },
        { name: "station_id", label: "Station Profile", type: "select", required: true, options: optionList(state.lookups.stations, "station_id", "station_name") },
        { name: "crime_type_id", label: "Classification", type: "select", required: true, options: optionList(state.lookups.crime_types, "crime_type_id", "crime_type_name") },
        { name: "location_id", label: "Crime Scene Radius Location", type: "select", required: true, options: optionList(state.lookups.locations, "location_id", "area_name") },
        { name: "reported_by", label: "Complainant Full Name", required: true },
        { name: "reporter_cnic", label: "Complainant Identity (CNIC)" },
        { name: "reporter_phone", label: "Complainant Cellular Connection" },
        { name: "incident_at", label: "Incident Timestamp", type: "datetime-local" },
        { name: "description", label: "Incident Narrative & Statements", type: "textarea", required: true },
    ], async (data) => {
        await api("/api/firs", { method: "POST", body: data });
        toast("FIR saved successfully into secure Oracle cluster log matrices");
        closeModal();
        await loadFirs();
        await loadLookups();
    });
}

function openCriminalForm() {
    openModal("👤 Create Criminal Profile Dossier", [
        { name: "criminal_name", label: "Full Name", required: true },
        { name: "cnic", label: "Identity Grid Card (CNIC)" },
        { name: "gender", label: "Gender" },
        { name: "date_of_birth", label: "Date of Birth", type: "date" },
        { name: "phone", label: "Contact Trace Number" },
        { name: "criminal_status", label: "Classification Status", type: "select", options: ["SUSPECT", "WANTED", "ARRESTED", "CONVICTED", "RELEASED", "CLEARED"].map((s) => `<option>${s}</option>`).join("") },
        { name: "address", label: "Known Residence Address", type: "textarea" },
        { name: "previous_record", label: "Historical Crime Roster Profiles", type: "textarea" },
    ], async (data) => {
        await api("/api/criminals", { method: "POST", body: data });
        toast("Dossier entry initialized");
        closeModal();
        await loadCriminals();
        await loadLookups();
    });
}

function openEvidenceForm(caseId = "") {
    openModal("🔍 Authenticate & Log Physical/Digital Evidence", [
        { name: "case_id", label: "Target Case Profile Linkage", type: "select", required: true, options: optionList(state.lookups.cases, "case_id", "case_title", caseId) },
        { name: "evidence_code", label: "Evidence Tracking Identifier Code", required: true },
        { name: "evidence_type", label: "Classification Format Group", required: true },
        { name: "collected_by", label: "Recovering Agent (Officer ID)", type: "select", options: optionList(state.lookups.officers, "officer_id", "officer_name") },
        { name: "storage_location", label: "Secure Vault Storage Locker Unit" },
        { name: "evidence_description", label: "Recovery Summary Description Details", type: "textarea" },
    ], async (data) => {
        await api("/api/evidence", { method: "POST", body: data });
        toast("Evidence profile logged successfully");
        closeModal();
        await loadEvidence();
        if (caseId) await loadCaseDetail(caseId);
    });
}

function openVehicleForm() {
    openModal("🚗 Log Motorized Tracking Vehicle Profile", [
        { name: "vehicle_number", label: "License Registration Grid Code", required: true },
        { name: "owner_name", label: "Registered Owner Name" },
        { name: "owner_cnic", label: "Owner Identity (CNIC)" },
        { name: "vehicle_type", label: "Body Architecture Configuration" },
        { name: "make", label: "Manufacturing Brand Brand" },
        { name: "model", label: "Production Line Variant Model" },
        { name: "color", label: "Vehicle Primary Tone Tint" },
    ], async (data) => {
        await api("/api/vehicles", { method: "POST", body: data });
        toast("Tracking vehicle added successfully");
        closeModal();
        await loadVehicles();
    });
}

function openMobileForm() {
    openModal("📱 Track Network Cellular Line Node", [
        { name: "mobile_number", label: "Cellular Connection String Number", required: true },
        { name: "owner_name", label: "Registered SIM User" },
        { name: "network", label: "Service Provider Network Carrier" },
        { name: "registered_cnic", label: "Identity Linkage (CNIC)" },
    ], async (data) => {
        await api("/api/mobiles", { method: "POST", body: data });
        toast("Network tracking item mapped correctly");
        closeModal();
        await loadMobiles();
    });
}

function openAssignOfficer(caseId) {
    openModal("👮 Assign Case Lead Officer", [
        { name: "officer_id", label: "Select Lead Officer Agent", type: "select", required: true, options: optionList(state.lookups.officers, "officer_id", "officer_name") },
    ], async (data) => {
        await api(`/api/cases/${caseId}/assign-officer`, { method: "POST", body: data });
        toast("Case assignment finalized inside relational constraints");
        closeModal();
        await loadCaseDetail(caseId);
        await loadCases();
    });
}

function openCaseStatus(caseId) {
    openModal("⏳ Transition Operational Case State", [
        { name: "case_status", label: "Target State", type: "select", required: true, options: ["OPEN", "UNDER_INVESTIGATION", "PENDING", "SOLVED", "CLOSED", "ARCHIVED"].map((s) => `<option>${s}</option>`).join("") },
        { name: "remarks", label: "State Change Progress Log Entry", type: "textarea", required: true },
    ], async (data) => {
        await api(`/api/cases/${caseId}/status`, { method: "POST", body: data });
        toast("Case tracking parameter records shifted cleanly");
        closeModal();
        await loadCases();
        if (state.currentSection === 'cases' && !$("#caseDetail").classList.contains("hidden")) await loadCaseDetail(caseId);
    });
}

function openSuspect(caseId) {
    openModal("👤 Bind Known Profile Suspect Node", [
        { name: "criminal_id", label: "Target Database Subject", type: "select", required: true, options: optionList(state.lookups.criminals, "criminal_id", "criminal_name") },
        { name: "suspect_role", label: "Alleged Involvement Classification" },
        { name: "involvement_status", label: "Current Interrogation Assessment Status" },
    ], async (data) => {
        await api(`/api/cases/${caseId}/suspects`, { method: "POST", body: data });
        toast("Relational binding index committed");
        closeModal();
        await loadCaseDetail(caseId);
    });
}

function openVictim(caseId) {
    openModal("🧾 Document Case Victim Information", [
        { name: "victim_name", label: "Victim Full Name", required: true },
        { name: "cnic", label: "Identity Card Code Number (CNIC)" },
        { name: "gender", label: "Gender" },
        { name: "phone", label: "Cellular Contact Point" },
        { name: "address", label: "Residence Address", type: "textarea" },
        { name: "injury_details", label: "Physical Trauma Summaries & Remarks", type: "textarea" },
    ], async (data) => {
        await api(`/api/cases/${caseId}/victims`, { method: "POST", body: data });
        toast("Victim folder profile cached");
        closeModal();
        await loadCaseDetail(caseId);
    });
}

function openWitness(caseId) {
    openModal("👁️ Bind Witness Sworn Statement Profile", [
        { name: "witness_name", label: "Witness Full Name", required: true },
        { name: "cnic", label: "Witness Identity Card (CNIC)" },
        { name: "phone", label: "Witness Cellular Grid String" },
        { name: "statement_summary", label: "Sworn Account Core Deposition Statement", type: "textarea", required: true },
    ], async (data) => {
        await api(`/api/cases/${caseId}/witnesses`, { method: "POST", body: data });
        toast("Witness folder statement added");
        closeModal();
        await loadCaseDetail(caseId);
    });
}

function openCaseLog(caseId) {
    openModal("📝 Append Investigation Log Progression Note", [
        { name: "officer_id", label: "Logging Personnel Agent", type: "select", options: optionList(state.lookups.officers, "officer_id", "officer_name") },
        { name: "progress_note", label: "Activity Log Progression Core Entry", type: "textarea", required: true },
        { name: "next_action", label: "Planned Target Milestone Action Plan", type: "textarea" },
    ], async (data) => {
        await api(`/api/cases/${caseId}/logs`, { method: "POST", body: data });
        toast("Case milestone ledger entry appended successfully");
        closeModal();
        await loadCaseDetail(caseId);
    });
}

function openCaseEvidence(caseId) {
    openEvidenceForm(caseId);
}

function openVehicleLink(vehicleId) {
    openModal("🚗 Map Tracking Vehicle To Active File", [
        { name: "case_id", label: "Target Case Association Profile", type: "select", required: true, options: optionList(state.lookups.cases, "case_id", "case_title") },
        { name: "detected_location", label: "Detection / Capture Radius Location" },
        { name: "relation_to_case", label: "Contextual Relation Assignment" },
        { name: "suspicious_status", label: "Anomalous Severity Flag Level", type: "select", options: ["NORMAL", "SUSPICIOUS", "REPEATED", "CLEARED"].map((s) => `<option>${s}</option>`).join("") },
    ], async (data) => {
        await api(`/api/vehicles/${vehicleId}/link`, { method: "POST", body: data });
        toast("Relational model linkage completed smoothly");
        closeModal();
        await loadVehicles();
    });
}

function openMobileLink(mobileId) {
    openModal("📱 Link Network Target Line To Case Matrix", [
        { name: "case_id", label: "Target Active File Profile", type: "select", required: true, options: optionList(state.lookups.cases, "case_id", "case_title") },
        { name: "linked_person", label: "Identified Account User / Node Holder" },
        { name: "relation_to_case", label: "Intelligence Context Relation" },
        { name: "suspicious_status", label: "Flag Target Parameter State", type: "select", options: ["NORMAL", "SUSPICIOUS", "REPEATED", "CLEARED"].map((s) => `<option>${s}</option>`).join("") },
    ], async (data) => {
        await api(`/api/mobiles/${mobileId}/link`, { method: "POST", body: data });
        toast("Cellular intelligence relationship linkage initialized");
        closeModal();
        await loadMobiles();
    });
}

async function editFir(id) {
    openModal("✏️ Modify Core Complaint Parameter Sets (FIR)", [
        { name: "reported_by", label: "Complainant Full Name" },
        { name: "reporter_phone", label: "Complainant Contact Node Line" },
        { name: "fir_status", label: "Current Core State", type: "select", options: ["REGISTERED", "VERIFIED", "REJECTED", "ARCHIVED"].map((s) => `<option>${s}</option>`).join("") },
        { name: "description", label: "Core Narrative & Summary Index", type: "textarea" },
    ], async (data) => {
        await api(`/api/firs/${id}`, { method: "PUT", body: data });
        toast("FIR log edits committed into Oracle");
        closeModal();
        await loadFirs();
    });
}

function editCriminal(id) {
    openModal("✏️ Update Criminal Subject Dossier Records", [
        { name: "criminal_name", label: "Full Profile Name" },
        { name: "phone", label: "Contact Tracking Number String" },
        { name: "criminal_status", label: "Current Judicial Status Classification", type: "select", options: ["SUSPECT", "WANTED", "ARRESTED", "CONVICTED", "RELEASED", "CLEARED"].map((s) => `<option>${s}</option>`).join("") },
        { name: "previous_record", label: "Historical Offense Logs & Summaries", type: "textarea" },
    ], async (data) => {
        await api(`/api/criminals/${id}`, { method: "PUT", body: data });
        toast("Dossier profile matrix synchronized cleanly");
        closeModal();
        await loadCriminals();
    });
}

function archiveFir(id) {
    confirmAction("Archive this FIR document entirely? This will flag it in your Oracle engine tables.", async () => {
        await api(`/api/firs/${id}`, { method: "DELETE" });
        toast("FIR data archived safely");
        await loadFirs();
    });
}

function clearCriminal(id) {
    confirmAction("Mark this subject record as cleared from active operational watch lists?", async () => {
        await api(`/api/criminals/${id}`, { method: "DELETE" });
        toast("Subject cleared from watch frames");
        await loadCriminals();
    });
}

function archiveCase(id) {
    confirmAction("Archive this entire case file record stream?", async () => {
        await api(`/api/cases/${id}`, { method: "DELETE" });
        toast("Case data archived cleanly");
        await loadCases();
        $("#caseDetail").classList.add("hidden");
    });
}

function archiveEvidence(id) {
    confirmAction("Archive this evidence room locker record tracking parameter?", async () => {
        await api(`/api/evidence/${id}`, { method: "DELETE" });
        toast("Locker logging unit status updated to archived");
        await loadEvidence();
    });
}

async function verifyEvidence(id, status) {
    await api(`/api/evidence/${id}`, { method: "PUT", body: { verification_status: status } });
    toast("Evidence room verification signature logged");
    await loadEvidence();
}

async function alertAction(id, action) {
    await api(`/api/alerts/${id}/${action}`, { method: "POST" });
    toast("System automated tracking anomaly log updated");
    await loadAlerts();
}

// Custom manual initialization layout engine for adding completely new files
function openManualCaseCreationForm() {
    openModal("➕ Compile New Manual Case File Dossier", [
        { name: "case_title", label: "Case Profile Title", required: true },
        { name: "case_description", label: "Core Description & Briefing Summary", type: "textarea", required: true },
        { name: "fir_id", label: "Reference Parent FIR Record Tracking Identification", type: "select", required: true, options: optionList(state.lookups.cases, "case_id", "case_title") },
        { name: "officer_id", label: "Assign Primary Field Investigator Agent", type: "select", options: optionList(state.lookups.officers, "officer_id", "officer_name") },
        { name: "priority", label: "Initial Priority Allocation", type: "select", options: ["LOW", "MEDIUM", "HIGH", "CRITICAL"].map(s => `<option>${s}</option>`).join("") },
        { name: "case_status", label: "Initial Investigation Status File State", type: "select", options: ["OPEN", "UNDER_INVESTIGATION", "PENDING"].map(s => `<option>${s}</option>`).join("") }
    ], async (data) => {
        const processedData = {
            ...data,
            fir_id: parseInt(data.fir_id) || null,
            officer_id: parseInt(data.officer_id) || null
        };
        await api("/api/cases", { method: "POST", body: processedData });
        toast("Relational manual case file profile mapped successfully into Oracle");
        closeModal();
        await loadCases();
    });
}

function bindEvents() {
    $("#loginForm").addEventListener("submit", async (event) => {
        event.preventDefault();
        try {
            const data = await api("/api/login", { method: "POST", body: formData(event.target) });
            showApp(data.user);
            await loadLookups();
            await showSection("dashboard");
        } catch (err) {
            toast(err.message, "error");
        }
    });
    $("#logoutBtn").addEventListener("click", async () => {
        await api("/api/logout", { method: "POST" });
        location.reload();
    });
    $$(".nav-btn").forEach((btn) => btn.addEventListener("click", () => showSection(btn.dataset.section).catch((err) => toast(err.message, "error"))));
    $("#mobileMenu").addEventListener("click", () => $("#sidebar").classList.toggle("open"));
    $$("[data-close-modal]").forEach((btn) => btn.addEventListener("click", closeModal));
    $("#cancelConfirm").addEventListener("click", () => $("#confirmModal").classList.add("hidden"));
    $("#modalForm").addEventListener("submit", async (event) => {
        event.preventDefault();
        if (!state.modalAction) return;
        try {
            event.submitter.disabled = true;
            await state.modalAction(formData(event.target));
        } catch (err) {
            toast(err.message, "error");
        } finally {
            event.submitter.disabled = false;
        }
    });
    const reloaders = [
        ["firSearch", loadFirs], ["firStatus", loadFirs], ["criminalSearch", loadCriminals], ["criminalStatus", loadCriminals],
        ["caseSearch", loadCases], ["caseStatus", loadCases], ["evidenceSearch", loadEvidence], ["evidenceStatus", loadEvidence],
        ["vehicleSearch", loadVehicles], ["mobileSearch", loadMobiles], ["alertStatus", loadAlerts],
    ];
    reloaders.forEach(([id, fn]) => $(`#${id}`).addEventListener("input", () => fn().catch((err) => toast(err.message, "error"))));
    $$("[data-open-form]").forEach((btn) => btn.addEventListener("click", () => {
        const form = btn.dataset.openForm;
        if (form === "fir") openFirForm();
        if (form === "criminal") openCriminalForm();
        if (form === "evidence") openEvidenceForm();
        if (form === "vehicle") openVehicleForm();
        if (form === "mobile") openMobileForm();
        if (form === "case") openManualCaseCreationForm(); // Dynamic routing endpoint logic wire-up
    }));
    $("#loadReports").addEventListener("click", () => loadReports().catch((err) => toast(err.message, "error")));
    $("#exportReports").addEventListener("click", () => { window.location.href = "/api/reports/export"; });
}

async function init() {
    bindEvents();
    try {
        const data = await api("/api/session");
        if (data.user) {
            showApp(data.user);
            await loadLookups();
            await showSection("dashboard");
        }
    } catch (err) {
        toast(err.message, "error");
    }
}

init();