# Proposal: Build a Configurable CKEditor-Compatible Flutter Plugin for LIMS

## Problem Statement

The `lims` Flutter application currently depends on `flutter_quill`, but it does not have an owned editor plugin with a stable public API, CKEditor-style feature plugins, configurable toolbar/theme, or a clear integration boundary. The requested editor includes the complete free and premium CKEditor feature set plus self-hosted video upload/playback. This is a package/platform effort rather than a single widget change and requires explicit provider contracts for storage, AI, collaboration, and document conversion.

## Proposed Solution

Create a private `flutter_rich_editor` package in this repository and integrate it into `lims` through a path dependency. Build on `super_editor` after a Phase 0 compatibility spike, with a CKEditor-inspired plugin registry and command bus. Each feature plugin owns its document nodes/attributes, commands, toolbar/menu contributions, keyboard shortcuts, and serializers. Expose a strongly typed `RichEditorController`, HTML/Markdown/JSON codecs, upload/provider interfaces, and a complete `EditorTheme` so every editor surface color and style is configurable. Keep collaboration, AI, conversion, and file-management integrations provider-agnostic and optional.

The implementation is phased behind a compatibility matrix: the foundation must be validated before feature work, and no feature is considered complete until its document model, command behavior, rendering, serialization, accessibility behavior, and tests are covered.

## Scope

- IN SCOPE: private package structure and public exports; `super_editor` foundation; plugin registry and command bus; formatting, structure, media, tables, links, embeds, code/Mermaid, paste, HTML/Markdown/JSON I/O; native image/video upload, hosting references, playback, thumbnails, resizing and progress; configurable toolbar/menu/theme; RTL/i18n/accessibility/watchdog; comments/review hooks; optional real-time collaboration, track changes, AI, PDF/Word, advanced document/table/list/file-management/productivity features; LIMS path integration and example showcase.
- OUT OF SCOPE: implementation of a CKEditor JavaScript runtime or browser wrapper; hard-coded backend/storage/LLM/collaboration vendor; shipping a collaboration server, AI model, DOCX conversion service, or file-management backend; claiming adaptive streaming until the provider contract is approved; publishing the private package to pub.dev.

## Affected Files

- `pubspec.yaml` — add the local editor package dependency and remove/retire direct editor dependencies once migration is complete; preserve existing LIMS dependencies and dependency overrides unless compatibility validation requires a documented change.
- `flutter_rich_editor/pubspec.yaml` — new private package manifest with the pinned editor foundation and optional feature dependencies.
- `flutter_rich_editor/lib/` — new core, feature, serialization, theme, toolbar, and widget implementation.
- `flutter_rich_editor/example/` — new feature showcase and integration reference for the LIMS team.
- `flutter_rich_editor/test/` — new unit, widget, golden, codec, provider-contract, and integration tests.
- `flutter_rich_editor/README.md` — installation, configuration, public API, provider contracts, feature matrix, and platform setup.
- `flutter_rich_editor/CHANGELOG.md` — private package release notes and compatibility changes.

## Risk Assessment

- `super_editor` API churn: pin the validated version, isolate it behind adapter classes, and keep the Phase 0 spike as a release gate.
- Tables, nested lists, merged cells, and pagination are high-complexity: implement them as isolated node/command modules with golden and round-trip tests before enabling them in presets.
- Video and file uploads depend on host infrastructure: require an injected upload adapter, cancellation/progress/error states, MIME/size validation, and never embed credentials in the package.
- Real-time collaboration and track changes require conflict-safe backend protocols: ship provider interfaces and local review behavior first; do not imply offline conflict resolution without a selected CRDT/OT design.
- AI, DOCX, PDF, Mermaid, and HTML embeds introduce platform/security risks: use injected providers, sanitize untrusted HTML/Mermaid input, isolate raw embeds, and gate unsupported platforms explicitly.
- Theme/configuration drift can make the package unusable in LIMS: make all visual tokens immutable and overridable at the root, then verify every built-in surface consumes tokens rather than literals.
