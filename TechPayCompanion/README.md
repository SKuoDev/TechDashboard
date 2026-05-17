# Tech Pay Companion

SwiftUI iPhone companion source for creating Tech Pay import-batch JSON files.

## Setup

1. Open `TechPayCompanion.xcodeproj` in Xcode.
2. Select the `TechPayCompanion` scheme in the top toolbar.
3. Select an iPhone simulator or connected iPhone.
4. Press the play button.

If you create a fresh Xcode project instead, set the minimum iOS version to iOS 17, add the Swift files in `TechPayCompanion/` to the app target, and add this privacy key to `Info.plist`:

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Select work-stop screenshots so Tech Pay can extract import records.</string>
```

The app uses Apple's on-device Vision OCR. Exported files are named like:

```text
tech-pay-import-2026-05-16-143012.json
```

Save the exported JSON to iCloud Drive, then import it in the web app from the `iPhone batch` picker.

## Batch Format

The web app accepts either a plain array of records or this envelope:

```json
{
  "schema": "tech-pay.import-batch.v1",
  "createdAt": "2026-05-16T18:30:12Z",
  "source": "TechPayCompanion-iOS",
  "records": []
}
```

Each record uses the same fields as the web database: `date`, `name`, `address`, `orderNumber`, `locationNumber`, `timeStarted`, `timeCompleted`, `serviceType`, `payType`, `amount`, `rawText`, and `importedAt`.
