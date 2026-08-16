import AppKit
import SwiftUI

struct ProviderIconView: View {
    let provider: UsageProvider
    let size: CGFloat

    var body: some View {
        if let image = ProviderIconImage.image(for: provider) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: provider.icon)
                .font(.system(size: size * 0.8))
                .frame(width: size, height: size)
        }
    }
}

enum ProviderIconImage {
    static func image(for provider: UsageProvider) -> NSImage? {
        guard let url = Bundle.main.url(forResource: provider.rawValue, withExtension: "svg"),
        let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        return image
    }
}
