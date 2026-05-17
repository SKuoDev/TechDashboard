const crypto = require("crypto");
const fs = require("fs/promises");
const path = require("path");

const express = require("express");
const multer = require("multer");
const { createWorker } = require("tesseract.js");

const app = express();
const upload = multer({ storage: multer.memoryStorage() });

const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || "127.0.0.1";
const DEFAULT_DATABASE = "work-stops.json";
const BACKUP_DIR = path.join(__dirname, "backups");
const PAY_TYPES = ["Prod", "IS INI", "PS INI", "SENTRICON", "SEN INI", "TI", "ISR", "PM", "MSC", "MSS", "MISC NOPAY"];
const PAY_TYPE_MAPPINGS_FILE = path.join(__dirname, "pay-type-mappings.json");
const PAY_SETTINGS_FILE = path.join(__dirname, "pay-settings.json");
const PAY_RULES_FILE = path.join(__dirname, "pay-rules.json");
const DEFAULT_PAY_TYPE_MAPPINGS = {
  "Taexx Pest Control Service": "Prod"
};
const DEFAULT_PAY_SETTINGS = {
  commissionRate: 0.2
};
const DEFAULT_PAY_RULES = {
  Prod: { label: "Production", rule: "commission" },
  "IS INI": { label: "Inside Initial", rule: "initialCommission" },
  "PS INI": { label: "Premium Service Initial", rule: "initialCommission" },
  SENTRICON: { label: "Sentricon", rule: "sentriconEightPercent" },
  "SEN INI": { label: "Sentricon Initial", rule: "flat45" },
  TI: { label: "Termite Inspection", rule: "flat10" },
  ISR: { label: "Inside Sales Referral", rule: "noPay" },
  PM: { label: "Production Management", rule: "commission" },
  MSC: { label: "MSC", rule: "commission" },
  MSS: { label: "MSS", rule: "commission" },
  "MISC NOPAY": { label: "Misc No Pay", rule: "noPay" }
};
const PAY_RULE_DEFINITIONS = {
  commission: {
    name: "Commission",
    equation: "Amount x Commission Rate",
    calculation: { type: "commission", multiplier: 1 }
  },
  initialCommission: {
    name: "Initial Service",
    equation: "Amount x Commission Rate x 1.5",
    calculation: { type: "commission", multiplier: 1.5 }
  },
  sentriconEightPercent: {
    name: "Sentricon",
    equation: "Amount x 8%",
    calculation: { type: "percent", rate: 0.08 }
  },
  flat10: {
    name: "Flat Rate",
    equation: "$10.00",
    calculation: { type: "flat", amount: 10 }
  },
  flat45: {
    name: "Flat Rate",
    equation: "$45.00",
    calculation: { type: "flat", amount: 45 }
  },
  noPay: {
    name: "No Pay",
    equation: "$0.00",
    calculation: { type: "none" }
  }
};
const REQUIRED_FIELDS = ["date", "name", "address", "orderNumber", "timeStarted", "timeCompleted", "serviceType", "payType", "amount"];
const SUPPORTED_IMAGE_TYPES = new Set(["image/jpeg", "image/png"]);
const SUPPORTED_BATCH_TYPES = new Set(["application/json", "text/json", ""]);

app.use(express.json({ limit: "1mb" }));
app.use(express.static(path.join(__dirname, "public")));
app.use("/graphics", express.static(path.join(__dirname, "graphics")));

let workerPromise;

function getWorker() {
  if (!workerPromise) {
    workerPromise = createWorker("eng");
  }
  return workerPromise;
}

function cleanDatabaseName(name) {
  const cleaned = String(name || DEFAULT_DATABASE)
    .trim()
    .replace(/\.json$/i, "")
    .replace(/[^a-z0-9 _-]/gi, "")
    .replace(/\s+/g, "-")
    .toLowerCase();

  return `${cleaned || "work-stops"}.json`;
}

function getDatabaseFile(name) {
  return path.join(__dirname, cleanDatabaseName(name));
}

function getUnresolvedFile(name) {
  const database = cleanDatabaseName(name).replace(/\.json$/i, "");
  return path.join(__dirname, `unresolved-${database}.json`);
}

function backupStamp() {
  return new Date().toISOString().replace(/[:.]/g, "-");
}

function getBackupDir(file) {
  return path.join(BACKUP_DIR, path.basename(file, ".json"));
}

async function fileExists(file) {
  try {
    await fs.access(file);
    return true;
  } catch (_error) {
    return false;
  }
}

async function backupFile(file, reason = "auto") {
  if (!(await fileExists(file))) return null;

  const backupDir = getBackupDir(file);
  const backupName = `${backupStamp()}-${reason}.json`;
  const backupFilePath = path.join(backupDir, backupName);
  await fs.mkdir(backupDir, { recursive: true });
  await fs.copyFile(file, backupFilePath);
  return backupName;
}

async function readJsonArray(file) {
  try {
    const text = await fs.readFile(file, "utf8");
    const parsed = JSON.parse(text);
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    if (error.code === "ENOENT") return [];
    throw error;
  }
}

async function readJsonObject(file, fallback = {}) {
  try {
    const text = await fs.readFile(file, "utf8");
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : fallback;
  } catch (error) {
    if (error.code === "ENOENT") return fallback;
    throw error;
  }
}

async function readDatabase(name) {
  return readJsonArray(getDatabaseFile(name));
}

async function writeDatabase(name, records, options = {}) {
  if (options.backup !== false) {
    await backupFile(getDatabaseFile(name), options.reason || "database-write");
  }
  await fs.writeFile(getDatabaseFile(name), `${JSON.stringify(records, null, 2)}\n`);
}

async function readUnresolved(name) {
  return readJsonArray(getUnresolvedFile(name));
}

async function writeUnresolved(name, records, options = {}) {
  if (options.backup !== false) {
    await backupFile(getUnresolvedFile(name), options.reason || "unresolved-write");
  }
  await fs.writeFile(getUnresolvedFile(name), `${JSON.stringify(records, null, 2)}\n`);
}

async function listBackups(name) {
  const backupDir = getBackupDir(getDatabaseFile(name));

  try {
    const entries = await fs.readdir(backupDir);
    return entries
      .filter((entry) => entry.endsWith(".json"))
      .sort((a, b) => b.localeCompare(a));
  } catch (error) {
    if (error.code === "ENOENT") return [];
    throw error;
  }
}

async function restoreBackup(name, backupName) {
  const database = cleanDatabaseName(name);
  const backups = await listBackups(database);

  if (!backups.includes(backupName)) {
    const error = new Error("That backup was not found.");
    error.status = 404;
    throw error;
  }

  const dataFile = getDatabaseFile(database);
  const backupFilePath = path.join(getBackupDir(dataFile), backupName);
  const records = await readJsonArray(backupFilePath);
  await backupFile(dataFile, "before-restore");
  await writeDatabase(database, records, { backup: false });
  return records;
}

async function readPayTypeMappings() {
  const mappings = await readJsonObject(PAY_TYPE_MAPPINGS_FILE, DEFAULT_PAY_TYPE_MAPPINGS);
  const merged = { ...DEFAULT_PAY_TYPE_MAPPINGS, ...mappings };
  await fs.writeFile(PAY_TYPE_MAPPINGS_FILE, `${JSON.stringify(merged, null, 2)}\n`);
  return merged;
}

async function writePayTypeMappings(mappings) {
  await backupFile(PAY_TYPE_MAPPINGS_FILE, "pay-type-mapping-write");
  await fs.writeFile(PAY_TYPE_MAPPINGS_FILE, `${JSON.stringify(mappings, null, 2)}\n`);
}

async function writePayTypeMapping(serviceType, payType) {
  if (!serviceType || !payType || !PAY_TYPES.includes(payType)) return;
  const mappings = await readPayTypeMappings();
  mappings[serviceType] = payType;
  await writePayTypeMappings(mappings);
}

async function readPaySettings() {
  const settings = await readJsonObject(PAY_SETTINGS_FILE, DEFAULT_PAY_SETTINGS);
  const commissionRate = Number(settings.commissionRate);
  const merged = {
    ...DEFAULT_PAY_SETTINGS,
    ...settings,
    commissionRate: Number.isFinite(commissionRate) && commissionRate >= 0 ? commissionRate : DEFAULT_PAY_SETTINGS.commissionRate
  };
  await fs.writeFile(PAY_SETTINGS_FILE, `${JSON.stringify(merged, null, 2)}\n`);
  return merged;
}

async function writePaySettings(settings) {
  await backupFile(PAY_SETTINGS_FILE, "pay-settings-write");
  await fs.writeFile(PAY_SETTINGS_FILE, `${JSON.stringify(settings, null, 2)}\n`);
}

async function readPayRules() {
  const rules = await readJsonObject(PAY_RULES_FILE, DEFAULT_PAY_RULES);
  const merged = { ...DEFAULT_PAY_RULES };

  for (const payType of PAY_TYPES) {
    const rule = rules[payType];
    if (rule && PAY_RULE_DEFINITIONS[rule.rule]) {
      merged[payType] = {
        label: String(rule.label || DEFAULT_PAY_RULES[payType]?.label || payType),
        rule: rule.rule
      };
    }
  }

  await fs.writeFile(PAY_RULES_FILE, `${JSON.stringify(merged, null, 2)}\n`);
  return merged;
}

async function listDatabases() {
  const entries = await fs.readdir(__dirname);
  const databases = [];

  for (const entry of entries) {
    if (
      !entry.endsWith(".json") ||
      entry.startsWith("unresolved-") ||
      entry === path.basename(PAY_TYPE_MAPPINGS_FILE) ||
      entry === path.basename(PAY_SETTINGS_FILE) ||
      entry === path.basename(PAY_RULES_FILE) ||
      entry === "package.json" ||
      entry === "package-lock.json"
    ) {
      continue;
    }

    try {
      const text = await fs.readFile(path.join(__dirname, entry), "utf8");
      if (Array.isArray(JSON.parse(text))) {
        databases.push(entry);
      }
    } catch (_error) {
      // Ignore JSON files that are not work stop databases.
    }
  }

  if (!databases.includes(DEFAULT_DATABASE)) {
    await writeDatabase(DEFAULT_DATABASE, [], { backup: false });
    databases.push(DEFAULT_DATABASE);
  }

  return databases.sort((a, b) => a.localeCompare(b));
}

function normalizeText(text) {
  return text
    .replace(/\r/g, "")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function matchValue(text, regex) {
  const match = text.match(regex);
  return match ? match[1].trim() : "";
}

function parseMoney(value) {
  if (!value) return null;
  const number = Number(value.replace(/[$,]/g, ""));
  return Number.isFinite(number) ? number : null;
}

function normalizeTime(value) {
  return value.replace(/\s*([AP]M)$/i, " $1").toUpperCase();
}

function timeToMinutes(value) {
  const match = normalizeTime(String(value || "").trim()).match(/^(\d{1,2}):(\d{2})\s*([AP]M)$/i);
  if (!match) return null;

  let hour = Number(match[1]);
  const minute = Number(match[2]);
  const marker = match[3].toUpperCase();

  if (!Number.isInteger(hour) || !Number.isInteger(minute)) return null;
  if (marker === "PM" && hour !== 12) hour += 12;
  if (marker === "AM" && hour === 12) hour = 0;

  return hour * 60 + minute;
}

function hasValidTimeRange(record) {
  const started = timeToMinutes(record.timeStarted);
  const completed = timeToMinutes(record.timeCompleted);
  return started !== null && completed !== null && completed > started;
}

function getMissingFields(record) {
  const missingFields = REQUIRED_FIELDS.filter((field) => {
    const value = record[field];
    if (field === "date") return !/^\d{4}-\d{2}-\d{2}$/.test(String(value || ""));
    if (field === "amount") return typeof value !== "number" || !Number.isFinite(value);
    if (field === "payType") return !PAY_TYPES.includes(value);
    return !String(value || "").trim();
  });

  if (
    !missingFields.includes("timeStarted") &&
    !missingFields.includes("timeCompleted") &&
    !hasValidTimeRange(record)
  ) {
    missingFields.push("timeCompleted");
  }

  return missingFields;
}

function withReviewState(record) {
  const missingFields = getMissingFields(record);
  return {
    ...record,
    status: missingFields.length ? "unresolved" : "complete",
    missingFields
  };
}

async function parseWorkStop(rawText, importDate) {
  const text = normalizeText(rawText);
  const lines = text.split("\n").map((line) => line.trim()).filter(Boolean);
  const locationIndex = lines.findIndex((line) => /^Location #/i.test(line));
  const servicesIndex = lines.findIndex((line) => /^SERVICES$/i.test(line));
  const serviceLine = servicesIndex >= 0 ? lines[servicesIndex + 1] || "" : "";
  const serviceMatch = serviceLine.match(/^(.*?)\s+\$?([\d,]+\.\d{2})\s*x\s*\d+/i);
  const serviceType = serviceMatch ? serviceMatch[1].trim() : "";
  const addressLines = locationIndex >= 0 ? lines.slice(locationIndex + 2, locationIndex + 4) : [];
  const payTypeMappings = await readPayTypeMappings();

  return withReviewState({
    id: crypto.randomUUID(),
    date: importDate,
    name: locationIndex >= 0 ? lines[locationIndex + 1] || "" : "",
    address: addressLines.join(", "),
    orderNumber: matchValue(text, /Order\s*#\s*(\d+)/i),
    locationNumber: matchValue(text, /Location\s*#\s*(\d+)/i),
    timeStarted: normalizeTime(matchValue(text, /Time Started\s+([0-9:]+\s*[AP]M)/i)),
    timeCompleted: normalizeTime(matchValue(text, /Time Completed\s+([0-9:]+\s*[AP]M)/i)),
    serviceType,
    payType: payTypeMappings[serviceType] || "",
    amount: parseMoney(serviceMatch ? serviceMatch[2] : matchValue(text, /Total:\s*\$?([\d,]+\.\d{2})/i)),
    rawText: text,
    importedAt: new Date().toISOString()
  });
}

function finalizedRecord(record) {
  const {
    status: _status,
    missingFields: _missingFields,
    unresolvedAt: _unresolvedAt,
    ...cleanRecord
  } = record;

  return {
    ...cleanRecord,
    amount: typeof cleanRecord.amount === "number" ? cleanRecord.amount : parseMoney(String(cleanRecord.amount || "")),
    ...(record.unresolvedAt ? { resolvedAt: new Date().toISOString() } : {})
  };
}

function duplicateKey(record) {
  return String(record.orderNumber || "").trim();
}

function duplicateNotice(record, reason) {
  return {
    orderNumber: record.orderNumber || "",
    name: record.name || "",
    serviceType: record.serviceType || "",
    date: record.date || "",
    reason
  };
}

function normalizeEditableRecord(record) {
  return withReviewState({
    ...record,
    amount: parseMoney(String(record.amount ?? ""))
  });
}

function recordsFromImportBatch(payload) {
  if (Array.isArray(payload)) return payload;
  if (payload && Array.isArray(payload.records)) return payload.records;
  if (payload && Array.isArray(payload.imported)) return payload.imported;
  return [];
}

function normalizeBatchRecord(record, fallbackDate) {
  const sourceRecord = record && typeof record === "object" ? record : {};
  const rawText = normalizeText(String(sourceRecord.rawText || ""));
  return withReviewState({
    id: sourceRecord.id || crypto.randomUUID(),
    date: /^\d{4}-\d{2}-\d{2}$/.test(String(sourceRecord.date || "")) ? sourceRecord.date : fallbackDate,
    name: String(sourceRecord.name || "").trim(),
    address: String(sourceRecord.address || "").trim(),
    orderNumber: String(sourceRecord.orderNumber || "").trim(),
    locationNumber: String(sourceRecord.locationNumber || "").trim(),
    timeStarted: normalizeTime(String(sourceRecord.timeStarted || "").trim()),
    timeCompleted: normalizeTime(String(sourceRecord.timeCompleted || "").trim()),
    serviceType: String(sourceRecord.serviceType || "").trim(),
    payType: String(sourceRecord.payType || "").trim(),
    amount: typeof sourceRecord.amount === "number" ? sourceRecord.amount : parseMoney(String(sourceRecord.amount || "")),
    rawText,
    importedAt: sourceRecord.importedAt || new Date().toISOString(),
    source: sourceRecord.source || "ios-batch"
  });
}

app.get("/api/databases", async (_request, response, next) => {
  try {
    response.json({
      defaultDatabase: DEFAULT_DATABASE,
      databases: await listDatabases()
    });
  } catch (error) {
    next(error);
  }
});

app.post("/api/databases", async (request, response, next) => {
  try {
    const database = cleanDatabaseName(request.body.name);
    if (await fileExists(getDatabaseFile(database))) {
      response.status(409).json({ error: `${database} already exists.` });
      return;
    }

    await writeDatabase(database, [], { backup: false });
    await writeUnresolved(database, [], { backup: false });
    response.json({
      database,
      databases: await listDatabases(),
      records: []
    });
  } catch (error) {
    next(error);
  }
});

app.delete("/api/databases", async (request, response, next) => {
  try {
    const database = cleanDatabaseName(request.body.database);

    if (database === DEFAULT_DATABASE) {
      response.status(400).json({ error: "The default database cannot be deleted." });
      return;
    }

    const dataFile = getDatabaseFile(database);
    const unresolvedFile = getUnresolvedFile(database);
    await backupFile(dataFile, "before-delete");
    await backupFile(unresolvedFile, "before-delete");

    await fs.rm(dataFile, { force: true });
    await fs.rm(unresolvedFile, { force: true });

    const databases = await listDatabases();
    const selectedDatabase = databases[0] || DEFAULT_DATABASE;
    response.json({
      database: selectedDatabase,
      databases,
      records: await readDatabase(selectedDatabase)
    });
  } catch (error) {
    next(error);
  }
});

app.get("/api/backups", async (request, response, next) => {
  try {
    response.json({ backups: await listBackups(request.query.database) });
  } catch (error) {
    next(error);
  }
});

app.post("/api/backups/restore", async (request, response, next) => {
  try {
    const database = cleanDatabaseName(request.body.database);
    const records = await restoreBackup(database, request.body.backup);
    response.json({
      database,
      backups: await listBackups(database),
      records
    });
  } catch (error) {
    next(error);
  }
});

app.get("/api/records", async (request, response, next) => {
  try {
    response.json(await readDatabase(request.query.database));
  } catch (error) {
    next(error);
  }
});

app.get("/api/records/:id", async (request, response, next) => {
  try {
    const records = await readDatabase(request.query.database);
    const record = records.find((entry) => entry.id === request.params.id);

    if (!record) {
      response.status(404).json({ error: "That entry was not found." });
      return;
    }

    response.json(record);
  } catch (error) {
    next(error);
  }
});

app.put("/api/records/:id", async (request, response, next) => {
  try {
    const database = request.body.database;
    const records = await readDatabase(database);
    const index = records.findIndex((entry) => entry.id === request.params.id);

    if (index === -1) {
      response.status(404).json({ error: "That entry was not found." });
      return;
    }

    const updated = normalizeEditableRecord({
      ...records[index],
      ...request.body.record,
      id: records[index].id,
      updatedAt: new Date().toISOString()
    });

    if (updated.missingFields.length) {
      response.status(400).json({
        error: "Fill in all required fields before saving this entry.",
        missingFields: updated.missingFields
      });
      return;
    }

    const duplicate = records.find((entry) => entry.id !== updated.id && duplicateKey(entry) === duplicateKey(updated));
    if (duplicateKey(updated) && duplicate) {
      response.status(400).json({ error: `Order #${updated.orderNumber} already exists in this save file.` });
      return;
    }

    await writePayTypeMapping(updated.serviceType, updated.payType);
    records[index] = finalizedRecord(updated);
    await writeDatabase(database, records);

    response.json({ record: records[index], records });
  } catch (error) {
    next(error);
  }
});

app.get("/api/pay-types", async (_request, response, next) => {
  try {
    response.json({
      payTypes: PAY_TYPES,
      mappings: await readPayTypeMappings(),
      settings: await readPaySettings(),
      rules: await readPayRules(),
      ruleDefinitions: PAY_RULE_DEFINITIONS
    });
  } catch (error) {
    next(error);
  }
});

app.put("/api/pay-settings", async (request, response, next) => {
  try {
    const commissionRate = Number(request.body.commissionRate);

    if (!Number.isFinite(commissionRate) || commissionRate < 0 || commissionRate > 1) {
      response.status(400).json({ error: "Commission rate must be between 0% and 100%." });
      return;
    }

    const settings = { commissionRate };
    await writePaySettings(settings);
    response.json({ settings });
  } catch (error) {
    next(error);
  }
});

app.put("/api/pay-types/mappings", async (request, response, next) => {
  try {
    const serviceType = String(request.body.serviceType || "").trim();
    const payType = String(request.body.payType || "").trim();

    if (!serviceType) {
      response.status(400).json({ error: "Service type is required." });
      return;
    }

    if (!PAY_TYPES.includes(payType)) {
      response.status(400).json({ error: "Choose a valid pay type." });
      return;
    }

    await writePayTypeMapping(serviceType, payType);
    response.json({
      payTypes: PAY_TYPES,
      mappings: await readPayTypeMappings(),
      settings: await readPaySettings(),
      rules: await readPayRules(),
      ruleDefinitions: PAY_RULE_DEFINITIONS
    });
  } catch (error) {
    next(error);
  }
});

app.delete("/api/pay-types/mappings", async (request, response, next) => {
  try {
    const serviceType = String(request.body.serviceType || "").trim();
    const mappings = await readPayTypeMappings();
    delete mappings[serviceType];
    await writePayTypeMappings(mappings);
    response.json({
      payTypes: PAY_TYPES,
      mappings,
      settings: await readPaySettings(),
      rules: await readPayRules(),
      ruleDefinitions: PAY_RULE_DEFINITIONS
    });
  } catch (error) {
    next(error);
  }
});

app.get("/api/unresolved", async (request, response, next) => {
  try {
    response.json(await readUnresolved(request.query.database));
  } catch (error) {
    next(error);
  }
});

app.get("/api/unresolved/count", async (request, response, next) => {
  try {
    const unresolved = await readUnresolved(request.query.database);
    response.json({ count: unresolved.length });
  } catch (error) {
    next(error);
  }
});

app.post("/api/unresolved/:id/resolve", async (request, response, next) => {
  try {
    const database = request.body.database;
    const unresolved = await readUnresolved(database);
    const index = unresolved.findIndex((record) => record.id === request.params.id);

    if (index === -1) {
      response.status(404).json({ error: "That unresolved entry was not found." });
      return;
    }

    const updated = withReviewState({
      ...unresolved[index],
      ...request.body.record,
      amount: parseMoney(String(request.body.record?.amount ?? unresolved[index].amount ?? ""))
    });

    if (updated.missingFields.length) {
      response.status(400).json({
        error: "Fill in the red fields before saving this entry.",
        missingFields: updated.missingFields
      });
      return;
    }

    const records = await readDatabase(database);
    const duplicate = records.find((entry) => duplicateKey(entry) === duplicateKey(updated));
    if (duplicateKey(updated) && duplicate) {
      response.status(400).json({ error: `Order #${updated.orderNumber} already exists in this save file.` });
      return;
    }

    await writePayTypeMapping(updated.serviceType, updated.payType);

    records.push(finalizedRecord(updated));
    unresolved.splice(index, 1);

    await writeDatabase(database, records);
    await writeUnresolved(database, unresolved);

    response.json({ records, unresolved, resolved: updated.id });
  } catch (error) {
    next(error);
  }
});

app.post("/api/unresolved/:id/skip", async (request, response, next) => {
  try {
    const database = request.body.database;
    const unresolved = await readUnresolved(database);
    const remaining = unresolved.filter((record) => record.id !== request.params.id);
    await writeUnresolved(database, remaining);
    response.json({ unresolved: remaining, skipped: request.params.id });
  } catch (error) {
    next(error);
  }
});

app.post("/api/import", upload.array("screenshots"), async (request, response, next) => {
  try {
    const importDate = request.body.date;
    const database = request.body.database;
    const files = request.files || [];

    if (!/^\d{4}-\d{2}-\d{2}$/.test(importDate || "")) {
      response.status(400).json({ error: "Choose a valid import date." });
      return;
    }

    if (!files.length) {
      response.status(400).json({ error: "Choose one or more JPG or PNG screenshots." });
      return;
    }

    const unsupportedFiles = files.filter((file) => !SUPPORTED_IMAGE_TYPES.has(file.mimetype));
    if (unsupportedFiles.length) {
      response.status(400).json({ error: "Only JPG and PNG screenshots can be imported." });
      return;
    }

    const records = await readDatabase(database);
    const unresolved = await readUnresolved(database);
    const seenOrderNumbers = new Set([
      ...records.map(duplicateKey).filter(Boolean),
      ...unresolved.map(duplicateKey).filter(Boolean)
    ]);

    const worker = await getWorker();
    const imported = [];
    const unresolvedImports = [];
    const duplicates = [];

    for (const file of files) {
      const result = await worker.recognize(file.buffer);
      const parsed = {
        ...(await parseWorkStop(result.data.text, importDate)),
        date: importDate
      };
      const orderNumber = duplicateKey(parsed);

      if (orderNumber && seenOrderNumbers.has(orderNumber)) {
        duplicates.push(duplicateNotice(parsed, "Duplicate order number"));
        continue;
      }

      if (orderNumber) {
        seenOrderNumbers.add(orderNumber);
      }

      if (parsed.missingFields.length) {
        unresolvedImports.push({
          ...parsed,
          unresolvedAt: new Date().toISOString()
        });
      } else {
        imported.push(finalizedRecord(parsed));
      }
    }

    records.push(...imported);
    await writeDatabase(database, records);

    unresolved.push(...unresolvedImports);
    await writeUnresolved(database, unresolved);

    response.json({
      imported,
      unresolved: unresolvedImports,
      duplicates,
      unresolvedCount: unresolved.length,
      records
    });
  } catch (error) {
    next(error);
  }
});

app.post("/api/import-batch", upload.single("batch"), async (request, response, next) => {
  try {
    const importDate = request.body.date;
    const database = request.body.database;
    const file = request.file;

    if (!/^\d{4}-\d{2}-\d{2}$/.test(importDate || "")) {
      response.status(400).json({ error: "Choose a valid import date." });
      return;
    }

    if (!file) {
      response.status(400).json({ error: "Choose an import-batch JSON file." });
      return;
    }

    if (!SUPPORTED_BATCH_TYPES.has(file.mimetype) && !file.originalname.toLowerCase().endsWith(".json")) {
      response.status(400).json({ error: "Only JSON import-batch files can be imported." });
      return;
    }

    let payload;
    try {
      payload = JSON.parse(file.buffer.toString("utf8"));
    } catch (_error) {
      response.status(400).json({ error: "That import-batch file is not valid JSON." });
      return;
    }

    const batchRecords = recordsFromImportBatch(payload).map((record) => normalizeBatchRecord(record, importDate));
    if (!batchRecords.length) {
      response.status(400).json({ error: "That import-batch file does not contain any records." });
      return;
    }

    const records = await readDatabase(database);
    const unresolved = await readUnresolved(database);
    const seenOrderNumbers = new Set([
      ...records.map(duplicateKey).filter(Boolean),
      ...unresolved.map(duplicateKey).filter(Boolean)
    ]);

    const imported = [];
    const unresolvedImports = [];
    const duplicates = [];

    for (const parsed of batchRecords) {
      const orderNumber = duplicateKey(parsed);

      if (orderNumber && seenOrderNumbers.has(orderNumber)) {
        duplicates.push(duplicateNotice(parsed, "Duplicate order number"));
        continue;
      }

      if (orderNumber) {
        seenOrderNumbers.add(orderNumber);
      }

      if (parsed.missingFields.length) {
        unresolvedImports.push({
          ...parsed,
          unresolvedAt: new Date().toISOString()
        });
      } else {
        imported.push(finalizedRecord(parsed));
      }
    }

    records.push(...imported);
    await writeDatabase(database, records);

    unresolved.push(...unresolvedImports);
    await writeUnresolved(database, unresolved);

    response.json({
      imported,
      unresolved: unresolvedImports,
      duplicates,
      unresolvedCount: unresolved.length,
      records
    });
  } catch (error) {
    next(error);
  }
});

app.use((error, _request, response, _next) => {
  console.error(error);
  response.status(error.status || 500).json({ error: error.message || "Request failed. Check the terminal for details." });
});

app.listen(PORT, HOST, () => {
  console.log(`Tech Pay importer running at http://localhost:${PORT}`);
  console.log(`Default database: ${getDatabaseFile(DEFAULT_DATABASE)}`);
});
