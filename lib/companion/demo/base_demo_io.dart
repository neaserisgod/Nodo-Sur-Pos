import 'package:drift/native.dart';

import '../../data/database.dart';

Future<AppDatabase> abrirBaseDemo() async => AppDatabase(NativeDatabase.memory());
