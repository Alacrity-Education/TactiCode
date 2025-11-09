import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Block Detector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const CameraPage(),
    );
  }
}

// ---------------------------------------------------------
// Command parsing logic
// ---------------------------------------------------------
Map<String, dynamic>? mapToCommand(String text) {
  text = text.toLowerCase().trim();

  // START
  if (text.contains("start")) return {"command": "start"};

  // END REPEAT
  if (RegExp(r'\bend\s*repeat\b').hasMatch(text)) {
    return {"command": "endRepeat"};
  }

  // REPEAT n TIMES
  if (RegExp(r'\brepeat\b').hasMatch(text)) {
    final numberMatch =
        RegExp(r'repeat\s+(\d+)\s*(?:times|x)?\b').firstMatch(text);
    final number = numberMatch != null ? int.parse(numberMatch.group(1)!) : 1;
    return {"command": "repeat", "value": number, "body": []};
  }

  // INSTRUMENT (+ optional note 1..7 on same line)
  if (text.contains("drum") ||
      text.contains("piano") ||
      text.contains("guitar")) {
    final instrumentMatch = RegExp(r'(drum|piano|guitar)').firstMatch(text);
    final numOnSameLine = RegExp(r'\b([1-7])\b').firstMatch(text);

    final instrument = instrumentMatch != null
        ? instrumentMatch.group(0)![0].toUpperCase() +
            instrumentMatch.group(0)!.substring(1).toLowerCase()
        : "Instrument";

    final result = {
      "command": "setInstrument",
      "value": instrument,
      "note": numOnSameLine != null ? int.parse(numOnSameLine.group(1)!) : null
    };

    return result;
  }

  // Standalone NOTE line (only a number)
  final onlyNumber = RegExp(r'^\s*([1-7])\s*$').firstMatch(text);
  if (onlyNumber != null) {
    return {"command": "note", "value": int.parse(onlyNumber.group(1)!)};
  }

  // PLAY / STOP
  if (text.contains("play") || text.contains("final") || text.contains("stop")) {
    return {"command": "play"};
  }

  return null;
}

// ---------------------------------------------------------
// Attach notes (right-side numbers) to previous instruments
// ---------------------------------------------------------
List<Map<String, dynamic>> _attachNotesToInstruments(
    List<Map<String, dynamic>> tokens) {
  final List<Map<String, dynamic>> out = [];
  int? lastInstrumentIdx;

  for (final tok in tokens) {
    final cmd = (tok["command"] ?? "").toString().toLowerCase();

    if (cmd == "setinstrument") {
      out.add(Map<String, dynamic>.from(tok));
      lastInstrumentIdx = out.length - 1;
      continue;
    }

    if (cmd == "note") {
      if (lastInstrumentIdx != null) {
        final inst = out[lastInstrumentIdx!];
        inst["note"] = tok["value"];
        continue; // don't add note separately
      }
    }

    out.add(Map<String, dynamic>.from(tok));
  }

  // make sure every instrument has a note (default 0 if none)
  for (final item in out) {
    if (item["command"] == "setInstrument" && item["note"] == null) {
      item["note"] = 0;
    }
  }

  return out;
}

// ---------------------------------------------------------
// Main camera + OCR handling
// ---------------------------------------------------------
class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  final ImagePicker _picker = ImagePicker();
  final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  String? _jsonResult;
  bool _loading = false;

  Future<void> _scanWithCamera() async {
    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera permission denied')),
      );
      return;
    }

    final pickedFile = await _picker.pickImage(source: ImageSource.camera);
    if (pickedFile == null) return;

    final imageFile = File(pickedFile.path);
    await _processImage(imageFile);
  }

  Future<void> _processImage(File image) async {
    setState(() {
      _loading = true;
      _jsonResult = null;
    });

    print("📸 Captured image path: ${image.path}");
    final inputImage = InputImage.fromFile(image);
    final RecognizedText recognized =
        await textRecognizer.processImage(inputImage);

    final fullText = recognized.text.trim();
    if (fullText.isEmpty) {
      print("⚠️ No text detected.");
      setState(() {
        _loading = false;
        _jsonResult = "No text detected.";
      });
      return;
    }

    print("🟢 Detected text:\n$fullText\n");

    // Split text lines
    final parts = fullText
        .split(RegExp(r'[\n\r\.]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // Convert text -> tokens
    final tokens = parts
        .map((text) => mapToCommand(text))
        .whereType<Map<String, dynamic>>()
        .toList();

    // Attach numeric notes (to right of instrument)
    final commands = _attachNotesToInstruments(tokens);

    // Nest repeats
    final program = _nestCommands(commands);

    final jsonProgram = {
      "program": program,
      "params": ["camera_scan"],
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(jsonProgram);

    print("==== OCR JSON OUTPUT ====");
    print(jsonString);
    print("==========================");

    setState(() {
      _jsonResult = jsonString;
      _loading = false;
    });
  }

  // ---------------------------------------------------------
  // Helper: create nested repeats correctly
  // ---------------------------------------------------------
  List<Map<String, dynamic>> _nestCommands(List<Map<String, dynamic>> cmds) {
    final List<Map<String, dynamic>> program = [];
    final List<Map<String, dynamic>> repeatStack = [];

    void _append(Map<String, dynamic> node) {
      if (repeatStack.isEmpty) {
        program.add(node);
      } else {
        (repeatStack.last["body"] as List).add(node);
      }
    }

    for (final cmd in cmds) {
      final type = (cmd["command"] ?? "").toString().toLowerCase();

      if (type == "repeat") {
        final rep = {
          "command": "repeat",
          "value": cmd["value"] ?? 1,
          "body": <Map<String, dynamic>>[],
        };
        repeatStack.add(rep);
        continue;
      }

      if (type == "endrepeat") {
        if (repeatStack.isNotEmpty) {
          final completed = repeatStack.removeLast();
          _append(completed);
        }
        continue;
      }

      _append(cmd);
    }

    while (repeatStack.isNotEmpty) {
      _append(repeatStack.removeLast());
    }

    return program;
  }

  // ---------------------------------------------------------
  // UI
  // ---------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Block Detector')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Open Scanner'),
                        onPressed: _scanWithCamera,
                      ),
                      const SizedBox(height: 20),
                      if (_jsonResult != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blueAccent),
                          ),
                          child: Text(
                            _jsonResult!,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
