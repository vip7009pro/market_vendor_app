import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

class ContactSerializer {
  // Custom toJson cho Contact (chỉ lưu cần thiết: displayName, phones, photo nếu có)
  static Map<String, dynamic> contactToJson(Contact contact) {
    return {
      'displayName': contact.displayName,
      'phones': contact.phones.map((p) => {
        'label': p.label.name, // Lưu name của enum
        'number': p.number,
      }).toList(),
      'photo': contact.photo != null ? base64Encode(contact.photo!) : null, // Encode base64 nếu có ảnh
    };
  }

  // Custom fromJson để reconstruct Contact
  static Contact contactFromJson(Map<String, dynamic> json) {
    final phonesJson = json['phones'] as List<dynamic>? ?? [];
    final phones = phonesJson.map<Phone>((pJson) {
      final labelStr = pJson['label'] as String? ?? 'mobile';
      PhoneLabel label = PhoneLabel.mobile; // Default
      try {
        label = PhoneLabel.values.firstWhere((e) => e.name == labelStr); // FIX: firstWhere an toàn
      } catch (e) {
        label = PhoneLabel.mobile; // Fallback
      }
      // FIX: Positional constructor cho number, named cho label
      return Phone(pJson['number'] as String, label: label);
    }).toList();

    Contact contact = Contact(
      displayName: json['displayName'] as String,
      phones: phones,
    );

    // FIX: Tạo new Contact nếu có photo (không dùng copyWith)
    final photoB64 = json['photo'] as String?;
    if (photoB64 != null && photoB64.isNotEmpty) {
      final photoBytes = base64Decode(photoB64);
      contact = Contact(
        displayName: contact.displayName,
        phones: contact.phones,
        photo: photoBytes,
      );
    }

    return contact;
  }

  // Lưu list Contact vào SharedPreferences (JSON array)
  static Future<void> saveContactsToPrefs(List<Contact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = contacts.map((c) => contactToJson(c)).toList();
    await prefs.setString('cached_contacts', jsonEncode(jsonList));
  }

  // Load list Contact từ SharedPreferences
  static Future<List<Contact>> loadContactsFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('cached_contacts');
    if (jsonString == null || jsonString.isEmpty) return [];

    final jsonList = jsonDecode(jsonString) as List<dynamic>;
    return jsonList.map((json) => contactFromJson(json as Map<String, dynamic>)).toList();
  }

  // Clear cache nếu cần refresh
  static Future<void> clearContactsCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_contacts');
  }
}