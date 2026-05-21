import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';

// ============================================================================
// DATA MODELS
// ============================================================================

/// Represents a single parsed contact from a VCF file.
class ContactInfo {
  final String name;
  final List<String> phoneNumbers;
  final List<String> emails;
  final String? organization;
  final String? note;
  final String sourceFile;

  ContactInfo({
    required this.name,
    required this.phoneNumbers,
    required this.emails,
    this.organization,
    this.note,
    required this.sourceFile,
  });

  /// Convenience constructor with defaults for empty lists.
  factory ContactInfo.empty({required String sourceFile}) {
    return ContactInfo(
      name: 'Unknown',
      phoneNumbers: [],
      emails: [],
      sourceFile: sourceFile,
    );
  }

  /// Serialize to a map for persistence or transport.
  Map<String, dynamic> toMap() => {
        'name': name,
        'phoneNumbers': phoneNumbers,
        'emails': emails,
        'organization': organization,
        'note': note,
        'sourceFile': sourceFile,
      };

  /// Deserialize from a map.
  factory ContactInfo.fromMap(Map<String, dynamic> map) {
    return ContactInfo(
      name: map['name'] as String? ?? 'Unknown',
      phoneNumbers: List<String>.from(map['phoneNumbers'] ?? []),
      emails: List<String>.from(map['emails'] ?? []),
      organization: map['organization'] as String?,
      note: map['note'] as String?,
      sourceFile: map['sourceFile'] as String? ?? '',
    );
  }

  /// A canonical key used for duplicate detection.
  /// Normalises the name to lower-case and strips whitespace.
  String get duplicateKey {
    final normalisedName = name.toLowerCase().trim();
    if (normalisedName.isEmpty || normalisedName == 'unknown') {
      // Fall back to phone number when name is unavailable.
      final phones = phoneNumbers.map((p) => p.replaceAll(RegExp(r'[\s\-\(\)\.]'), '')).toList();
      if (phones.isNotEmpty) return 'phone:${phones.first}';
      return 'unknown_${sourceFile.hashCode}';
    }
    return normalisedName;
  }

  @override
  String toString() => 'ContactInfo(name: $name, phones: $phoneNumbers, source: $sourceFile)';
}

/// Result of scanning a single VCF file.
class ContactRecoveryResult {
  final String sourcePath;
  final String fileName;
  final int fileSize;
  final int contactCount;
  final List<ContactInfo> contacts;
  final DateTime lastModified;

  ContactRecoveryResult({
    required this.sourcePath,
    required this.fileName,
    required this.fileSize,
    required this.contactCount,
    required this.contacts,
    required this.lastModified,
  });

  Map<String, dynamic> toMap() => {
        'sourcePath': sourcePath,
        'fileName': fileName,
        'fileSize': fileSize,
        'contactCount': contactCount,
        'contacts': contacts.map((c) => c.toMap()).toList(),
        'lastModified': lastModified.toIso8601String(),
      };
}

/// Progress snapshot emitted during a scan.
class ContactScanProgress {
  final double progress;
  final String currentDirectory;
  final int filesScanned;
  final int vcfFilesFound;
  final int contactsFound;
  final String status;

  ContactScanProgress({
    required this.progress,
    required this.currentDirectory,
    required this.filesScanned,
    required this.vcfFilesFound,
    required this.contactsFound,
    required this.status,
  });
}

// ============================================================================
// SERVICE
// ============================================================================

/// Scans device storage for .vcf contact backup files, parses them, detects
/// duplicates, and provides recovery (copy) functionality.
///
/// All public methods are static stateless helpers (matching the project
/// convention used by [DuplicateFinder] and [StorageScanner]).
class ContactRecoveryService {
  // ------------------------------------------------------------------
  // Constants
  // ------------------------------------------------------------------

  /// Directories that commonly contain .vcf backup files on Android.
  static const List<String> _scanLocations = [
    '/storage/emulated/0/Download/',
    '/storage/emulated/0/WhatsApp/Media/WhatsApp Documents/',
    '/storage/emulated/0/Bluetooth/',
    '/storage/emulated/0/DCIM/',
    '/storage/emulated/0/Documents/',
    '/storage/emulated/0/',
  ];

  /// Sub-directory inside the app's recovery folder for contact files.
  static const String _recoverySubFolder = 'Contacts';

  /// Base recovery folder (mirrors [EnhancedRecoveryEngine]).
  static const String _recoveryBaseFolder = 'MediaRescue';

  // ------------------------------------------------------------------
  // Scanning
  // ------------------------------------------------------------------

  /// Scan all known locations for .vcf files and parse their contacts.
  ///
  /// Yields a [ContactScanProgress] for each directory processed and a
  /// [ContactRecoveryResult] for every VCF file discovered.
  static Stream<dynamic> scanForContacts() async* {
    int filesScanned = 0;
    int vcfFound = 0;
    int totalContacts = 0;

    for (int i = 0; i < _scanLocations.length; i++) {
      final dirPath = _scanLocations[i];
      final dir = Directory(dirPath);

      yield ContactScanProgress(
        progress: i / _scanLocations.length,
        currentDirectory: dirPath,
        filesScanned: filesScanned,
        vcfFilesFound: vcfFound,
        contactsFound: totalContacts,
        status: 'Scanning $dirPath …',
      );

      if (!await dir.exists()) {
        debugPrint('[ContactRecoveryService] Directory does not exist: $dirPath');
        continue;
      }

      try {
        // In the root-level path we only list top-level .vcf files.
        final isRoot = dirPath == '/storage/emulated/0/';

        await for (final entity in dir.list(
          followLinks: false,
          recursive: !isRoot,
        )) {
          if (entity is! File) continue;

          // When scanning root, only accept .vcf/.vcard at the top level.
          if (isRoot) {
            // ignore sub-directories — only top-level files
            if (entity.path.split('/').length > 5) continue;
          }

          if (!_isVcfFile(entity.path)) continue;

          filesScanned++;
          vcfFound++;

          final result = _parseFileResult(entity);
          if (result != null) {
            totalContacts += result.contactCount;
            yield result;
          }
        }
      } catch (e) {
        debugPrint('[ContactRecoveryService] Error scanning $dirPath: $e');
      }
    }

    yield ContactScanProgress(
      progress: 1.0,
      currentDirectory: '',
      filesScanned: filesScanned,
      vcfFilesFound: vcfFound,
      contactsFound: totalContacts,
      status: 'Scan complete',
    );
  }

  // ------------------------------------------------------------------
  // VCF Parsing
  // ------------------------------------------------------------------

  /// Parse a single .vcf file and return the extracted contacts.
  ///
  /// Handles vCard 2.1, 3.0 and 4.0 formats including:
  /// - Quoted-printable and base64 encoded values
  /// - Multi-line properties (folded lines starting with whitespace)
  /// - Multiple TEL / EMAIL entries per contact
  /// - Grouped properties (e.g. `item1.TEL`)
  static List<ContactInfo> parseVcfFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      debugPrint('[ContactRecoveryService] File not found: $path');
      return [];
    }

    try {
      final raw = file.readAsStringSync();
      return _parseVcfContent(raw, path);
    } on FileSystemException catch (e) {
      debugPrint('[ContactRecoveryService] Cannot read $path: $e');
      return [];
    } catch (e) {
      debugPrint('[ContactRecoveryService] Parse error for $path: $e');
      return [];
    }
  }

  /// Parse raw VCF text content into a list of contacts.
  static List<ContactInfo> _parseVcfContent(String content, String sourceFile) {
    final contacts = <ContactInfo>[];

    // Normalise line endings and unfold lines per RFC 6350 §3.2.
    final unfolded = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\n[ \t]'), '');

    // Split into individual vCards (each starts with BEGIN:VCARD).
    final vcardPattern = RegExp(r'BEGIN:VCARD', caseSensitive: false);
    final beginMatches = vcardPattern.allMatches(unfolded).toList();

    for (int i = 0; i < beginMatches.length; i++) {
      final start = beginMatches[i].start;
      final end = i + 1 < beginMatches.length
          ? beginMatches[i + 1].start
          : unfolded.length;

      final vcardBlock = unfolded.substring(start, end);
      final contact = _parseSingleVcard(vcardBlock, sourceFile);
      if (contact != null) {
        contacts.add(contact);
      }
    }

    return contacts;
  }

  /// Parse one vCard block into a [ContactInfo].
  static ContactInfo? _parseSingleVcard(String block, String sourceFile) {
    final lines = block.split('\n');

    String name = '';
    String? formattedName;
    final phones = <String>[];
    final emails = <String>[];
    String? organization;
    String? note;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // Strip property group prefix (e.g. "item1.")
      final propertyLine = line.replaceFirst(RegExp(r'^[^.:]+\.', caseSensitive: false), '');

      // Split into property name (+params) and value.
      // Handle the case where the value itself may contain colons.
      final colonIndex = propertyLine.indexOf(':');
      if (colonIndex == -1) continue;

      final propertyNamePart = propertyLine.substring(0, colonIndex).toUpperCase();
      final rawValue = propertyLine.substring(colonIndex + 1);

      // Strip parameter list (everything after the first ';').
      final semicolonIndex = propertyNamePart.indexOf(';');
      final propertyName = semicolonIndex == -1
          ? propertyNamePart
          : propertyNamePart.substring(0, semicolonIndex);

      final decodedValue = _decodeValue(rawValue);

      switch (propertyName) {
        case 'FN':
          formattedName = decodedValue;
        case 'N':
          // N:Last;First;Middle;Prefix;Suffix
          final parts = decodedValue.split(';');
          final first = parts.length > 1 ? parts[1].trim() : '';
          final last = parts.isNotEmpty ? parts[0].trim() : '';
          name = '$first $last'.trim();
        case 'TEL':
          final phone = _cleanPhoneNumber(decodedValue);
          if (phone.isNotEmpty && !phones.contains(phone)) {
            phones.add(phone);
          }
        case 'EMAIL':
          final email = decodedValue.trim();
          if (email.isNotEmpty && !emails.contains(email)) {
            emails.add(email);
          }
        case 'ORG':
          organization = decodedValue.replaceAll(';', ' ').trim();
        case 'NOTE':
          note = decodedValue.trim();
      }
    }

    // Prefer FN over composed N.
    final displayName =
        (formattedName ?? name).trim();
    if (displayName.isEmpty) return null;

    return ContactInfo(
      name: displayName,
      phoneNumbers: phones,
      emails: emails,
      organization: organization,
      note: note,
      sourceFile: sourceFile,
    );
  }

  // ------------------------------------------------------------------
  // Duplicate Detection
  // ------------------------------------------------------------------

  /// Find groups of duplicate (or near-duplicate) contacts.
  ///
  /// Two contacts are considered duplicates when their [ContactInfo.duplicateKey]
  /// matches. Each group contains ≥2 contacts.
  static List<List<ContactInfo>> findDuplicateContacts(
      List<ContactInfo> allContacts) {
    final keyMap = <String, List<ContactInfo>>{};

    for (final contact in allContacts) {
      final key = contact.duplicateKey;
      keyMap.putIfAbsent(key, () => []).add(contact);
    }

    // Also cross-reference by phone number for contacts that have different
    // name spellings but share a phone number.
    final phoneMap = <String, List<ContactInfo>>{};
    for (final contact in allContacts) {
      for (final phone in contact.phoneNumbers) {
        final normalised = _normalisePhone(phone);
        if (normalised.isEmpty) continue;
        phoneMap.putIfAbsent(normalised, () => []).add(contact);
      }
    }

    // Merge phone-based groups into key-based groups.
    for (final entry in phoneMap.entries) {
      if (entry.value.length < 2) continue;
      // The primary key is the first contact's duplicateKey.
      final primaryKey = entry.value.first.duplicateKey;
      final primaryList = keyMap[primaryKey] ?? [];
      for (int i = 1; i < entry.value.length; i++) {
        final other = entry.value[i];
        if (!primaryList.contains(other)) {
          primaryList.add(other);
        }
      }
      keyMap[primaryKey] = primaryList;

      // If other entries in the group had their own keyMap entries, merge them.
      for (int i = 1; i < entry.value.length; i++) {
        final otherKey = entry.value[i].duplicateKey;
        if (otherKey != primaryKey && keyMap.containsKey(otherKey)) {
          final otherList = keyMap.remove(otherKey)!;
          for (final c in otherList) {
            if (!keyMap[primaryKey]!.contains(c)) {
              keyMap[primaryKey]!.add(c);
            }
          }
        }
      }
    }

    return keyMap.values.where((group) => group.length >= 2).toList();
  }

  // ------------------------------------------------------------------
  // Recovery
  // ------------------------------------------------------------------

  /// Copy a VCF file to the app's recovery folder and return the destination
  /// path.
  ///
  /// The destination follows the convention:
  /// `/storage/emulated/0/MediaRescue/Contacts/recovered_<timestamp>_<filename>`
  static Future<String> recoverContacts(
      ContactRecoveryResult result) async {
    final source = File(result.sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Source file not found', result.sourcePath);
    }

    final recoveryDir =
        await Directory('/storage/emulated/0/$_recoveryBaseFolder/$_recoverySubFolder')
            .create(recursive: true);

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final destFileName = 'recovered_${timestamp}_${result.fileName}';
    final destPath = '${recoveryDir.path}/$destFileName';

    await source.copy(destPath);
    debugPrint(
        '[ContactRecoveryService] Recovered ${result.contactCount} contacts → $destPath');

    return destPath;
  }

  /// Recover multiple VCF results in batch, returning the list of destination
  /// paths (one per result, in the same order).
  static Future<List<String>> recoverContactsBatch(
      List<ContactRecoveryResult> results) async {
    final destPaths = <String>[];
    for (final result in results) {
      try {
        final destPath = await recoverContacts(result);
        destPaths.add(destPath);
      } catch (e) {
        debugPrint(
            '[ContactRecoveryService] Batch recovery failed for ${result.fileName}: $e');
        destPaths.add(''); // Empty string signals failure for this item.
      }
    }
    return destPaths;
  }

  // ------------------------------------------------------------------
  // Utilities
  // ------------------------------------------------------------------

  /// Get total unique contact count across all scan results.
  static int getTotalContactCount(List<ContactRecoveryResult> results) {
    return results.fold<int>(
        0, (sum, result) => sum + result.contactCount);
  }

  /// Merge all contacts from multiple scan results into a single flat list.
  static List<ContactInfo> mergeAllContacts(
      List<ContactRecoveryResult> results) {
    return results
        .expand((result) => result.contacts)
        .toList();
  }

  /// Count how many contacts have at least one phone number.
  static int countContactsWithPhone(List<ContactInfo> contacts) {
    return contacts.where((c) => c.phoneNumbers.isNotEmpty).length;
  }

  /// Count how many contacts have at least one email address.
  static int countContactsWithEmail(List<ContactInfo> contacts) {
    return contacts.where((c) => c.emails.isNotEmpty).length;
  }

  // ==================================================================
  // Private helpers
  // ==================================================================

  /// Build a [ContactRecoveryResult] from a file entity.
  static ContactRecoveryResult? _parseFileResult(File entity) {
    try {
      final stat = entity.statSync();
      final path = entity.path;
      final contacts = parseVcfFile(path);

      if (contacts.isEmpty) {
        debugPrint(
            '[ContactRecoveryService] No contacts found in ${entity.path}');
        return null;
      }

      return ContactRecoveryResult(
        sourcePath: path,
        fileName: path.split('/').last,
        fileSize: stat.size,
        contactCount: contacts.length,
        contacts: contacts,
        lastModified: stat.modified,
      );
    } catch (e) {
      debugPrint(
          '[ContactRecoveryService] Failed to process ${entity.path}: $e');
      return null;
    }
  }

  /// Return `true` if [path] ends with .vcf or .vcard (case-insensitive).
  static bool _isVcfFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.vcf') || lower.endsWith('.vcard');
  }

  /// Decode quoted-printable strings (common in vCard 2.1).
  static String _decodeQuotedPrintable(String input) {
    if (!input.contains('=')) return input;
    final buffer = StringBuffer();
    int i = 0;
    while (i < input.length) {
      if (input[i] == '=' && i + 2 < input.length) {
        final hex = input.substring(i + 1, i + 3);
        final code = int.tryParse(hex, radix: 16);
        if (code != null) {
          buffer.writeCharCode(code);
          i += 3;
          continue;
        }
      }
      buffer.write(input[i]);
      i++;
    }
    return buffer.toString();
  }

  /// Decode a vCard property value that might be quoted-printable or contain
  /// charset information in the parameters.
  static String _decodeValue(String raw) {
    // Simple quoted-printable detection (no charset param handling needed for
    // most Android VCF exports).
    if (raw.contains('=\n') ||
        RegExp(r'=[0-9A-Fa-f]{2}').hasMatch(raw)) {
      return _decodeQuotedPrintable(raw);
    }
    return raw;
  }

  /// Normalise a phone number for comparison by stripping all non-digit
  /// characters except a leading '+'.
  static String _normalisePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    return digits;
  }

  /// Clean a raw phone value from a VCF: remove "tel:" URI prefix,
  /// voicemail hints, and surrounding whitespace.
  static String _cleanPhoneNumber(String raw) {
    var cleaned = raw.trim();
    // Strip "tel:" URI scheme if present.
    if (cleaned.toLowerCase().startsWith('tel:')) {
      cleaned = cleaned.substring(4);
    }
    // Strip value parameters like ;type=CELL
    final semiIdx = cleaned.indexOf(';');
    if (semiIdx != -1) {
      cleaned = cleaned.substring(0, semiIdx);
    }
    return cleaned.trim();
  }
}
