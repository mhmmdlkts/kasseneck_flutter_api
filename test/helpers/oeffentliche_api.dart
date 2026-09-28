// Liest die oeffentliche Oberflaeche des Pakets aus dem Quelltext: was ein
// Verbraucher ueber `package:kasseneck_api/<einstieg>.dart` erreicht.
//
// Nur geparst, nicht aufgeloest: die Exporte, ihre `show`/`hide`-Listen und
// die Deklarationen stehen woertlich im Quelltext, dafuer braucht es keinen
// Typpruefer. So bleibt der Waechter schnell und haengt nicht an der
// Flutter-SDK-Aufloesung.
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Ein oeffentlicher Name samt Fundstelle `<Datei>:<Besitzer>.<Name>`.
class OeffentlicherName {
  OeffentlicherName(this.name, this.art, this.herkunft);

  final String name;

  /// `export`, `member`, `parameter`, `record`, `pfad`.
  final String art;
  final String herkunft;

  @override
  String toString() => '$herkunft ($art)';
}

/// Die Einstiege: jede Datei unter `lib/` ausser `lib/src/`. Jede davon ist
/// als `package:kasseneck_api/<pfad>` importierbar, nicht nur die Dateien
/// direkt unter `lib/`; `lib/src/` ist nach Dart-Konvention privat und zaehlt
/// nur mit dem, was ein Einstieg daraus exportiert.
List<File> einstiege(Directory lib) =>
    lib
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.dart') &&
              !f.absolute.path.contains('/lib/src/'),
        )
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

/// Liest die Oberflaeche aus den [dateien] (Standard: alle Einstiege unter
/// `lib/`). `quelltext` ersetzt einzelne Dateien im Speicher (Rot-Probe).
List<OeffentlicherName> oeffentlicheApi(
  Directory lib, {
  List<File>? dateien,
  Map<String, String> quelltext = const {},
}) {
  final leser = _Leser(lib, quelltext);
  for (final e in dateien ?? einstiege(lib)) {
    leser.bibliothek(e.absolute.path, const _Filter.alles());
  }
  return leser.funde;
}

class _Filter {
  const _Filter.alles() : show = null, hide = const {};
  const _Filter(this.show, this.hide);

  final Set<String>? show;
  final Set<String> hide;

  bool zeigt(String name) =>
      (show == null || show!.contains(name)) && !hide.contains(name);

  _Filter und(Combinators c) {
    Set<String>? s = show;
    final h = {...hide};
    for (final k in c.liste) {
      if (k is ShowCombinator) {
        final namen = k.shownNames.map((n) => n.name).toSet();
        s = s == null ? namen : s.intersection(namen);
      } else if (k is HideCombinator) {
        h.addAll(k.hiddenNames.map((n) => n.name));
      }
    }
    return _Filter(s, h);
  }
}

class Combinators {
  Combinators(this.liste);
  final List<Combinator> liste;
}

class _Leser {
  _Leser(this.lib, this.quelltext);

  final Directory lib;
  final Map<String, String> quelltext;
  final List<OeffentlicherName> funde = [];
  final Set<String> _gesehen = {};

  String _relativ(String pfad) =>
      pfad.substring(lib.absolute.parent.path.length + 1);

  CompilationUnit _parse(String pfad) {
    final rel = _relativ(pfad);
    final text = quelltext[rel] ?? File(pfad).readAsStringSync();
    return parseString(
      content: text,
      path: pfad,
      throwIfDiagnostics: false,
    ).unit;
  }

  String? _ziel(String von, String uri) {
    if (uri.startsWith('dart:')) return null;
    if (uri.startsWith('package:')) {
      if (!uri.startsWith('package:kasseneck_api/')) return null;
      return '${lib.absolute.path}/${uri.substring('package:kasseneck_api/'.length)}';
    }
    return File(von).parent.uri.resolve(uri).toFilePath();
  }

  void bibliothek(String pfad, _Filter filter) {
    final unit = _parse(pfad);
    final rel = _relativ(pfad);
    if (_gesehen.add('pfad:$rel') && !rel.startsWith('lib/src/')) {
      funde.add(OeffentlicherName(rel, 'pfad', rel));
    }
    for (final d in unit.directives) {
      if (d is ExportDirective) {
        final ziel = _ziel(pfad, d.uri.stringValue!);
        if (ziel == null) continue;
        bibliothek(ziel, filter.und(Combinators(d.combinators)));
      }
    }
    for (final d in unit.declarations) {
      _deklaration(rel, d, filter);
    }
  }

  void _neu(String name, String art, String herkunft) {
    if (name.isEmpty || name.startsWith('_')) return;
    if (_gesehen.add('$art:$herkunft')) {
      funde.add(OeffentlicherName(name, art, herkunft));
    }
  }

  void _deklaration(String rel, CompilationUnitMember d, _Filter filter) {
    final String? name = switch (d) {
      ClassDeclaration c => c.namePart.typeName.lexeme,
      EnumDeclaration e => e.namePart.typeName.lexeme,
      ExtensionTypeDeclaration x => x.primaryConstructor.typeName.lexeme,
      MixinDeclaration m => m.name.lexeme,
      ExtensionDeclaration x => x.name?.lexeme,
      FunctionDeclaration f => f.name.lexeme,
      TypeAlias t => t.name.lexeme,
      _ => null,
    };
    if (d is TopLevelVariableDeclaration) {
      for (final v in d.variables.variables) {
        final n = v.name.lexeme;
        if (n.startsWith('_') || !filter.zeigt(n)) continue;
        _neu(n, 'export', '$rel:$n');
        _signatur(rel, n, d.variables.type);
      }
      return;
    }
    if (name == null || name.startsWith('_') || !filter.zeigt(name)) return;
    _neu(name, 'export', '$rel:$name');
    final besitzer = name;
    if (d is FunctionDeclaration) {
      _parameter(rel, besitzer, d.functionExpression.parameters);
      _signatur(rel, besitzer, d.returnType);
    } else if (d is GenericTypeAlias) {
      _signatur(rel, besitzer, d.type);
    } else if (d is FunctionTypeAlias) {
      _parameter(rel, besitzer, d.parameters);
    }
    final members = switch (d) {
      ClassDeclaration c => _body(c.body),
      MixinDeclaration m => _body(m.body),
      EnumDeclaration e => _enumBody(e),
      ExtensionDeclaration x => _body(x.body),
      ExtensionTypeDeclaration x => _body(x.body),
      _ => const <ClassMember>[],
    };
    if (d is EnumDeclaration) {
      for (final k in _konstanten(d)) {
        _neu(k.name.lexeme, 'member', '$rel:$besitzer.${k.name.lexeme}');
      }
    }
    if (d is ExtensionTypeDeclaration) {
      final p = d.primaryConstructor;
      _neu(
        p.formalParameters.parameters.first.name?.lexeme ?? '',
        'member',
        '$rel:$besitzer.${p.formalParameters.parameters.first.name?.lexeme}',
      );
    }
    for (final m in members) {
      _member(rel, besitzer, m);
    }
  }

  List<ClassMember> _body(ClassBody body) => body.members;

  List<ClassMember> _enumBody(EnumDeclaration e) => e.body.members;

  List<EnumConstantDeclaration> _konstanten(EnumDeclaration e) =>
      e.body.constants;

  void _member(String rel, String besitzer, ClassMember m) {
    if (m is FieldDeclaration) {
      for (final v in m.fields.variables) {
        final n = v.name.lexeme;
        if (n.startsWith('_')) continue;
        _neu(n, 'member', '$rel:$besitzer.$n');
        _signatur(rel, '$besitzer.$n', m.fields.type);
      }
    } else if (m is MethodDeclaration) {
      final n = m.name.lexeme;
      if (n.startsWith('_')) return;
      if (!m.isOperator) _neu(n, 'member', '$rel:$besitzer.$n');
      _parameter(rel, '$besitzer.$n', m.parameters);
      _signatur(rel, '$besitzer.$n', m.returnType);
    } else if (m is ConstructorDeclaration) {
      final n = m.name?.lexeme;
      if (n != null && n.startsWith('_')) return;
      if (n != null) _neu(n, 'member', '$rel:$besitzer.$n');
      _parameter(rel, '$besitzer${n == null ? '' : '.$n'}', m.parameters);
    }
  }

  void _parameter(String rel, String besitzer, FormalParameterList? liste) {
    if (liste == null) return;
    for (final p in liste.parameters) {
      final innen = p is DefaultFormalParameter ? p.parameter : p;
      final n = p.name?.lexeme;
      if (n != null) _neu(n, 'parameter', '$rel:$besitzer($n)');
      if (innen is SimpleFormalParameter) _signatur(rel, besitzer, innen.type);
      if (innen is FunctionTypedFormalParameter) {
        _parameter(rel, besitzer, innen.parameters);
      }
    }
  }

  /// Benannte Felder von Records und die Parameter von Funktionstypen,
  /// die in einer oeffentlichen Signatur stehen.
  void _signatur(String rel, String besitzer, TypeAnnotation? typ) {
    if (typ == null) return;
    typ.accept(_TypLeser((n, art) => _neu(n, art, '$rel:$besitzer{$n}')));
  }
}

class _TypLeser extends RecursiveAstVisitor<void> {
  _TypLeser(this.melde);
  final void Function(String name, String art) melde;

  @override
  void visitRecordTypeAnnotationNamedField(RecordTypeAnnotationNamedField f) {
    melde(f.name.lexeme, 'record');
    super.visitRecordTypeAnnotationNamedField(f);
  }

  @override
  void visitRecordTypeAnnotationPositionalField(
    RecordTypeAnnotationPositionalField f,
  ) {
    final n = f.name?.lexeme;
    if (n != null) melde(n, 'record');
    super.visitRecordTypeAnnotationPositionalField(f);
  }

  @override
  void visitGenericFunctionType(GenericFunctionType node) {
    for (final p in node.parameters.parameters) {
      final n = p.name?.lexeme;
      if (n != null) melde(n, 'parameter');
    }
    super.visitGenericFunctionType(node);
  }
}
