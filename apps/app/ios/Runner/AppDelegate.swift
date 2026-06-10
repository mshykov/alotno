import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Channel for PNGs opened into the app ("Open with Alotno" from Files etc.).
  /// Dart side: lib/mobile/incoming_files.dart.
  private var incomingChannel: FlutterMethodChannel?
  /// Files that arrived before Dart was listening; drained by `getInitialFiles`.
  private var pendingFiles: [String] = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Cold-start "Open with Alotno": the URL rides in the launch options.
    if let url = launchOptions?[.url] as? URL {
      stash(url)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let messenger = engineBridge.pluginRegistry
      .registrar(forPlugin: "app.alotno.incoming")?.messenger() {
      let channel = FlutterMethodChannel(name: "app.alotno/incoming", binaryMessenger: messenger)
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self else { return result(nil) }
        if call.method == "getInitialFiles" {
          result(self.pendingFiles)
          self.pendingFiles.removeAll()
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      incomingChannel = channel
    }
  }

  /// Warm "Open with Alotno": iOS has already copied the document into our
  /// sandbox Inbox (we register CFBundleDocumentTypes *without* open-in-place),
  /// so the path is directly readable — no security scoping needed.
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    guard url.isFileURL else {
      return super.application(app, open: url, options: options)
    }
    stash(url)
    return true
  }

  /// Accepts a file URL if it's a PNG; pushes it to Dart (or buffers until the
  /// channel is up). Called from here and from SceneDelegate (scene lifecycle).
  func stash(_ url: URL) {
    guard url.isFileURL, url.pathExtension.lowercased() == "png" else { return }
    if let channel = incomingChannel {
      channel.invokeMethod("openFiles", arguments: [url.path])
    } else {
      pendingFiles.append(url.path)
    }
  }
}
