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

        do {
            let worksStore = try DrawingDocumentStore()
            let delayStore = try DrawingDocumentStore(
                documentsDirectoryName: "DelayLabDrawings",
                thumbnailsDirectoryName: "DelayLabThumbnails"
            )

            let delayDocument = try loadOrCreateDelayDocument(in: delayStore)
            let delayController = ViewController(store: delayStore, document: delayDocument)
            delayController.title = "Delay"
            let delayNavigation = DrawingNavigationController(rootViewController: delayController)
            delayNavigation.tabBarItem = UITabBarItem(
                title: "Delay",
                image: UIImage(systemName: "scribble.variable"),
                selectedImage: UIImage(systemName: "scribble.variable")
            )

            let canvasController = CanvasExperimentViewController()
            let canvasNavigation = UINavigationController(rootViewController: canvasController)
            canvasNavigation.tabBarItem = UITabBarItem(
                title: "Canvas",
                image: UIImage(systemName: "square.on.square"),
                selectedImage: UIImage(systemName: "square.on.square.fill")
            )

            let worksController = HomeViewController(store: worksStore)
            let worksNavigation = DrawingNavigationController(rootViewController: worksController)
            worksNavigation.tabBarItem = UITabBarItem(
                title: "Works",
                image: UIImage(systemName: "rectangle.grid.2x2"),
                selectedImage: UIImage(systemName: "rectangle.grid.2x2.fill")
            )

            let tabBarController = UITabBarController()
            tabBarController.viewControllers = [delayNavigation, canvasNavigation, worksNavigation]
            tabBarController.selectedIndex = 0

            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = tabBarController
            window.makeKeyAndVisible()
            self.window = window
        } catch {
            let fallback = UIViewController()
            fallback.view.backgroundColor = .systemBackground

            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = "OffsetDraw could not open its local workspace."
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            label.numberOfLines = 0
            fallback.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: fallback.view.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(equalTo: fallback.view.trailingAnchor, constant: -24),
                label.centerYAnchor.constraint(equalTo: fallback.view.centerYAnchor)
            ])

            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = fallback
            window.makeKeyAndVisible()
            self.window = window
        }
    }

    private func loadOrCreateDelayDocument(in store: DrawingDocumentStore) throws -> DrawingDocument {
        if let existing = store.listDocuments().first {
            return try store.loadDocument(id: existing.id)
        }

        let document = try store.createDocument()
        try store.renameDocument(id: document.id, title: "Delay Lab")
        return try store.loadDocument(id: document.id)
    }
}
