const form = document.querySelector("#import-form");
const dateInput = document.querySelector("#work-date");
const fileInput = document.querySelector("#screenshots");
const batchInput = document.querySelector("#batch-file");
const folderLabel = document.querySelector("#folder-label");
const batchLabel = document.querySelector("#batch-label");
const importButton = document.querySelector("#import-button");
const statusEl = document.querySelector("#status");
const recordsBody = document.querySelector("#records-body");
const recordCount = document.querySelector("#record-count");
const databaseSelect = document.querySelector("#database-select");
const reviewButton = document.querySelector("#review-button");
const databaseControlsButton = document.querySelector("#database-controls-button");
const paySettingsButton = document.querySelector("#pay-settings-button");
const editDatabaseButton = document.querySelector("#edit-database-button");
const latestImportSection = document.querySelector("#latest-import-section");
const synopsisDatabase = document.querySelector("#synopsis-database");
const synopsisRecords = document.querySelector("#synopsis-records");
const synopsisProduction = document.querySelector("#synopsis-production");
const synopsisDateRange = document.querySelector("#synopsis-date-range");
const synopsisUnresolved = document.querySelector("#synopsis-unresolved");

const selectedDatabaseKey = "techPaySelectedDatabase";
const supportedImageTypes = new Set(["image/jpeg", "image/png"]);
let currentRecords = [];
let unresolvedCount = 0;
let latestImportIds = [];

function currentDateValue() {
  const date = new Date();
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

dateInput.value = currentDateValue();

function messageTargetOrigin() {
  return window.location.origin && window.location.origin !== "null" ? window.location.origin : "*";
}

function isTrustedMessage(event) {
  return window.location.origin === "null" || event.origin === window.location.origin;
}

function notifyMainWindow(type = "tech-pay-record-updated", database = databaseSelect.value, extra = {}) {
  const message = { type, database, ...extra };

  if (window.opener) {
    window.opener.postMessage(message, messageTargetOrigin());
  }

  if (window.parent && window.parent !== window) {
    window.parent.postMessage(message, messageTargetOrigin());
  }
}

function openModule(url, title, fallbackName, fallbackFeatures) {
  if (window.parent && window.parent !== window) {
    window.parent.postMessage({ type: "tech-pay-open-module", url, title }, messageTargetOrigin());
    return;
  }

  window.open(url, fallbackName, fallbackFeatures);
}

function money(value) {
  if (typeof value !== "number") return "";
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(value);
}

function moneyOrZero(value) {
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(value || 0);
}

function productionTotal(records) {
  return records.reduce((total, record) => total + (typeof record.amount === "number" ? record.amount : 0), 0);
}

function formatDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value || "")) return "";
  const [year, month, day] = value.split("-");
  return `${month}/${day}/${year}`;
}

function renderSynopsis() {
  const dates = currentRecords.map((record) => record.date).filter(Boolean).sort();
  const dateRange = dates.length
    ? `${formatDate(dates[0])} - ${formatDate(dates[dates.length - 1])}`
    : "No entries";

  synopsisDatabase.textContent = databaseSelect.value || "No save file selected";
  synopsisRecords.textContent = String(currentRecords.length);
  synopsisProduction.textContent = moneyOrZero(productionTotal(currentRecords));
  synopsisDateRange.textContent = dateRange;
  synopsisUnresolved.textContent = String(unresolvedCount);
}

function clearLatestImport() {
  latestImportIds = [];
  latestImportSection.hidden = true;
  recordCount.textContent = "0 records";
  recordsBody.innerHTML = "";
}

function refreshLatestImport() {
  if (!latestImportIds.length) return;
  const importedRecords = latestImportIds
    .map((id) => currentRecords.find((record) => record.id === id))
    .filter(Boolean);
  renderRecords(importedRecords);
}

function renderRecords(records, { show = true } = {}) {
  latestImportSection.hidden = !show;
  recordCount.textContent = `${records.length} ${records.length === 1 ? "record" : "records"}`;
  recordsBody.innerHTML = "";

  for (const record of [...records].reverse()) {
    const row = document.createElement("tr");
    const cells = [
      record.date,
      record.name,
      record.address,
      record.orderNumber,
      record.timeStarted,
      record.timeCompleted,
      record.serviceType,
      record.payType,
      money(record.amount),
    ];

    for (const value of cells) {
      const cell = document.createElement("td");
      cell.textContent = value || "";
      row.append(cell);
    }

    const actionCell = document.createElement("td");
    const editButton = document.createElement("button");
    editButton.type = "button";
    editButton.className = "small-button";
    editButton.textContent = "Edit";
    editButton.addEventListener("click", () => {
      const returnUrl = `/import.html`;
      openModule(
        `/edit.html?database=${encodeURIComponent(databaseSelect.value)}&id=${encodeURIComponent(record.id)}&return=${encodeURIComponent(returnUrl)}&returnTitle=${encodeURIComponent("Import / Manage")}`,
        "Edit Work Stop",
        "tech-pay-edit",
        "width=900,height=760"
      );
    });
    actionCell.append(editButton);
    row.append(actionCell);

    recordsBody.append(row);
  }
}

async function loadRecords() {
  const response = await fetch(`/api/records?database=${encodeURIComponent(databaseSelect.value)}`);
  currentRecords = await response.json();
  renderSynopsis();
}

async function loadUnresolvedCount() {
  const response = await fetch(`/api/unresolved/count?database=${encodeURIComponent(databaseSelect.value)}`);
  const payload = await response.json();
  unresolvedCount = payload.count || 0;
  reviewButton.hidden = payload.count === 0;
  reviewButton.textContent = payload.count ? `Review unresolved (${payload.count})` : "Review unresolved";
  renderSynopsis();
}

function renderDatabases(databases, selectedDatabase) {
  databaseSelect.innerHTML = "";

  for (const database of databases) {
    const option = document.createElement("option");
    option.value = database;
    option.textContent = database;
    databaseSelect.append(option);
  }

  databaseSelect.value = databases.includes(selectedDatabase) ? selectedDatabase : databases[0] || "";
}

async function loadDatabases() {
  const response = await fetch("/api/databases");
  const payload = await response.json();
  const selectedDatabase = localStorage.getItem(selectedDatabaseKey) || payload.defaultDatabase;
  renderDatabases(payload.databases, selectedDatabase);
  await loadRecords();
  await loadUnresolvedCount();
  clearLatestImport();
}

databaseSelect.addEventListener("change", async () => {
  localStorage.setItem(selectedDatabaseKey, databaseSelect.value);
  statusEl.textContent = `Using ${databaseSelect.value}.`;
  await loadRecords();
  await loadUnresolvedCount();
  clearLatestImport();
});

databaseControlsButton.addEventListener("click", () => {
  openModule("/database-controls.html", "Save Files", "tech-pay-database-controls", "width=900,height=760");
});

reviewButton.addEventListener("click", () => {
  openModule(
    `/resolve.html?database=${encodeURIComponent(databaseSelect.value)}`,
    "Unresolved Entries",
    "tech-pay-resolve",
    "width=900,height=760"
  );
});

paySettingsButton.addEventListener("click", () => {
  openModule("/pay-settings.html", "Pay Type Settings", "tech-pay-settings", "width=900,height=760");
});

editDatabaseButton.addEventListener("click", () => {
  openModule(
    `/database-editor.html?database=${encodeURIComponent(databaseSelect.value)}`,
    "Edit Database",
    "tech-pay-database-editor",
    "width=1180,height=820"
  );
});

window.addEventListener("message", async (event) => {
  if (
    !isTrustedMessage(event) ||
    !["tech-pay-unresolved-updated", "tech-pay-record-updated", "tech-pay-databases-updated"].includes(event.data?.type)
  ) {
    return;
  }

  if (event.data?.type === "tech-pay-databases-updated") {
    await loadDatabases();
    return;
  }

  if (event.data.database === databaseSelect.value) {
    await loadRecords();
    await loadUnresolvedCount();
    refreshLatestImport();
    notifyMainWindow(event.data.type, event.data.database);
  }
});

fileInput.addEventListener("change", () => {
  const files = [...fileInput.files];
  if (!files.length) {
    folderLabel.textContent = "No screenshots selected";
    return;
  }

  if (files.length === 1) {
    folderLabel.textContent = files[0].name;
    return;
  }

  folderLabel.textContent = `${files.length} screenshots selected`;
});

batchInput.addEventListener("change", () => {
  const [file] = [...batchInput.files];
  batchLabel.textContent = file ? file.name : "No batch selected";
});

function importSummaryText(payload) {
  const duplicates = payload.duplicates || [];
  const duplicateText = duplicates.length
    ? ` ${duplicates.length} duplicate ${duplicates.length === 1 ? "was" : "were"} removed.`
    : "";
  return `Import finished: ${payload.imported.length} saved, ${payload.unresolved.length} unresolved.${duplicateText}`;
}

async function finishImport(payload) {
  currentRecords = payload.records || [];
  latestImportIds = (payload.imported || []).map((record) => record.id).filter(Boolean);
  renderRecords(payload.imported || []);
  await loadUnresolvedCount();

  statusEl.textContent = importSummaryText(payload);
  notifyMainWindow("tech-pay-import-completed", databaseSelect.value, {
    database: databaseSelect.value,
    date: dateInput.value,
    saved: payload.imported.length,
    unresolved: payload.unresolved.length,
    duplicates: (payload.duplicates || []).length,
    completedAt: new Date().toISOString()
  });
  notifyMainWindow("tech-pay-record-updated");
  if (payload.unresolved.length) {
    openModule(
      `/resolve.html?database=${encodeURIComponent(databaseSelect.value)}`,
      "Unresolved Entries",
      "tech-pay-resolve",
      "width=900,height=760"
    );
  }
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();

  const files = [...fileInput.files].filter((file) => supportedImageTypes.has(file.type));
  const [batchFile] = [...batchInput.files].filter((file) => file.type === "application/json" || file.name.toLowerCase().endsWith(".json"));

  if (!files.length && !batchFile) {
    statusEl.textContent = "Choose screenshots or an iPhone import-batch JSON file first.";
    return;
  }

  if (files.length && batchFile) {
    statusEl.textContent = "Choose screenshots or one iPhone batch, not both at the same time.";
    return;
  }

  importButton.disabled = true;
  statusEl.textContent = batchFile ? "Reading iPhone import batch..." : `Reading ${files.length} screenshot${files.length === 1 ? "" : "s"}...`;

  try {
    const formData = new FormData();
    formData.append("date", dateInput.value);
    formData.append("database", databaseSelect.value);
    let endpoint = "/api/import";

    if (batchFile) {
      endpoint = "/api/import-batch";
      formData.append("batch", batchFile, batchFile.name);
    } else {
      for (const file of files) {
        formData.append("screenshots", file, file.name);
      }
    }

    const response = await fetch(endpoint, {
      method: "POST",
      body: formData
    });

    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error || "Import failed.");

    await finishImport(payload);
    form.reset();
    dateInput.value = currentDateValue();
    folderLabel.textContent = "No screenshots selected";
    batchLabel.textContent = "No batch selected";
  } catch (error) {
    statusEl.textContent = error.message;
  } finally {
    importButton.disabled = false;
  }
});

loadDatabases().catch(() => {
  statusEl.textContent = "Could not load the JSON save files yet.";
});
