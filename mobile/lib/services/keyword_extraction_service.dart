/// Extracts grocery keywords from natural language transcripts.
///
/// Handles Hindi, English, and Hinglish (mixed) sentences.
/// Removes filler words, extracts quantities and units,
/// and returns a list of structured grocery items.
///
/// All processing is LOCAL — no API calls needed.
class KeywordExtractionService {
  /// Extract grocery items from a transcript.
  ///
  /// Example inputs and outputs:
  /// - "मुझे 2 किलो आलू चाहिए" → [{keyword: "आलू", qty: 2, unit: "kg"}]
  /// - "aloo aur doodh chahiye" → [{keyword: "aloo"}, {keyword: "doodh"}]
  /// - "2 kilo aloo aur ek litre doodh" → [{keyword: "aloo", qty: 2, unit: "kg"}, {keyword: "doodh", qty: 1, unit: "litre"}]
  static List<ExtractedItem> extract(String transcript) {
    if (transcript.trim().isEmpty) return [];

    // Normalize
    String text = transcript.toLowerCase().trim();

    // Remove filler words/phrases
    text = _removeFillers(text);

    // Split into item segments by conjunctions
    final segments = _splitByConjunctions(text);

    // Extract item + qty + unit from each segment
    final items = <ExtractedItem>[];
    for (final segment in segments) {
      final trimmed = segment.trim();
      if (trimmed.isEmpty) continue;
      final item = _extractFromSegment(trimmed);
      if (item != null) items.add(item);
    }

    return items;
  }

  /// Get just the keyword strings (for search API calls).
  static List<String> extractKeywords(String transcript) {
    return extract(transcript).map((e) => e.keyword).toList();
  }

  // ═══════════════════════════════════════
  // FILLER REMOVAL
  // ═══════════════════════════════════════

  static String _removeFillers(String text) {
    // Multi-word fillers first (order matters — longer phrases before shorter)
    for (final filler in _multiWordFillers) {
      text = text.replaceAll(filler, ' ');
    }
    // Single-word fillers — split into words, remove matches, rejoin
    // (more reliable than regex \b which can fail with mixed scripts)
    final words = text.split(RegExp(r'\s+'));
    final filtered = words.where((w) => !_singleWordFillersSet.contains(w)).toList();
    return filtered.join(' ').trim();
  }

  static final _singleWordFillersSet = <String>{..._singleWordFillers};

  static const _multiWordFillers = [
    // Hindi phrases
    'मुझे चाहिए', 'मुझको चाहिए', 'दे दो', 'दे दीजिए',
    'ला दो', 'ला दीजिए', 'लेकर आओ', 'लेकर आना',
    'भेज दो', 'भेज दीजिए',
    // English phrases
    'i want', 'i need', 'please give me', 'give me',
    'get me', 'bring me', 'can you get', 'can you bring',
    'i would like', "i'd like", 'please get',
    // Hinglish phrases
    'mujhe chahiye', 'mujhko chahiye', 'de do', 'de dijiye',
    'la do', 'la dijiye', 'lekar aao', 'lekar aana',
    'bhej do', 'bhej dijiye',
  ];

  static const _singleWordFillers = [
    // Hindi
    'मुझे', 'मुझको', 'चाहिए', 'लाओ', 'लाना', 'है', 'हैं',
    'भी', 'बस', 'जरा', 'थोड़ा', 'थोड़े', 'थोड़ी', 'कुछ',
    'वाला', 'वाली', 'वाले', 'का', 'की', 'के', 'में', 'से',
    'को', 'पर', 'ले', 'लो', 'दो', 'दे',
    // English
    'please', 'the', 'a', 'an', 'some', 'few', 'of',
    'want', 'need', 'get', 'bring', 'give',
    // Hinglish
    'chahiye', 'chahie', 'lao', 'lana', 'bhi', 'bas',
    'zara', 'thoda', 'thodi', 'thode', 'kuch',
    'wala', 'wali', 'wale', 'mujhe', 'mujhko',
    'le', 'lo', 'do', 'de',
  ];

  // ═══════════════════════════════════════
  // CONJUNCTION SPLITTING
  // ═══════════════════════════════════════

  static List<String> _splitByConjunctions(String text) {
    // Split by Hindi/English/Hinglish conjunctions
    return text.split(RegExp(
      r'\s+(?:और|aur|or|and|,|एवं|तथा|व)\s+|'  // conjunctions
      r',\s*'                                     // comma-separated
    ));
  }

  // ═══════════════════════════════════════
  // SEGMENT PARSING (qty + unit + keyword)
  // ═══════════════════════════════════════

  static ExtractedItem? _extractFromSegment(String segment) {
    double? qty;
    String? unit;
    String remaining = segment;

    // Try to extract quantity + unit pattern
    // Pattern: [number] [unit] [item]
    // e.g. "2 kilo aloo", "ek litre doodh", "आधा किलो प्याज"

    // Step 1: Extract leading number (Hindi or English)
    final numMatch = RegExp(
      r'^(\d+(?:\.\d+)?)\s*'           // digits: 2, 0.5, etc.
      r'|^(एक|दो|तीन|चार|पांच|छह|सात|आठ|नौ|दस|आधा|डेढ़|ढाई|पौने)\s*'  // Hindi words
      r'|^(ek|do|teen|char|panch|cheh|saat|aath|nau|das|aadha|dedh|dhai|paune)\s*'  // Hinglish
      r'|^(one|two|three|four|five|six|seven|eight|nine|ten|half)\s*'  // English
    ).firstMatch(remaining);

    if (numMatch != null) {
      final digitStr = numMatch.group(1);
      final hindiWord = numMatch.group(2);
      final hinglishWord = numMatch.group(3);
      final englishWord = numMatch.group(4);

      if (digitStr != null) {
        qty = double.tryParse(digitStr);
      } else {
        qty = _wordToNumber(hindiWord ?? hinglishWord ?? englishWord ?? '');
      }
      remaining = remaining.substring(numMatch.end).trim();
    }

    // Step 2: Extract unit
    final unitMatch = RegExp(
      r'^(किलो|किलोग्राम|ग्राम|लीटर|लिटर|पैकेट|पीस|दर्जन|बंडल|बोतल|डिब्बा|'
      r'kilo|kilogram|kg|gram|gm|g|litre|liter|ltr|lt|l|'
      r'packet|pack|pkt|piece|pcs|pc|dozen|dzn|'
      r'bundle|bottle|btl|box|dabba|dibba)\s*'
    ).firstMatch(remaining);

    if (unitMatch != null) {
      unit = _normalizeUnit(unitMatch.group(1)!);
      remaining = remaining.substring(unitMatch.end).trim();
    }

    // Step 3: Whatever remains is the keyword — translate to English
    remaining = remaining.trim();
    if (remaining.isEmpty) return null;

    final translated = translateToEnglish(remaining);

    return ExtractedItem(
      keyword: translated,
      qty: qty,
      unit: unit,
    );
  }

  // ═══════════════════════════════════════
  // NUMBER WORD → DOUBLE
  // ═══════════════════════════════════════

  static double? _wordToNumber(String word) {
    const map = {
      // Hindi
      'एक': 1.0, 'दो': 2.0, 'तीन': 3.0, 'चार': 4.0, 'पांच': 5.0,
      'छह': 6.0, 'सात': 7.0, 'आठ': 8.0, 'नौ': 9.0, 'दस': 10.0,
      'आधा': 0.5, 'डेढ़': 1.5, 'ढाई': 2.5, 'पौने': 0.75,
      // Hinglish
      'ek': 1.0, 'do': 2.0, 'teen': 3.0, 'char': 4.0, 'panch': 5.0,
      'cheh': 6.0, 'saat': 7.0, 'aath': 8.0, 'nau': 9.0, 'das': 10.0,
      'aadha': 0.5, 'dedh': 1.5, 'dhai': 2.5, 'paune': 0.75,
      // English
      'one': 1.0, 'two': 2.0, 'three': 3.0, 'four': 4.0, 'five': 5.0,
      'six': 6.0, 'seven': 7.0, 'eight': 8.0, 'nine': 9.0, 'ten': 10.0,
      'half': 0.5,
    };
    return map[word.toLowerCase()];
  }

  // ═══════════════════════════════════════
  // UNIT NORMALIZATION
  // ═══════════════════════════════════════

  static String _normalizeUnit(String raw) {
    final lower = raw.toLowerCase();
    // kg
    if ({'किलो', 'किलोग्राम', 'kilo', 'kilogram', 'kg'}.contains(lower)) {
      return 'kg';
    }
    // gram
    if ({'ग्राम', 'gram', 'gm', 'g'}.contains(lower)) return 'gm';
    // litre
    if ({'लीटर', 'लिटर', 'litre', 'liter', 'ltr', 'lt', 'l'}.contains(lower)) {
      return 'litre';
    }
    // packet
    if ({'पैकेट', 'packet', 'pack', 'pkt'}.contains(lower)) return 'packet';
    // piece
    if ({'पीस', 'piece', 'pcs', 'pc'}.contains(lower)) return 'piece';
    // dozen
    if ({'दर्जन', 'dozen', 'dzn'}.contains(lower)) return 'dozen';
    // bundle
    if ({'बंडल', 'bundle'}.contains(lower)) return 'bundle';
    // bottle
    if ({'बोतल', 'bottle', 'btl'}.contains(lower)) return 'bottle';
    // box
    if ({'डिब्बा', 'box', 'dabba', 'dibba'}.contains(lower)) return 'box';
    return raw;
  }

  // ═══════════════════════════════════════
  // DEVANAGARI → ROMAN TRANSLITERATION
  // ═══════════════════════════════════════

  /// Transliterate Devanagari text to Roman (Hinglish).
  /// "मुझे चावल चाहिए" → "mujhe chaaval chaahie"
  /// Works character by character — no API needed.
  static String transliterate(String text) {
    if (text.isEmpty) return text;

    // If text has no Devanagari characters, return as-is
    if (!RegExp(r'[\u0900-\u097F]').hasMatch(text)) return text;

    final buffer = StringBuffer();
    final runes = text.runes.toList();

    for (var i = 0; i < runes.length; i++) {
      final char = String.fromCharCode(runes[i]);
      final nextChar = i + 1 < runes.length ? String.fromCharCode(runes[i + 1]) : null;

      // Check for conjunct/half letter (followed by halant ्)
      if (nextChar == '्') {
        // Output consonant without vowel
        buffer.write(_consonantMap[char] ?? char);
        i++; // skip the halant
        continue;
      }

      // Dependent vowel signs (matras)
      if (_matraMap.containsKey(char)) {
        buffer.write(_matraMap[char]);
        continue;
      }

      // Independent vowels
      if (_vowelMap.containsKey(char)) {
        buffer.write(_vowelMap[char]);
        continue;
      }

      // Consonants (with implicit 'a' unless followed by matra or halant)
      if (_consonantMap.containsKey(char)) {
        buffer.write(_consonantMap[char]);
        // Add implicit 'a' if NOT followed by matra, halant, or another modifier
        if (nextChar != null &&
            !_matraMap.containsKey(nextChar) &&
            nextChar != '्' &&
            nextChar != 'ं' &&
            nextChar != 'ः' &&
            nextChar != 'ँ') {
          buffer.write('a');
        }
        // Also add 'a' if this is the last character
        if (i == runes.length - 1) {
          buffer.write('a');
        }
        continue;
      }

      // Anusvara (ं) → n/m
      if (char == 'ं') {
        buffer.write('n');
        continue;
      }
      // Visarga (ः) → h
      if (char == 'ः') {
        buffer.write('h');
        continue;
      }
      // Chandrabindu (ँ) → n
      if (char == 'ँ') {
        buffer.write('n');
        continue;
      }
      // Nukta (़) → skip (already handled in consonant)
      if (char == '़') continue;

      // Devanagari digits
      if (_digitMap.containsKey(char)) {
        buffer.write(_digitMap[char]);
        continue;
      }

      // Everything else (spaces, punctuation, English chars) pass through
      buffer.write(char);
    }

    return buffer.toString();
  }

  static const _vowelMap = <String, String>{
    'अ': 'a', 'आ': 'aa', 'इ': 'i', 'ई': 'ee',
    'उ': 'u', 'ऊ': 'oo', 'ए': 'e', 'ऐ': 'ai',
    'ओ': 'o', 'औ': 'au', 'ऋ': 'ri',
  };

  static const _matraMap = <String, String>{
    'ा': 'aa', 'ि': 'i', 'ी': 'ee', 'ु': 'u', 'ू': 'oo',
    'े': 'e', 'ै': 'ai', 'ो': 'o', 'ौ': 'au', 'ृ': 'ri',
  };

  static const _consonantMap = <String, String>{
    'क': 'k', 'ख': 'kh', 'ग': 'g', 'घ': 'gh', 'ङ': 'ng',
    'च': 'ch', 'छ': 'chh', 'ज': 'j', 'झ': 'jh', 'ञ': 'ny',
    'ट': 't', 'ठ': 'th', 'ड': 'd', 'ढ': 'dh', 'ण': 'n',
    'त': 't', 'थ': 'th', 'द': 'd', 'ध': 'dh', 'न': 'n',
    'प': 'p', 'फ': 'ph', 'ब': 'b', 'भ': 'bh', 'म': 'm',
    'य': 'y', 'र': 'r', 'ल': 'l', 'व': 'v', 'श': 'sh',
    'ष': 'sh', 'स': 's', 'ह': 'h',
    // With nukta
    'क़': 'q', 'ख़': 'kh', 'ग़': 'gh', 'ज़': 'z', 'फ़': 'f',
    'ड़': 'r', 'ढ़': 'rh',
  };

  static const _digitMap = <String, String>{
    '०': '0', '१': '1', '२': '2', '३': '3', '४': '4',
    '५': '5', '६': '6', '७': '7', '८': '8', '९': '9',
  };

  // ═══════════════════════════════════════
  // HINDI/HINGLISH → ENGLISH TRANSLATION
  // ═══════════════════════════════════════

  /// Translate a Hindi/Hinglish keyword to English using local dictionary.
  /// First transliterates Devanagari to Roman, then checks dictionary.
  /// Returns English if found, otherwise returns transliterated Hinglish.
  static String translateToEnglish(String keyword) {
    final lower = keyword.toLowerCase().trim();
    // Direct dictionary match (Devanagari or romanized)
    if (_groceryDict.containsKey(lower)) return _groceryDict[lower]!;
    // Transliterate Devanagari → Roman
    final roman = transliterate(lower);
    // Check dictionary with transliterated form
    if (_groceryDict.containsKey(roman)) return _groceryDict[roman]!;
    // Check each word individually
    final words = lower.split(RegExp(r'\s+'));
    final translated = words.map((w) {
      if (_groceryDict.containsKey(w)) return _groceryDict[w]!;
      final romanW = transliterate(w);
      if (_groceryDict.containsKey(romanW)) return _groceryDict[romanW]!;
      // No dictionary match — return transliterated (Hinglish) form
      return romanW;
    }).toList();
    return translated.join(' ');
  }

  /// Common grocery items: Hindi + Hinglish → English
  static const _groceryDict = <String, String>{
    // ── Devanagari transliterations of English words (STT hi-IN outputs these) ──
    'राइस': 'rice', 'मिल्क': 'milk', 'एग': 'egg', 'एग्स': 'eggs',
    'ब्रेड': 'bread', 'बटर': 'butter', 'शुगर': 'sugar', 'साल्ट': 'salt',
    'ऑयल': 'oil', 'फ्लोर': 'flour', 'टी': 'tea', 'कॉफ़ी': 'coffee',
    'चीज़': 'cheese', 'जूस': 'juice', 'वॉटर': 'water',
    'पोटैटो': 'potato', 'टोमैटो': 'tomato', 'ऑनियन': 'onion',
    'कैरट': 'carrot', 'स्पिनच': 'spinach', 'कॉर्न': 'corn',
    'चिकन': 'chicken', 'फिश': 'fish', 'मीट': 'meat',
    'बिस्किट': 'biscuit', 'चिप्स': 'chips', 'नूडल्स': 'noodles',
    'सॉस': 'sauce', 'केचप': 'ketchup', 'चॉकलेट': 'chocolate',
    'आइसक्रीम': 'ice cream', 'सोप': 'soap', 'शैम्पू': 'shampoo',

    // ── Vegetables (सब्ज़ियाँ) ──
    'आलू': 'potato', 'aloo': 'potato', 'aaloo': 'potato',
    'प्याज': 'onion', 'pyaaz': 'onion', 'pyaz': 'onion',
    'टमाटर': 'tomato', 'tamatar': 'tomato',
    'मिर्च': 'chilli', 'mirch': 'chilli', 'mirchi': 'chilli',
    'हरी मिर्च': 'green chilli', 'hari mirch': 'green chilli',
    'लाल मिर्च': 'red chilli', 'lal mirch': 'red chilli',
    'धनिया': 'coriander', 'dhaniya': 'coriander',
    'पालक': 'spinach', 'palak': 'spinach',
    'गोभी': 'cauliflower', 'gobhi': 'cauliflower', 'gobi': 'cauliflower',
    'फूलगोभी': 'cauliflower', 'phool gobhi': 'cauliflower',
    'बंदगोभी': 'cabbage', 'bandgobhi': 'cabbage', 'patta gobhi': 'cabbage',
    'पत्ता गोभी': 'cabbage',
    'भिंडी': 'okra', 'bhindi': 'okra',
    'बैंगन': 'brinjal', 'baingan': 'brinjal',
    'लौकी': 'bottle gourd', 'lauki': 'bottle gourd',
    'तोरी': 'ridge gourd', 'tori': 'ridge gourd', 'turai': 'ridge gourd',
    'करेला': 'bitter gourd', 'karela': 'bitter gourd',
    'मूली': 'radish', 'mooli': 'radish',
    'गाजर': 'carrot', 'gajar': 'carrot',
    'मटर': 'peas', 'matar': 'peas',
    'शिमला मिर्च': 'capsicum', 'shimla mirch': 'capsicum',
    'अदरक': 'ginger', 'adrak': 'ginger',
    'लहसुन': 'garlic', 'lahsun': 'garlic', 'lehsun': 'garlic',
    'हल्दी': 'turmeric', 'haldi': 'turmeric',
    'नींबू': 'lemon', 'nimbu': 'lemon', 'neembu': 'lemon',
    'खीरा': 'cucumber', 'kheera': 'cucumber',
    'सब्ज़ी': 'vegetable', 'sabzi': 'vegetable', 'sabji': 'vegetable',

    // ── Fruits (फल) ──
    'सेब': 'apple', 'seb': 'apple',
    'केला': 'banana', 'kela': 'banana',
    'अंगूर': 'grapes', 'angoor': 'grapes',
    'संतरा': 'orange', 'santra': 'orange',
    'आम': 'mango', 'aam': 'mango',
    'पपीता': 'papaya', 'papita': 'papaya',
    'अनार': 'pomegranate', 'anar': 'pomegranate',
    'तरबूज': 'watermelon', 'tarbooz': 'watermelon',
    'खरबूजा': 'muskmelon', 'kharbooja': 'muskmelon',

    // ── Dairy (डेयरी) ──
    'दूध': 'milk', 'doodh': 'milk', 'dudh': 'milk',
    'दही': 'curd', 'dahi': 'curd',
    'पनीर': 'paneer', 'panir': 'paneer',
    'मक्खन': 'butter', 'makhan': 'butter',
    'घी': 'ghee', 'ghee': 'ghee',
    'क्रीम': 'cream', 'cream': 'cream',
    'छाछ': 'buttermilk', 'chaach': 'buttermilk', 'chhachh': 'buttermilk',
    'लस्सी': 'lassi',

    // ── Eggs & Meat ──
    'अंडा': 'egg', 'anda': 'egg',
    'अंडे': 'eggs', 'ande': 'eggs',
    'murga': 'chicken', 'मुर्गा': 'chicken',
    'मटन': 'mutton', 'mutton': 'mutton',
    'मछली': 'fish', 'machli': 'fish', 'machhli': 'fish',

    // ── Grains & Staples (अनाज) ──
    'चावल': 'rice', 'chawal': 'rice',
    'आटा': 'flour', 'aata': 'flour', 'atta': 'flour',
    'गेहूं': 'wheat', 'gehu': 'wheat', 'gehun': 'wheat',
    'मैदा': 'maida', 'maida': 'refined flour',
    'बेसन': 'besan', 'besan': 'gram flour',
    'सूजी': 'semolina', 'suji': 'semolina', 'sooji': 'semolina',
    'दाल': 'dal', 'daal': 'dal',
    'चना': 'chickpea', 'chana': 'chickpea',
    'राजमा': 'kidney beans', 'rajma': 'kidney beans',
    'मूंग': 'moong', 'moong': 'moong dal',
    'उड़द': 'urad', 'urad': 'urad dal',
    'तूर': 'toor', 'toor': 'toor dal', 'arhar': 'toor dal',
    'मसूर': 'masoor', 'masoor': 'masoor dal',
    'पोहा': 'poha', 'poha': 'flattened rice',

    // ── Spices (मसाले) ──
    'नमक': 'salt', 'namak': 'salt',
    'चीनी': 'sugar', 'cheeni': 'sugar', 'chini': 'sugar',
    'मिर्च पाउडर': 'chilli powder', 'mirch powder': 'chilli powder',
    'गरम मसाला': 'garam masala',
    'जीरा': 'cumin', 'jeera': 'cumin',
    'सरसों': 'mustard', 'sarson': 'mustard',
    'काली मिर्च': 'black pepper', 'kali mirch': 'black pepper',
    'दालचीनी': 'cinnamon', 'dalchini': 'cinnamon',
    'लौंग': 'cloves', 'laung': 'cloves',
    'इलायची': 'cardamom', 'elaichi': 'cardamom',
    'तेज पत्ता': 'bay leaf', 'tej patta': 'bay leaf',
    'अजवाइन': 'carom seeds', 'ajwain': 'carom seeds',
    'मेथी': 'fenugreek', 'methi': 'fenugreek',
    'सौंफ': 'fennel', 'saunf': 'fennel',

    // ── Oil & Cooking (तेल) ──
    'तेल': 'oil', 'tel': 'oil',
    'सरसों का तेल': 'mustard oil', 'sarson ka tel': 'mustard oil',
    'रिफाइंड': 'refined oil', 'refined': 'refined oil',

    // ── Bread & Bakery ──
    'bread': 'bread',
    'बिस्कुट': 'biscuit', 'biscuit': 'biscuit', 'biskut': 'biscuit',
    'केक': 'cake',
    'रस्क': 'rusk', 'rusk': 'rusk',

    // ── Beverages ──
    'चाय': 'tea', 'chai': 'tea',
    'coffee': 'coffee',
    'पानी': 'water', 'paani': 'water', 'pani': 'water',
    'juice': 'juice',

    // ── Snacks ──
    'chips': 'chips',
    'नमकीन': 'namkeen', 'namkeen': 'snacks',
    'मूंगफली': 'peanut', 'mungfali': 'peanut', 'moongfali': 'peanut',
    'काजू': 'cashew', 'kaju': 'cashew',
    'बादाम': 'almond', 'badam': 'almond',
    'किशमिश': 'raisin', 'kishmish': 'raisin',

    // ── Household ──
    'साबुन': 'soap', 'sabun': 'soap',
    'शैंपू': 'shampoo', 'shampoo': 'shampoo',
    'डिटर्जेंट': 'detergent', 'detergent': 'detergent',
    'तौलिया': 'towel',
    'टूथपेस्ट': 'toothpaste', 'toothpaste': 'toothpaste',

    // ── Miscellaneous ──
    'सिरका': 'vinegar', 'sirka': 'vinegar',
    'सोडा': 'soda',
    'अचार': 'pickle', 'achaar': 'pickle', 'achar': 'pickle',
    'पापड़': 'papad', 'papad': 'papad',
    'noodles': 'noodles',
    'मैगी': 'maggi', 'maggi': 'maggi',
    'ketchup': 'ketchup',
    'sauce': 'sauce',
  };
}

/// A single extracted grocery item from voice transcript.
class ExtractedItem {
  final String keyword;
  final double? qty;
  final String? unit;

  const ExtractedItem({required this.keyword, this.qty, this.unit});

  @override
  String toString() {
    final parts = <String>[keyword];
    if (qty != null) parts.insert(0, '${qty!.toStringAsFixed(qty == qty!.roundToDouble() ? 0 : 1)}');
    if (unit != null) parts.insert(1, unit!);
    return parts.join(' ');
  }

  /// Display string for search bar: "2 kg आलू"
  String get displayText => toString();

  /// Just the keyword for API search
  String get searchQuery => keyword;
}
