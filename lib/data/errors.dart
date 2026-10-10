import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/strings.dart';
import '../state/network.dart';

/// Server errors raised in schema.sql, by code.
const _serverCodes = [
  'NOT_SIGNED_IN',
  'NOT_A_CUSTOMER',
  'PROFILE_INCOMPLETE',
  'TAILOR_UNAVAILABLE',
  'INVALID_MEASUREMENT_SET',
  'INVALID_MEASUREMENTS',
  'INVALID_DESIGN',
  'INVALID_QUANTITY',
  'INVALID_WEARER',
  'ORDER_NOT_FOUND',
  'ORDER_LOCKED',
  'TRANSITION_NOT_ALLOWED',
  'PRICE_AND_DATE_REQUIRED',
  'NOTE_REQUIRED',
  // limits from supabase/security_fixes.sql
  'TOO_MANY_ORDERS',
  'TOO_MANY_PEOPLE',
  // from supabase/shop_options.sql
  'OPTION_UNAVAILABLE',
  // from supabase/admin.sql
  'ACCOUNT_BLOCKED',
];

/// What kind of problem happened, which decides the icon, the title and what
/// the person can do about it.
enum ErrorKind {
  /// Wi-Fi and mobile data are off.
  offline,

  /// On a network, but the server can't be reached.
  noInternet,

  /// The server took too long to answer.
  timeout,

  /// The server answered with its own failure.
  server,

  /// Signed out on the server (expired or revoked): sign in again.
  session,

  /// This account isn't allowed to do this.
  forbidden,

  /// The thing no longer exists.
  notFound,

  /// Someone else changed it meanwhile.
  conflict,

  /// Something entered isn't acceptable.
  invalid,

  /// Too many tries in a short time.
  tooMany,

  /// Anything else.
  unknown,
}

/// One problem, explained: a short [title], a [message] that says what
/// happened and what to do, and how to draw it.
class ErrorInfo {
  const ErrorInfo(this.kind, this.title, this.message);

  final ErrorKind kind;
  final String title;
  final String message;

  /// About the connection rather than about what the person did.
  bool get isNetwork => kind == ErrorKind.offline || kind == ErrorKind.noInternet || kind == ErrorKind.timeout;

  /// Trying the same thing again might work.
  bool get canRetry => isNetwork || kind == ErrorKind.server || kind == ErrorKind.unknown || kind == ErrorKind.conflict;

  IconData get icon => switch (kind) {
        ErrorKind.offline => Icons.wifi_off_rounded,
        ErrorKind.noInternet => Icons.signal_cellular_connected_no_internet_4_bar_rounded,
        ErrorKind.timeout => Icons.hourglass_bottom_rounded,
        ErrorKind.server => Icons.cloud_off_rounded,
        ErrorKind.session => Icons.lock_clock_outlined,
        ErrorKind.forbidden => Icons.block_rounded,
        ErrorKind.notFound => Icons.search_off_rounded,
        ErrorKind.conflict => Icons.sync_problem_rounded,
        ErrorKind.invalid => Icons.edit_note_rounded,
        ErrorKind.tooMany => Icons.front_hand_outlined,
        ErrorKind.unknown => Icons.error_outline_rounded,
      };
}

/// The kind of problem behind [error], before any wording.
ErrorKind errorKindOf(Object error, {NetStatus? net}) {
  // the connection: decide between "off", "no internet" and "server" using
  // what the network monitor last saw
  ErrorKind network() => switch (net) {
        NetStatus.offline => ErrorKind.offline,
        NetStatus.serverDown => ErrorKind.server,
        _ => ErrorKind.noInternet,
      };

  if (error is TimeoutException) return ErrorKind.timeout;
  if (error is SocketException || error is HandshakeException || error is HttpException) return network();
  if (error is AuthRetryableFetchException) {
    // used both for "no answer" and for a 502/503 from the server
    final status = int.tryParse(error.statusCode ?? '');
    return _isServerStatus(status) ? ErrorKind.server : network();
  }
  if (error is AuthSessionMissingException || error is AuthInvalidJwtException) return ErrorKind.session;
  if (error is AuthException) {
    final status = int.tryParse(error.statusCode ?? '');
    final m = error.message.toLowerCase();
    if (_isServerStatus(status)) return ErrorKind.server;
    if (status == 429 || m.contains('rate limit')) return ErrorKind.tooMany;
    if (m.contains('socket') || m.contains('host lookup') || m.contains('connection')) return network();
    if (m.contains('refresh token') || m.contains('jwt') || m.contains('session')) return ErrorKind.session;
    return ErrorKind.invalid; // wrong password, taken email, weak password…
  }
  if (error is PostgrestException) {
    final code = error.code ?? '';
    final status = int.tryParse(code);
    if (_isServerStatus(status)) return ErrorKind.server;
    if (code == 'PGRST301' || code == 'PGRST303' || error.message.toLowerCase().contains('jwt')) {
      return ErrorKind.session;
    }
    if (code == '42501') return ErrorKind.forbidden;
    if (code == 'PGRST116' || error.message.contains('ORDER_NOT_FOUND')) return ErrorKind.notFound;
    if (error.message.contains('TRANSITION_NOT_ALLOWED') ||
        error.message.contains('ORDER_LOCKED') ||
        error.message.contains('TAILOR_UNAVAILABLE') ||
        error.message.contains('OPTION_UNAVAILABLE')) {
      return ErrorKind.conflict;
    }
    if (error.message.contains('NOT_SIGNED_IN')) return ErrorKind.session;
    if (error.message.contains('NOT_A_CUSTOMER') || error.message.contains('ACCOUNT_BLOCKED')) {
      return ErrorKind.forbidden;
    }
    if (error.message.contains('TOO_MANY')) return ErrorKind.tooMany;
    if (_serverCodes.any(error.message.contains) || code == '23514') return ErrorKind.invalid;
    return ErrorKind.server;
  }
  if (error is FormatException) return ErrorKind.server; // a reply we couldn't read
  final text = error.toString();
  if (text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('Failed host lookup') ||
      text.contains('Connection closed') ||
      text.contains('Connection reset')) {
    return network();
  }
  return ErrorKind.unknown;
}

/// Explains [error] in the person's language: what happened and what to do.
ErrorInfo describeError(BuildContext context, Object error) {
  final net = _monitor(context);
  final kind = errorKindOf(error, net: net?.status);
  if (kind == ErrorKind.offline || kind == ErrorKind.noInternet || kind == ErrorKind.timeout) {
    // a failed request is a good moment to look at the connection again
    net?.reportFailure();
  }
  final title = context.tr('err.title.${kind.name}');
  return ErrorInfo(kind, title, _detail(context, error, kind));
}

/// Just the sentence, for places that show one line.
String friendlyError(BuildContext context, Object error) => describeError(context, error).message;

/// The specific sentence where we know one (a server rule, a sign-in
/// problem), otherwise the general one for the kind.
String _detail(BuildContext context, Object error, ErrorKind kind) {
  if (error is AuthException && kind == ErrorKind.invalid) {
    final m = error.message.toLowerCase();
    if (m.contains('invalid login')) return context.tr('err.badLogin');
    if (m.contains('already registered') || m.contains('already been registered')) return context.tr('err.emailTaken');
    if (m.contains('email not confirmed')) return context.tr('err.emailNotConfirmed');
    if (m.contains('password')) return context.tr('err.weakPassword');
  }
  if (error is AuthException && kind == ErrorKind.tooMany) return context.tr('err.tooFast');
  if (error is PostgrestException) {
    for (final code in _serverCodes) {
      if (error.message.contains(code)) return context.tr('err.$code');
    }
    if (error.code == '23514') {
      // a database check failed: a text length limit, or a size out of range
      if (error.message.contains('_text_len')) return context.tr('err.tooLong');
      if (error.message.contains('shops_options_valid')) return context.tr('err.badOptions');
      return context.tr('err.INVALID_MEASUREMENTS');
    }
  }
  return context.tr('err.body.${kind.name}');
}

NetworkMonitor? _monitor(BuildContext context) {
  try {
    return Provider.of<NetworkMonitor?>(context, listen: false);
  } catch (_) {
    return null; // tests and previews run without one
  }
}

/// An HTTP 5xx. Postgres error codes such as 42501 are numbers too, so the
/// range matters.
bool _isServerStatus(int? status) => status != null && status >= 500 && status <= 599;
