import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TactiCode',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const CameraPage(),
    );
  }
}

// ------------------ Command parsing logic ------------------
Map<String, dynamic>? mapToCommand(String text) {
  text = text.toLowerCase().trim();

  if (text.contains("start")) return {"command": "start"};
  if (RegExp(r'\bend\s*repeat\b').hasMatch(text)) {
    return {"command": "endRepeat"};
  }

  if (RegExp(r'\brepeat\b').hasMatch(text)) {
    final numberMatch =
        RegExp(r'repeat\s+(\d+)\s*(?:times|x)?\b').firstMatch(text);
    final number = numberMatch != null ? int.parse(numberMatch.group(1)!) : 1;
    return {"command": "repeat", "value": number, "body": []};
  }

  if (text.contains("drum") || text.contains("piano") || text.contains("guitar")) {
    final instrumentMatch = RegExp(r'(drum|piano|guitar)').firstMatch(text);
    final numOnSameLine = RegExp(r'\b([1-7])\b').firstMatch(text);

    final instrument = instrumentMatch != null
        ? instrumentMatch.group(0)![0].toUpperCase() +
            instrumentMatch.group(0)!.substring(1).toLowerCase()
        : "Instrument";

    return {
      "command": "setInstrument",
      "value": instrument,
      "note": numOnSameLine != null ? int.parse(numOnSameLine.group(1)!) : null
    };
  }

  final onlyNumber = RegExp(r'^\s*([1-7])\s*$').firstMatch(text);
  if (onlyNumber != null) {
    return {"command": "note", "value": int.parse(onlyNumber.group(1)!)};
  }

  if (text.contains("play") || text.contains("final") || text.contains("stop")) {
    return {"command": "play"};
  }

  return null;
}

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
        continue;
      }
    }

    out.add(Map<String, dynamic>.from(tok));
  }

  for (final item in out) {
    if (item["command"] == "setInstrument" && item["note"] == null) {
      item["note"] = 0;
    }
  }

  return out;
}

// ------------------ CameraPage ------------------
class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  final ImagePicker _picker = ImagePicker();
  final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  late final WebViewController _webController;
  bool _pageLoaded = false;
  bool _loading = false;
  String? _savedJsonPath;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    // iOS params allow inline playback and remove gesture requirement for media
    final iOSParams = WebKitWebViewControllerCreationParams(
      allowsInlineMediaPlayback: true,
      mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
    );

    // Android params (no special ctor flag for media gesture here)
    final androidParams =  AndroidWebViewControllerCreationParams();

    final PlatformWebViewControllerCreationParams params =
        WebViewPlatform.instance is WebKitWebViewPlatform
            ? iOSParams
            : androidParams;

    final controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) {
          setState(() => _pageLoaded = true);
        }),
      )
      ..loadFlutterAsset('assets/viewer.html');

    // Android-only: disable media playback gesture requirement on the platform controller
    final platformCtrl = controller.platform;
    if (platformCtrl is AndroidWebViewController) {
      await platformCtrl.setMediaPlaybackRequiresUserGesture(false);
    }

    _webController = controller;
  }

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
    await _processImage(File(pickedFile.path));
  }

  Future<File> _saveJsonToFile(String jsonContent) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/program.json');
    await file.writeAsString(jsonContent);
    return file;
  }

  Future<void> _sendJsonToWeb(String jsonContent, String filePath) async {
    if (!_pageLoaded) return;
    // ensure we pass a JSON literal string to JS
    final jsSafe = jsonEncode(json.decode(jsonContent));
    final js = 'render($jsSafe, ${jsonEncode(filePath)});';
    await _webController.runJavaScript(js);
  }

  Future<void> _processImage(File image) async {
    setState(() {
      _loading = true;
      _savedJsonPath = null;
    });

    final inputImage = InputImage.fromFile(image);
    final recognized = await textRecognizer.processImage(inputImage);
    final fullText = recognized.text.trim();

    if (fullText.isEmpty) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No text detected')));
      return;
    }

    final parts = fullText
        .split(RegExp(r'[\n\r\.]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final tokens = parts
        .map((t) => mapToCommand(t))
        .whereType<Map<String, dynamic>>()
        .toList();

    final commands = _attachNotesToInstruments(tokens);
    final program = _nestCommands(commands);

    final jsonProgram = {
      "program": program,
      "params": ["camera_scan"]
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(jsonProgram);

    // console snapshot
    print("==== OCR JSON OUTPUT ====");
    print(jsonString);
    print("=========================");

    final savedFile = await _saveJsonToFile(jsonString);
    _savedJsonPath = savedFile.path;
    await _sendJsonToWeb(jsonString, _savedJsonPath!);

    setState(() => _loading = false);
  }

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
        repeatStack.add({
          "command": "repeat",
          "value": cmd["value"] ?? 1,
          "body": <Map<String, dynamic>>[],
        });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TactiCode Detector')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Open Scanner'),
                  onPressed: _loading ? null : _scanWithCamera,
                ),
                const SizedBox(width: 12),
                if (_savedJsonPath != null)
                  Expanded(
                    child: Text(
                      'Saved: $_savedJsonPath',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                if (_pageLoaded)
                  WebViewWidget(controller: _webController)
                else
                  const Center(child: CircularProgressIndicator()),
                if (_loading)
                  Container(
                    color: Colors.black.withOpacity(0.05),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
