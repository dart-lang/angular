import 'package:angular/src/compiler/analyzed_class.dart';
import 'package:angular/src/compiler/expression_parser/ast.dart';
import 'package:angular/src/compiler/html_events.dart';
import 'package:angular/src/compiler/output/output_ast.dart' as o;
import 'package:angular/src/compiler/template_ast.dart'
    show BoundEventAst, DirectiveAst;
import 'package:angular/src/compiler/view_compiler/bound_value_converter.dart'
    show extractFunction, wrapHandler;
import 'package:angular_compiler/cli.dart';

import 'compile_element.dart' show CompileElement;
import 'compile_method.dart' show CompileMethod;
import 'constants.dart' show DetectChangesVars;
import 'expression_converter.dart' show NameResolver, convertCdStatementToIr;
import 'ir/provider_source.dart';
import 'parse_utils.dart';

/// Generates code to listen to a single eventName on a [CompileElement].
///
/// Since multiple directives on an element could potentially listen to the
/// same event, this class collects the individual handlers as actions and
/// creates a single member method on the component that calls each of the
/// handlers and then applies logical AND to determine resulting
/// prevent default value.
class CompileEventListener {
  /// Resolves names used in actions of this event listener.
  ///
  /// Each event listener needs a scoped copy of its view's [NameResolver] to
  /// ensure locals are cached only in the methods they're used.
  final NameResolver _nameResolver;
  final CompileElement _compileElement;
  final String eventName;
  final _method = CompileMethod();
  final String _methodName;

  var _isSimple = true;
  var _handlerType = HandlerType.notSimple;
  o.Expression _simpleHandler;
  BoundEventAst _simpleHostEvent;

  /// Helper function to search for an event in [targetEventListeners] list and
  /// add a new one if it doesn't exist yet.
  /// TODO: try using Map, this code is quadratic and assumes typical event
  /// lists are very small.
  static CompileEventListener _getOrCreate(CompileElement compileElement,
      String eventName, List<CompileEventListener> targetEventListeners) {
    for (var existingListener in targetEventListeners) {
      if (existingListener.eventName == eventName) return existingListener;
    }
    var listener = CompileEventListener(
        compileElement, eventName, targetEventListeners.length);
    targetEventListeners.add(listener);
    return listener;
  }

  CompileEventListener(this._compileElement, this.eventName, int listenerIndex)
      : _nameResolver = _compileElement.view.nameResolver.scope(),
        _methodName = '_handle_${sanitizeEventName(eventName)}_'
            '${_compileElement.nodeIndex}_'
            '$listenerIndex';

  void _addAction(
    BoundEventAst hostEvent,
    ProviderSource directiveInstance,
    AnalyzedClass clazz,
  ) {
    if (_isTearOff(hostEvent)) {
      hostEvent = _rewriteTearOff(hostEvent, clazz);
    }
    if (_isSimple) {
      _handlerType = hostEvent.handlerType;
      _simpleHostEvent = hostEvent;
      _isSimple = _method.isEmpty && _handlerType != HandlerType.notSimple;
    }

    final context = directiveInstance?.build() ?? DetectChangesVars.cachedCtx;
    final actionStmts = convertCdStatementToIr(
      _nameResolver,
      context,
      hostEvent.handler,
      hostEvent.sourceSpan,
      _compileElement.view.component,
    );
    _method.addStmts(actionStmts);
  }

  void _finish() {
    if (_isSimple) {
      final returnExpr = convertStmtIntoExpression(_method.finish().last);
      if (returnExpr is! o.InvokeMethodExpr) {
        final message = "Expected method for event binding.";
        throwFailure(_simpleHostEvent != null
            ? _simpleHostEvent.sourceSpan.message(message)
            : message);
      }

      // If debug info is enabled, the first statement is a call to [dbg], so
      // retrieve last statement to ensure it's the handler invocation.
      _simpleHandler = extractFunction(returnExpr);
    } else {
      _compileElement.view.createEventHandler(
        _methodName,
        _method.finish(),
        localDeclarations: _nameResolver.getLocalDeclarations(),
      );
    }
  }

  void _listenToRenderer() {
    final handlerExpr = _createEventHandlerExpr();
    if (isNativeHtmlEvent(eventName)) {
      _compileElement.view.addDomEventListener(
        _compileElement.renderNode,
        eventName,
        handlerExpr,
      );
    } else {
      _compileElement.view.addCustomEventListener(
        _compileElement.renderNode,
        eventName,
        handlerExpr,
      );
    }
  }

  void _listenToDirective(
    DirectiveAst directiveAst,
    o.Expression directiveInstance,
    String observablePropName,
  ) {
    final handlerExpr = _createEventHandlerExpr();
    _compileElement.view.createSubscription(
      directiveInstance.prop(observablePropName),
      handlerExpr,
      isMockLike: directiveAst.directive.analyzedClass.isMockLike,
    );
  }

  o.Expression _createEventHandlerExpr() {
    o.Expression handlerExpr;
    int numArgs;

    if (_isSimple) {
      handlerExpr = _simpleHandler;
      numArgs = _handlerType == HandlerType.simpleNoArgs ? 0 : 1;
    } else {
      handlerExpr = o.ReadClassMemberExpr(_methodName);
      numArgs = 1;
    }

    return wrapHandler(handlerExpr, numArgs);
  }

  bool _isTearOff(BoundEventAst hostEvent) =>
      _handler(hostEvent) is PropertyRead;

  BoundEventAst _rewriteTearOff(BoundEventAst hostEvent, AnalyzedClass clazz) =>
      BoundEventAst(hostEvent.name, rewriteTearOff(_handler(hostEvent), clazz),
          hostEvent.sourceSpan);

  AST _handler(BoundEventAst hostEvent) {
    final handler = hostEvent.handler;
    return handler is ASTWithSource ? handler.ast : handler;
  }
}

List<CompileEventListener> collectEventListeners(
  List<BoundEventAst> hostEvents,
  List<DirectiveAst> dirs,
  CompileElement compileElement,
  AnalyzedClass analyzedClass,
) {
  final eventListeners = <CompileEventListener>[];
  for (final hostEvent in hostEvents) {
    final listener = CompileEventListener._getOrCreate(
      compileElement,
      hostEvent.name,
      eventListeners,
    );
    listener._addAction(hostEvent, null, analyzedClass);
  }
  for (var i = 0, len = dirs.length; i < len; i++) {
    final directiveAst = dirs[i];
    // Don't collect component host event listeners because they're registered
    // by the component implementation.
    if (directiveAst.directive.isComponent) {
      continue;
    }
    for (final hostEvent in directiveAst.hostEvents) {
      final listener = CompileEventListener._getOrCreate(
        compileElement,
        hostEvent.name,
        eventListeners,
      );
      listener._addAction(
        hostEvent,
        compileElement.directiveInstances[i],
        analyzedClass,
      );
    }
  }
  for (final eventListener in eventListeners) {
    eventListener._finish();
  }
  return eventListeners;
}

void bindDirectiveOutputs(
  DirectiveAst directiveAst,
  o.Expression directiveInstance,
  List<CompileEventListener> eventListeners,
) {
  directiveAst.directive.outputs.forEach((observablePropName, eventName) {
    for (final listener in eventListeners) {
      if (listener.eventName == eventName) {
        listener._listenToDirective(
          directiveAst,
          directiveInstance,
          observablePropName,
        );
      }
    }
  });
}

void bindRenderOutputs(List<CompileEventListener> eventListeners) {
  for (final listener in eventListeners) {
    listener._listenToRenderer();
  }
}

o.Expression convertStmtIntoExpression(o.Statement stmt) {
  if (stmt is o.ExpressionStatement) {
    return stmt.expr;
  } else if (stmt is o.ReturnStatement) {
    return stmt.value;
  }
  return null;
}
