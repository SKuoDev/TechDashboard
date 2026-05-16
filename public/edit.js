const params = new URLSearchParams(window.location.search);
const database = params.get("database") || "work-stops.json";
const recordId = params.get("id");
const returnUrl = params.get("return");
const returnTitle = params.get("returnTitle") || "Module";
const statusEl = document.querySelector("#edit-status");
const subtitle = document.querySelector("#edit-subtitle");
const editPanel = document.querySelector("#edit-panel");
let payTypes = [];

const fields = [
  ["date", "Date", "date"],
  ["name", "Name", "text"],
  ["address", "Physical address", "text"],
  ["orderNumber", "Order number", "text"],
  ["timeStarted", "Time started", "text"],
  ["timeCompleted", "Time completed", "text"],
  ["serviceType", "Service type", "text"],
  ["payType", "Pay type", "select"],
  ["amount", "Amount", "number"]
];

subtitle.textContent = `Editing an entry in ${database}.`;

function messageTargetOrigin() {
  return window.location.origin && window.location.origin !== "null" ? window.location.origin : "*";
}

function inputHasValue(input) {
  if (input.name === "amount") return Number.isFinite(Number(input.value)) && Number(input.value) >= 0;
  if (input.name === "date") return /^\d{4}-\d{2}-\d{2}$/.test(input.value);
  return Boolean(input.value.trim());
}

function fieldValue(record, field) {
  const value = record[field];
  if (field === "amount" && typeof value === "number") return value.toFixed(2);
  return value || "";
}

function markMissingFields(form) {
  let hasMissing = false;

  for (const input of form.querySelectorAll("input, select")) {
    const wrapper = input.closest("label");
    const missing = !inputHasValue(input);
    wrapper.classList.toggle("missing-field", missing);
    hasMissing = hasMissing || missing;
  }

  return hasMissing;
}

function notifyMainWindow() {
  if (window.opener) {
    window.opener.postMessage({ type: "tech-pay-record-updated", database }, messageTargetOrigin());
  }

  if (window.parent && window.parent !== window) {
    window.parent.postMessage({ type: "tech-pay-record-updated", database }, messageTargetOrigin());
  }
}

function leaveEditor() {
  if (window.parent && window.parent !== window) {
    if (returnUrl) {
      window.parent.postMessage({ type: "tech-pay-open-module", url: returnUrl, title: returnTitle }, messageTargetOrigin());
      return;
    }

    window.parent.postMessage({ type: "tech-pay-close-module" }, messageTargetOrigin());
    return;
  }

  window.close();
}

function createField(record, field, label, type) {
  const wrapper = document.createElement("label");
  wrapper.textContent = label;

  const input = type === "select" ? document.createElement("select") : document.createElement("input");
  input.name = field;

  if (type === "select") {
    const blank = document.createElement("option");
    blank.value = "";
    blank.textContent = "Choose pay type";
    input.append(blank);

    for (const payType of payTypes) {
      const option = document.createElement("option");
      option.value = payType;
      option.textContent = payType;
      input.append(option);
    }
  } else {
    input.type = type;
    if (field === "amount") {
      input.step = "0.01";
      input.min = "0";
    }
  }

  input.value = fieldValue(record, field);
  wrapper.classList.toggle("missing-field", !inputHasValue(input));
  input.addEventListener("input", () => wrapper.classList.toggle("missing-field", !inputHasValue(input)));
  input.addEventListener("change", () => wrapper.classList.toggle("missing-field", !inputHasValue(input)));
  wrapper.append(input);
  return wrapper;
}

function renderEditor(record) {
  editPanel.innerHTML = "";

  const card = document.createElement("article");
  card.className = "review-card";

  const heading = document.createElement("div");
  heading.className = "review-card-heading";
  heading.innerHTML = `<strong>${record.name || "Saved entry"}</strong><span>${record.orderNumber || ""}</span>`;
  card.append(heading);

  const form = document.createElement("form");
  form.className = "review-form";

  for (const [field, label, type] of fields) {
    form.append(createField(record, field, label, type));
  }

  const rawText = document.createElement("details");
  rawText.className = "raw-text";
  rawText.innerHTML = "<summary>OCR text</summary><pre></pre>";
  rawText.querySelector("pre").textContent = record.rawText || "";
  form.append(rawText);

  const actions = document.createElement("div");
  actions.className = "review-actions";

  const saveButton = document.createElement("button");
  saveButton.type = "submit";
  saveButton.textContent = "Save Changes";

  const closeButton = document.createElement("button");
  closeButton.type = "button";
  closeButton.className = "secondary-button";
  closeButton.textContent = "Close";
  closeButton.addEventListener("click", leaveEditor);

  actions.append(saveButton, closeButton);
  form.append(actions);

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    if (markMissingFields(form)) {
      statusEl.textContent = "Fill in the red fields before saving this entry.";
      return;
    }
    saveRecord(new FormData(form));
  });

  card.append(form);
  editPanel.append(card);
  statusEl.textContent = "Ready to edit.";
}

async function loadEditor() {
  const payTypesResponse = await fetch("/api/pay-types");
  const payTypesPayload = await payTypesResponse.json();
  payTypes = payTypesPayload.payTypes || [];

  const response = await fetch(`/api/records/${encodeURIComponent(recordId)}?database=${encodeURIComponent(database)}`);
  const record = await response.json();
  if (!response.ok) throw new Error(record.error || "Could not load that entry.");
  renderEditor(record);
}

async function saveRecord(formData) {
  const record = Object.fromEntries(formData.entries());

  try {
    const response = await fetch(`/api/records/${encodeURIComponent(recordId)}`, {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ database, record })
    });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error || "Could not save changes.");

    notifyMainWindow();
    statusEl.textContent = "Saved.";
    setTimeout(leaveEditor, 500);
  } catch (error) {
    statusEl.textContent = error.message;
  }
}

loadEditor().catch((error) => {
  statusEl.textContent = error.message;
});
