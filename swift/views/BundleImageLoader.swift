import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

// Loads token images from the root /Resources/icons/ folder via Bundle.main — no xcassets dependency.
// A PBXFileSystemSynchronizedRootGroup in the Xcode project references ../Resources so the
// directory lands in the bundle as:
//   {bundle.resourceURL}/Resources/icons/{name}.png
// On non-Apple targets, replace the UIKit branch with whatever image-loading API the
// platform provides; the on-disk layout (a flat folder of {assetName}.png files) stays identical.
enum BundleImageLoader {
    #if canImport(UIKit)
        private static let imageCache: NSCache<NSString, UIImage> = {
            let cache = NSCache<NSString, UIImage>()
            cache.countLimit = 64
            // Bound by total pixel cost too — prevents the resident-memory
            // footprint from scaling linearly with countLimit when icons are
            // high-res bitmaps. 16 MB is plenty for 64 token icons at 256×256.
            cache.totalCostLimit = 16 * 1024 * 1024
            return cache
        }()
        private final class CachedURL {
            let url: URL?
            init(_ url: URL?) { self.url = url }
        }
        private static let urlCache = NSCache<NSString, CachedURL>()
    #endif

    private static func url(forImageNamed name: String) -> URL? {
        #if canImport(UIKit)
            let key = name as NSString
            if let cached = urlCache.object(forKey: key) { return cached.url }
        #endif
        let resolved = resolvedURL(forImageNamed: name)
        #if canImport(UIKit)
            urlCache.setObject(CachedURL(resolved), forKey: name as NSString)
        #endif
        return resolved
    }

    private static func resolvedURL(forImageNamed name: String) -> URL? {
        // Xcode's PBXFileSystemSynchronizedRootGroup flattens the referenced
        // folder's contents into the bundle root, so icons/*.png end up
        // at the top level. Ask Bundle first, then fall back to legacy subpaths.
        if let url = Bundle.main.url(forResource: name, withExtension: "png") { return url }
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        for subpath in ["icons", "Resources/icons"] {
            let candidate =
                resourceURL
                .appendingPathComponent(subpath, isDirectory: true)
                .appendingPathComponent("\(name).png")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// Returns a UIImage loaded directly from the bundle directory, bypassing xcassets.
    /// Returns nil if no file named `\(name).png` exists in icons/.
    static func image(named name: String) -> UIImage? {
        #if canImport(UIKit)
            let key = name as NSString
            if let cached = imageCache.object(forKey: key) { return cached }
            guard let url = url(forImageNamed: name), let image = UIImage(contentsOfFile: url.path) else { return nil }
            let cost = approximateByteCost(for: image)
            imageCache.setObject(image, forKey: key, cost: cost)
            return image
        #else
            return nil
        #endif
    }

    #if canImport(UIKit)
        private static func approximateByteCost(for image: UIImage) -> Int {
            let scale = image.scale
            return Int(image.size.width * scale * image.size.height * scale * 4)
        }
    #endif

    /// Returns true when a bundle image exists for the given name.
    static func hasImage(named name: String) -> Bool { url(forImageNamed: name) != nil }
}

/// A SwiftUI view that renders a token image loaded from Resources/icons/.
/// Falls back to `nil` content when the image is unavailable so callers can provide their own fallback.
struct BundleTokenImage: View {
    let name: String
    var size: CGFloat = 40

    var body: some View {
        if let uiImage = BundleImageLoader.image(named: name) {
            Image(uiImage: uiImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        }
    }
}
