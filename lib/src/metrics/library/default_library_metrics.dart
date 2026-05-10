import 'coupling.dart';
import 'library_metric.dart';

const List<LibraryMetric> defaultLibraryMetrics = [
  EfferentCoupling(),
  AfferentCoupling(),
  Instability(),
];
