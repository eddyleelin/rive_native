# Bubblegum fork of `rive_native`

This is a fork of the published `rive_native` **0.1.9** package (MIT, © Rive)
with a single, surgical patch. It is consumed by the Bubblegum app via a
`dependency_overrides` git ref, mirroring the `flutter_soloud` fork.

## Why this fork exists — BUBBLEGUM-APP-2E4 (and -263)

On Android, `_RiveNativeFFI.initialize()` (run once on the first Rive file
decode, before any draw) **eagerly** calls the native `riveFactory()` to build
the `Factory.rive` GL render context. That render context's constructor compiles
its GLSL shaders **synchronously on the calling (UI) thread**. On low-end Mali
GPUs the driver's shader compiler stalls the main thread past the Android ANR
deadline on the first Rive load (e.g. onboarding cold start) — surfaced as
`ApplicationNotResponding` BUBBLEGUM-APP-2E4 (itel A671LC, Android 14) and
earlier BUBBLEGUM-APP-263 (Galaxy A21s, Android 12).

The Bubblegum app renders **exclusively** with `Factory.flutter` on Android (see
the app's `resolveRiveFactory()`), which uses its own independent native factory
(`_makeFlutterFactory()`) and never touches the `Factory.rive` pointer. So that
eagerly-built GL context + shader compile is pure dead work on Android — yet it
still ANRs the app.

The original fix (route everything through `Factory.flutter`) addressed the
draw-time fd leak (rive-flutter #522) but **not** this init-time compile, because
the compile lives in the package's init path regardless of which factory the app
draws with.

## The patch (Dart-only — native `.so` unchanged)

- `lib/src/rive_native_ffi.dart` — the Android branch of `initialize()` no longer
  *calls* `riveFactory()`; it stores the resolved function pointer in
  `FFIRiveFactory.deferredAndroidFactory` instead.
- `lib/src/ffi/rive_renderer_ffi.dart` — `FFIRiveFactory` invokes that deferred
  function **lazily**, on the first genuine `Factory.rive` use (`makePath` /
  `makePaint` / `makeText` / `make*Buffer` / `decodeImage` / `nativePointerAddress`).
  `isSupported` reports `true` when the deferred factory is present, without
  triggering the build.

Net effect: apps that only ever use `Factory.flutter` on Android never build the
native GL context and never pay the shader compile (no ANR). Any real
`Factory.rive` use on Android still works — it just builds the context lazily on
first use instead of during init. iOS/desktop/web are untouched.

When upstream `rive_native` defers this init (or exposes a flag to skip it),
drop this fork and return to the hosted package.
