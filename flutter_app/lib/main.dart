import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'tag_map.dart';
import 'package:image/image.dart' as img;
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;

List<String> recognizedBlocks = [];

void main() {
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

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

Future<void> sendToPythonOCR(String imagePath,
    {required String baseUrl}) async {
  final uri = Uri.parse('$baseUrl/ocr');

  final request = http.MultipartRequest('POST', uri)
    ..files.add(await http.MultipartFile.fromPath('image', imagePath));

  final streamed = await request.send();
  final body = await streamed.stream.bytesToString();

  if (streamed.statusCode == 200) {
    final jsonResp = jsonDecode(body) as Map<String, dynamic>;
    final List<dynamic> instr = jsonResp['instructions'] ?? [];

    print('Python OCR result: $instr');

    recognizedBlocks.clear();
    for (final cmd in instr) {
      if (cmd is Map<String, dynamic>) {
        recognizedBlocks
            .add(jsonEncode(cmd)); // store each command as JSON string
      }
    }
  } else {
    print('Python OCR error: HTTP ${streamed.statusCode} $body');
  }
}

Map<String, dynamic>? mapToCommand(String text) {
  text = text.toLowerCase();

  if (text.contains("start")) {
    return {"command": "start"};
  }
  if (RegExp(r'\bend\s*repeat\b').hasMatch(text)) {
    return {"command": "endRepeat"};
  }
  if (RegExp(r'\brepeat\b').hasMatch(text)) {
    final numberMatch = RegExp(r'\d+').firstMatch(text);
    final number = numberMatch != null ? int.parse(numberMatch.group(0)!) : 1;
    return {"command": "repeat", "value": number, "body": []};
  }
  if (text.contains("drum")) {
    return {"command": "setInstrument", "value": "Drums"};
  }
  if (text.contains("piano")) {
    return {"command": "setInstrument", "value": "Piano"};
  }
  if (text.contains("guitar")) {
    return {"command": "setInstrument", "value": "Guitar"};
  }
  if (text.contains("play") ||
      text.contains("final") ||
      text.contains("stop")) {
    return {"command": "play"};
  }

  return null;
}

class _CameraPageState extends State<CameraPage> {
  final ImagePicker _picker = ImagePicker();
  final List<File> _photos = [];

  Future<void> _takePhoto() async {
    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera permission denied')),
      );
      return;
    }

    final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
    if (photo != null) {
      setState(() {
        _photos.add(File(photo.path));
      });

      //IP VERY IMPORTANT CHANGE IT
      const baseUrl = 'http://10.41.141.29:5000';
      await sendToPythonOCR(photo.path, baseUrl: baseUrl);

      //Automatically generate and save JSON file
      await _saveProgramJson(photo.path);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo + JSON saved')),
      );
    }
  }

  Future<File> _preprocessImage(File file) async {
    final bytes = await file.readAsBytes();
    final original = img.decodeImage(bytes)!;

    //Ccrop tighter around the center
    final w = original.width, h = original.height;
    final crop = img.copyCrop(
      original,
      x: (w * 0.1).round(),
      y: (h * 0.15).round(),
      width: (w * 0.8).round(),
      height: (h * 0.7).round(),
    );

    //Resize+Math
    final resized = img.copyResize(crop, width: 2000);
    final gray = img.grayscale(resized);
    final inverted = img.invert(gray);
    final contrast = img.adjustColor(inverted, contrast: 3.0, brightness: 0.3);
    final bw = img.Image.from(contrast);

    for (int y = 0; y < bw.height; y++) {
      for (int x = 0; x < bw.width; x++) {
        final l = img.getLuminance(bw.getPixel(x, y));
        final newColor = l > 120
            ? img.ColorUint8.rgb(255, 255, 255)
            : img.ColorUint8.rgb(0, 0, 0);
        bw.setPixel(x, y, newColor);
      }
    }

    final smoothed = img.gaussianBlur(bw, radius: 1);
    final outPath = '${file.path}_ocr.jpg';
    final processedFile = File(outPath);
    processedFile.writeAsBytesSync(img.encodeJpg(smoothed, quality: 95));
    return processedFile;
  }


  void _openGallery() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GalleryPage(photos: _photos)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Block Detector')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Take a photo of a block to detect its type.'),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.camera_alt),
              label: const Text('Take Photo'),
              onPressed: _takePhoto,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.photo_library),
              label: const Text('View Photos'),
              onPressed: _photos.isEmpty ? null : _openGallery,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProgramJson(String imagePath) async {
    if (recognizedBlocks.isEmpty) return;

    final List<Map<String, dynamic>> flat = recognizedBlocks
        .map((e) => jsonDecode(e) as Map<String, dynamic>)
        .toList();

    final normalized = flat.map((cmd) {
      if (!cmd.containsKey('command') && cmd.containsKey('text')) {
        return mapToCommand(cmd['text'] ?? '') ?? {};
      }
      return cmd;
    }).toList();

    final program = _nestCommands(normalized);

    final Map<String, dynamic> jsonProgram = {
      "program": program,
      "params": ["downloadable song"],
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(jsonProgram);

    // Doesnt work yet -save next to the image
    final jsonFile = File('${imagePath}_program.json');
    await jsonFile.writeAsString(jsonString);
  }

  // Convert a flat command list into nested repeat blocks.
  // Commands appearing between 'repeat' and 'endRepeat' are placed in the repeat body.
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
        final rep = <String, dynamic>{
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

      // Instrument or beat commands get placed inside the current repeat body
      if (type == "setinstrument" || type == "addbeat") {
        _append({
          "command": cmd["command"],
          "value": cmd["value"],
        });
        continue;
      }

      // Everything else (start, play, stop, etc.)
      _append(Map<String, dynamic>.from(cmd));
    }

    // Close any open repeat
    while (repeatStack.isNotEmpty) {
      final completed = repeatStack.removeLast();
      _append(completed);
    }

    return program;
  }
}
class GalleryPage extends StatelessWidget {
  final List<File> photos;
  const GalleryPage({super.key, required this.photos});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Photos')),
      body: photos.isEmpty
          ? const Center(child: Text('No photos yet'))
          : GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: photos.length,
              itemBuilder: (context, index) {
                return Image.file(
                  photos[index],
                  fit: BoxFit.cover,
                );
              },
            ),
    );
  }
}
