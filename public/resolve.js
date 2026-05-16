const params = new URLSearchParams(window.location.search);
const database = params.get("database") || "work-stops.json";
const statusEl = document.querySelector("#review-status");
const subtitle = document.querySelector("#review-subtitle");
const reviewList = document.querySelector("#review-list");
let payTypes = [];
let unresolvedRecords = [];
const deferredRecordIds = new Set();

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

subtitle.textContent = `Reviewing unresolved entries for ${database}.`;

function messageTargetOrigin() {
  return window.location.origin && window.location.origin !== "null" ? window.location.origin : "*";
}

function isMissing(record, field) {
  return (record.missingFields || []).includes(field);
}

function fieldValue(record, field) {
  const value = record[field];
  if (field === "amount" && typeof value === "number") return value.toFixed(2);
  return value || "";
}

function inputHasValue(input) {
  if (input.name === "amount") return Number.isFinite(Number(input.value)) && Number(input.value) >= 0;
  if (input.name === "date") return /^\d{4}-\d{2}-\d{2}$/.test(input.value);
  return Boolean(input.value.trim());
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
    window.opener.postMessage({ type: "tech-pay-unresolved-updated", database }, messageTargetOrigin());
  }

  if (window.parent && window.parent !== window) {
    window.parent.postMessage({ type: "tech-pay-unresolved-updated", database }, messageTargetOrigin());
  }
}

function renderEmpty() {
  reviewList.innerHTML = "";
  const empty = document.createElement("div");
  empty.className = "empty-state";
  empty.textContent = "No unresolved entries for this save file.";
  reviewList.append(empty);
  statusEl.textContent = "All caught up.";
}

function closeWhenComplete(records) {
  if (records.length) return;

  notifyMainWindow();
  setTimeout(() => {
    if (window.parent && window.parent !== window) {
      window.parent.postMessage({ type: "tech-pay-close-module" }, messageTargetOrigin());
      return;
    }

    if (window.opener) {
      window.close();
    }
  }, 500);
}

function visibleRecords(records = unresolvedRecords) {
  return records.filter((record) => !deferredRecordIds.has(record.id));
}

function deferRecord(id) {
  deferredRecordIds.add(id);
  notifyMainWindow();
  renderRecords(visibleRecords());
  closeWhenComplete(visibleRecords());
}

function renderRecords(records) {
  reviewList.innerHTML = "";

  if (!records.length) {
    renderEmpty();
    return;
  }

  statusEl.textContent = `${records.length} unresolved ${records.length === 1 ? "entry" : "entries"} need review.`;

  for (const record of records) {
    const card = document.createElement("article");
    card.className = "review-card";

    const heading = document.createElement("div");
    heading.className = "review-card-heading";
    heading.innerHTML = `<strong>${record.name || "Unresolved entry"}</strong><span>${record.date || ""}</span>`;
    card.append(heading);

    const form = document.createElement("form");
    form.className = "review-form";

    for (const [field, label, type] of fields) {
      const wrapper = document.createElement("label");
      wrapper.className = isMissing(record, field) ? "missing-field" : "";
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
      input.addEventListener("input", () => {
        wrapper.classList.toggle("missing-field", !inputHasValue(input));
      });
      input.addEventListener("change", () => {
        wrapper.classList.toggle("missing-field", !inputHasValue(input));
      });

      wrapper.append(input);
      form.append(wrapper);
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
    saveButton.textContent = "Save to Database";

    const skipButton = document.createElement("button");
    skipButton.type = "button";
    skipButton.className = "secondary-button";
    skipButton.textContent = "Skip Import";
    skipButton.addEventListener("click", () => skipRecord(record.id));

    const laterButton = document.createElement("button");
    laterButton.type = "button";
    laterButton.className = "secondary-button";
    laterButton.textContent = "Keep for Later";
    laterButton.addEventListener("click", () => deferRecord(record.id));

    actions.append(saveButton, laterButton, skipButton);
    form.append(actions);

    form.addEventListener("submit", (event) => {
      event.preventDefault();
      if (markMissingFields(form)) {
        statusEl.textContent = "Fill in the red fields before saving this entry.";
        return;
      }
      resolveRecord(record.id, new FormData(form));
    });

    card.append(form);
    reviewList.append(card);
  }
}

async function loadUnresolved() {
  const payTypesResponse = await fetch("/api/pay-types");
  const payTypesPayload = await payTypesResponse.json();
  payTypes = payTypesPayload.payTypes || [];

  const response = await fetch(`/api/unresolved?database=${encodeURIComponent(database)}`);
  const records = await response.json();
  unresolvedRecords = records;
  renderRecords(visibleRecords());
}

async function resolveRecord(id, formData) {
  const record = Object.fromEntries(formData.entries());

  try {
    const response = await fetch(`/api/unresolved/${encodeURIComponent(id)}/resolve`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ database, record })
    });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error || "Could not save that entry.");

    notifyMainWindow();
    unresolvedRecords = payload.unresolved;
    renderRecords(visibleRecords());
    closeWhenComplete(visibleRecords());
  } catch (error) {
    statusEl.textContent = error.message;
  }
}

async function skipRecord(id) {
  try {
    const response = await fetch(`/api/unresolved/${encodeURIComponent(id)}/skip`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ database })
    });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error || "Could not skip that entry.");

    notifyMainWindow();
    unresolvedRecords = payload.unresolved;
    renderRecords(visibleRecords());
    closeWhenComplete(visibleRecords());
  } catch (error) {
    statusEl.textContent = error.message;
  }
}

loadUnresolved().catch(() => {
  statusEl.textContent = "Could not load unresolved entries.";
});
