const databaseSelect = document.querySelector("#database-select");
const useDatabaseButton = document.querySelector("#use-database-button");
const databaseForm = document.querySelector("#database-form");
const databaseName = document.querySelector("#database-name");
const restoreForm = document.querySelector("#restore-form");
const backupSelect = document.querySelector("#backup-select");
const deleteDatabaseButton = document.querySelector("#delete-database-button");
const statusEl = document.querySelector("#database-status");
const activeDatabaseLabel = document.querySelector("#active-database-label");
const backupCount = document.querySelector("#backup-count");

const selectedDatabaseKey = "techPaySelectedDatabase";
let defaultDatabase = "work-stops.json";

function messageTargetOrigin() {
  return window.location.origin && window.location.origin !== "null" ? window.location.origin : "*";
}

function notifyDatabasesUpdated(database = databaseSelect.value) {
  localStorage.setItem(selectedDatabaseKey, database);

  if (window.opener) {
    window.opener.postMessage({ type: "tech-pay-databases-updated", database }, messageTargetOrigin());
  }

  if (window.parent && window.parent !== window) {
    window.parent.postMessage({ type: "tech-pay-databases-updated", database }, messageTargetOrigin());
  }
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
  activeDatabaseLabel.textContent = databaseSelect.value || "No save file selected";
  deleteDatabaseButton.disabled = databaseSelect.value === defaultDatabase;
}

async function loadBackups() {
  const response = await fetch(`/api/backups?database=${encodeURIComponent(databaseSelect.value)}`);
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error || "Could not load backups.");

  backupSelect.innerHTML = "";
  const backups = payload.backups || [];
  const blank = document.createElement("option");
  blank.value = "";
  blank.textContent = backups.length ? "Choose backup" : "No backups yet";
  backupSelect.append(blank);

  for (const backup of backups) {
    const option = document.createElement("option");
    option.value = backup;
    option.textContent = backup;
    backupSelect.append(option);
  }

  backupCount.textContent = `${backups.length} backup${backups.length === 1 ? "" : "s"}`;
}

async function loadDatabases() {
  const response = await fetch("/api/databases");
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error || "Could not load save files.");

  defaultDatabase = payload.defaultDatabase;
  const selectedDatabase = localStorage.getItem(selectedDatabaseKey) || payload.defaultDatabase;
  renderDatabases(payload.databases, selectedDatabase);
  await loadBackups();
  statusEl.textContent = `Using ${databaseSelect.value}.`;
}

databaseSelect.addEventListener("change", async () => {
  activeDatabaseLabel.textContent = databaseSelect.value;
  deleteDatabaseButton.disabled = databaseSelect.value === defaultDatabase;
  await loadBackups();
});

useDatabaseButton.addEventListener("click", () => {
  notifyDatabasesUpdated(databaseSelect.value);
  statusEl.textContent = `Using ${databaseSelect.value}.`;
});

databaseForm.addEventListener("submit", async (event) => {
  event.preventDefault();

  const name = databaseName.value.trim();
  if (!name) {
    statusEl.textContent = "Type a name for the new save file first.";
    return;
  }

  try {
    const response = await fetch("/api/databases", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name })
    });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error || "Could not create save file.");

    renderDatabases(payload.databases, payload.database);
    await loadBackups();
    databaseForm.reset();
    notifyDatabasesUpdated(payload.database);
    statusEl.textContent = `Created and selected ${payload.database}.`;
  } catch (error) {
    statusEl.textContent = error.message;
  }
});

restoreForm.addEventListener("submit", async (event) => {
  event.preventDefault();

  if (!backupSelect.value) {
    statusEl.textContent = "Choose a backup to restore first.";
    return;
  }

  const ok = window.confirm(`Restore ${databaseSelect.value} from this backup? A backup of the current file will be made first.`);
  if (!ok) return;

  try {
    const response = await fetch("/api/backups/restore", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ database: databaseSelect.value, backup: backupSelect.value })
    });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error || "Could not restore backup.");

    await loadBackups();
    notifyDatabasesUpdated(databaseSelect.value);
    statusEl.textContent = `Restored ${databaseSelect.value}.`;
  } catch (error) {
    statusEl.textContent = error.message;
  }
});

deleteDatabaseButton.addEventListener("click", async () => {
  const database = databaseSelect.value;
  const ok = window.confirm(`Delete ${database}? A backup will be made first.`);
  if (!ok) return;

  try {
    const response = await fetch("/api/databases", {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ database })
    });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error || "Could not delete save file.");

    renderDatabases(payload.databases, payload.database);
    await loadBackups();
    notifyDatabasesUpdated(payload.database);
    statusEl.textContent = `Deleted ${database}.`;
  } catch (error) {
    statusEl.textContent = error.message;
  }
});

loadDatabases().catch((error) => {
  statusEl.textContent = error.message || "Could not load save files.";
});
