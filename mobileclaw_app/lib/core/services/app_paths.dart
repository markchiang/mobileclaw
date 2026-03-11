import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<Directory> getMobileClawAppRoot() async {
  final dir = await getApplicationSupportDirectory();
  final appRoot = Directory('${dir.path}/mobileclaw');
  await appRoot.create(recursive: true);
  return appRoot;
}

