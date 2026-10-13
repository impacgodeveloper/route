/// Outcome of a service operation. Failures carry user-facing messages so
/// screens can show inline errors while preserving form input.
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;
  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => null,
  };
  List<String> get errors => switch (this) {
    Ok<T>() => const [],
    Err<T>(:final messages) => messages,
  };
  String get message => switch (this) {
    Ok<T>(:final info) => info ?? 'Done',
    Err<T>(:final messages) => messages.join('\n'),
  };
}

class Ok<T> extends Result<T> {
  const Ok(this.value, {this.info, this.warnings = const []});
  final T value;
  final String? info;
  final List<String> warnings;
}

class Err<T> extends Result<T> {
  const Err(this.messages);
  Err.single(String message) : messages = [message];
  final List<String> messages;
}
