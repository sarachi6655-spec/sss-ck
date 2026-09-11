# Specification: Build a Configurable CKEditor-Compatible Flutter Plugin for LIMS

## Changes Required

### `flutter_rich_editor/pubspec.yaml`
- Create a private Flutter package with SDK constraint compatible with the application (`>=3.4.0 <4.0.0`) and `publish_to: none`.
- Pin the validated `super_editor` version after the Phase 0 spike. Do not add it to `lims` directly; the package is the dependency boundary.
- Add only feature dependencies that are actually implemented. Required candidates are `html`, Markdown support, `video_player`, `flutter_highlight`, `pdf`, and `intl`; optional integrations such as thumbnails, DOCX, math, WebView, or collaboration transport must be isolated behind optional packages/adapters rather than making every host app pay for them.

### `flutter_rich_editor/lib/flutter_rich_editor.dart`
- Export only stable public contracts: `RichEditor`, `RichEditorController`, `EditorConfig`, `EditorTheme`, `ToolbarConfig`, `Plugin`, `PluginRegistry`, commands, document value types, codecs, upload/provider interfaces, and error types.
- Do not expose `super_editor` types as the primary public API; provide conversion/adaptation at the boundary so foundation upgrades do not break LIMS callers.

### `flutter_rich_editor/lib/src/core/plugin_system/` and `flutter_rich_editor/lib/src/core/command_bus/`
- Define `EditorPlugin` with registration hooks for document node/attribute handlers, commands, toolbar/menu items, shortcuts, serializers, and lifecycle disposal.
- Define `PluginRegistry` with deterministic registration order, duplicate command/node-key rejection, enabled-feature lookup, and disposal.
- Define typed `EditorCommand`, command execution results, selection/document context, undo/redo grouping, and failure propagation. Commands must be the only mutation path used by toolbar actions, keyboard shortcuts, paste handlers, providers, and programmatic API calls.
- Define plugin presets (`basic`, `media`, `full`, and caller-supplied list) without silently enabling network, AI, collaboration, or raw HTML capabilities.

### `flutter_rich_editor/lib/src/core/controller/` and `document_model/`
- Implement `RichEditorController` for initial content, current document value, selection, focus, read-only state, execute/undo/redo/select-all, import/export, and change notifications.
- Use a versioned canonical JSON document tree for persistence. Include node type, stable node id, attributes, inline marks, and child/content data; unknown nodes must round-trip as preserved extension nodes or produce a typed unsupported-content error.
- Provide adapters around the foundation document and selection types; never store mutable widget state in codec/provider objects.
- Expose lifecycle-safe `dispose`, rejection of commands after disposal, and an error callback/event stream that preserves the last valid document.

### `flutter_rich_editor/lib/src/theme/`, `toolbar/`, and `widgets/`
- Implement immutable `EditorTheme` tokens covering editor background/foreground, surface, border, divider, focus, selection, cursor, placeholder, disabled/read-only, toolbar/menu, icon, tooltip, dropdown, dialog, link, code block, quote, table, image, video, upload progress/error, comment/suggestion, and validation states. Include typography, spacing, radii, elevations, icon theme, and density.
- Support `EditorTheme.merge`/copy-with overrides and an optional host `ThemeData` bridge; no built-in editor surface may use a hard-coded color, text style, spacing, or radius when a token exists.
- Build configurable toolbar/menu models with ordered groups, separators, overflow behavior, enabled/visible predicates, custom actions, localization labels, and responsive layout. The full preset must expose every implemented feature without making toolbar placement mandatory.
- Implement `RichEditor`, read-only rendering, placeholder/title, fullscreen wrapper, focus/keyboard handling, directionality/RTL, accessibility semantics, and watchdog fallback that displays a recoverable error while retaining the last valid serialized content.

### `flutter_rich_editor/lib/src/features/formatting/`
- Implement bold, italic, underline, strikethrough, subscript, superscript, inline code, font family/size, text color, background/highlight, remove formatting, line height, alignment, indentation, and predefined styles as attributes/commands.
- Ensure collapsed-selection typing uses pending marks and expanded-selection changes are undoable transactions. Unsupported font/color values must be validated before mutation.

### `flutter_rich_editor/lib/src/features/structure/`
- Implement headings, block quote, horizontal rule, ordered/unordered lists, nested/multi-level lists, to-do lists, list editing behavior, start index/reversed/custom marker properties, document title, block visibility/debug mode, page breaks, bookmarks, outline/TOC, merge fields, templates, slash commands, case change, and format painter.
- Keep list structure valid when indenting, outdenting, splitting, merging, deleting, or pasting blocks. Define stable node schemas and converters for each node.

### `flutter_rich_editor/lib/src/features/media/`
- Implement links, mentions, emoji, images, external media embeds, tables, and captions/alt text/responsive sizing. Table nodes must support captions, scrolling, cell selection, insert/delete rows/columns, merged cells, styling presets, resizing, and borderless layout mode.
- Define `UploadAdapter` with MIME validation, byte/file input, progress, cancellation, retry, result metadata, and typed errors. Image and video adapters must be separate capability wrappers even if they share a base contract.
- Implement `VideoNode` and renderer using `video_player`, custom themed controls, poster/thumbnail support, buffering/error states, direct-file playback, inline resizing, and upload progress. Adaptive HLS/DASH is not enabled until a provider contract and platform matrix are approved.
- Sanitize external URLs, define allowed embed providers, and render untrusted HTML/iframe content only through an explicit opt-in isolated renderer.

### `flutter_rich_editor/lib/src/features/code/`
- Implement code blocks with language metadata, copy action, syntax highlighting through the configured highlighter, and Mermaid diagrams through a sanitized/isolated renderer or an injected renderer. Unsupported languages/rendering failures must fall back to editable code text with a typed warning.

### `flutter_rich_editor/lib/src/serialization/` and `features/html_markdown/`
- Implement canonical JSON codec plus HTML import/export, GitHub-flavored Markdown export/import, Delta interoperability where needed for migration from current `flutter_quill`, HTML comments, general custom tag/attribute preservation, source-code view/edit, and email-safe inline-style export.
- Define explicit conversion behavior for every supported node/mark, unknown tags/attributes, malformed input, comments, links, media, tables, code, and unsafe HTML. Round-trip canonical JSON must be the fidelity reference; HTML/Markdown are lossless only for supported constructs.

### `flutter_rich_editor/lib/src/features/paste/`
- Implement plain-text paste, Markdown paste, HTML paste sanitization, Word/Google Docs cleanup, image/file paste routing, and undoable insertion. Preserve text content while dropping unsupported or unsafe formatting with diagnostics.

### `flutter_rich_editor/lib/src/features/collaboration_basic/` and optional modules
- Implement comments-only/reviewer mode, pluggable users, comment anchors/threads/resolution, and permission-driven read-only behavior without requiring a server.
- Define optional collaboration contracts for transport, CRDT/OT document operations, presence/cursors, track changes (suggest/accept/reject), revision history, compare/restore, and roles. The package must not select a backend or claim conflict resolution until one is approved.
- Define provider-agnostic AI contracts for chat/history/context, quick actions, MCP/tool calls, and trackable suggestions. API keys and network calls remain in the host app.
- Define export/import contracts for PDF, DOCX, pagination, and HTML; use the existing LIMS `pdf`/`printing` dependencies only through a package adapter and do not silently promise DOCX fidelity without an implemented converter.

### `flutter_rich_editor/lib/src/features/accessibility_ui/`
- Provide keyboard shortcut help, RTL, localized strings via injectable `EditorLocalizations`, semantic labels/actions, focus traversal, text scaling, minimap, restricted regions, word/character count, find/replace, special characters, spell/grammar provider hooks, and watchdog diagnostics.
- Ensure toolbar buttons, dropdowns, media controls, table actions, comments, dialogs, and source editing are keyboard and screen-reader reachable.

### `flutter_rich_editor/example/`
- Add a showcase app that demonstrates basic/full presets, custom `EditorTheme`, every toolbar group, HTML/Markdown/JSON load/save, image/video provider states, table/list editing, read-only/reviewer mode, source view, RTL/localization, error fallback, and host-provider injection.

### `pubspec.yaml`
- Add `flutter_rich_editor` as a local path dependency after the package builds. Migrate the LIMS editor integration to the package public API; retain `flutter_quill` only while the migration adapter is active, then remove it and direct editor conversion dependencies when no call site remains.
- Do not alter unrelated dependencies or existing `intl` overrides without a solver-validated reason documented in the changelog.

### `flutter_rich_editor/README.md` and `CHANGELOG.md`
- Document package setup, path dependency, platform requirements, provider contracts, theme token override examples, feature/preset matrix, serialization guarantees, security constraints, migration from `flutter_quill`, and unsupported optional backends.
- Record each phase, foundation version, breaking public API change, and known platform limitation.

## New Files (if any)

- Entire `flutter_rich_editor/` package as listed above, including `lib/src/**`, `example/**`, `test/**`, `README.md`, `CHANGELOG.md`, `pubspec.yaml`, analysis/lint configuration, and platform integration files required by `video_player` or optional renderers.
- No backend/server files are required by this story; provider interfaces must be sufficient for the existing LIMS application to supply its own services.

## Test Requirements

Test names below are contracts for the later test-generation phase.

- `test_pluginRegistry_rejectsDuplicateCommandIds`; `test_pluginRegistry_registersAndDisposesPluginsInOrder`.
- `test_commandBus_executesUndoableCommandAndRestoresPreviousDocument`; `test_controller_rejectsCommandsAfterDispose`; `test_watchdog_preservesLastValidDocumentWhenPluginFails`.
- `test_jsonCodec_roundTripsAllSupportedNodesAndAttributes`; `test_htmlCodec_preservesSupportedStructureAndComments`; `test_markdownCodec_roundTripsSupportedGitHubMarkdown`; `test_deltaMigration_preservesExistingQuillContent`.
- `test_themeOverride_appliesToEveryEditorSurface`; `test_toolbarConfig_hidesAndReordersCommandsWithoutChangingCommandBehavior`; `test_editorConfig_rendersReadOnlyAndPlaceholderStates`.
- `test_formattingCommand_appliesCollapsedSelectionPendingMark`; `test_formattingCommand_removesExpandedSelectionMark`; `test_structureCommand_keepsNestedListValidAfterIndentAndOutdent`.
- `test_tableCommands_supportRowsColumnsMergedCellsAndResize`; `test_pasteHandler_sanitizesUnsafeHtmlAndCreatesUndoableInsertion`.
- `test_uploadAdapter_reportsProgressSupportsCancellationAndReturnsTypedFailure`; `test_videoNode_rendersPosterBufferingPlaybackAndErrorStates`; `test_mediaPolicy_rejectsDisallowedEmbedUrl`.
- `test_codeBlock_highlightsConfiguredLanguageAndFallsBackToEditableText`; `test_mermaidRenderer_rejectsUnsafeInput`.
- `test_reviewerMode_allowsCommentsAndRejectsDocumentMutation`; `test_trackChangesProvider_mapsSuggestionToAcceptRejectCommands`; `test_collaborationTransport_reconcilesProviderOperationsWithoutLocalDataLoss`.
- `test_aiProvider_returnsTrackableSuggestionWithoutEmbeddingCredentials`; `test_pdfExport_usesConfiguredAdapter`; `test_docxImportReportsUnsupportedConstructs`.
- `test_accessibility_exposesToolbarMediaAndTableSemantics`; `test_rtlLayout_reversesDirectionWithoutChangingDocumentOrder`; `test_localizations_replaceAllVisibleEditorLabels`.
- Widget/golden tests must cover toolbar, menus, dialogs, tables, images, videos, comments, source view, fullscreen, light/dark/custom themes, read-only mode, narrow width, text scaling, RTL, and error fallback.
- Integration tests must build the `lims` host with the path package, load/save a document, execute representative commands, and verify no direct `flutter_quill` import remains after migration.

## Acceptance Criteria Mapping

| Acceptance Criteria | Implementation | Test |
|---|---|---|
| LIMS can integrate an owned private Flutter editor package | `flutter_rich_editor` path package, public barrel export, host integration in `pubspec.yaml` and editor call sites | `test_limsPathDependency_buildsAndLoadsRichEditor` |
| CKEditor-style plugin architecture is extensible | `EditorPlugin`, `PluginRegistry`, typed command bus, presets, registration validation | `test_pluginRegistry_registersAndDisposesPluginsInOrder` |
| Formatting, structure, media, tables, code, paste, and serialization work without hidden coupling | Feature modules with nodes, commands, renderers, and codecs | Feature tests listed above plus codec round trips |
| Images and self-hosted videos support real host services | `UploadAdapter`, `VideoNode`, progress/cancel/error contracts, `video_player` renderer, poster/thumbnail hooks | upload/video tests listed above |
| All editor styles and colors are dynamically configurable | `EditorTheme` token coverage, merge/copy-with, token-only surface rendering | `test_themeOverride_appliesToEveryEditorSurface` and goldens |
| Host app can use read-only/reviewer, RTL, localization, accessibility, fullscreen, source, and watchdog modes | `EditorConfig`, accessibility UI module, comments/reviewer and watchdog contracts | corresponding accessibility/reviewer/watchdog tests |
| Optional premium capabilities do not hard-code vendors or require unavailable services | injected AI, collaboration, conversion, file-manager, and spell/grammar providers | provider contract tests and missing-provider failure tests |
| Existing Quill content can migrate and no editor dependency is silently duplicated | Delta adapters and staged `pubspec.yaml` migration | `test_deltaMigration_preservesExistingQuillContent`, host integration test |
| Delivery is production-ready and documented | example showcase, README, changelog, pinned dependencies, security/platform matrix | build, analyze, unit/widget/golden/integration test suite |
