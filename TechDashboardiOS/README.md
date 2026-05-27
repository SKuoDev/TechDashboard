# TechDashboardiOS

Native SwiftUI port of the Tech Pay dashboard. This project is intentionally separate from the web dashboard at the workspace root and the existing `TechPayCompanion` app.

## Shared iCloud Drive data

Choose the iCloud Drive folder that contains the same JSON files used by the web app:

- `work-stops.json`
- `unresolved-work-stops.json`
- `pay-settings.json`
- `pay-rules.json`
- `pay-type-mappings.json`

Additional save files keep the same pattern as the web app, for example `test.json` and `unresolved-test.json`.

## Current app features

- iCloud Drive folder selection with saved access
- dashboard totals matching the web app calculations
- month-to-date pay breakdown by pay type
- day entry list with edit support
- save-file creation, switching, and deletion
- JSON import-batch intake from the companion app export format
- unresolved entry review, resolve, and skip
- commission rate and service-to-pay-type mapping management

Open `TechDashboardiOS.xcodeproj` in Xcode and run the `TechDashboardiOS` target on iPhone or simulator.
