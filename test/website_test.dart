// Pure-Shell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Checks of the static website in github-pages/: it must stay consistent with
/// the app (permissions, claims) and with its own promise of no third-party
/// requests.
void main() {
  const site = 'github-pages';
  const email = 'janos.szabo@gmail.com';

  String read(String path) => File('$site/$path').readAsStringSync();

  final pages = {
    'index.html': read('index.html'),
    'privacy.html': read('privacy.html'),
    'terms/index.html': read('terms/index.html'),
  };

  String text(String html) => html
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&rarr;', '->')
      .replaceAll('&larr;', '<-')
      .replaceAll('&copy;', '(c)')
      .replaceAll(RegExp(r'\s+'), ' ');

  test('the pages, stylesheet, assets and deploy files exist', () {
    for (final f in [
      'index.html',
      'privacy.html',
      'terms/index.html',
      '404.html',
      'style.css',
      'robots.txt',
      'sitemap.xml',
      'CNAME',
      'web_assets/icon.svg',
      'web_assets/favicon.png',
      'web_assets/apple-touch-icon.png',
      'web_assets/og_image.png',
    ]) {
      expect(File('$site/$f').existsSync(), isTrue, reason: f);
    }
    final workflow = File('.github/workflows/pages.yml').readAsStringSync();
    expect(workflow, contains('path: github-pages'));
    expect(read('CNAME').trim(), 'pure-shell.eu');
  });

  test('every local link and image resolves to a file', () {
    final all = {...pages, '404.html': read('404.html')};
    for (final e in all.entries) {
      final dir = e.key.contains('/')
          ? e.key.substring(0, e.key.lastIndexOf('/'))
          : '';
      for (final m in RegExp(r'(?:href|src)="([^"]+)"').allMatches(e.value)) {
        final link = m.group(1)!;
        if (RegExp(r'^(https?:|mailto:|#)').hasMatch(link)) continue;
        final path = link.split('#').first;
        var resolved = path.startsWith('/')
            ? path.substring(1)
            : Uri.parse('$dir/').resolve(path).path;
        resolved = resolved.replaceFirst(RegExp(r'^/'), '');
        if (resolved.isEmpty || resolved.endsWith('/')) {
          resolved = '${resolved}index.html';
        }
        expect(
          File('$site/$resolved').existsSync(),
          isTrue,
          reason: '${e.key} links to $link ($resolved)',
        );
      }
    }
  });

  test('no third-party requests: no scripts, fonts, trackers or embeds', () {
    final all = {
      ...pages,
      '404.html': read('404.html'),
      'style.css': read('style.css'),
    };
    for (final e in all.entries) {
      expect(e.value, isNot(contains('<script')), reason: e.key);
      expect(e.value, isNot(contains('<iframe')), reason: e.key);
      expect(e.value, isNot(contains('@import')), reason: e.key);
      expect(
        e.value,
        isNot(matches(RegExp(r'url\(\s*["\x27]?https?:'))),
        reason: e.key,
      );
    }
    for (final e in pages.entries) {
      // Only plain links to other sites; images and stylesheets are our own.
      for (final m in RegExp(
        r'<(?:img|link)\b[^>]*?(?:src|href)="(https?:[^"]+)"[^>]*>',
      ).allMatches(e.value)) {
        final tag = m.group(0)!;
        // canonical and social-preview addresses name our own domain.
        expect(
          m.group(1)!.startsWith('https://pure-shell.eu/') ||
              tag.contains('rel="canonical"'),
          isTrue,
          reason: '${e.key}: $tag',
        );
      }
      for (final m in RegExp(
        r'<meta[^>]*content="(https?:[^"]+)"',
      ).allMatches(e.value)) {
        expect(
          m.group(1)!.startsWith('https://pure-shell.eu/'),
          isTrue,
          reason: '${e.key}: ${m.group(1)}',
        );
      }
    }
  });

  test('mobile friendly, dark and light, one title per page', () {
    final titles = <String>{};
    for (final e in pages.entries) {
      expect(e.value, contains('name="viewport"'), reason: e.key);
      expect(
        e.value,
        contains('name="color-scheme" content="dark light"'),
        reason: e.key,
      );
      expect(e.value, contains('<html lang="en">'), reason: e.key);
      titles.add(
        RegExp(r'<title>(.*?)</title>').firstMatch(e.value)!.group(1)!,
      );
    }
    expect(titles.length, pages.length);
    final css = read('style.css');
    expect(css, contains('prefers-color-scheme: light'));
    expect(css, contains('color-scheme: dark light'));
    expect(css, contains('--bg: #000000')); // black by default, like the app
    expect(css, contains('--accent: #33ff66')); // the app's green
  });

  test('every page links Privacy and Terms in the footer, and the contact', () {
    for (final e in pages.entries) {
      final footer = e.value.substring(e.value.indexOf('<footer'));
      expect(footer, contains('privacy.html">Privacy</a>'), reason: e.key);
      expect(footer, contains('terms/">Terms</a>'), reason: e.key);
      expect(footer, contains('mailto:$email'), reason: e.key);
      expect(
        footer,
        contains('github.com/janos-raul/pure-shell'),
        reason: e.key,
      );
    }
  });

  test('one contact address everywhere', () {
    for (final e in pages.entries) {
      // The address only: a link may add ?subject=...
      for (final m in RegExp(r'mailto:([^"?]+)[^"]*"').allMatches(e.value)) {
        expect(m.group(1), email, reason: e.key);
      }
    }
  });

  test('the beta section is on the landing page and well formed', () {
    final html = pages['index.html']!;
    final beta = html.substring(
      html.indexOf('<section id="beta">'),
      html.indexOf('</main>'),
    );
    expect(html, contains('<a href="#beta">'));
    expect(html.indexOf('id="beta"'), greaterThan(html.indexOf('id="get"')));
    expect(html.indexOf('id="beta"'), lessThan(html.indexOf('<footer')));
    expect(
      beta,
      contains('href="https://groups.google.com/g/pure-shell-testers"'),
    );
    expect(
      beta,
      contains('href="https://play.google.com/apps/testing/eu.pureshell.app"'),
    );
    expect(
      beta,
      contains('mailto:$email?subject=Pure-Shell%20beta%20promo%20code'),
    );
    expect(RegExp('<li>').allMatches(beta.split('</ol>').first).length, 3);
    expect(beta, contains('paid app (&euro;4.99)'));
    // No promo codes or numbers of testers on the page.
    expect(beta, isNot(matches(RegExp(r'\b[A-Z0-9]{10,}\b'))));
    expect(text(beta), isNot(contains('12 testers')));
  });

  test('the sitemap lists every page, and robots points to it', () {
    final sitemap = read('sitemap.xml');
    for (final url in [
      'https://pure-shell.eu/',
      'https://pure-shell.eu/privacy.html',
      'https://pure-shell.eu/terms/',
    ]) {
      expect(sitemap, contains('<loc>$url</loc>'));
    }
    expect(
      read('robots.txt'),
      contains('Sitemap: https://pure-shell.eu/sitemap.xml'),
    );
  });

  test('the images have the sizes the pages and social cards expect', () {
    int width(String f) {
      final b = File('$site/web_assets/$f').readAsBytesSync();
      return (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
    }

    int height(String f) {
      final b = File('$site/web_assets/$f').readAsBytesSync();
      return (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23];
    }

    expect([width('og_image.png'), height('og_image.png')], [1200, 630]);
    expect([width('favicon.png'), height('favicon.png')], [64, 64]);
    expect(
      [width('apple-touch-icon.png'), height('apple-touch-icon.png')],
      [180, 180],
    );
  });

  test('the README names every permission the app declares', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final readme = File('README.md').readAsStringSync();
    for (final m in RegExp(
      r'uses-permission android:name="android\.permission\.([A-Z_]+)"',
    ).allMatches(manifest)) {
      expect(readme, contains(m.group(1)!), reason: m.group(1));
    }
    // Added by libraries, so not in our own manifest, but in the merged one.
    for (final name in [
      'USE_FINGERPRINT',
      'DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION',
    ]) {
      expect(readme, contains(name), reason: name);
    }
    expect(readme, contains('https://pure-shell.eu'));
    expect(readme, isNot(contains('only\n  permission')));
  });

  group('landing page', () {
    final t = text(pages['index.html']!);

    test('name, one-line description, key features, store and source', () {
      expect(t, contains('Pure-Shell'));
      expect(t, contains('A private, open-source SSH client for Android.'));
      for (final feature in [
        'Hardware-backed keys',
        'Strict host keys',
        'No tracking',
        'Open source',
      ]) {
        expect(t, contains(feature));
      }
      expect(t, contains('Google Play: coming soon'));
      expect(
        pages['index.html'],
        contains('href="https://github.com/janos-raul/pure-shell"'),
      );
      expect(pages['index.html'], contains('web_assets/icon.svg'));
    });

    test('never says PureShell, and has nothing left from another app', () {
      for (final e in pages.entries) {
        expect(e.value, isNot(contains('PureShell')), reason: e.key);
        expect(e.value, isNot(contains('Pure-QR')), reason: e.key);
        expect(e.value, isNot(contains('QR code')), reason: e.key);
        expect(e.value, isNot(contains('camera')), reason: e.key);
      }
    });
  });

  group('privacy policy', () {
    final t = text(pages['privacy.html']!);

    test('says what the app promises', () {
      for (final phrase in [
        'does not collect, share, or process any personal information',
        'Analytics, telemetry or tracking technologies',
        'Advertising SDKs',
        'Accounts or sign-in',
        'Crash reporting',
        'Nothing is sent to the developer',
        'only on your phone',
        'Android Keystore',
        'servers you add yourself',
        'only how many sessions are active',
        'uninstalling Pure-Shell or clearing its data removes all of it',
      ]) {
        expect(t, contains(phrase));
      }
      expect(t, contains(email));
    });

    test('numbered sections like the other app, ending in Contact', () {
      final headings = RegExp(r'<h2>(\d+)\. (.*?)</h2>')
          .allMatches(pages['privacy.html']!)
          .toList();
      expect([
        for (final h in headings) int.parse(h.group(1)!),
      ], List.generate(headings.length, (i) => i + 1));
      expect(headings.last.group(2), 'Contact');
    });

    test('covers every permission the app declares, and no other', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      final declared = {
        for (final m in RegExp(
          r'uses-permission android:name="android\.permission\.([A-Z_]+)"',
        ).allMatches(manifest))
          m.group(1)!,
      };
      // If this set changes, the privacy policy (and the Play data safety
      // form) must be reviewed first.
      expect(declared, {
        'INTERNET',
        'FOREGROUND_SERVICE',
        'FOREGROUND_SERVICE_SPECIAL_USE',
        'POST_NOTIFICATIONS',
      });
      expect(t, contains('internet permission'));
      expect(t, contains('background service'));
      expect(t, contains('notification permission'));
      // Biometrics come from the Android prompt, and the policy says so.
      expect(t, contains('never receives your fingerprint'));
    });
  });

  group('terms of service', () {
    final raw = pages['terms/index.html']!;
    final t = text(raw);

    test('the eleven sections, in the same order as the other app', () {
      final titles = [
        for (final m in RegExp(r'<h2>(\d+)\. (.*?)</h2>').allMatches(raw))
          '${m.group(1)}. ${m.group(2)}',
      ];
      expect(titles, [
        '1. Who We Are',
        '2. Accepting These Terms',
        '3. What the App Does',
        '4. Purchase and Refunds',
        '5. Source Code and Your License',
        '6. Your Servers and Your Keys',
        '7. Updates and Availability',
        '8. Warranty and Liability',
        '9. Changes to These Terms',
        '10. Governing Law',
        '11. Contact',
      ]);
    });

    test('GPLv3 source, signed build purchase, GPL sections 15 and 16', () {
      expect(t, contains('licensed under the GNU General Public License'));
      expect(t, contains('version 3 or (at your option) any later version'));
      expect(t, contains('Anyone may build Pure-Shell from the source code'));
      expect(
        t,
        contains(
          'the signed, maintained build distributed through Google Play',
        ),
      );
      expect(t, contains('provided "as is", without warranty of any kind'));
      expect(
        t,
        contains('sections 15 and 16 of the GNU General Public License'),
      );
      expect(raw, contains('https://www.gnu.org/licenses/gpl-3.0.html'));
    });

    test('purchases and refunds go through Google Play', () {
      expect(
        raw,
        contains('https://support.google.com/googleplay/answer/2479637'),
      );
      expect(t, contains('Google Play refund policy'));
      expect(t, contains('you keep all the rights those laws give you'));
    });

    test('users are responsible for their servers and for another way in', () {
      expect(t, contains('you are responsible for them'));
      expect(t, contains('Keep another way into your servers'));
      expect(
        t,
        contains('they are lost if you uninstall the app, clear its data'),
      );
      expect(t, contains('We can\'t recover a lost key'));
    });

    test('no liability for lost access, data or damage', () {
      expect(
        t,
        contains(
          'not liable for lost access to servers or keys, lost or damaged data',
        ),
      );
      expect(t, contains('limited to the amount you paid for the app'));
      expect(t, contains('statutory rights as a consumer')); // mandatory law
    });

    test('contact and governing law', () {
      expect(t, contains('governed by the laws of Romania'));
      expect(t, contains(email));
    });
  });
}
