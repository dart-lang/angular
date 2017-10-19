// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(const ['codegen'])
@TestOn('browser')
import 'dart:async';
import 'package:test/test.dart';
import 'package:angular/angular.dart';
import 'package:angular_test/angular_test.dart';

@AngularEntrypoint()
void main() {
  tearDown(disposeAnyRunningTest);

  test('should support overriding providers', () async {
    final fixture = await new NgTestBed<TestViewComponent>().create();
    expect(fixture.text, 'Hello World');
  });
}

@Component(
  selector: 'view-comp',
  providers: const [DataService],
  template: '{{value}}',
)
class ViewComponent implements OnInit {
  final DataService _service;

  String value;

  ViewComponent(this._service);

  @override
  ngOnInit() async => value = await _service.fetch();
}

@Component(
  selector: 'test-view-comp',
  directives: const [
    OverrideDirective,
    ViewComponent,
  ],
  template: '<view-comp override></view-comp>',
)
class TestViewComponent {}

@Directive(
  selector: '[override]',
  providers: const [
    const Provider(DataService, useClass: FakeDataService),
  ],
)
class OverrideDirective {}

@Injectable()
class DataService {
  Future<String> fetch() => throw new UnimplementedError();
}

@Injectable()
class FakeDataService implements DataService {
  @override
  Future<String> fetch() async => 'Hello World';
}
