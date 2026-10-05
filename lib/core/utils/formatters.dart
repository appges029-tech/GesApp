import 'package:intl/intl.dart';

String formatXaf(num value) => '${NumberFormat.decimalPattern('fr_FR').format(value)} FCFA';
