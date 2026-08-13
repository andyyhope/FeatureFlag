# ``FeatureFlagUI``

A companion app's editor, rendered entirely from a schema the host app published.

## Overview

This module is for a **companion app**. A host app should never link it: the views render
from a published ``FeatureFlag/FlagSchema`` and never see the host's concrete flag types.

That is the whole point. One companion build can edit any app that publishes a schema,
and your shipping app carries no editor UI at all.

```swift
import FeatureFlagUI
import SwiftUI

@main
struct CompanionApp: App {

    private let store = try? FlagEditingStore(appGroup: "group.com.example.flags")

    var body: some Scene {
        WindowGroup {
            if let store {
                FlagOverridesView(store: store)
            } else {
                Text("Run the host app once so it can publish its schema.")
            }
        }
    }
}
```

### Platforms

iOS and macOS only. watchOS has no `Menu`, `TextEditor` or bordered text field, and tvOS
has no text entry worth the name; a flag editor on either is not a real use case, so this
module compiles to nothing there rather than pretending. The core `FeatureFlag` module
supports all four platforms.

### The two screens

``FlagOverridesView`` answers *what have I changed?* — the question you actually have
before filing a bug or handing a device to someone else. It is also where overrides leave
the device: as JSON, as a property list, or as a QR code.

``FlagBrowserView`` answers *what can I change?* — the whole tree, with groups walked one
screen at a time and a search that flattens everything.

Both take the same ``FlagEditingStore``, so a tab view with one of each shares state for
free. See [Building a companion app](doc:BuildingACompanionApp).

## Topics

### Essentials

- <doc:BuildingACompanionApp>
- ``FlagEditingStore``

### Screens

- ``FlagOverridesView``
- ``FlagBrowserView``
- ``FlagGroupView``
- ``FlagRowView``
- ``FlagQRCodeView``
- ``FlagImportView``

### Structure

- ``FlagTreeNode``
- ``FlagSection``

### Choosing a control

- ``FlagEditorKind``
