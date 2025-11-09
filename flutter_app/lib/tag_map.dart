final List<Map<String, dynamic>> tagMap = [
  {"category": "Control", "item": "START", "id": 0, "aliases": ["start"]},

  // Musical Notes
  {"category": "Musical Notes", "item": "Note 1 (e.g., C)", "id": 1, "aliases": ["note 1", "c"]},
  {"category": "Musical Notes", "item": "Note 2 (e.g., D)", "id": 2, "aliases": ["note 2", "d"]},
  {"category": "Musical Notes", "item": "Note 3 (e.g., E)", "id": 3, "aliases": ["note 3", "e"]},
  {"category": "Musical Notes", "item": "Note 4 (e.g., F)", "id": 4, "aliases": ["note 4", "f"]},
  {"category": "Musical Notes", "item": "Note 5 (e.g., G)", "id": 5, "aliases": ["note 5", "g"]},
  {"category": "Musical Notes", "item": "Note 6 (e.g., A)", "id": 6, "aliases": ["note 6", "a"]},
  {"category": "Musical Notes", "item": "Note 7 (e.g., B)", "id": 7, "aliases": ["note 7", "b"]},

  {"category": "Control", "item": "FINAL (Stop)", "id": 8, "aliases": ["final", "stop"]},

  // REPEAT BLOCK
  {"category": "Control", "item": "REPEAT", "id": 9, "aliases": ["repeat", "repeat times", "times"]},

  // END REPEAT BLOCK
  {"category": "Control", "item": "END REPEAT", "id": 10, "aliases": ["end", "end repeat", "endrepeat"]},

  // Instruments
  {"category": "Instruments", "item": "Instrument 1", "id": 11, "aliases": ["drum"]},
  {"category": "Instruments", "item": "Instrument 2", "id": 12, "aliases": ["piano"]},
  {"category": "Instruments", "item": "Instrument 3", "id": 13, "aliases": ["guitar"]},

  // Numbers
  {"category": "Numbers", "item": "Number 0", "id": 16, "aliases": ["0", "zero"]},
  {"category": "Numbers", "item": "Number 1", "id": 17, "aliases": ["1", "one"]},
  {"category": "Numbers", "item": "Number 2", "id": 18, "aliases": ["2", "two"]},
  {"category": "Numbers", "item": "Number 3", "id": 19, "aliases": ["3", "three"]},
  {"category": "Numbers", "item": "Number 4", "id": 20, "aliases": ["4", "four"]},
  {"category": "Numbers", "item": "Number 5", "id": 21, "aliases": ["5", "five"]},
  {"category": "Numbers", "item": "Number 6", "id": 22, "aliases": ["6", "six"]},
  {"category": "Numbers", "item": "Number 7", "id": 23, "aliases": ["7", "seven"]},
  {"category": "Numbers", "item": "Number 8", "id": 24, "aliases": ["8", "eight"]},
  {"category": "Numbers", "item": "Number 9", "id": 25, "aliases": ["9", "nine"]},
];

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

Map<String, dynamic>? findTagByText(String text) {
  final normalized = _norm(text);
  for (final tag in tagMap) {
    final item = _norm(tag['item'].toString());
    if (item.contains(normalized) || normalized.contains(item)) return tag;

    final aliases = (tag['aliases'] as List).map((e) => _norm(e.toString()));
    for (final a in aliases) {
      if (a.isEmpty) continue;
      if (a.contains(normalized) || normalized.contains(a)) return tag;
    }
  }
  return null;
}
