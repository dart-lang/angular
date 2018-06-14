// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:build/build.dart';

// This file lives in environments where we don't use sass_builder.
// This builder is used with the external build process (build_runner), but
// there are environments (Bazel) where it is not available (or used).
//
import 'package:sass_builder/sass_builder.dart' as sass;

Builder scssBuilder(BuilderOptions options) =>
    // See ignore above.
    sass.SassBuilder(outputExtension: '.scss.css');
