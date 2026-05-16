const params = new URLSearchParams(window.location.search);
const database = params.get("database") || "work-stops.json";
const subtitle = document.querySelector("#editor-subtitle");
const statusEl = document.querySelector("#editor-status");
const filterForm = document.querySelector("#filter-form");
const startDateInput = document.querySelector("#start-date");
const endDateInput = document.querySelector("#end-date");
const showAllInput = document.querySelector("#show-all");
const filteredCount = document.querySelector("#filtered-count");
const filteredStops = document.querySelector("#filtered-stops");
const filteredProduction = document.querySelector("#filtered-production");
const filteredRange = document.querySelector("#filtered-range");
const recordsBody = document.querySelector("#editor-records-body");
const emptyState = document.querySelector("#editor-empty");
const tableWrap = document.querySelector("#editor-table-wrap");

let records = [];

function currentDateValue() {
  const date = new Date();
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

const today = currentDateValue();
startDateInput.value = today;
endDateInput.value = today;
subtitle.textContent = `Editing ${database}.`;

function messageTargetOrigin() {
  return window.location.origin && window.location.origin !== "null" ? window.location.origin : "*";
}

function isTrustedMessage(event) {
  return window.location.origin === "null" || event.origin === window.location.origin;
}

function money(value) {
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(value || 0);
}

function formatDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value || "")) return "";
  const [year, month, day] = value.split("-");
  return `${month}/${day}/${year}`;
}

function productionTotal(list) {
  return list.reduce((total, record) => total + (typeof record.amount === "number" ? record.amount : 0), 0);
}

function filteredRecords() {
  if (showAllInput.checked) return [...records];

  const start = startDateInput.value || today;
  const end = endDateInput.value || start;
  return records.filter((record) => record.date >= start && record.date <= end);
}

function filterLabel() {
  if (showAllInput.checked) return "All";
  if (startDateInput.value === endDateInput.value) return formatDate(startDateInput.value);
  return `${formatDate(startDateInput.value)} - ${formatDate(endDateInput.value)}`;
}

function notifyParent() {
  if (window.opener) {
    window.opener.postMessage({ type: "tech-pay-record-updated", database }, messageTargetOrigin());
  }

  if (window.parent && window.parent !== window) {
    window.parent.postMessage({ type: "tech-pay-record-updated", database }, messageTargetOrigin());
  }
}

function openModule(url, title, fallbackName, fallbackFeatures) {
  if (window.parent && window.parent !== window) {
    window.parent.postMessage({ type: "tech-pay-open-module", url, title }, messageTargetOrigin());
    return;
  }

  window.open(url, fallbackName, fallbackFeatures);
}

function openEditWindow(record) {
  const returnUrl = `/database-editor.html?database=${encodeURIComponent(database)}`;
  openModule(
    `/edit.html?database=${encodeURIComponent(database)}&id=${encodeURIComponent(record.id)}&return=${encodeURIComponent(returnUrl)}&returnTitle=${encodeURIComponent("Edit Database")}`,
    "Edit Work Stop",
    "tech-pay-edit",
    "width=900,height=760"
  );
}

function renderRecords() {
  const list = filteredRecords().sort((a, b) => {
    const dateCompare = String(a.date || "").localeCompare(String(b.date || ""));
    if (dateCompare !== 0) return dateCompare;
    return String(a.timeStarted || "").localeCompare(String(b.timeStarted || ""));
  });

  filteredCount.textContent = `${list.length} ${list.length === 1 ? "record" : "records"}`;
  filteredStops.textContent = String(list.length);
  filteredProduction.textContent = money(productionTotal(list));
  filteredRange.textContent = filterLabel();
  recordsBody.innerHTML = "";
  emptyState.hidden = list.length > 0;
  tableWrap.hidden = list.length === 0;

  for (const record of list) {
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
      money(record.amount)
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
    editButton.addEventListener("click", () => openEditWindow(record));
    actionCell.append(editButton);
    row.append(actionCell);
    recordsBody.append(row);
  }

  statusEl.textContent = `Showing ${filterLabel()} in ${database}.`;
}

async function loadRecords() {
  const response = await fetch(`/api/records?database=${encodeURIComponent(database)}`);
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error || "Could not load database.");
  records = payload;
  renderRecords();
}

filterForm.addEventListener("submit", (event) => {
  event.preventDefault();
  if (!showAllInput.checked && startDateInput.value > endDateInput.value) {
    statusEl.textContent = "Start date must be before the end date.";
    return;
  }
  renderRecords();
});

showAllInput.addEventListener("change", () => {
  startDateInput.disabled = showAllInput.checked;
  endDateInput.disabled = showAllInput.checked;
  renderRecords();
});

window.addEventListener("message", async (event) => {
  if (
    !isTrustedMessage(event) ||
    event.data?.type !== "tech-pay-record-updated" ||
    event.data.database !== database
  ) {
    return;
  }

  await loadRecords();
  notifyParent();
});

loadRecords().catch((error) => {
  statusEl.textContent = error.message || "Could not load database.";
});
