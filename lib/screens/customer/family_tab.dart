import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repository.dart';
import '../../l10n/strings.dart';
import '../../models/garment_spec.dart';
import '../../models/measurement_set.dart';
import '../../state/session.dart';
import '../../theme/theme.dart';
import '../../util/format.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/common.dart';
import '../../widgets/live.dart';
import 'measurement_editor_screen.dart';

/// Saved sizes for everyone the customer orders for.
class FamilyTab extends StatefulWidget {
  const FamilyTab({super.key});

  @override
  State<FamilyTab> createState() => _FamilyTabState();
}

class _FamilyTabState extends State<FamilyTab> {
  List<MeasurementSet>? _sets;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = context.read<Session>().user!.id;
    try {
      final sets = await context.read<Repository>().listMeasurementSets(uid);
      if (mounted) {
        setState(() {
          _sets = sets;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _open([MeasurementSet? person]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => MeasurementEditorScreen(existing: person)),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final unit = context.watch<Session>().unit;
    Widget body;
    if (_sets == null && _error != null) {
      body = ErrorView(error: _error!, onRetry: _load);
    } else if (_sets == null) {
      body = const SkeletonList();
    } else if (_sets!.isEmpty) {
      body = EmptyState(
        icon: Icons.straighten_rounded,
        title: context.tr('family.emptyTitle'),
        body: context.tr('family.emptyBody'),
        action: FilledButton(onPressed: () => _open(), child: Text(context.tr('family.add'))),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(context.tr('family.intro'), style: const TextStyle(color: Palette.muted, height: 1.5)),
            const SizedBox(height: 14),
            for (final s in _sets!)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Panel(
                  onTap: () => _open(s),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: Palette.goldSoft, shape: BoxShape.circle),
                        child: Text(
                          GarmentSpec.sizeFor(s.measurements.chest),
                          style: monoStyle(13, color: Palette.goldInk, weight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                            const SizedBox(height: 2),
                            Text(
                              '${context.tr('relation.${s.relation}')} · '
                              '${context.tr('m.height')} ${formatLength(s.measurements.height, unit)} · '
                              '${context.tr('m.chest')} ${formatLength(s.measurements.chest, unit)}',
                              style: const TextStyle(color: Palette.muted, fontSize: 12.5),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: Palette.chalk),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () => _open(),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: Text(context.tr('family.add')),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(leading: const DrawerMenuButton(), title: Text(context.tr('tab.family'))),
      body: body,
    );
  }
}
