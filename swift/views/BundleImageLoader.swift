import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

// Loads chain/token images from the root `resources/icons/` folder via
// Bundle.main — no xcassets dependency. The icons folder lands in the iOS
// bundle via a PBXFileSystemSynchronizedRootGroup that references `../resources`.
//
// Lookup order in `image(named:)`:
//   1. Cached UIImage (a previously-decoded PNG OR a previously-rendered SVG snapshot).
//   2. Flat-bundle `<name>.svg` — rendered once via `SVGRenderer.render` (WKWebView
//      snapshot, async). The cache miss returns nil; callers should pre-warm
//      the cache via `warmRasterCache()` so this miss never happens at render time.
//   3. Flat-bundle `<name>.png` — synchronous fallback for icons that haven't
//      been migrated to SVG yet.
//
// On non-Apple targets, replace the UIKit branch with whatever image-loading
// API the platform provides; the on-disk layout (`resources/icons/{name}.{svg,png}`)
// stays identical.
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

    private static func pngURL(forImageNamed name: String) -> URL? {
        #if canImport(UIKit)
            let key = "png:\(name)" as NSString
            if let cached = urlCache.object(forKey: key) { return cached.url }
        #endif
        let resolved = resolvedURL(forImageNamed: name, ext: "png")
        #if canImport(UIKit)
            urlCache.setObject(CachedURL(resolved), forKey: "png:\(name)" as NSString)
        #endif
        return resolved
    }

    /// SVG file URL for `name` if `<name>.svg` exists in the bundle. SVGs are
    /// rendered to UIImage via `SVGRenderer.render(svgURL:size:)` and cached.
    static func svgURL(forImageNamed name: String) -> URL? {
        #if canImport(UIKit)
            let key = "svg:\(name)" as NSString
            if let cached = urlCache.object(forKey: key) { return cached.url }
        #endif
        let resolved = resolvedURL(forImageNamed: name, ext: "svg")
        #if canImport(UIKit)
            urlCache.setObject(CachedURL(resolved), forKey: "svg:\(name)" as NSString)
        #endif
        return resolved
    }

    private static func resolvedURL(forImageNamed name: String, ext: String) -> URL? {
        // Xcode's PBXFileSystemSynchronizedRootGroup flattens the referenced
        // folder's contents into the bundle root, so icons/*.{ext} end up
        // at the top level. Ask Bundle first, then fall back to legacy subpaths.
        if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        for subpath in ["icons", "Resources/icons"] {
            let candidate =
                resourceURL
                .appendingPathComponent(subpath, isDirectory: true)
                .appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// Synchronous lookup. Returns the cached UIImage if present, or loads a
    /// flat-bundle PNG synchronously. Returns nil if the only available file
    /// is an SVG that hasn't been rendered yet — call `resolveImage(named:size:)`
    /// to render and cache it asynchronously.
    static func image(named name: String) -> UIImage? {
        #if canImport(UIKit)
            let key = name as NSString
            if let cached = imageCache.object(forKey: key) { return cached }
            guard let url = pngURL(forImageNamed: name), let image = UIImage(contentsOfFile: url.path) else { return nil }
            imageCache.setObject(image, forKey: key, cost: approximateByteCost(for: image))
            return image
        #else
            return nil
        #endif
    }

    /// Asynchronous lookup. Resolution order:
    /// 1. Cached UIImage (cache hit returns immediately).
    /// 2. Flat-bundle `<name>.svg` — rendered via `SVGRenderer`, cached.
    /// 3. Flat-bundle `<name>.png` — loaded synchronously, cached.
    /// Returns nil only when no icon file exists. `targetSize` is used as the
    /// SVG render size (UIImage then scales cleanly to any display size).
    @MainActor
    static func resolveImage(named name: String, targetSize: CGFloat = 256) async -> UIImage? {
        #if canImport(UIKit)
            let key = name as NSString
            if let cached = imageCache.object(forKey: key) { return cached }
            // SVG first — the user's preferred format going forward.
            if let svg = svgURL(forImageNamed: name) {
                let size = CGSize(width: targetSize, height: targetSize)
                if let rendered = await SVGRenderer.render(svgURL: svg, size: size) {
                    imageCache.setObject(rendered, forKey: key, cost: approximateByteCost(for: rendered))
                    return rendered
                }
            }
            // PNG fallback for icons not yet migrated to SVG.
            if let url = pngURL(forImageNamed: name), let image = UIImage(contentsOfFile: url.path) {
                imageCache.setObject(image, forKey: key, cost: approximateByteCost(for: image))
                return image
            }
            return nil
        #else
            return nil
        #endif
    }

    /// Renders all SVGs in the bundle into the cache. Optional warm-up that
    /// makes the first badge render after launch already a cache hit. Most
    /// callers should rely on `resolveImage(named:size:)` per-badge instead.
    @MainActor
    static func warmRasterCache(targetSize: CGFloat = 256) async {
        #if canImport(UIKit)
            guard let bundleURL = Bundle.main.resourceURL else { return }
            let candidateDirs: [URL] = [
                bundleURL,
                bundleURL.appendingPathComponent("icons", isDirectory: true),
                bundleURL.appendingPathComponent("Resources/icons", isDirectory: true),
            ]
            var seen = Set<String>()
            for dir in candidateDirs {
                guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
                    continue
                }
                for file in contents where file.pathExtension.lowercased() == "svg" {
                    let stem = file.deletingPathExtension().lastPathComponent
                    guard seen.insert(stem).inserted else { continue }
                    if imageCache.object(forKey: stem as NSString) != nil { continue }
                    let size = CGSize(width: targetSize, height: targetSize)
                    if let rendered = await SVGRenderer.render(svgURL: file, size: size) {
                        imageCache.setObject(rendered, forKey: stem as NSString, cost: approximateByteCost(for: rendered))
                    }
                }
            }
        #endif
    }

    #if canImport(UIKit)
        private static func approximateByteCost(for image: UIImage) -> Int {
            let scale = image.scale
            return Int(image.size.width * scale * image.size.height * scale * 4)
        }
    #endif

    /// Returns true when an SVG OR PNG file exists in the flat bundle layout.
    static func hasImage(named name: String) -> Bool {
        svgURL(forImageNamed: name) != nil || pngURL(forImageNamed: name) != nil
    }
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
