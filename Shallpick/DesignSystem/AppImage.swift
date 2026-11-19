import SwiftUI

/// Bundled demo photos use the same rendering path as remote production photos.
struct AppImage: View {
    let url: URL?
    private let content: (AsyncImagePhase) -> AnyView

    init<Content: View>(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = { AnyView(content($0)) }
    }

    init<Content: View, Placeholder: View>(url: URL?, @ViewBuilder content: @escaping (Image) -> Content,
                                         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.content = { phase in
            if let image = phase.image { AnyView(content(image)) }
            else { AnyView(placeholder()) }
        }
    }

    var body: some View {
        if url?.scheme == "demo-asset", let name = url?.lastPathComponent {
            content(.success(Image(name)))
        } else {
            AsyncImage(url: url) { phase in content(phase) }
        }
    }
}
