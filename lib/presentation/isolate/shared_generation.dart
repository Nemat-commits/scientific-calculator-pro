import 'dart:ffi';

/// A 32-bit counter in native memory that the UI isolate and the worker
/// isolate can both see.
///
/// Dart isolates do not share their heaps, so a busy worker cannot be told
/// through a message that a newer keystroke arrived - it would only read the
/// message after finishing. A word of `malloc`ed memory is visible to both
/// sides instantly: the UI isolate stores the latest generation id, the
/// worker compares it against its own in every cooperative check.
final class SharedGeneration {
  SharedGeneration._(this._word);

  final Pointer<Int32> _word;

  /// Allocates the counter, or returns `null` where the C allocator cannot be
  /// reached (the pool then falls back to time budgets only).
  static SharedGeneration? tryAllocate() {
    try {
      final allocate = DynamicLibrary.process()
          .lookupFunction<Pointer<Void> Function(IntPtr), Pointer<Void> Function(int)>('malloc');
      final memory = allocate(sizeOf<Int32>());
      if (memory == nullptr) return null;
      final word = memory.cast<Int32>()..value = 0;
      return SharedGeneration._(word);
    } on Object {
      return null;
    }
  }

  /// Attaches to a counter that another isolate allocated.
  factory SharedGeneration.fromAddress(int address) => SharedGeneration._(Pointer<Int32>.fromAddress(address));

  /// Address to hand to the worker isolate.
  int get address => _word.address;

  int get value => _word.value;

  set value(int generation) => _word.value = generation;
}
