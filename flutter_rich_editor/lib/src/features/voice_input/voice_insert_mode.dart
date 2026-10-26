/// Controls how the HTML returned by the voice API is inserted into the editor.
enum VoiceInsertMode {
  /// Clears all existing content and replaces the entire document with the
  /// API response HTML.
  ///
  /// Use when: the user wants a fresh document generated entirely by voice.
  replace,

  /// Keeps the existing document content and appends the API response HTML
  /// at the very end of the document.
  ///
  /// Use when: the user wants to add new sections to an existing document.
  append,

  /// Inserts the API response HTML immediately after the node where the
  /// cursor is currently positioned, pushing subsequent nodes down.
  ///
  /// Use when: the user places their cursor at a specific spot and speaks
  /// to insert content precisely there (the most natural UX for mid-document
  /// editing).
  insertAtCursor,
}
