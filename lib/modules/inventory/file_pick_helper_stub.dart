class PickedFile {
  final String name;
  final List<int> bytes;
  PickedFile(this.name, this.bytes);
}

// Non-web stub returns null. On web, the conditional import provides a real implementation.
Future<PickedFile?> pickSingleFile({String accept = '*/*'}) async {
  return null;
}
