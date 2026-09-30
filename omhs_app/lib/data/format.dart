enum CholUnit { mgdl, mmoll }

/// Height and weight display. Values are always stored in cm and kg.
enum BodyUnits { metric, imperial }

const double kCmPerInch = 2.54;
const double kKgPerLb = 0.45359237;

/// e.g. "175 cm" or "5 ft 9 in"
String formatHeight(double cm, BodyUnits u) {
  if (u == BodyUnits.metric) return '${cm.round()} cm';
  final inches = (cm / kCmPerInch).round();
  return '${inches ~/ 12} ft ${inches % 12} in';
}

/// e.g. "70.5 kg" or "155 lb"
String formatWeight(double kg, BodyUnits u) => u == BodyUnits.metric
    ? '${kg.toStringAsFixed(kg == kg.roundToDouble() ? 0 : 1)} kg'
    : '${(kg / kKgPerLb).round()} lb';

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

/// e.g. "29 Sep"
String formatShortDate(DateTime t) => '${t.day} ${_months[t.month - 1]}';
