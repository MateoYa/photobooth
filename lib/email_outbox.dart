import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server/gmail.dart';
import 'package:path_provider/path_provider.dart';

import 'email_config.dart';

/// Emails photo strips, keeping each one on disk until it has been sent so
/// nothing is lost if the Wi-Fi drops or the app is closed.
///
/// Each queued email is `<id>.jpg` (the strip; older ones may be `.png`) plus `<id>.json`
/// (`{to, createdAt, attempts}`) in `<app documents>/outbox/`.
class EmailOutbox {
  EmailOutbox._();
  static final EmailOutbox instance = EmailOutbox._();

  static const _retryEvery = Duration(seconds: 30);
  static const _sendTimeout = Duration(seconds: 20);
  // Emails the server keeps rejecting (e.g. a mistyped address) are set
  // aside after this many tries instead of retrying forever.
  static const _maxRejectedAttempts = 5;

  Directory? _dir;
  Timer? _retryTimer;
  Future<void>? _flushing;
  bool _flushAgain = false;

  Future<Directory> _outboxDir() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/outbox');
    await dir.create(recursive: true);
    return _dir = dir;
  }

  /// Sends anything left over from a previous run.
  Future<void> start() => flush();

  /// Saves the email to the outbox (fast) and starts sending it in the
  /// background. Once this returns, the email is safe on disk and will be
  /// delivered even if the Wi-Fi is down or the app is closed.
  Future<void> enqueue(String to, Uint8List jpeg) async {
    final dir = await _outboxDir();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await File('${dir.path}/$id.jpg').writeAsBytes(jpeg, flush: true);
    // The .json is written last: a job only counts once its image is saved.
    await File('${dir.path}/$id.json').writeAsString(
        jsonEncode({
          'to': to,
          'createdAt': DateTime.now().toIso8601String(),
          'attempts': 0,
        }),
        flush: true);
    unawaited(flush());
  }

  /// Tries to send every queued email. Only one flush runs at a time.
  /// If called while a flush is running, another pass runs right after so
  /// newly queued emails aren't left waiting for the retry timer.
  Future<void> flush() {
    if (_flushing != null) {
      _flushAgain = true;
      return _flushing!;
    }
    return _flushing = _flush().whenComplete(() {
      _flushing = null;
      if (_flushAgain) {
        _flushAgain = false;
        flush();
      }
    });
  }

  Future<void> _flush() async {
    final dir = await _outboxDir();
    final jobs = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final jobFile in jobs) {
      final id = jobFile.uri.pathSegments.last.replaceAll('.json', '');
      final jpgFile = File('${dir.path}/$id.jpg');
      final imageFile = await jpgFile.exists()
          ? jpgFile
          : File('${dir.path}/$id.png'); // queued by an older version
      Map<String, dynamic> job;
      try {
        job = jsonDecode(await jobFile.readAsString()) as Map<String, dynamic>;
      } catch (_) {
        await jobFile.delete();
        continue;
      }
      if (!await imageFile.exists()) {
        await jobFile.delete();
        continue;
      }

      try {
        await _send(job['to'] as String, imageFile);
        await jobFile.delete();
        await imageFile.delete();
      } on SocketException catch (e) {
        debugPrint('Email offline, will retry: $e');
        break; // No network: no point trying the rest now.
      } on TimeoutException catch (e) {
        debugPrint('Email timed out, will retry: $e');
        break;
      } on SmtpClientAuthenticationException catch (e) {
        // Wrong Gmail address/app password: our setup problem, not the
        // guest's. Keep everything queued until the config is fixed.
        debugPrint('Email login failed, check email_config.dart: $e');
        break;
      } on MailerException catch (e) {
        // Server answered but refused (bad address, auth problem, etc.).
        final attempts = (job['attempts'] as int? ?? 0) + 1;
        debugPrint('Email rejected (attempt $attempts): $e');
        if (attempts >= _maxRejectedAttempts) {
          final failed = Directory('${dir.path}/failed');
          await failed.create(recursive: true);
          await imageFile
              .rename('${failed.path}/${imageFile.uri.pathSegments.last}');
          await jobFile.rename('${failed.path}/$id.json');
        } else {
          job['attempts'] = attempts;
          await jobFile.writeAsString(jsonEncode(job), flush: true);
        }
      } catch (e) {
        debugPrint('Email failed, will retry: $e');
        break;
      }
    }

    _scheduleRetry(dir);
  }

  void _scheduleRetry(Directory dir) {
    final pending =
        dir.listSync().any((f) => f is File && f.path.endsWith('.json'));
    if (pending) {
      _retryTimer ??= Timer.periodic(_retryEvery, (_) => flush());
    } else {
      _retryTimer?.cancel();
      _retryTimer = null;
    }
  }

  Future<void> _send(String to, File image) async {
    final isPng = image.path.endsWith('.png');
    final message = Message()
      ..from = const Address(gmailAddress, senderName)
      ..recipients.add(to)
      ..headers['Reply-To'] = replyTo
      ..subject = emailSubject
      ..text = emailText
      ..html = emailHtml
      ..attachments.add(FileAttachment(image,
          contentType: isPng ? 'image/png' : 'image/jpeg',
          fileName: isPng
              ? attachmentName.replaceAll(RegExp(r'\.jpe?g$'), '.png')
              : attachmentName));
    await send(message, gmail(gmailAddress, gmailAppPassword),
        timeout: _sendTimeout);
  }
}
