import 'cbo.dart';
import 'class_length.dart';
import 'class_metric.dart';
import 'lcom4.dart';
import 'nom.dart';
import 'rfc.dart';
import 'wmc.dart';

const List<ClassMetric> defaultClassMetrics = [
  NumberOfMethods(),
  WeightedMethodsPerClass(),
  Lcom4(),
  CouplingBetweenObjects(),
  ResponseForClass(),
  ClassLength(),
];
