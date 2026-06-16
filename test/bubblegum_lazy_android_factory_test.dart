import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:rive_native/src/ffi/rive_renderer_ffi.dart';

/// BUBBLEGUM FORK regression guard — BUBBLEGUM-APP-2E4 / -263.
///
/// Upstream `rive_native` eagerly calls the native `riveFactory()` during
/// `_RiveNativeFFI.initialize()` on Android, which builds the GL render context
/// and compiles Mali shaders on the UI thread — the ANR. This fork instead
/// stores the resolver in [FFIRiveFactory.deferredAndroidFactory] and only
/// invokes it on the first genuine `Factory.rive` use.
///
/// These tests lock that contract with a fake resolver returning a sentinel
/// pointer that is never dereferenced, so they need no native library and run
/// on any host (CI included).
void main() {
  late FFIRiveFactory factory;
  // A non-null fake native factory pointer. Only its `.address` is ever read;
  // it is never dereferenced.
  final sentinel = Pointer<Void>.fromAddress(0xB00B1E);

  setUp(() {
    factory = FFIRiveFactory.instance;
    // Reset the singleton to the pristine Android pre-init state.
    factory.pointer = nullptr;
    FFIRiveFactory.deferredAndroidFactory = null;
  });

  tearDown(() {
    factory.pointer = nullptr;
    FFIRiveFactory.deferredAndroidFactory = null;
  });

  test('deferred resolver is NOT invoked during init or support checks', () {
    var resolverCalls = 0;
    FFIRiveFactory.deferredAndroidFactory = () {
      resolverCalls++;
      return sentinel;
    };

    // The factory reports as supported (it WILL work when used)...
    expect(factory.isSupported, isTrue);
    // ...but the native render context has NOT been built. This is the whole
    // point of the fork: no GL context / shader compile during init, so the
    // first Rive load on a low-end Mali device cannot ANR.
    expect(
      resolverCalls,
      0,
      reason: 'native riveFactory() must not run eagerly (would compile Mali '
          'shaders on the UI thread and ANR)',
    );
    expect(factory.pointer, nullptr);
  });

  test('resolver fires exactly once, lazily, on first genuine use', () {
    var resolverCalls = 0;
    FFIRiveFactory.deferredAndroidFactory = () {
      resolverCalls++;
      return sentinel;
    };

    // First real use of the Factory.rive pointer builds the context once.
    expect(factory.nativePointerAddress, sentinel.address);
    expect(resolverCalls, 1);

    // Subsequent uses reuse the built context; it is not rebuilt.
    expect(factory.nativePointerAddress, sentinel.address);
    expect(factory.pointer, sentinel);
    expect(resolverCalls, 1);
  });

  test('with no deferred resolver, factory is unsupported and never builds', () {
    // Mirrors a platform where init assigns the pointer directly (iOS/desktop)
    // or has not run: a null pointer with no resolver is simply unsupported and
    // the lazy hook is a no-op.
    expect(factory.isSupported, isFalse);
    expect(factory.nativePointerAddress, 0);
    expect(factory.pointer, nullptr);
  });
}
