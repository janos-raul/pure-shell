// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

import '../../core/keys/ssh_ec_encoding.dart' show ecdsaP256Type;
import '../../core/keys/ssh_ed25519_encoding.dart' show ed25519Type;

/// The in-app help: offline, short sections, plain language. Inline markup in
/// the texts: `code` is shown in monospace, **bold** in bold.
///
/// Every sentence here describes what the app really does; the tests tie the
/// key types and the button labels to the code.
sealed class HelpBlock {
  const HelpBlock();
}

/// A small heading inside a topic.
class HelpHeading extends HelpBlock {
  const HelpHeading(this.text);
  final String text;
}

class HelpText extends HelpBlock {
  const HelpText(this.text);
  final String text;
}

/// Numbered steps.
class HelpSteps extends HelpBlock {
  const HelpSteps(this.steps);
  final List<String> steps;
}

/// A command or line to copy, monospace.
class HelpCommand extends HelpBlock {
  const HelpCommand(this.command);
  final String command;
}

class HelpTopic {
  const HelpTopic(this.id, this.title, this.summary, this.blocks);

  final String id;
  final String title;

  /// One line shown in the topic list.
  final String summary;
  final List<HelpBlock> blocks;
}

const helpAddKey = 'add-key';
const helpFirstConnect = 'first-connect';

final List<HelpTopic> helpTopics = [
  HelpTopic(
    helpAddKey,
    'Adding a key to a server',
    'The authorized_keys line, and the from= restriction',
    [
      const HelpText(
        'Pure-Shell makes your key inside the phone. The private part never '
        'leaves it; the server only needs the public part.',
      ),
      HelpSteps([
        'Open Keys, tap your key, then tap Copy. This copies one line, the '
            '`authorized_keys` line. It starts with `$ecdsaP256Type`, or with '
            '`$ed25519Type` for a software key on a phone without secure '
            'hardware.',
        'On the server, log in as the user Pure-Shell will log in as. Add that '
            'line as a new line at the end of `~/.ssh/authorized_keys`.',
        'Make sure the permissions are strict, or the server ignores the file:',
      ]),
      const HelpCommand(
        'mkdir -p ~/.ssh && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys',
      ),
      const HelpText(
        'Then edit the host in Pure-Shell, set Login to Key and choose the key.',
      ),
      const HelpText(
        'The fingerprint shown under the key (`SHA256:...`) is only a short '
        'name to recognise the key, for example in `ssh-keygen -lf` or in the '
        "server's log. The server needs the whole line, not the fingerprint.",
      ),
      const HelpHeading('Limiting where a key can be used'),
      const HelpText(
        'You can write `from=` in front of the key on its line to say where '
        'it may log in from, for example:',
      ),
      HelpCommand('from="192.168.1.0/24" $ecdsaP256Type AAAA... pureshell'),
      const HelpText(
        "On your home Wi-Fi the server sees your phone's address on the local "
        'network (for example 192.168.1.23), so a local subnet like this '
        'works there. On mobile data or another Wi-Fi the server sees a '
        'different address and rejects the key.',
      ),
      const HelpHeading('If the server rejects the key'),
      const HelpText(
        "Check that the line is in the right user's file and is one single "
        'line (not broken in two), that any `from=` matches, that the '
        "permissions are as above, and read the server's log for the exact "
        'reason, for example `journalctl -u ssh` or `/var/log/auth.log`.',
      ),
    ],
  ),
  const HelpTopic(
    helpFirstConnect,
    'The first connection and host keys',
    'The fingerprint prompt, and why a changed key blocks',
    [
      HelpText(
        'The first time you connect to a server, it presents its host key. '
        'Pure-Shell shows the key type and its fingerprint and asks whether to '
        "trust it. Compare the fingerprint with the server's, using the "
        'command shown in the prompt, for example:',
      ),
      HelpCommand('ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub'),
      HelpText(
        'If they match, tap Trust. Pure-Shell remembers the key for that host '
        'and port. Cancel stores nothing. The server only waits a limited '
        'time for you to decide and then closes the connection; if that '
        'happens, just connect again.',
      ),
      HelpHeading('When the key changes'),
      HelpText(
        'Every later connection must present the same key. If it differs, '
        'Pure-Shell blocks the connection and shows both fingerprints. Nothing '
        'is sent to the server: no password and no key signature. There is '
        'only Back, and no "continue anyway" button, because that is the '
        'button an attacker relies on.',
      ),
      HelpText(
        "A changed key means either the server's keys were replaced (for "
        'example it was reinstalled) or someone is intercepting the '
        'connection. If you are sure the change is legitimate, check the new '
        'fingerprint on the server itself or with its administrator. Then '
        'open Edit host, tap Remove trusted key, and connect again to go '
        'through the first-connection prompt.',
      ),
    ],
  ),
  const HelpTopic(
    'input',
    'Direct and Composing input',
    'How the keyboard talks to the terminal',
    [
      HelpText('You can change this in Settings, under Terminal, Input mode.'),
      HelpText(
        '**Direct** (the default) sends every character as soon as you type '
        'it. It works with every keyboard. In this mode the keyboard cannot '
        'do swipe typing or suggestions; use the command box for those.',
      ),
      HelpText(
        '**Composing** lets the keyboard keep a word until it is finished. '
        'It is needed for Chinese, Japanese and Korean input.',
      ),
    ],
  ),
  const HelpTopic(
    'command-box',
    'The command box',
    'Type a whole line with swipe and suggestions',
    [
      HelpText(
        'Tap the last key in the row above the keyboard to open the command '
        'box. It is an ordinary text field: swipe typing, suggestions and '
        'editing work. Autocorrect and automatic capital letters are off, so '
        'your command is sent exactly as typed.',
      ),
      HelpText(
        'Send (or Enter at the end of the text) sends the line followed by '
        'Enter and closes the box. Turn on Keep open to leave it open.',
      ),
      HelpText(
        'Text with several lines is sent as a paste without a final Enter, so '
        'you can look at it in the terminal and press Enter yourself.',
      ),
      HelpText(
        'While the box is open the keys in the row act on the box: the '
        'arrows move the cursor, Esc closes it and clears it, Tab and Ctrl '
        'are off.',
      ),
      HelpText(
        'Nothing typed in the box is stored, logged or kept as history, and '
        'the keyboard is asked not to learn from it. The box closes and its '
        'text is cleared when the app is locked or goes to the background, '
        'and when the session ends.',
      ),
      HelpHeading('SwiftKey capitalizes the first letter'),
      HelpText(
        'SwiftKey capitalizes the first letter in the command box regardless '
        "of the app's settings. Turn off Auto-capitalization in SwiftKey's "
        'Typing settings, or type directly in the terminal (Direct mode).',
      ),
    ],
  ),
  const HelpTopic(
    'copy-paste',
    'Copy and paste',
    'Long-press the terminal, or use the Paste key',
    [
      HelpText(
        'Long-press the terminal to select a word and open a menu: Paste '
        'always, and Copy and Select all when something is selected. There '
        'is also a Paste key in the row above the keyboard; while the '
        'command box is open it pastes into the box.',
      ),
      HelpText(
        'Pasted text goes to the server as one paste. Programs that support '
        'bracketed paste (most shells and editors) receive it as a block and '
        'never run it line by line. If the running program did not ask for '
        'that and the text has several lines, Pure-Shell asks first, because '
        'each line would run as it is entered.',
      ),
      HelpText(
        'Control characters are removed from pasted text (Escape included, '
        'so pasted text cannot end the paste early), except tabs and line '
        'breaks.',
      ),
      HelpText(
        'Pure-Shell reads the clipboard only when you tap Paste, never in the '
        'background. On Android 13 and later, text you copy from the '
        "terminal is marked sensitive so the system's clipboard preview does "
        'not show it; older versions do a normal copy. Copy and paste are '
        'off while the app is locked or in the background. Nothing pasted or '
        'copied is logged.',
      ),
    ],
  ),
  const HelpTopic(
    'keep-alive',
    'Keeping sessions alive',
    'The notification, and what ends a session',
    [
      HelpText(
        'Android cuts off the network of an app a few seconds after you '
        'leave it, which would end your SSH sessions. While you are '
        'connected, Pure-Shell therefore runs a small background service with '
        'a notification that shows only how many sessions are active (for '
        'example "2 active sessions"): never hostnames, usernames or '
        'terminal content. The notification has a Disconnect all button.',
      ),
      HelpText(
        'The first time you connect, Pure-Shell explains this and Android '
        'asks to allow notifications. If you say no, sessions are still kept '
        'alive; you just do not see the notification.',
      ),
      HelpText(
        'You can turn it off in Settings, under Connection, Keep sessions '
        'alive. Then Android ends your sessions shortly after you leave the '
        'app.',
      ),
      HelpText(
        'Closing the app (Back from the host list, or swiping it away in the '
        'recent apps) ends your sessions. They also end when the server '
        'closes the connection, when the network drops or when the phone '
        'restarts. Pure-Shell pings idle sessions every 30 seconds and '
        'treats a connection that stops answering as lost after roughly a '
        'minute.',
      ),
    ],
  ),
  const HelpTopic(
    'tmux',
    'Long-running jobs: tmux',
    'Keep a job running when the connection drops',
    [
      HelpText(
        'A session lasts only as long as its connection. For a job that must '
        'survive a dropped connection, start it inside tmux on the server:',
      ),
      HelpCommand('tmux new -s work'),
      HelpText('If the connection is lost, connect again and reattach:'),
      HelpCommand('tmux attach -t work'),
      HelpText(
        'To leave a job running on purpose, tap Ctrl, then press b, then d. '
        '(Ctrl stays active for the next key you press.)',
      ),
    ],
  ),
  const HelpTopic(
    'keys-lost',
    'Keys can be lost',
    'When your key is gone, and what to do about it',
    [
      HelpText(
        "Keys live in the phone's Keystore. They are not backed up and "
        'cannot be exported. They are destroyed if you uninstall Pure-Shell, '
        'clear its data, or reinstall it signed with a different key (for '
        'example a build from another source). Android also deletes keys '
        "like these if you remove the phone's screen lock.",
      ),
      HelpText(
        'Keep another way into your servers, such as a password or a second '
        'key.',
      ),
    ],
  ),
];

HelpTopic? helpTopicById(String id) {
  for (final t in helpTopics) {
    if (t.id == id) return t;
  }
  return null;
}
