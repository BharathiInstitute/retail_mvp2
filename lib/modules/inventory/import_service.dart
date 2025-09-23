// Placeholder legacy import service removed.

class ImportProgress {
  final int total;
  final int processed;
  final int added;
  final int updated;
  final int errors;
  final String? message;
  const ImportProgress({
    required this.total,
    required this.processed,
    required this.added,
    required this.updated,
    required this.errors,
    this.message,
  });
}

class ImportResult {
  final int added;
  final int updated;
  final int errors;
  final List<String> errorMessages;
  const ImportResult({
    required this.added,
    required this.updated,
    required this.errors,
    required this.errorMessages,
  });
}

// Legacy import service removed. Kept as a minimal placeholder.
// Do not import this file in new code.

class LegacyImportServicePlaceholder {
  const LegacyImportServicePlaceholder();
}
// End placeholder
