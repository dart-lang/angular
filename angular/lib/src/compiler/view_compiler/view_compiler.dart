import 'package:angular/src/core/change_detection/change_detection.dart'
    show ChangeDetectionStrategy;
import 'package:angular_compiler/cli.dart';

import 'package:source_span/source_span.dart';

import '../compile_metadata.dart'
    show CompileDirectiveMetadata, CompileTypeMetadata, CompilePipeMetadata;
import '../expression_parser/parser.dart';
import '../output/output_ast.dart' as o;
import '../parse_util.dart' show ParseErrorLevel;
import '../schema/element_schema_registry.dart';
import '../style_compiler.dart' show StylesCompileResult;
import '../template_ast.dart' show TemplateAst, templateVisitAll;
import 'compile_element.dart' show CompileElement;
import 'compile_view.dart' show CompileView;
import 'view_binder.dart' show bindView, bindViewHostProperties;
import 'view_builder.dart';
import 'view_compiler_utils.dart' show outlinerDeprecated;

class ViewCompileResult {
  List<o.Statement> statements;
  String viewFactoryVar;
  ViewCompileResult(this.statements, this.viewFactoryVar);
}

/// Compiles a single component to a set of CompileView(s) and generates top
/// level statements to support debugging and view factories.
///
/// - Creates main CompileView
/// - Runs ViewBuilderVisitor over template ast nodes
///     - For each embedded template creates a child CompileView and recurses.
/// - Builds a tree of CompileNode/Element(s)
class ViewCompiler {
  final CompilerFlags _genConfig;
  final ElementSchemaRegistry _schemaRegistry;
  Parser parser;

  ViewCompiler(this._genConfig, this.parser, this._schemaRegistry);

  ViewCompileResult compileComponent(
      CompileDirectiveMetadata component,
      List<TemplateAst> template,
      StylesCompileResult stylesCompileResult,
      o.Expression styles,
      List<CompileTypeMetadata> directiveTypes,
      List<CompilePipeMetadata> pipes,
      Map<String, String> deferredModules) {
    var statements = <o.Statement>[];
    var view = CompileView(component, _genConfig, directiveTypes, pipes, styles,
        0, CompileElement.root(), [], deferredModules);
    buildView(view, template, stylesCompileResult);
    // Need to separate binding from creation to be able to refer to
    // variables that have been declared after usage.
    bindView(view, template);
    bindHostProperties(view);
    finishView(view, statements);
    return ViewCompileResult(statements, view.viewFactory.name);
  }

  void bindHostProperties(CompileView view) {
    var errorHandler =
        (String message, SourceSpan sourceSpan, [ParseErrorLevel level]) {
      if (level == ParseErrorLevel.FATAL) {
        throwFailure(message);
      } else {
        logWarning(message);
      }
    };
    bindViewHostProperties(view, parser, _schemaRegistry, errorHandler);
  }

  /// Builds the view and returns number of nested views generated.
  int buildView(CompileView view, List<TemplateAst> template,
      StylesCompileResult stylesCompileResult) {
    var builderVisitor = ViewBuilderVisitor(view, stylesCompileResult);
    templateVisitAll(builderVisitor, template,
        view.declarationElement.parent ?? view.declarationElement);
    return builderVisitor.nestedViewCount;
  }

  /// Creates top level statements for main and nested views generated by
  /// buildView.
  void finishView(CompileView view, List<o.Statement> targetStatements) {
    view.afterNodes();
    createViewTopLevelStmts(view, targetStatements);
    int nodeCount = view.nodes.length;
    var nodes = view.nodes;
    for (int i = 0; i < nodeCount; i++) {
      var node = nodes[i];
      if (node is CompileElement &&
          node.embeddedView != null &&
          !node.embeddedView.isInlined) {
        finishView(node.embeddedView, targetStatements);
      }
    }
  }

  void createViewTopLevelStmts(
      CompileView view, List<o.Statement> targetStatements) {
    // If we are compiling root view, create a render type for the component.
    // Example: RenderComponentType renderType_MaterialButtonComponent;
    bool creatingMainView = view.viewIndex == 0;

    o.ClassStmt viewClass = createViewClass(view, parser);
    targetStatements.add(viewClass);

    targetStatements.add(createViewFactory(view, viewClass));

    if (creatingMainView &&
        view.component.inputs != null &&
        view.component.changeDetection == ChangeDetectionStrategy.Stateful &&
        outlinerDeprecated) {
      writeInputUpdaters(view, targetStatements);
    }
  }

  bool get genDebugInfo => _genConfig.genDebugInfo;
}
