import 'class_length.dart';
import 'class_metric.dart';
import 'dit.dart';
import 'lcom4.dart';
import 'noc.dart';
import 'nom.dart';
import 'wmc.dart';

const List<ClassMetric> defaultClassMetrics = [
  NumberOfMethods(),
  WeightedMethodsPerClass(),
  Lcom4(),
  DepthOfInheritanceTree(),
  NumberOfChildren(),
  ClassLength(),
];
