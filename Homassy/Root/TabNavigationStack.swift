import SwiftUI

/// Encodes a `NavigationPath` for `@SceneStorage`. Paths containing non-Codable values are not stored.
enum NavigationPathCoding {
    static func decode(_ data: Data?) -> NavigationPath {
        guard let data,
              let representation = try? JSONDecoder().decode(NavigationPath.CodableRepresentation.self, from: data)
        else { return NavigationPath() }
        return NavigationPath(representation)
    }

    static func encode(_ path: NavigationPath) -> Data? {
        guard let representation = path.codable else { return nil }
        return try? JSONEncoder().encode(representation)
    }
}

/// One tab's navigation stack. Its path is restored with the scene, so rotation, backgrounding and
/// scene restoration keep the user where they were.
struct TabNavigationStack<Root: View>: View {
    @SceneStorage private var storedPath: Data?
    @State private var path = NavigationPath()
    @State private var restored = false
    private let root: Root

    init(tab: AppTab, @ViewBuilder root: () -> Root) {
        _storedPath = SceneStorage("navigationPath.\(tab.rawValue)")
        self.root = root()
    }

    var body: some View {
        NavigationStack(path: $path) {
            root
        }
        .onAppear {
            guard !restored else { return }
            restored = true
            path = NavigationPathCoding.decode(storedPath)
        }
        .onChange(of: path) { _, newPath in
            storedPath = NavigationPathCoding.encode(newPath)
        }
    }
}
