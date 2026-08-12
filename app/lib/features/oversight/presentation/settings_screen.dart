import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../l10n/app_localizations.dart';
import '../../directory/presentation/providers.dart' as directory;
import '../domain/models.dart';
import 'providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AsyncValue<EditableSettings> settings = ref.watch(
      editableSettingsProvider,
    );

    return AppScaffold(
      title: l.navSettings,
      currentRoute: AppRoutes.settings,
      body: AsyncView<EditableSettings>(
        value: settings,
        onRetry: () => ref.invalidate(editableSettingsProvider),
        // Keyed so the form rebuilds from scratch after a save.
        builder: (EditableSettings data) => _SettingsForm(
          key: ValueKey<String>(data.toJson().toString()),
          initial: data,
        ),
      ),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.initial, super.key});

  final EditableSettings initial;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  late final Map<String, TextEditingController> _fields =
      <String, TextEditingController>{
        'associationName': TextEditingController(
          text: widget.initial.associationName,
        ),
        'currency': TextEditingController(text: widget.initial.currency),
        'fatherFee': TextEditingController(text: widget.initial.fatherFee),
        'sonFee': TextEditingController(text: widget.initial.sonFee),
        'eligibilityAge': TextEditingController(
          text: '${widget.initial.eligibilityAge}',
        ),
        'warningMonths': TextEditingController(
          text: '${widget.initial.warningMonths}',
        ),
        'systemStart': TextEditingController(text: widget.initial.systemStart),
        'treasurerName': TextEditingController(
          text: widget.initial.treasurer.name,
        ),
        'treasurerNationalId': TextEditingController(
          text: widget.initial.treasurer.nationalId,
        ),
        'treasurerPhone': TextEditingController(
          text: widget.initial.treasurer.phone,
        ),
        'financeName': TextEditingController(
          text: widget.initial.financeManager.name,
        ),
        'financeNationalId': TextEditingController(
          text: widget.initial.financeManager.nationalId,
        ),
        'financePhone': TextEditingController(
          text: widget.initial.financeManager.phone,
        ),
      };

  bool _saving = false;

  @override
  void dispose() {
    for (final TextEditingController controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _text(String key) => _fields[key]!.text.trim();

  EditableSettings _collect() => EditableSettings(
    associationName: _text('associationName'),
    currency: _text('currency'),
    fatherFee: _text('fatherFee'),
    sonFee: _text('sonFee'),
    eligibilityAge: int.tryParse(_text('eligibilityAge')) ?? 0,
    warningMonths: int.tryParse(_text('warningMonths')) ?? 0,
    systemStart: _text('systemStart'),
    autoClosePreviousMonths: widget.initial.autoClosePreviousMonths,
    treasurer: OfficialInput(
      name: _text('treasurerName'),
      nationalId: _text('treasurerNationalId'),
      phone: _text('treasurerPhone'),
    ),
    financeManager: OfficialInput(
      name: _text('financeName'),
      nationalId: _text('financeNationalId'),
      phone: _text('financePhone'),
    ),
  );

  Future<void> _save(L l) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final EditableSettings next = _collect();

    // These values are financially load-bearing, so the change is restated
    // before it is written rather than saved silently.
    final List<String> preview = <String>[
      if (next.fatherFee != widget.initial.fatherFee)
        '${l.fatherFeeField}: ${widget.initial.fatherFee} → ${next.fatherFee}',
      if (next.sonFee != widget.initial.sonFee)
        '${l.sonFeeField}: ${widget.initial.sonFee} → ${next.sonFee}',
      if (next.eligibilityAge != widget.initial.eligibilityAge)
        '${l.eligibilityAgeField}: ${widget.initial.eligibilityAge} → ${next.eligibilityAge}',
      if (next.warningMonths != widget.initial.warningMonths)
        '${l.warningMonthsField}: ${widget.initial.warningMonths} → ${next.warningMonths}',
      if (next.systemStart != widget.initial.systemStart)
        '${l.systemStartField}: ${widget.initial.systemStart} → ${next.systemStart}',
    ];

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => GlassDialog(
        title: Text(l.confirmChangesTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l.settingsWarning,
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.md),
            if (preview.isEmpty)
              Text(l.noChanges, style: const TextStyle(color: AppColors.muted))
            else
              for (final String line in preview)
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: 4),
                  child: Text(line, style: const TextStyle(fontSize: 13)),
                ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.save),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await ref.read(oversightRepositoryProvider).saveSettings(next);
      ref.invalidate(editableSettingsProvider);
      ref.invalidate(directory.settingsProvider);
      ref.invalidate(directory.officialsProvider);
      ref.invalidate(auditProvider(''));
      messenger.showSnackBar(SnackBar(content: Text(l.settingsSaved)));
    } on ApiException catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeApiFailure(l, failure))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return ListView(
      padding: screenPadding(context),
      children: <Widget>[
        Text(
          l.settingsIntro,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.warningSoft,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Text(
            l.settingsWarning,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF854D0E),
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        _Section(title: l.generalSection),
        _Field(
          label: l.associationNameField,
          controller: _fields['associationName']!,
        ),
        _Field(label: l.currencyField, controller: _fields['currency']!),
        _Field(
          label: l.fatherFeeField,
          controller: _fields['fatherFee']!,
          money: true,
        ),
        _Field(
          label: l.sonFeeField,
          controller: _fields['sonFee']!,
          money: true,
        ),
        _Field(
          label: l.eligibilityAgeField,
          controller: _fields['eligibilityAge']!,
          integer: true,
        ),
        _Field(
          label: l.warningMonthsField,
          controller: _fields['warningMonths']!,
          integer: true,
        ),
        _Field(label: l.systemStartField, controller: _fields['systemStart']!),

        const SizedBox(height: AppSpacing.lg),
        _Section(title: l.treasurerSection),
        _Field(label: l.fullNameField, controller: _fields['treasurerName']!),
        _Field(
          label: l.nationalId,
          controller: _fields['treasurerNationalId']!,
        ),
        _Field(label: l.phone, controller: _fields['treasurerPhone']!),

        const SizedBox(height: AppSpacing.lg),
        _Section(title: l.financeManagerSection),
        _Field(label: l.fullNameField, controller: _fields['financeName']!),
        _Field(label: l.nationalId, controller: _fields['financeNationalId']!),
        _Field(label: l.phone, controller: _fields['financePhone']!),

        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          onPressed: _saving ? null : () => _save(l),
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.onFill,
                  ),
                )
              : const Icon(Icons.save_outlined, size: 18),
          label: Text(l.save),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.money = false,
    this.integer = false,
  });

  final String label;
  final TextEditingController controller;
  final bool money;
  final bool integer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
      child: TextField(
        controller: controller,
        keyboardType: money || integer
            ? TextInputType.numberWithOptions(decimal: money)
            : TextInputType.text,
        inputFormatters: <TextInputFormatter>[
          if (money)
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          if (integer) FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }
}
