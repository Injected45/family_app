import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../finance/presentation/payment_sheet.dart';
import '../domain/models.dart';
import 'providers.dart';

Color eligibilityTone(EligibilityKey key) => switch (key) {
  EligibilityKey.eligible => AppColors.info,
  EligibilityKey.soon => AppColors.warning,
  EligibilityKey.under => AppColors.muted,
  EligibilityKey.inactive => AppColors.muted,
};

class FamilyDetailScreen extends ConsumerWidget {
  const FamilyDetailScreen({required this.familyId, super.key});

  final int familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AsyncValue<FamilyDetail> detail = ref.watch(
      familyDetailProvider(familyId),
    );
    final String currency =
        ref.watch(settingsProvider).valueOrNull?.currency ?? '';

    final AppRole role =
        ref.watch(authControllerProvider).user?.role ?? AppRole.viewer;

    return AppScaffold(
      title: l.navFamilies,
      currentRoute: AppRoutes.families,
      actions: <Widget>[
        if (role.atLeast(AppRole.financeManager))
          IconButton(
            tooltip: l.editFamily,
            onPressed: () => context.go('${AppRoutes.families}/$familyId/edit'),
            icon: const Icon(Icons.edit_outlined),
          ),
      ],
      body: AsyncView<FamilyDetail>(
        value: detail,
        onRetry: () => ref.invalidate(familyDetailProvider(familyId)),
        builder: (FamilyDetail family) => ListView(
          padding: screenPadding(context),
          children: <Widget>[
            Text(
              family.father?.fullName ?? '',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${family.familyCode} • ${family.father?.nationalId ?? ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),

            _SummaryCard(family: family, currency: currency),
            const SizedBox(height: AppSpacing.lg),

            if (ref
                    .watch(authControllerProvider)
                    .user
                    ?.role
                    .atLeast(AppRole.treasurer) ??
                false) ...<Widget>[
              // Disabled rather than hidden when nothing is owed, with the
              // reason shown — index.html:548 does the same, and a vanishing
              // button reads as a bug.
              FilledButton.icon(
                onPressed: (double.tryParse(family.debt) ?? 0) > 0
                    ? () async {
                        final bool saved = await showPaymentSheet(
                          context,
                          familyId: family.id,
                        );
                        if (saved) {
                          ref.invalidate(familyDetailProvider(family.id));
                        }
                      }
                    : null,
                icon: const Icon(Icons.add_card, size: 18),
                label: Text(l.registerPayment),
              ),
              if ((double.tryParse(family.debt) ?? 0) <= 0) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l.noDebtForFamily,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
            ],

            if (family.father != null) ...<Widget>[
              _SectionCard(
                title: l.fatherData,
                child: Wrap(
                  spacing: AppSpacing.xl,
                  runSpacing: AppSpacing.lg,
                  children: <Widget>[
                    LabelledValue(label: l.phone, value: family.father!.phone),
                    LabelledValue(
                      label: l.subscriptionNo,
                      value: family.father!.subscriptionNo,
                    ),
                    LabelledValue(
                      label: l.dateOfBirth,
                      value: family.father!.dob,
                    ),
                    LabelledValue(
                      label: l.nationality,
                      value: family.father!.nationality,
                    ),
                    LabelledValue(
                      label: l.workplace,
                      value: family.father!.workplace,
                    ),
                    LabelledValue(
                      label: l.registeredAt,
                      value: family.father!.registeredAt,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            _SectionCard(
              title: l.sonsSection,
              // Cards, not a table: the prototype's eight-column sons table
              // (index.html:560) cannot be read on a phone.
              child: Column(
                children: <Widget>[
                  for (final MemberView son in family.sons)
                    _SonTile(son: son, currency: currency),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.family, required this.currency});

  final FamilyDetail family;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final bool owes = (double.tryParse(family.debt) ?? 0) > 0;

    // This is the one hero surface on the screen, so it is the one that earns a
    // blur. The mint-to-teal LinearGradient it used to carry is gone: Flat
    // Design has no gradients, and a frosted pane over the vibrant field now
    // does the job the gradient was doing — separating the summary from the
    // detail below it.
    return GlassSurface(
      blurred: true,
      lifted: true,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.summarize_outlined,
                  size: 18,
                  color: AppColors.brandDeep,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  l.familySummary,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          StatCardGrid(
            children: <Widget>[
              _Kpi(label: l.sonsCount, value: '${family.sonsCount}'),
              _Kpi(label: l.eligibleCount, value: '${family.eligibleCount}'),
              _Kpi(label: l.soonCount, value: '${family.soonCount}'),
              _Kpi(
                label: l.monthlyExpected,
                value: formatMoney(family.monthlyExpected),
              ),
              _Kpi(
                label: l.debt,
                value: formatMoney(family.debt),
                tone: owes ? AppColors.danger : AppColors.success,
              ),
              _Kpi(label: l.totalPaid, value: formatMoney(family.paid)),
            ],
          ),
          if (currency.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(currency, style: Theme.of(context).textTheme.labelSmall),
          ],
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    // A recessed well, not another pane: these sit INSIDE the summary glass, and
    // glass on glass has no readable boundary.
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: GlassColors.well,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: GlassColors.wellEdge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: tone ?? AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(title: title, child: child);
  }
}

class _SonTile extends StatelessWidget {
  const _SonTile({required this.son, required this.currency});

  final MemberView son;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    return GlassCard(
      margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  son.fullName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StatusBadge(
                label: son.eligibilityLabel,
                tone: eligibilityTone(son.eligibility),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.md,
            children: <Widget>[
              LabelledValue(label: l.nationalId, value: son.nationalId),
              LabelledValue(
                label: l.age,
                value: son.age == null ? '' : l.ageYears(son.age!),
              ),
              LabelledValue(label: l.dateOfBirth, value: son.dob),
              LabelledValue(label: l.workplace, value: son.workplace),
              LabelledValue(
                label: l.currentValue,
                value: son.currentFee == null
                    ? '—'
                    : '${formatMoney(son.currentFee)} $currency',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
