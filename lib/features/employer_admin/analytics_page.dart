import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/rules/parameter_catalog.dart';
import 'billing_page.dart';
import 'employer_common.dart';

/// Shared, prominent disclaimer for indicative carbon credits.
const carbonCreditDisclaimer =
    'Indicative only — not issued carbon credits. Real credits require project eligibility checks, '
    'verified measurement (MRV) and certification under a recognised standard (e.g. Verra or Gold Standard).';

String fmtKg(double kg) => kg.abs() >= 1000
    ? '${(kg / 1000).toStringAsFixed(2)} t'
    : '${kg.toStringAsFixed(1)} kg';

/// Employer analytics: emissions avoided, time and money saved by pooled,
/// optimized trips versus a single-occupancy baseline.
class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({super.key});

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage> {
  int _days = 7;
  DateTimeRange? _custom;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(dataProvider);
    final employer = data.primaryEmployer;
    final range = _days == 0 && _custom != null
        ? DateRange(_custom!.start, _custom!.end)
        : DateRange.lastDays(data.today, _days == 0 ? 7 : _days);
    final s = ref.read(servicesProvider).analytics.summary(employer.id, range);
    final policy = s.policy;
    final cfg = data.optimizationConfigs.firstOrNull;
    double param(String k) => cfg == null
        ? ParameterCatalog.byKey(k)!.defaultValue
        : ParameterCatalog.value(cfg, k);
    final t = Theme.of(context).textTheme;
    String dayLabel(DateTime d) =>
        range.days <= 7 ? Fmt.weekday(d).split(',').first : '${d.day}';

    const header = [
      'Trip',
      'Date',
      'Riders',
      'Actual km',
      'Baseline km',
      'Distance estimated',
      'CO2 actual kg',
      'CO2 baseline kg',
      'CO2 avoided kg',
      'Cost ₹',
      'Baseline cost ₹',
      'Saved ₹',
      'Vehicle min',
      'Baseline min',
    ];
    List<List<Object?>> rows() => [
      for (final x in s.trips)
        [
          x.trip.tripCode,
          Fmt.date(x.trip.serviceDate),
          x.riders,
          x.actualKm.toStringAsFixed(1),
          x.baselineKm.toStringAsFixed(1),
          x.distanceEstimated ? 'yes' : 'no',
          x.actualCo2Kg.toStringAsFixed(2),
          x.baselineCo2Kg.toStringAsFixed(2),
          x.co2SavedKg.toStringAsFixed(2),
          x.actualCost.toStringAsFixed(2),
          x.baselineCost.toStringAsFixed(2),
          x.costSaved.toStringAsFixed(2),
          x.actualVehicleMinutes.toStringAsFixed(0),
          x.baselineVehicleMinutes.toStringAsFixed(0),
        ],
    ];

    return AdminPage(
      title: 'Analytics & Carbon',
      subtitle:
          '${Fmt.date(range.start)} – ${Fmt.date(range.end)} · completed ${employer.code} trips vs a single-occupancy baseline',
      actions: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            const ButtonSegment(value: 7, label: Text('7 days')),
            const ButtonSegment(value: 30, label: Text('30 days')),
            const ButtonSegment(value: 90, label: Text('90 days')),
            ButtonSegment(
              value: 0,
              label: Text(
                _days == 0 && _custom != null
                    ? '${Fmt.dateShort(_custom!.start)}–${Fmt.dateShort(_custom!.end)}'
                    : 'Custom',
              ),
            ),
          ],
          selected: {_days},
          onSelectionChanged: (sel) async {
            final v = sel.first;
            if (v == 0) {
              final r = await showDateRangePicker(
                context: context,
                firstDate: data.today.subtract(const Duration(days: 365)),
                lastDate: data.today,
                initialDateRange: _custom,
              );
              if (r == null) return;
              setState(() {
                _custom = r;
                _days = 0;
              });
            } else {
              setState(() => _days = v);
            }
          },
        ),
        OutlinedButton.icon(
          onPressed: s.trips.isEmpty
              ? null
              : () => exportCsv(
                  context,
                  ref,
                  'analytics_${employer.code}_${range.days}d.csv',
                  header,
                  rows(),
                ),
          icon: const Icon(Icons.download_outlined),
          label: const Text('Export CSV'),
        ),
      ],
      children: [
        MetricGrid(
          minTileWidth: 200,
          children: [
            MetricTile(
              key: const Key('kpi-co2'),
              label: 'CO₂ avoided',
              value: fmtKg(s.co2SavedKg),
              caption:
                  '${s.co2ReductionPct.toStringAsFixed(0)}% below baseline (${fmtKg(s.baselineCo2Kg)} → ${fmtKg(s.actualCo2Kg)})',
              icon: Icons.eco_outlined,
              tone: StatusTone.success,
            ),
            MetricTile(
              key: const Key('kpi-time'),
              label: 'Time saved',
              value: '${(s.minutesSaved / 60).toStringAsFixed(1)} vehicle-h',
              caption: 'Vehicle hours vs everyone driving alone',
              icon: Icons.timer_outlined,
              tone: StatusTone.info,
            ),
            MetricTile(
              key: const Key('kpi-cost'),
              label: 'Financial savings',
              value: Fmt.inr0(s.costSaved),
              caption:
                  'Baseline ${Fmt.inr0(s.baselineCost)} vs actual ${Fmt.inr0(s.actualCost)}',
              icon: Icons.savings_outlined,
              tone: StatusTone.teal,
            ),
            MetricTile(
              key: const Key('kpi-riders'),
              label: 'Riders',
              value: '${s.riders}',
              caption:
                  'On ${s.trips.length} completed trip${s.trips.length == 1 ? '' : 's'}',
              icon: Icons.groups_outlined,
            ),
            MetricTile(
              key: const Key('kpi-km'),
              label: 'Vehicle km',
              value: Fmt.km(s.vehicleKm),
              caption: 'vs ${Fmt.km(s.baselineKm)} baseline',
              icon: Icons.straighten_rounded,
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        ResponsiveColumns(
          left: PanelCard(
            title: 'CO₂ avoided by day',
            subtitle: 'kg, by trip service date',
            child: SimpleBarChart(
              values: [
                for (final d in s.co2ByDay()) (dayLabel(d.day), d.value),
              ],
              color: AppColors.success,
              format: (v) => v.toStringAsFixed(1),
              emptyMessage: 'No completed trips in this period.',
            ),
          ),
          right: PanelCard(
            title: 'Carbon credits (indicative)',
            subtitle:
                'At the fleet policy price of ${Fmt.inr0(policy.carbonCreditPricePerTonne)} per tonne CO₂e',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${s.creditTonnes.toStringAsFixed(3)} tCO₂e',
                  key: const Key('credit-tonnes'),
                  style: t.headlineSmall!.copyWith(
                    fontFeatures: AppText.tabular,
                  ),
                ),
                Text(
                  'Indicative value ${Fmt.inr(s.indicativeCreditValue)}',
                  key: const Key('credit-value'),
                  style: AppText.secondary(context),
                ),
                const SizedBox(height: AppSpace.sm),
                const InlineBanner(
                  key: Key('credit-disclaimer'),
                  tone: StatusTone.warning,
                  icon: Icons.gpp_maybe_outlined,
                  title: 'Not issued credits',
                  message: carbonCreditDisclaimer,
                ),
              ],
            ),
          ),
        ),
        if (s.estimatedDistanceTrips > 0) ...[
          const SizedBox(height: AppSpace.md),
          InlineBanner(
            tone: StatusTone.info,
            title:
                '${s.estimatedDistanceTrips} trip${s.estimatedDistanceTrips == 1 ? ' uses' : 's use'} an estimated distance',
            message:
                'No actual odometer distance was recorded, so the planned route distance is used for analytics only (never for billing).',
          ),
        ],
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: 'Per-trip savings',
          subtitle:
              '${s.trips.length} completed trip${s.trips.length == 1 ? '' : 's'}',
          child: AdaptiveTable<TripSavings>(
            rows: s.trips,
            breakpoint: 820,
            onRowTap: (x) => context.go(EmployerPaths.trip(x.trip.id)),
            empty: const EmptyState(
              icon: Icons.insights_outlined,
              title: 'No completed trips',
              message: 'Savings are calculated once trips are completed.',
              compact: true,
            ),
            columns: [
              TableCol(
                'Trip',
                (x) => Text(
                  x.trip.tripCode,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TableCol(
                'Distance source',
                (x) => x.distanceEstimated
                    ? const StatusBadge(
                        'Distance estimated',
                        tone: StatusTone.warning,
                        dense: true,
                      )
                    : const StatusBadge(
                        'Actual distance',
                        tone: StatusTone.success,
                        dense: true,
                      ),
                flex: 2,
              ),
              TableCol('Riders', (x) => Text('${x.riders}'), numeric: true),
              TableCol(
                'Actual km',
                (x) => Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(x.actualKm.toStringAsFixed(1)),
                    if (x.distanceEstimated) ...[
                      const SizedBox(width: 4),
                      const Tooltip(
                        message: 'Distance estimated (no actual reading)',
                        child: Icon(
                          Icons.info_outline_rounded,
                          size: 14,
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                  ],
                ),
                numeric: true,
              ),
              TableCol(
                'Baseline km',
                (x) => Text(x.baselineKm.toStringAsFixed(1)),
                numeric: true,
              ),
              TableCol(
                'CO₂ actual / baseline',
                (x) => Text(
                  '${x.actualCo2Kg.toStringAsFixed(1)} / ${x.baselineCo2Kg.toStringAsFixed(1)} kg',
                ),
                numeric: true,
                flex: 2,
              ),
              TableCol(
                'Cost / baseline',
                (x) => Text(
                  '${Fmt.inr0(x.actualCost)} / ${Fmt.inr0(x.baselineCost)}',
                ),
                numeric: true,
                flex: 2,
              ),
            ],
            mobileCard: (x) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${x.trip.tripCode} · ${x.riders} riders',
                        style: t.titleSmall,
                      ),
                    ),
                    if (x.distanceEstimated)
                      const StatusBadge(
                        'Distance estimated',
                        tone: StatusTone.warning,
                        dense: true,
                      ),
                  ],
                ),
                Text(
                  '${x.actualKm.toStringAsFixed(1)} km vs ${x.baselineKm.toStringAsFixed(1)} km · CO₂ ${x.actualCo2Kg.toStringAsFixed(1)} vs ${x.baselineCo2Kg.toStringAsFixed(1)} kg · ${Fmt.inr0(x.actualCost)} vs ${Fmt.inr0(x.baselineCost)}',
                  style: AppText.muted(context),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        PanelCard(
          title: 'Methodology',
          subtitle:
              'Transparent, deterministic demo calculation from local records',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final line in [
                'Baseline: every rider travels alone, directly from their pickup point to their office, in a typical single-occupancy ICE car.',
                'Baseline emissions: ${policy.baselineCo2GramsPerKm.toStringAsFixed(0)} g CO₂/km · baseline speed ${policy.baselineSpeedKmh.toStringAsFixed(0)} km/h · baseline cost ${Fmt.inr(policy.baselineCostPerKm)}/km (fleet policy).',
                'Actual emissions use the assigned vehicle: EV ${param('ev_co2_g_per_km').toStringAsFixed(0)} g/km (grid factor), ICE ${param('ice_co2_g_per_km').toStringAsFixed(0)} g/km, hybrid = average (parameter catalog).',
                'Actual distance is the recorded trip distance; if missing, the planned route distance is used and the trip is flagged "distance estimated".',
                'Actual cost is the trip\'s billing line where it exists, otherwise distance × the company rate.',
                'Only completed trips with at least one rider are counted. Carbon credit tonnes = max(0, CO₂ avoided) ÷ 1000.',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 7, right: 8),
                        child: Icon(
                          Icons.circle,
                          size: 5,
                          color: AppColors.textMuted,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          line,
                          style: t.bodySmall!.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
