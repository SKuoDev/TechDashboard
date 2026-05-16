const statusEl = document.querySelector("#settings-status");
const commissionForm = document.querySelector("#commission-form");
const commissionRateInput = document.querySelector("#commission-rate");
const mappingForm = document.querySelector("#mapping-form");
const serviceTypeInput = document.querySelector("#service-type");
const payTypeSelect = document.querySelector("#pay-type");
const rulesBody = document.querySelector("#rules-body");
const mappingBody = document.querySelector("#mapping-body");

let payTypes = [];
let mappings = {};
let paySettings = { commissionRate: 0 };
let payRules = {};
let ruleDefinitions = {};

function messageTargetOrigin() {
  return window.location.origin && window.location.origin !== "null" ? window.location.origin : "*";
}

function notifyParent() {
  if (window.opener) {
    window.opener.postMessage({ type: "tech-pay-pay-settings-updated" }, messageTargetOrigin());
  }

  if (window.parent && window.parent !== window) {
    window.parent.postMessage({ type: "tech-pay-pay-settings-updated" }, messageTargetOrigin());
  }
}

function renderPayTypes() {
  payTypeSelect.innerHTML = "";

  for (const payType of payTypes) {
    const option = document.createElement("option");
    option.value = payType;
    option.textContent = payType;
    payTypeSelect.append(option);
  }
}

function renderPaySettings() {
  commissionRateInput.value = ((Number(paySettings.commissionRate) || 0) * 100).toFixed(2);
}

function renderPayRules() {
  rulesBody.innerHTML = "";

  for (const payType of payTypes) {
    const payRule = payRules[payType] || { rule: "noPay" };
    const definition = ruleDefinitions[payRule.rule] || { name: payRule.rule || "Unknown", equation: "$0.00" };
    const row = document.createElement("tr");
    const cells = [payType, definition.name, definition.equation];

    for (const value of cells) {
      const cell = document.createElement("td");
      cell.textContent = value;
      row.append(cell);
    }

    rulesBody.append(row);
  }
}

function renderMappings() {
  mappingBody.innerHTML = "";

  const entries = Object.entries(mappings).sort(([a], [b]) => a.localeCompare(b));
  for (const [serviceType, payType] of entries) {
    const row = document.createElement("tr");

    const serviceCell = document.createElement("td");
    serviceCell.textContent = serviceType;

    const payTypeCell = document.createElement("td");
    payTypeCell.textContent = payType;

    const actionCell = document.createElement("td");
    const editButton = document.createElement("button");
    editButton.type = "button";
    editButton.className = "small-button";
    editButton.textContent = "Edit";
    editButton.addEventListener("click", () => {
      serviceTypeInput.value = serviceType;
      payTypeSelect.value = payType;
      serviceTypeInput.focus();
    });

    const deleteButton = document.createElement("button");
    deleteButton.type = "button";
    deleteButton.className = "small-button danger-button";
    deleteButton.textContent = "Delete";
    deleteButton.addEventListener("click", () => deleteMapping(serviceType));

    actionCell.append(editButton, deleteButton);
    row.append(serviceCell, payTypeCell, actionCell);
    mappingBody.append(row);
  }

  statusEl.textContent = `${entries.length} mapping${entries.length === 1 ? "" : "s"} loaded.`;
}

async function loadMappings() {
  const response = await fetch("/api/pay-types");
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error || "Could not load pay type mappings.");

  payTypes = payload.payTypes || [];
  mappings = payload.mappings || {};
  paySettings = payload.settings || { commissionRate: 0 };
  payRules = payload.rules || {};
  ruleDefinitions = payload.ruleDefinitions || {};
  renderPayTypes();
  renderPaySettings();
  renderPayRules();
  renderMappings();
}

async function saveCommissionRate() {
  const commissionRate = Number(commissionRateInput.value) / 100;
  if (!Number.isFinite(commissionRate) || commissionRate < 0 || commissionRate > 1) {
    statusEl.textContent = "Commission rate must be between 0% and 100%.";
    return;
  }

  const response = await fetch("/api/pay-settings", {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ commissionRate })
  });
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error || "Could not save commission rate.");

  paySettings = payload.settings || { commissionRate };
  renderPaySettings();
  statusEl.textContent = `Saved base commission rate at ${commissionRateInput.value}%.`;
  notifyParent();
}

async function saveMapping(serviceType, payType) {
  const response = await fetch("/api/pay-types/mappings", {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ serviceType, payType })
  });
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error || "Could not save mapping.");

  mappings = payload.mappings || {};
  renderMappings();
  mappingForm.reset();
  statusEl.textContent = `Saved mapping for ${serviceType}.`;
  notifyParent();
}

async function deleteMapping(serviceType) {
  const ok = window.confirm(`Delete the pay type mapping for "${serviceType}"?`);
  if (!ok) return;

  const response = await fetch("/api/pay-types/mappings", {
    method: "DELETE",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ serviceType })
  });
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error || "Could not delete mapping.");

  mappings = payload.mappings || {};
  renderMappings();
  statusEl.textContent = `Deleted mapping for ${serviceType}.`;
  notifyParent();
}

mappingForm.addEventListener("submit", async (event) => {
  event.preventDefault();

  const serviceType = serviceTypeInput.value.trim();
  const payType = payTypeSelect.value;
  if (!serviceType || !payType) {
    statusEl.textContent = "Service type and pay type are required.";
    return;
  }

  try {
    await saveMapping(serviceType, payType);
  } catch (error) {
    statusEl.textContent = error.message;
  }
});

commissionForm.addEventListener("submit", async (event) => {
  event.preventDefault();

  try {
    await saveCommissionRate();
  } catch (error) {
    statusEl.textContent = error.message;
  }
});

loadMappings().catch((error) => {
  statusEl.textContent = error.message;
});
