# Tech Pay Dashboard

Tech Pay Dashboard is a local web app for importing work-stop screenshots, extracting the job details with OCR, storing them in JSON save files, and calculating production/pay summaries.

The app is built with JavaScript, Express, and Tesseract OCR. It runs locally in your browser and stores data in JSON files inside this project folder.

## Quick Start

Install dependencies:

```bash
npm install
```

Start the server:

```bash
npm start
```

Open the app:

```text
http://localhost:3000/
```

Stop the server with `Ctrl + C` in Terminal.

## Main Workflow

1. Open the dashboard.
2. Confirm the active save file in the status pill.
3. Choose the work day.
4. Click `Import / Manage`.
5. Select JPG or PNG screenshots.
6. Click `Import`.
7. Review the import summary and resolve any unresolved entries.

The dashboard shows:

- Month-to-date production
- Month-to-date stops
- Month-to-date pay
- Month-to-date hourly
- Selected-day production
- Selected-day stops
- Hours worked
- Selected-day pay
- Selected-day hourly
- Last import summary
- Unresolved entry count

Click the `MTD Pay` card to show or hide the pay-type breakdown.

## Screenshot Import

Supported screenshot formats:

- JPG / JPEG
- PNG
- Tech Pay iPhone import-batch JSON

The importer extracts:

- Date
- Name
- Physical address
- Order number
- Time started
- Time completed
- Service type
- Pay type
- Amount

If required information is missing, the entry goes into unresolved review instead of being saved directly into the main database.

## iPhone Companion App

The `TechPayCompanion/` folder contains SwiftUI source for an iPhone companion app. It selects screenshots from Photos, runs on-device Vision OCR, extracts the same work-stop fields, lets you review/edit records, and exports a `tech-pay.import-batch.v1` JSON file.

Save the exported JSON file to iCloud Drive. Later, open the web import module and choose it from the `iPhone batch` picker.

## Unresolved Entries

Unresolved entries are kept separately from completed database records.

From the unresolved panel, you can:

- Fill missing fields and save the entry
- Keep the entry for later
- Skip import and remove it from unresolved

The dashboard keeps a persistent unresolved badge so unresolved work is hard to miss.

## Save Files

Save files are JSON databases stored in the project folder.

Use `Save Files` to:

- Switch the active save file
- Create test save files
- Restore backups
- Delete test save files

The default save file is:

```text
work-stops.json
```

Each save file has a matching unresolved file:

```text
unresolved-work-stops.json
```

## Backups

The app creates backups before important write operations, including database edits, unresolved edits, deletes, restores, pay mapping changes, and pay settings changes.

Backups are stored in:

```text
backups/
```

## Pay Settings

Pay settings live in:

```text
pay-settings.json
```

Current setting:

```json
{
  "commissionRate": 0.17
}
```

The commission rate can be edited in the `Pay Type Settings` panel.

## Pay Rules

Pay rules live in:

```text
pay-rules.json
```

Current rules:

| Pay Type | Rule |
| --- | --- |
| Prod | Amount x commission rate |
| PM | Amount x commission rate |
| MSC | Amount x commission rate |
| MSS | Amount x commission rate |
| IS INI | Amount x commission rate x 1.5 |
| PS INI | Amount x commission rate x 1.5 |
| SENTRICON | Amount x 8% |
| SEN INI | Flat $45 |
| TI | Flat $10 |
| ISR | No pay |
| MISC NOPAY | No pay |

The dashboard calculates pay from the structured rule definitions returned by the server, so the displayed equations and pay totals stay aligned.

## Service-To-Pay-Type Mappings

Service names from screenshots are mapped to pay types in:

```text
pay-type-mappings.json
```

Example:

```json
{
  "Taexx Pest Control Service": "Prod"
}
```

If an imported service type is unknown, the entry goes unresolved until a pay type is selected. Saving the entry also remembers that service-to-pay-type mapping for future imports.

## Duplicate Protection

The app checks duplicate work orders by order number.

Duplicate protection happens during:

- Import
- Saved-entry editing
- Resolving unresolved entries

If a duplicate order number is found, the app rejects the newer duplicate so pay and production totals are not inflated.

## Project Structure

```text
server.js                    Express API and OCR pipeline
public/index.html            Dashboard
public/dashboard.js          Dashboard logic and pay summaries
public/import.html           Import module
public/app.js                Import module logic
public/resolve.html          Unresolved review panel
public/resolve.js            Unresolved review logic
public/edit.html             Single-entry edit panel
public/edit.js               Single-entry edit logic
public/database-controls.*   Save file controls
public/database-editor.*     Filtered database editor
public/pay-settings.*        Pay settings and service mappings
public/styles.css            Shared app styling
pay-settings.json            Base commission setting
pay-rules.json               Pay type rule mapping
pay-type-mappings.json       Service type to pay type mapping
work-stops.json              Default completed-entry database
unresolved-work-stops.json   Default unresolved-entry database
backups/                     Automatic JSON backups
```

## Useful Commands

Start the app:

```bash
npm start
```

Run OCR test:

```bash
npm run test:ocr
```

Check JavaScript syntax manually:

```bash
node --check server.js
node --check public/dashboard.js
node --check public/app.js
```

## Current Notes

- The app is local-first and JSON-backed.
- Pay totals are only as accurate as the selected pay type and pay rule.
- OCR is expected to occasionally miss fields; unresolved review is part of the normal workflow.
- Full iPhone screenshots should work as PNG, but cropped screenshots may still OCR more cleanly.
