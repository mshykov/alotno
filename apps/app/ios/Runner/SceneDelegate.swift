import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  // With the UIScene lifecycle, "Open with Alotno" file URLs arrive here (the
  // legacy AppDelegate application(_:open:options:) is not called). Forward
  // them to the AppDelegate, which owns the Flutter channel + buffering.

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    forward(connectionOptions.urlContexts)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    forward(URLContexts)
  }

  private func forward(_ contexts: Set<UIOpenURLContext>) {
    guard !contexts.isEmpty,
          let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
    for context in contexts {
      appDelegate.stash(context.url)
    }
  }
}
