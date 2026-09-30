enum CholUnit { mgdl, mmoll }

enum CholCategory { desirable, borderline, high }

/// mg/dL -> mmol/L for cholesterol.
const double kMgdlPerMmoll = 38.67;

String formatChol(double mgdl, CholUnit unit) => unit == CholUnit.mgdl
    ? mgdl.round().toString()
    : (mgdl / kMgdlPerMmoll).toStringAsFixed(2);

String unitLabel(CholUnit unit) =>
    unit == CholUnit.mgdl ? 'mg/dL' : 'mmol/L';

/// Standard adult total-cholesterol bands (NCEP ATP III).
CholCategory categorize(double mgdl) {
  if (mgdl < 200) return CholCategory.desirable;
  if (mgdl < 240) return CholCategory.borderline;
  return CholCategory.high;
}

String categoryLabel(CholCategory c) => switch (c) {
      CholCategory.desirable => 'Desirable',
      CholCategory.borderline => 'Borderline',
      CholCategory.high => 'High',
    };

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// e.g. "Tue 29 Sep · 09:14"
String formatWhen(DateTime t) =>
    '${_weekdays[t.weekday - 1]} ${t.day} ${_months[t.month - 1]} · '
    '${_two(t.hour)}:${_two(t.minute)}';

/// e.g. "29 Sep 1991"
String formatDate(DateTime t) => '${t.day} ${_months[t.month - 1]} ${t.year}';
