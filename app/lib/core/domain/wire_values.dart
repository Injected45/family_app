/// The Arabic values the API and database actually store.
///
/// These are NOT display strings — they are enum values that travel over the
/// wire, chosen to match `index.html` exactly so the migration could import the
/// association's existing records untouched.
///
/// This is the ONLY file allowed to contain them. Risk R7 in the migration plan
/// is that a spelling change in one screen silently breaks a comparison in
/// another; keeping every literal here means such a change is a one-line edit
/// with a compiler to catch the rest. `tool/rtl_lint.dart` exempts this file
/// and flags Arabic literals anywhere else in widget code.
///
/// Anything the user READS still comes from `lib/l10n/app_ar.arb`. Where a wire
/// value also happens to be shown — a receivable's status, say — the API sends
/// a display label alongside it rather than the screen reusing the enum.
library;

abstract final class ReceivableStatusWire {
  static const String unpaid = 'غير مسدد';
  static const String partiallyPaid = 'مسدد جزئياً';
  static const String fullyPaid = 'مسدد بالكامل';
  static const String cancelled = 'ملغي';
}

abstract final class MembershipStatusWire {
  static const String active = 'نشط';
  static const String suspended = 'موقوف';
  static const String deceased = 'متوفى';
}

abstract final class PaymentMethodWire {
  static const String cash = 'نقداً';
  static const String bankTransfer = 'تحويل مصرفي';
}

abstract final class MemberRelationWire {
  static const String father = 'أب';
  static const String son = 'ابن';
}

abstract final class MemberDefaults {
  /// index.html:496 defaults every member to Libyan and to active. These are
  /// stored values, not display text.
  static const String nationality = 'ليبي';
  static const String status = MembershipStatusWire.active;
}

abstract final class ArabicPunctuation {
  /// U+060C, the Arabic comma. Joining a list with a Latin ',' looks wrong in
  /// Arabic text and is what the prototype uses throughout.
  static const String listSeparator = '، ';
}
