import UIKit

final class DrawingNavigationController: UINavigationController, UINavigationControllerDelegate, UIGestureRecognizerDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        updateInteractivePopGesture(for: topViewController)
    }

    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        updateInteractivePopGesture(for: viewController)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === interactivePopGestureRecognizer
            || gestureRecognizer === contentSwipeGestureRecognizer else {
            return true
        }

        return viewControllers.count > 1 && !(topViewController is ViewController)
    }

    private func updateInteractivePopGesture(for viewController: UIViewController?) {
        let allowsInteractivePop = viewControllers.count > 1 && !(viewController is ViewController)
        let popGestures = [interactivePopGestureRecognizer, contentSwipeGestureRecognizer].compactMap { $0 }

        for popGesture in popGestures {
            popGesture.delegate = self
            popGesture.isEnabled = allowsInteractivePop
        }
    }

    private var contentSwipeGestureRecognizer: UIGestureRecognizer? {
        // iOS 26 uses a separate full-width swipe recognizer for navigation transitions.
        view.gestureRecognizers?.first { $0.name == "UINavigationController.contentSwipe" }
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        let window = UIWindow(windowScene: windowScene)
        let store: DrawingDocumentStore
        do {
            store = try DrawingDocumentStore()
        } catch {
            return
        }
        window.rootViewController = DrawingNavigationController(rootViewController: HomeViewController(store: store))
        window.makeKeyAndVisible()
        self.window = window
    }
}
