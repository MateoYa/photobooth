// Copy this file to lib/email_config.dart and fill in the real values.
// lib/email_config.dart is gitignored so the app password never gets committed.

/// Gmail account the photobooth sends from.
const String gmailAddress = 'your.photobooth@gmail.com';

/// 16-character Google app password (myaccount.google.com/apppasswords).
/// Needs 2-Step Verification turned on for the account.
const String gmailAppPassword = 'xxxxxxxxxxxxxxxx';

/// Name shown as the sender.
const String senderName = 'ACE Waterloo';

/// Replies go here instead of to the Gmail account.
const String replyTo = 'club@example.com';

const String emailSubject = 'Your IGNITE 2026 photo strip';

const String emailText =
    'Thanks for stopping by the ACE Waterloo photobooth at IGNITE Case '
    'Competition 2026!\n\nYour photo strip is attached.\n\n- ACE Waterloo';

const String emailHtml = '<p>Thanks for stopping by the <b>ACE Waterloo</b> '
    'photobooth at <b>IGNITE Case Competition 2026</b>!</p>'
    '<p>Your photo strip is attached.</p>'
    '<p>- ACE Waterloo</p>';

const String attachmentName = 'IGNITE-2026-photobooth.jpg';
