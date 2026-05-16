const dateInput = document.querySelector("#dashboard-date");
const openImporterButton = document.querySelector("#open-importer");
const openDatabaseControlsButton = document.querySelector("#open-database-controls");
const reviewButton = document.querySelector("#dashboard-review-button");
const statusEl = document.querySelector("#dashboard-status");
const activeDatabasePill = document.querySelector("#active-database-pill");
const activeDatePill = document.querySelector("#active-date-pill");
const dayHeading = document.querySelector("#day-heading");
const dayEntryCount = document.querySelector("#day-entry-count");
const dayRecordsBody = document.querySelector("#day-records-body");
const mtdPayCard = document.querySelector("#mtd-pay-card");
const lastImportSection = document.querySelector("#last-import-section");
const lastImportTime = document.querySelector("#last-import-time");
const lastImportDatabase = document.querySelector("#last-import-database");
const lastImportDate = document.querySelector("#last-import-date");
const lastImportSaved = document.querySelector("#last-import-saved");
const lastImportUnresolved = document.querySelector("#last-import-unresolved");
const lastImportDuplicates = document.querySelector("#last-import-duplicates");
const payBreakdownSection = document.querySelector("#pay-breakdown-section");
const payBreakdownIndicator = document.querySelector("#pay-breakdown-indicator");
const payBreakdownCount = document.querySelector("#pay-breakdown-count");
const payBreakdownBody = document.querySelector("#pay-breakdown-body");
const modulePanel = document.querySelector("#module-panel");
const moduleFrame = document.querySelector("#module-frame");
const closeModulePanelButton = document.querySelector("#close-module-panel");
const modulePanelBackdrop = document.querySelector("#module-panel-backdrop");

const selectedDatabaseKey = "techPaySelectedDatabase";
const lastImportKey = "techPayLastImportSummary";
let records = [];
let selectedDatabase = "";
let paySettings = { commissionRate: 0 };
let payRules = {};
let ruleDefinitions = {};
let payBreakdownVisible = false;

const fields = {
  mtdProduction: document.querySelector("#mtd-production"),
  mtdStops: document.querySelector("#mtd-stops"),
  mtdPay: document.querySelector("#mtd-pay"),
  mtdHourly: document.querySelector("#mtd-hourly"),
  dayProduction: document.querySelector("#day-production"),
  dayStops: document.querySelector("#day-stops"),
  dayHours: document.querySelector("#day-hours"),
  dayPay: document.querySelector("#day-pay"),
  dayHourly: document.querySelector("#day-hourly")
};

function currentDateValue() {
  const date = new Date();
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

dateInput.value = currentDateValue();

function isTrustedMessage(event) {
  return window.location.origin === "null" || event.origin === window.location.origin;
}

function openModule(url, title = "Import / Manage") {
  moduleFrame.src = url;
  document.querySelector("#module-panel-title").textContent = title;
  setModulePanelOpen(true);
}

function setModulePanelOpen(open) {
  modulePanel.classList.toggle("is-open", open);
  modulePanel.setAttribute("aria-hidden", open ? "false" : "true");
  document.body.classList.toggle("panel-open", open);

  if (open && !moduleFrame.src) {
    moduleFrame.src = "/import.html";
  }
}

function money(value) {
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(value || 0);
}

function monthKey(date) {
  return String(date || "").slice(0, 7);
}

function formatDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value || "")) return value || "";
  const [year, month, day] = value.split("-");
  return `${month}/${day}/${year}`;
}

function formatDateTime(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Just now";
  return new Intl.DateTimeFormat("en-US", {
    month: "2-digit",
    day: "2-digit",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit"
  }).format(date);
}

function parseDateTime(date, time) {
  const match = String(time || "").trim().match(/^(\d{1,2}):(\d{2})\s*([AP]M)$/i);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date || "") || !match) return null;

  let hours = Number(match[1]);
  const minutes = Number(match[2]);
  const period = match[3].toUpperCase();

  if (period === "PM" && hours !== 12) hours += 12;
  if (period === "AM" && hours === 12) hours = 0;

  return new Date(`${date}T${String(hours).padStart(2, "0")}:${String(minutes).padStart(2, "0")}:00`);
}

function hoursWorked(dayRecords) {
  const starts = dayRecords.map((record) => parseDateTime(record.date, record.timeStarted)).filter(Boolean);
  const completions = dayRecords.map((record) => parseDateTime(record.date, record.timeCompleted)).filter(Boolean);

  if (!starts.length || !completions.length) return 0;

  const firstStart = Math.min(...starts.map((date) => date.getTime()));
  const lastCompletion = Math.max(...completions.map((date) => date.getTime()));
  return Math.max(0, (lastCompletion - firstStart) / 36e5);
}

function totalWorkedHours(list) {
  const byDate = new Map();

  for (const record of list) {
    if (!byDate.has(record.date)) {
      byDate.set(record.date, []);
    }
    byDate.get(record.date).push(record);
  }

  return [...byDate.values()].reduce((total, dayRecords) => total + hoursWorked(dayRecords), 0);
}

function productionTotal(list) {
  return list.reduce((total, record) => total + (typeof record.amount === "number" ? record.amount : 0), 0);
}

function calculateRecordPay(record) {
  const amount = typeof record.amount === "number" ? record.amount : 0;
  const commissionRate = Number(paySettings.commissionRate) || 0;
  const ruleKey = payRules[record.payType]?.rule || "noPay";
  const calculation = ruleDefinitions[ruleKey]?.calculation || { type: "none" };

  if (calculation.type === "commission") {
    return amount * commissionRate * (Number(calculation.multiplier) || 1);
  }

  if (calculation.type === "percent") {
    return amount * (Number(calculation.rate) || 0);
  }

  if (calculation.type === "flat") {
    return Number(calculation.amount) || 0;
  }

  return 0;
}

function payTotal(list) {
  return list.reduce((total, record) => total + calculateRecordPay(record), 0);
}

function renderPayBreakdownVisibility() {
  payBreakdownSection.hidden = !payBreakdownVisible;
  mtdPayCard.setAttribute("aria-expanded", String(payBreakdownVisible));
  mtdPayCard.classList.toggle("is-expanded", payBreakdownVisible);
  payBreakdownIndicator.setAttribute("aria-label", payBreakdownVisible ? "Hide breakdown" : "Show breakdown");
}

function togglePayBreakdown() {
  payBreakdownVisible = !payBreakdownVisible;
  renderPayBreakdownVisibility();
}

function renderPayBreakdown(mtdRecords) {
  const byPayType = new Map();

  for (const record of mtdRecords) {
    const payType = record.payType || "Unassigned";
    const current = byPayType.get(payType) || { stops: 0, production: 0, pay: 0 };
    current.stops += 1;
    current.production += typeof record.amount === "number" ? record.amount : 0;
    current.pay += calculateRecordPay(record);
    byPayType.set(payType, current);
  }

  const rows = [...byPayType.entries()].sort(([a], [b]) => a.localeCompare(b));
  payBreakdownCount.textContent = `${rows.length} pay ${rows.length === 1 ? "type" : "types"}`;
  payBreakdownBody.innerHTML = "";

  if (!rows.length) {
    const row = document.createElement("tr");
    const cell = document.createElement("td");
    cell.colSpan = 4;
    cell.textContent = "No month-to-date entries for this selection.";
    row.append(cell);
    payBreakdownBody.append(row);
    return;
  }

  for (const [payType, totals] of rows) {
    const row = document.createElement("tr");
    const cells = [payType, String(totals.stops), money(totals.production), money(totals.pay)];

    for (const value of cells) {
      const cell = document.createElement("td");
      cell.textContent = value;
      row.append(cell);
    }

    payBreakdownBody.append(row);
  }
}

function updateDashboardStatus() {
  const selectedDate = dateInput.value;
  activeDatabasePill.textContent = selectedDatabase || "No save file";
  activeDatePill.textContent = formatDate(selectedDate);
}

function renderLastImportSummary(summary) {
  if (!summary) {
    lastImportSection.hidden = true;
    return;
  }

  lastImportSection.hidden = false;
  lastImportTime.textContent = `Completed ${formatDateTime(summary.completedAt)}`;
  lastImportDatabase.textContent = summary.database || "--";
  lastImportDate.textContent = formatDate(summary.date);
  lastImportSaved.textContent = String(summary.saved ?? 0);
  lastImportUnresolved.textContent = String(summary.unresolved ?? 0);
  lastImportDuplicates.textContent = String(summary.duplicates ?? 0);
}

function loadLastImportSummary() {
  try {
    renderLastImportSummary(JSON.parse(localStorage.getItem(lastImportKey)));
  } catch (_error) {
    renderLastImportSummary(null);
  }
}

function saveLastImportSummary(summary) {
  localStorage.setItem(lastImportKey, JSON.stringify(summary));
  renderLastImportSummary(summary);
}

function renderSummary() {
  const selectedDate = dateInput.value;
  const selectedMonth = monthKey(selectedDate);
  const dayRecords = records.filter((record) => record.date === selectedDate);
  const mtdRecords = records.filter((record) => monthKey(record.date) === selectedMonth && record.date <= selectedDate);
  const dayHoursValue = hoursWorked(dayRecords);
  const dayPayValue = payTotal(dayRecords);
  const mtdPayValue = payTotal(mtdRecords);
  const mtdHoursValue = totalWorkedHours(mtdRecords);

  fields.mtdProduction.textContent = money(productionTotal(mtdRecords));
  fields.mtdStops.textContent = String(mtdRecords.length);
  fields.mtdPay.textContent = money(mtdPayValue);
  fields.mtdHourly.textContent = `${money(mtdHoursValue ? mtdPayValue / mtdHoursValue : 0)}/hr`;

  fields.dayProduction.textContent = money(productionTotal(dayRecords));
  fields.dayStops.textContent = String(dayRecords.length);
  fields.dayHours.textContent = dayHoursValue.toFixed(2);
  fields.dayPay.textContent = money(dayPayValue);
  fields.dayHourly.textContent = `${money(dayHoursValue ? dayPayValue / dayHoursValue : 0)}/hr`;

  dayHeading.textContent = `Entries for ${selectedDate}`;
  dayEntryCount.textContent = `${dayRecords.length} ${dayRecords.length === 1 ? "record" : "records"}`;
  renderPayBreakdown(mtdRecords);
  renderDayRecords(dayRecords);
  updateDashboardStatus();
}

function renderDayRecords(dayRecords) {
  dayRecordsBody.innerHTML = "";

  const sorted = [...dayRecords].sort((a, b) => String(a.timeStarted || "").localeCompare(String(b.timeStarted || "")));
  for (const record of sorted) {
    const row = document.createElement("tr");
    const cells = [
      `${record.timeStarted || ""} - ${record.timeCompleted || ""}`,
      record.name,
      record.orderNumber,
      record.serviceType,
      record.payType,
      money(record.amount),
      money(calculateRecordPay(record))
    ];

    for (const value of cells) {
      const cell = document.createElement("td");
      cell.textContent = value || "";
      row.append(cell);
    }

    dayRecordsBody.append(row);
  }
}

async function loadRecords() {
  const response = await fetch(`/api/records?database=${encodeURIComponent(selectedDatabase)}`);
  records = await response.json();
  renderSummary();
}

async function loadUnresolvedCount() {
  const response = await fetch(`/api/unresolved/count?database=${encodeURIComponent(selectedDatabase)}`);
  const payload = await response.json();
  const count = payload.count || 0;
  reviewButton.disabled = count === 0;
  reviewButton.classList.toggle("has-unresolved", count > 0);
  reviewButton.textContent = count ? `Unresolved: ${count}` : "Unresolved: 0";
}

async function loadPaySettings() {
  const response = await fetch("/api/pay-types");
  const payload = await response.json();
  paySettings = payload.settings || { commissionRate: 0 };
  payRules = payload.rules || {};
  ruleDefinitions = payload.ruleDefinitions || {};
  renderSummary();
}

async function loadDatabases() {
  const response = await fetch("/api/databases");
  const payload = await response.json();
  const requestedDatabase = localStorage.getItem(selectedDatabaseKey) || payload.defaultDatabase;

  selectedDatabase = payload.databases.includes(requestedDatabase) ? requestedDatabase : payload.databases[0] || "";
  localStorage.setItem(selectedDatabaseKey, selectedDatabase);
  await loadPaySettings();
  await loadRecords();
  await loadUnresolvedCount();
  updateDashboardStatus();
}

dateInput.addEventListener("change", renderSummary);

mtdPayCard.addEventListener("click", togglePayBreakdown);
mtdPayCard.addEventListener("keydown", (event) => {
  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault();
    togglePayBreakdown();
  }
});

openImporterButton.addEventListener("click", () => {
  openModule("/import.html", "Import / Manage");
});

openDatabaseControlsButton.addEventListener("click", () => {
  openModule("/database-controls.html", "Save Files");
});

closeModulePanelButton.addEventListener("click", () => setModulePanelOpen(false));
modulePanelBackdrop.addEventListener("click", () => setModulePanelOpen(false));

window.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && modulePanel.classList.contains("is-open")) {
    setModulePanelOpen(false);
  }
});

reviewButton.addEventListener("click", () => {
  if (reviewButton.disabled) return;
  openModule(`/resolve.html?database=${encodeURIComponent(selectedDatabase)}`, "Unresolved Entries");
});

window.addEventListener("message", async (event) => {
  if (!isTrustedMessage(event)) {
    return;
  }

  if (event.data?.type === "tech-pay-open-module" && event.data.url) {
    openModule(event.data.url, event.data.title || "Module");
    return;
  }

  if (event.data?.type === "tech-pay-close-module") {
    setModulePanelOpen(false);
    return;
  }

  if (event.data?.type === "tech-pay-pay-settings-updated") {
    await loadPaySettings();
    return;
  }

  if (event.data?.type === "tech-pay-import-completed" && event.data.summary) {
    saveLastImportSummary(event.data.summary);
    await loadRecords();
    await loadUnresolvedCount();
    return;
  }

  if (!["tech-pay-unresolved-updated", "tech-pay-record-updated", "tech-pay-databases-updated"].includes(event.data?.type)) {
    return;
  }

  if (event.data?.type === "tech-pay-databases-updated") {
    await loadDatabases();
    return;
  }

  if (event.data.database === selectedDatabase) {
    await loadRecords();
    await loadUnresolvedCount();
  }
});

loadDatabases().catch((error) => {
  statusEl.textContent = error.message || "Could not load dashboard.";
});

renderPayBreakdownVisibility();
loadLastImportSummary();
