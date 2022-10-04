import 'dart:ffi';
import 'dart:io';

import 'bridge_generated.dart';

final sudachidylib = Platform.isIOS
    ? DynamicLibrary.process()
    : DynamicLibrary.open("libsudachi_ffi.so");
final sudachiAPI = SudachiFfiImpl(sudachidylib);
