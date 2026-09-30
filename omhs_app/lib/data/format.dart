enum CholUnit { mgdl, mmoll }

enum CholCategory { desirable, borderline, high }

/// mg/dL -> mmol/L for cholesterol.
const double kMgdlPerMmoll = 38.67;

String formatChol(double mgdl, CholUnit unit) => unit == CholUnit.mgdl
    ? mgdl.round().toString()
    : (mgdl / kMgdlPerMmoll).toStringAsFixed(2);

String unitLabel(CholUnit unit) =>
    unit == CholUnit.mgdl ? 'mg/dL' : 'mmol/L';

/// Total-cholesterol cut-offs in mg/dL. These depend on age but not sex
/// (sex changes the HDL cut-offs, which the device doesn't measure).
class CholRanges {
  const CholRanges(this.borderlineFrom, this.highFrom, this.label);

  final double borderlineFrom;
  final double highFrom;
  final String label;
}

/// Adults 20+ (NCEP ATP III).
const kAdultRanges = CholRanges(200, 240, 'Adult ranges');

/// Under 20 (NHLBI 2011 pediatric guidelines).
const kYouthRanges = CholRanges(170, 200, 'Under-20 ranges');

/// Adult ranges when the age is unknown.
CholRanges rangesFor(int? age) =>
    age != null && age < 20 ? kYouthRanges : kAdultRanges;

CholCategory categorize(double mgdl, {int? age}) {
  final r = rangesFor(age);
  if (mgdl < r.borderlineFrom) return CholCategory.desirable;
  if (mgdl < r.highFrom) return CholCategory.borderline;
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
