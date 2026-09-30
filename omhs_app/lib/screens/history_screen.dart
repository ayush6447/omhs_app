import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/format.dart';
import '../data/reading.dart';
import '../data/readings_store.dart';
import '../data/user_profile.dart';
import '../theme/app_colors.dart';
import '../theme/app_settings.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

enum _Filter { all, desirable, borderline, high, flagged }

const _filterLabels = {
  _Filter.all: 'All',
  _Filter.desirable: 'Desirable',
  _Filter.borderline: 'Borderline',
  _Filter.high: 'High',
  _Filter.flagged: 'Flagged',
};

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _search = TextEditingController();
  String _query = '';
  _Filter _filter = _Filter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Reading r, UserProfile profile) {
    final cat = categorize(r.totalChol, age: profile.ageAt(r.time));
    final ok = switch (_filter) {
      _Filter.all => true,
      _Filter.flagged => r.flagged,
      _Filter.desirable => cat == CholCategory.desirable,
      _Filter.borderline => cat == CholCategory.borderline,
      _Filter.high => cat == CholCategory.high,
    };
    if (!ok) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return (r.note ?? '').toLowerCase().contains(q) ||
        formatWhen(r.time).toLowerCase().contains(q) ||
        r.totalChol.round().toString().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final store = context.watch<ReadingsStore>();
    final unit = context.watch<AppSettings>().unit;
    final profile = context.watch<ProfileStore>().profile;
    final list = store.items.where((r) => _matches(r, profile)).toList();

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: (v) => setState(() => _query = v),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: c.text,
                        ),
                        decoration: InputDecoration.collapsed(
                          hintText: 'Search notes, dates, values',
                          hintStyle: TextStyle(fontSize: 18, color: c.muted),
                        ),
                      ),
                    ),
                    if (_query.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear',
                        icon: Icon(Icons.close_rounded, color: c.muted),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Icon(Icons.search_rounded, color: c.muted),
                      ),
                  ],
                ),
                Container(height: 1.5, color: c.text),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final f in _Filter.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 18),
                          child: GestureDetector(
                            onTap: () => setState(() => _filter = f),
                            child: Text(
                              _filterLabels[f]!,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: f == _filter
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: f == _filter ? c.primary : c.muted,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      store.items.isEmpty
                          ? 'No readings yet'
                          : 'Nothing matches',
                      style: TextStyle(color: c.muted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 120),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, i) => _ReadingCard(
                      reading: list[i],
                      unit: unit,
                      onTap: () => _showDetail(context, list[i].id),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context, String id) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReadingSheet(id: id),
    );
  }
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({
    required this.reading,
    required this.unit,
    required this.onTap,
  });

  final Reading reading;
  final CholUnit unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final r = reading;
    return Material(
      color: c.surfaceAlt,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.water_drop_outlined, color: c.text, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              formatChol(r.totalChol, unit),
                              style: mono(20, color: c.primary),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              unitLabel(unit),
                              style: mono(12,
                                  weight: FontWeight.w400, color: c.primary),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                color: c.primary, size: 22),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatWhen(r.time),
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  if (r.flagged)
                    Icon(Icons.flag_rounded, color: c.danger, size: 20),
                ],
              ),
              if ((r.note ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    r.note!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              KeyValueRow(
                'Signal quality',
                PillBadge('${(r.quality * 100).round()} / 100',
                    bg: c.badge, fg: c.onBadge),
              ),
              Divider(height: 20, color: c.divider),
              KeyValueRow(
                'Category',
                CategoryBadge(categorize(r.totalChol,
                    age: context
                        .watch<ProfileStore>()
                        .profile
                        .ageAt(r.time))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadingSheet extends StatelessWidget {
  const _ReadingSheet({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    final store = context.watch<ReadingsStore>();
    final unit = context.watch<AppSettings>().unit;
    final r = store.byId(id);
    if (r == null) return const SizedBox(height: 120);

    Widget value(String v) =>
        PillBadge(v, bg: c.badge, fg: c.onBadge);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(formatWhen(r.time),
                style: TextStyle(fontSize: 13, color: c.muted)),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatChol(r.totalChol, unit),
                    style: mono(40, color: c.primary)),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(unitLabel(unit),
                      style: mono(14,
                          weight: FontWeight.w400, color: c.primary)),
                ),
                const Spacer(),
                CategoryBadge(categorize(r.totalChol,
                    age: context
                        .watch<ProfileStore>()
                        .profile
                        .ageAt(r.time))),
              ],
            ),
            const SizedBox(height: 18),
            SoftCard(
              child: Column(
                children: [
                  KeyValueRow('Signal quality',
                      value('${(r.quality * 100).round()} / 100')),
                  Divider(height: 20, color: c.divider),
                  KeyValueRow('LED 1200 nm',
                      value('${r.ch1mA.toStringAsFixed(1)} mA')),
                  Divider(height: 20, color: c.divider),
                  KeyValueRow('LED 1720 nm',
                      value('${r.ch2mA.toStringAsFixed(1)} mA')),
                  Divider(height: 20, color: c.divider),
                  KeyValueRow('Peak cuff pressure',
                      value('${r.peakPressure.round()} mmHg')),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              (r.note ?? '').isEmpty ? 'No note' : r.note!,
              style: TextStyle(fontSize: 13, color: c.text),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: r.flagged ? 'Unflag' : 'Flag',
                    icon: r.flagged
                        ? Icons.outlined_flag_rounded
                        : Icons.flag_rounded,
                    expand: true,
                    onPressed: () =>
                        context.read<ReadingsStore>().toggleFlag(r.id),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PillButton(
                    label: 'Edit note',
                    icon: Icons.edit_outlined,
                    variant: PillVariant.outline,
                    expand: true,
                    onPressed: () async {
                      final store = context.read<ReadingsStore>();
                      final note = await showDialog<String>(
                        context: context,
                        builder: (_) => _NoteDialog(initial: r.note ?? ''),
                      );
                      if (note != null) store.setNote(r.id, note.trim());
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.initial});

  final String initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omhs;
    return AlertDialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text('Note', style: mono(18, color: c.text)),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLines: 3,
        minLines: 1,
        style: TextStyle(color: c.text),
        decoration: InputDecoration(
          hintText: 'e.g. fasting, cold hands, subject 04',
          hintStyle: TextStyle(color: c.muted),
          filled: true,
          fillColor: c.surfaceAlt,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
