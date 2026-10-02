import 'dart:async';
import 'dart:io';

/// HTTP failures keep their status so temporary outages and expired links can
/// be retried without retrying missing files or invalid upload credentials.
class TransferHttpException extends HttpException {
  TransferHttpException(this.statusCode, {String? message, super.uri})
    : super(message ?? 'HTTP $statusCode');
  final int statusCode;
  bool get retryable =>
      {408, 425, 429}.contains(statusCode) ||
      (statusCode >= 500 && statusCode < 600);
}

bool isTemporaryTransferError(Object error) =>
    error is SocketException ||
    error is TimeoutException ||
    (error is TransferHttpException ? error.retryable : error is HttpException);

String transferErrorMessage(Object error) {
  if (error is TransferHttpException) {
    if (error.statusCode == 429) {
      return 'The service is busy. Retrying shortly.';
    }
    if (error.retryable) return 'The service is unavailable. Retrying shortly.';
    if ({401, 403}.contains(error.statusCode)) {
      return 'The source denied this download. Try another source or retry.';
    }
    if (error.statusCode == 404) return 'This file is no longer available.';
    return error.message;
  }
  if (error is SocketException) {
    return 'Cannot reach the server. Check your connection; retrying automatically.';
  }
  if (error is TimeoutException || error is HttpException) {
    return 'The connection was interrupted. Retrying automatically.';
  }
  if (error is FileSystemException) return error.message;
  if (error is FormatException) return error.message;
  return '$error';
}

/// One backoff timer per queue, rather than one failing request per song.
/// Connectivity changes can trigger an earlier retry; a successful transfer
/// resets the backoff. Manual pause/cancel always cancels the timer.
class TransferRecovery {
  TransferRecovery({
    required this.onRetry,
    this.retryDelay = const Duration(seconds: 15),
  });
  final void Function() onRetry;
  final Duration retryDelay;
  Timer? _timer;
  int _failures = 0;
  String? message;
  bool get waiting => message != null;

  void wait(Object error) {
    message = transferErrorMessage(error);
    // Concurrent upload workers share the same outage and timer.
    if (_timer != null) return;
    final multiplier = 1 << _failures.clamp(0, 2);
    _failures++;
    _timer = Timer(retryDelay * multiplier, () {
      _timer = null;
      onRetry();
    });
  }

  void clear({bool reset = false}) {
    _timer?.cancel();
    _timer = null;
    message = null;
    if (reset) _failures = 0;
  }

  void dispose() => clear(reset: true);
}
