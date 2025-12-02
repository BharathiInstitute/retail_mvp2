// ignore_for_file: avoid_web_libraries_in_flutter
/// Web-specific URL launcher using dart:html
library;

import 'dart:html' as html;

/// Opens a URL in a new browser tab (web only)
void launchUrlInNewTab(String url) {
  html.window.open(url, '_blank');
}
