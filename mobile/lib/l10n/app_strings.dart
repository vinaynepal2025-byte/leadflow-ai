import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/locale_settings.dart';
import '../theme/label_overrides.dart';

/// Real translations, not machine-generated placeholders — covers the
/// screens a counselor looks at constantly (navigation, login, dashboard,
/// leads list, common actions). Screens not yet in this dictionary fall
/// back to their hardcoded English text rather than showing a broken key,
/// so nothing ever renders blank.
const Map<String, Map<String, String>> _translations = {
  // ---- Navigation ----
  'nav_dashboard': {'en': 'Dashboard', 'hi': 'डैशबोर्ड', 'ne': 'ड्यासबोर्ड'},
  'nav_leads': {'en': 'Leads', 'hi': 'लीड्स', 'ne': 'लिड्स'},
  'nav_followups': {'en': 'Follow-ups', 'hi': 'फॉलो-अप', 'ne': 'फलो-अप'},
  'nav_tasks': {'en': 'Tasks', 'hi': 'कार्य', 'ne': 'कार्यहरू'},
  'nav_more': {'en': 'More', 'hi': 'और', 'ne': 'थप'},

  // ---- Login / Register ----
  'app_tagline': {'en': 'Powered by VertiCore MetaOS', 'hi': 'VertiCore MetaOS द्वारा संचालित', 'ne': 'VertiCore MetaOS द्वारा संचालित'},
  'welcome_back': {'en': 'Welcome back', 'hi': 'वापसी पर स्वागत है', 'ne': 'फेरि स्वागत छ'},
  'login_subtitle': {'en': 'Log in to your consultancy workspace', 'hi': 'अपने कंसल्टेंसी वर्कस्पेस में लॉग इन करें', 'ne': 'आफ्नो कन्सल्टेन्सी वर्कस्पेसमा लगइन गर्नुहोस्'},
  'consultancy_id': {'en': 'Consultancy ID', 'hi': 'कंसल्टेंसी आईडी', 'ne': 'कन्सल्टेन्सी आईडी'},
  'email': {'en': 'Email', 'hi': 'ईमेल', 'ne': 'इमेल'},
  'password': {'en': 'Password', 'hi': 'पासवर्ड', 'ne': 'पासवर्ड'},
  'log_in': {'en': 'Log In', 'hi': 'लॉग इन करें', 'ne': 'लगइन गर्नुहोस्'},
  'create_account_prompt': {'en': 'New consultancy? Create an account', 'hi': 'नई कंसल्टेंसी? खाता बनाएं', 'ne': 'नयाँ कन्सल्टेन्सी? खाता बनाउनुहोस्'},

  // ---- Dashboard ----
  'today_glance': {'en': 'Today at a glance', 'hi': 'आज एक नज़र में', 'ne': 'आज एक नजरमा'},
  'total_leads': {'en': 'Total Leads', 'hi': 'कुल लीड्स', 'ne': 'कुल लिड्स'},
  'conversion': {'en': 'Conversion', 'hi': 'रूपांतरण', 'ne': 'रूपान्तरण'},
  'pending_followups': {'en': 'Follow-ups', 'hi': 'फॉलो-अप', 'ne': 'फलो-अप'},
  'overdue': {'en': 'Overdue', 'hi': 'बकाया', 'ne': 'बाँकी'},
  'pipeline_breakdown': {'en': 'Pipeline Breakdown', 'hi': 'पाइपलाइन विवरण', 'ne': 'पाइपलाइन विवरण'},
  'work_queue_title': {'en': "Today's Work Queue — AI-ranked leads", 'hi': 'आज की कार्य सूची — AI द्वारा क्रमबद्ध लीड्स', 'ne': 'आजको कार्य सूची — AI द्वारा क्रमबद्ध लिड्स'},

  // ---- Leads ----
  'add_lead': {'en': 'Add Lead', 'hi': 'लीड जोड़ें', 'ne': 'लिड थप्नुहोस्'},
  'search_leads': {'en': 'Search leads by name...', 'hi': 'नाम से लीड खोजें...', 'ne': 'नामद्वारा लिड खोज्नुहोस्...'},
  'full_name': {'en': 'Full Name', 'hi': 'पूरा नाम', 'ne': 'पूरा नाम'},
  'phone': {'en': 'Phone', 'hi': 'फ़ोन', 'ne': 'फोन'},
  'source': {'en': 'Source', 'hi': 'स्रोत', 'ne': 'स्रोत'},
  'notes': {'en': 'Notes', 'hi': 'टिप्पणियाँ', 'ne': 'टिप्पणीहरू'},
  'no_leads_yet': {'en': 'No leads yet', 'hi': 'अभी तक कोई लीड नहीं', 'ne': 'अहिलेसम्म कुनै लिड छैन'},

  // ---- Common actions ----
  'save': {'en': 'Save', 'hi': 'सहेजें', 'ne': 'सेभ गर्नुहोस्'},
  'cancel': {'en': 'Cancel', 'hi': 'रद्द करें', 'ne': 'रद्द गर्नुहोस्'},
  'delete': {'en': 'Delete', 'hi': 'हटाएं', 'ne': 'मेटाउनुहोस्'},
  'edit': {'en': 'Edit', 'hi': 'संपादित करें', 'ne': 'सम्पादन गर्नुहोस्'},
  'add': {'en': 'Add', 'hi': 'जोड़ें', 'ne': 'थप्नुहोस्'},
  'confirm': {'en': 'Confirm', 'hi': 'पुष्टि करें', 'ne': 'पुष्टि गर्नुहोस्'},
  'settings': {'en': 'Settings', 'hi': 'सेटिंग्स', 'ne': 'सेटिङहरू'},
  'log_out': {'en': 'Log out', 'hi': 'लॉग आउट', 'ne': 'लगआउट'},
};

/// Access via `context.tr('key')` — falls back to English, then to the
/// raw key itself, so a missing translation is visibly wrong rather than
/// silently blank.
extension Translate on BuildContext {
  String tr(String key) {
    // Theme Engine v3 -- a tenant's custom label override always wins
    // over the language-translation lookup below.
    final override = watch<LabelOverrides>()[key];
    if (override != null) return override;
    final lang = watch<LocaleSettings>().language.code;
    final entry = _translations[key];
    if (entry == null) return key;
    return entry[lang] ?? entry['en'] ?? key;
  }
}
