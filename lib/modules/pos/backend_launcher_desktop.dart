import 'dart:io';
import 'dart:async';

/// Attempts to start the local printer backend when running on Windows desktop if it's not reachable.
/// The Node process is launched via a temporary VBScript (wscript.exe) with window style hidden
/// so no PowerShell / console window flashes in front of the POS UI.
Future<void> ensurePrinterBackendRunning({String host = 'localhost', int port = 5005}) async {
  if (!Platform.isWindows) return;
  final reachable = await _isReachable(host, port, timeout: const Duration(milliseconds: 700));
  if (reachable) return; // already running

  // Locate backend directory (development assumption: alongside the executable / project root)
  final execDir = Directory.current;
  final backendDir = Directory('${execDir.path}\\printer_backend');
  if (!backendDir.existsSync()) return;
  final serverFile = File('${backendDir.path}\\server.js');
  if (!serverFile.existsSync()) return;

  try {
    // Build a temporary VBScript that runs: node server.js (hidden, not blocking)
    final tmpDir = Directory.systemTemp;
    final vbsFile = File('${tmpDir.path}\\launch_printer_backend_${DateTime.now().millisecondsSinceEpoch}.vbs');
    final nodeCmd = 'node'; // rely on PATH. If needed, user can adjust PATH or install Node.
    // Escape quotes for VBScript. We change working directory inside script to backendDir.
    final escapedPath = backendDir.path.replaceAll('"', '""');
    final script = [
      'Set sh = CreateObject("WScript.Shell")',
  'sh.CurrentDirectory = "$escapedPath"',
      // 0 = hidden window, False = do not wait
      'sh.Run """$nodeCmd"" ""server.js""", 0, False'
    ].join('\r\n');
    await vbsFile.writeAsString(script);

    // Launch the VBScript using wscript (not cscript) so it is detached & hidden.
    await Process.start('wscript.exe', [vbsFile.path], mode: ProcessStartMode.detached);
    // Leave the temp file; OS will clean temp eventually. We could schedule deletion but that
    // risks removing it before process spawn on very slow disks. Keeping is simplest.
  } catch (_) {
    // Swallow any failure; user can manually start backend.
  }
}

Future<bool> _isReachable(String host, int port, {Duration timeout = const Duration(milliseconds: 600)}) async {
  try {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}
