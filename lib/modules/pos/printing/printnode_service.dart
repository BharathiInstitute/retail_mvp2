// PrintNode Cloud Printing Service
// Enables one-click silent printing from any device
// 
// Setup:
// 1. Create account at https://www.printnode.com
// 2. Install PrintNode Client on one computer per store location
// 3. Get API key from PrintNode dashboard
// 4. Configure in app: Admin > Printer Settings
//
// Usage:
//   final service = PrintNodeService(apiKey: 'your-api-key');
//   final printers = await service.getPrinters();
//   await service.printReceipt(printerId: 12345, content: 'Hello');

import 'dart:convert';
import 'package:http/http.dart' as http;

/// PrintNode API response for a printer
class PrintNodePrinter {
  final int id;
  final String name;
  final String description;
  final String state; // online, offline, etc.
  final int? computerId;
  final String? computerName;
  final bool isDefault;

  const PrintNodePrinter({
    required this.id,
    required this.name,
    required this.description,
    required this.state,
    this.computerId,
    this.computerName,
    this.isDefault = false,
  });

  factory PrintNodePrinter.fromJson(Map<String, dynamic> json) {
    final computer = json['computer'] as Map<String, dynamic>?;
    final caps = json['capabilities'] as Map<String, dynamic>?;
    return PrintNodePrinter(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Unknown',
      description: json['description'] as String? ?? '',
      state: json['state'] as String? ?? 'unknown',
      computerId: computer?['id'] as int?,
      computerName: computer?['name'] as String?,
      isDefault: caps?['default'] == true,
    );
  }

  bool get isOnline => state == 'online';

  @override
  String toString() => 'PrintNodePrinter($id: $name, $state)';
}

/// PrintNode API response for a print job
class PrintNodeJob {
  final int id;
  final int printerId;
  final String state;
  final String title;
  final DateTime? createTimestamp;

  const PrintNodeJob({
    required this.id,
    required this.printerId,
    required this.state,
    required this.title,
    this.createTimestamp,
  });

  factory PrintNodeJob.fromJson(Map<String, dynamic> json) {
    DateTime? created;
    if (json['createTimestamp'] != null) {
      created = DateTime.tryParse(json['createTimestamp'] as String);
    }
    return PrintNodeJob(
      id: json['id'] as int,
      printerId: json['printerId'] as int? ?? 0,
      state: json['state'] as String? ?? 'unknown',
      title: json['title'] as String? ?? '',
      createTimestamp: created,
    );
  }

  bool get isComplete => state == 'done';
  bool get isPending => state == 'new' || state == 'sent_to_client';
  bool get isFailed => state == 'error' || state == 'deleted';
}

/// Result of a PrintNode operation
class PrintNodeResult {
  final bool success;
  final String? message;
  final int? jobId;
  final List<PrintNodePrinter>? printers;

  const PrintNodeResult({
    required this.success,
    this.message,
    this.jobId,
    this.printers,
  });

  factory PrintNodeResult.success({int? jobId, List<PrintNodePrinter>? printers}) =>
      PrintNodeResult(success: true, jobId: jobId, printers: printers);

  factory PrintNodeResult.failure(String message) =>
      PrintNodeResult(success: false, message: message);
}

/// PrintNode Cloud Printing Service
class PrintNodeService {
  final String apiKey;
  final String _baseUrl = 'https://api.printnode.com';

  PrintNodeService({required this.apiKey});

  /// HTTP headers with Basic auth
  Map<String, String> get _headers => {
        'Authorization': 'Basic ${base64Encode(utf8.encode(apiKey))}',
        'Content-Type': 'application/json',
      };

  /// Test if API key is valid
  Future<PrintNodeResult> testConnection() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/whoami'), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return PrintNodeResult.success();
      } else if (response.statusCode == 401) {
        return PrintNodeResult.failure('Invalid API key');
      } else {
        return PrintNodeResult.failure('Connection failed: ${response.statusCode}');
      }
    } catch (e) {
      return PrintNodeResult.failure('Connection error: $e');
    }
  }

  /// Get list of available printers
  Future<PrintNodeResult> getPrinters() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/printers'), headers: _headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final printers = data
            .map((p) => PrintNodePrinter.fromJson(p as Map<String, dynamic>))
            .toList();
        return PrintNodeResult.success(printers: printers);
      } else if (response.statusCode == 401) {
        return PrintNodeResult.failure('Invalid API key');
      } else {
        return PrintNodeResult.failure('Failed to get printers: ${response.statusCode}');
      }
    } catch (e) {
      return PrintNodeResult.failure('Error getting printers: $e');
    }
  }

  /// Print plain text receipt
  Future<PrintNodeResult> printReceipt({
    required int printerId,
    required String content,
    String title = 'Receipt',
  }) async {
    try {
      // PrintNode expects content to be base64 encoded for raw_base64 content type
      final contentBase64 = base64Encode(utf8.encode(content));

      final body = jsonEncode({
        'printerId': printerId,
        'title': title,
        'contentType': 'raw_base64',
        'content': contentBase64,
        'source': 'Retail MVP',
      });

      final response = await http
          .post(Uri.parse('$_baseUrl/printjobs'), headers: _headers, body: body)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 201) {
        // Response is the job ID as an integer
        final jobId = int.tryParse(response.body);
        return PrintNodeResult.success(jobId: jobId);
      } else if (response.statusCode == 401) {
        return PrintNodeResult.failure('Invalid API key');
      } else {
        String errorMsg = 'Print failed: ${response.statusCode}';
        try {
          final data = jsonDecode(response.body);
          if (data is Map && data['message'] != null) {
            errorMsg = data['message'] as String;
          }
        } catch (_) {}
        return PrintNodeResult.failure(errorMsg);
      }
    } catch (e) {
      return PrintNodeResult.failure('Print error: $e');
    }
  }

  /// Print HTML content (rendered as PDF by PrintNode)
  Future<PrintNodeResult> printHtml({
    required int printerId,
    required String htmlContent,
    String title = 'Receipt',
  }) async {
    try {
      // For HTML, we use pdf_uri or raw content with HTML mime type
      // PrintNode can render HTML to PDF automatically
      final contentBase64 = base64Encode(utf8.encode(htmlContent));

      final body = jsonEncode({
        'printerId': printerId,
        'title': title,
        'contentType': 'raw_base64',
        'content': contentBase64,
        'source': 'Retail MVP',
        'options': {
          'paper': '58mm',
        },
      });

      final response = await http
          .post(Uri.parse('$_baseUrl/printjobs'), headers: _headers, body: body)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 201) {
        final jobId = int.tryParse(response.body);
        return PrintNodeResult.success(jobId: jobId);
      } else {
        return PrintNodeResult.failure('Print failed: ${response.statusCode}');
      }
    } catch (e) {
      return PrintNodeResult.failure('Print error: $e');
    }
  }

  /// Get status of a print job
  Future<PrintNodeJob?> getJobStatus(int jobId) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/printjobs/$jobId'), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (data.isNotEmpty) {
          return PrintNodeJob.fromJson(data.first as Map<String, dynamic>);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get computers (where PrintNode client is installed)
  Future<List<Map<String, dynamic>>> getComputers() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/computers'), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}

/// Singleton for easy access (configured via settings)
PrintNodeService? _globalPrintNode;

/// Get or create PrintNode service with API key
PrintNodeService? getPrintNodeService(String? apiKey) {
  if (apiKey == null || apiKey.isEmpty) return null;
  if (_globalPrintNode?.apiKey == apiKey) return _globalPrintNode;
  _globalPrintNode = PrintNodeService(apiKey: apiKey);
  return _globalPrintNode;
}
