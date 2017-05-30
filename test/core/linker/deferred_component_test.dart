@Tags(const ['codegen'])
@TestOn('browser')
library angular2.test.core.linker.deferred_component_test;

import 'dart:html';

import 'package:angular2/angular2.dart';
import 'package:angular_test/angular_test.dart';
import 'package:test/test.dart';
import 'deferred_view.dart';

void main() {
  tearDown(disposeAnyRunningTest);

  test('should load a @deferred component', () async {
    final fixture = await new NgTestBed<SimpleContainerTest>().create();
    final view = fixture.rootElement.querySelector('my-deferred-view');
    expect(view, isNotNull);
    expect(fixture.text, contains('Title:'));
  });

  test('should load a @deferred component nested in an *ngIf', () async {
    final fixture = await new NgTestBed<NestedContainerTest>().create();
    Element view = fixture.rootElement.querySelector('my-deferred-view');
    expect(view, isNull);

    await fixture.update((c) => c.show = true);
    view = fixture.rootElement.querySelector('my-deferred-view');
    expect(view, isNotNull);
  });

  test('should pass property values to an @deferred component', () async {
    final fixture = await new NgTestBed<PropertyContainerTest>().create();
    await fixture.update();
    expect(fixture.text, contains('Title: Hello World'));
  });

  test('should listen to events from an @deferred component', () async {
    final fixture = await new NgTestBed<EventContainerTest>().create();
    final div = fixture.rootElement.querySelector('my-deferred-view > button');
    expect(fixture.text, contains('Events: 0'));
    await fixture.update((_) {
      div.click();
    });
    expect(fixture.text, contains('Events: 1'));
  });
}

@Component(
  selector: 'simple-container',
  directives: const [DeferredChildComponent],
  template: r'''
    <section>
      <my-deferred-view @deferred></my-deferred-view>
    </section>
  ''',
)
class SimpleContainerTest {}

@Component(
  selector: 'nested-container',
  directives: const [DeferredChildComponent, NgIf],
  template: r'''
    <section *ngIf="show">
      <my-deferred-view @deferred></my-deferred-view>
    </section>
  ''',
)
class NestedContainerTest {
  bool show = false;
}

@Component(
  selector: 'property-container',
  directives: const [DeferredChildComponent],
  template: r'''
    <section>
      <my-deferred-view @deferred [title]="'Hello World'"></my-deferred-view>
    </section>
  ''',
)
class PropertyContainerTest {}

@Component(
  selector: 'event-container',
  directives: const [DeferredChildComponent],
  template: r'''
    <section>
      Events: {{count}}
      <my-deferred-view @deferred (selected)="onSelected()"></my-deferred-view>
    </section>
  ''',
)
class EventContainerTest {
  int count = 0;

  void onSelected() {
    count++;
  }
}
