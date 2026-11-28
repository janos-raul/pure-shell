// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pureshell/core/snippets/snippet.dart';
import 'package:pureshell/core/snippets/snippet_repository.dart';
import 'package:pureshell/core/storage/secure_store.dart';

Snippet _s(String id, {String? host, String text = 'ls'}) =>
    Snippet(id: id, name: 'n$id', text: text, hostId: host);

void main() {
  group('Snippet', () {
    test('JSON round trip keeps every field', () {
      const s = Snippet(
        id: 'a',
        name: 'Update',
        text: 'sudo apt update\nsudo apt upgrade',
        hostId: 'h1',
        mode: SnippetMode.run,
        confirm: true,
      );
      final json = jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>;
      expect(Snippet.fromJson(json), s);
    });

    test('missing fields fall back: global, insert, no confirmation', () {
      final s = Snippet.fromJson({'id': 'x'});
      expect(s.isGlobal, isTrue);
      expect(s.mode, SnippetMode.insert);
      expect(s.confirm, isFalse);
      expect(s.name, '');
      expect(s.text, '');
    });

    test('an unknown mode falls back to insert, never to run', () {
      expect(
        Snippet.fromJson({'id': 'x', 'mode': 'launch-missiles'}).mode,
        SnippetMode.insert,
      );
    });

    test('a global snippet stores no hostId', () {
      expect(_s('a').toJson().containsKey('hostId'), isFalse);
    });

    test('multi-line detection and the confirmation default', () {
      expect(_s('a', text: 'ls').isMultiLine, isFalse);
      expect(_s('a', text: 'ls\npwd').isMultiLine, isTrue);
      expect(_s('a', text: 'ls\r\npwd').isMultiLine, isTrue);
      expect(Snippet.confirmDefaultFor('ls'), isFalse);
      expect(Snippet.confirmDefaultFor('ls\npwd'), isTrue);
    });

    test('copyWith can move a snippet to global', () {
      final s = _s('a', host: 'h1');
      expect(s.copyWith(clearHost: true).isGlobal, isTrue);
      expect(s.copyWith(name: 'x').hostId, 'h1');
    });

    test('new ids are unique', () {
      expect({for (var i = 0; i < 50; i++) Snippet.newId()}.length, 50);
    });
  });

  group('SnippetRepository', () {
    late MemorySecureStore store;
    late SnippetRepository repo;

    setUp(() {
      store = MemorySecureStore();
      repo = SnippetRepository(store);
    });

    test('starts empty and keeps everything in one document', () async {
      expect(await repo.list(), isEmpty);
      await repo.upsert(_s('a'));
      await repo.upsert(_s('b', host: 'h1'));
      expect(store.data.keys, ['snippets.v1']);
      expect((await repo.list()).map((s) => s.id), ['a', 'b']);
    });

    test('upsert replaces by id and keeps the place', () async {
      await repo.upsert(_s('a'));
      await repo.upsert(_s('b'));
      await repo.upsert(_s('a', text: 'pwd'));
      final all = await repo.list();
      expect(all.map((s) => s.id), ['a', 'b']);
      expect(all.first.text, 'pwd');
    });

    test('moving a snippet to another scope puts it at the end', () async {
      await repo.upsert(_s('a'));
      await repo.upsert(_s('b'));
      await repo.upsert(_s('a', host: 'h1'));
      expect((await repo.list()).map((s) => s.id), ['b', 'a']);
    });

    test('forHost: the host snippets first, then the global ones', () async {
      await repo.upsert(_s('g1'));
      await repo.upsert(_s('h1a', host: 'h1'));
      await repo.upsert(_s('other', host: 'h2'));
      await repo.upsert(_s('g2'));
      await repo.upsert(_s('h1b', host: 'h1'));
      expect((await repo.forHost('h1')).map((s) => s.id), [
        'h1a',
        'h1b',
        'g1',
        'g2',
      ]);
      expect((await repo.forHost('h3')).map((s) => s.id), ['g1', 'g2']);
    });

    test('inScope lists one scope only', () async {
      await repo.upsert(_s('g1'));
      await repo.upsert(_s('h1a', host: 'h1'));
      expect((await repo.inScope(null)).map((s) => s.id), ['g1']);
      expect((await repo.inScope('h1')).map((s) => s.id), ['h1a']);
    });

    test('delete removes one snippet', () async {
      await repo.upsert(_s('a'));
      await repo.upsert(_s('b'));
      await repo.delete(_s('a'));
      expect((await repo.list()).map((s) => s.id), ['b']);
    });

    test('deleteForHost removes only that host\'s snippets', () async {
      await repo.upsert(_s('g'));
      await repo.upsert(_s('h1a', host: 'h1'));
      await repo.upsert(_s('h2a', host: 'h2'));
      await repo.deleteForHost('h1');
      expect((await repo.list()).map((s) => s.id), ['g', 'h2a']);
    });

    test('reorder moves inside the scope and leaves other scopes', () async {
      await repo.upsert(_s('g1'));
      await repo.upsert(_s('h1', host: 'x'));
      await repo.upsert(_s('g2'));
      await repo.upsert(_s('h2', host: 'x'));
      await repo.upsert(_s('g3'));
      // ReorderableListView semantics: moving g1 below g2 is (0, 2).
      await repo.reorder(null, 0, 2);
      expect((await repo.inScope(null)).map((s) => s.id), ['g2', 'g1', 'g3']);
      expect((await repo.inScope('x')).map((s) => s.id), ['h1', 'h2']);
      // To the end, and back up to the start.
      await repo.reorder(null, 0, 3);
      expect((await repo.inScope(null)).map((s) => s.id), ['g1', 'g3', 'g2']);
      await repo.reorder(null, 2, 0);
      expect((await repo.inScope(null)).map((s) => s.id), ['g2', 'g1', 'g3']);
    });

    test('reorder with a bad index changes nothing', () async {
      await repo.upsert(_s('a'));
      await repo.reorder(null, 5, 0);
      expect((await repo.list()).map((s) => s.id), ['a']);
    });

    test('a damaged document reads as empty, it does not throw', () async {
      await store.write('snippets.v1', '{not json');
      expect(await repo.list(), isEmpty);
      await repo.upsert(_s('a'));
      expect((await repo.list()).map((s) => s.id), ['a']);
    });
  });
}
