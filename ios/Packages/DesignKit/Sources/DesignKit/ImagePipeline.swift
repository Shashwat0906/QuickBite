import UIKit

/// Two-level image cache:
/// 1. `NSCache` of decoded `UIImage`s (memory, auto-evicted under pressure)
/// 2. `URLCache` on disk for the raw bytes (survives relaunches)
///
/// Identical concurrent requests share one download, images are decoded and
/// downsampled off the main thread, and `prefetch(_:)` warms the cache for
/// collection-view prefetching.
public final class ImagePipeline: @unchecked Sendable {
    public static let shared = ImagePipeline()

    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private let lock = NSLock()

    /// Counters useful for the Instruments/performance write-up.
    public private(set) var memoryHits = 0
    public private(set) var downloads = 0

    public init(memoryLimitMB: Int = 80, diskLimitMB: Int = 200) {
        memory.totalCostLimit = memoryLimitMB * 1024 * 1024
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 0, diskCapacity: diskLimitMB * 1024 * 1024, directory: nil)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    public func cachedImage(for url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    /// Loads (and caches) an image, downsampled to `targetSize` points.
    public func image(for url: URL, targetSize: CGSize? = nil, scale: CGFloat = 3) async -> UIImage? {
        if let cached = cachedImage(for: url) {
            lock.lock(); memoryHits += 1; lock.unlock()
            return cached
        }
        let task: Task<UIImage?, Never> = {
            lock.lock(); defer { lock.unlock() }
            if let existing = inFlight[url] { return existing }
            let new = Task<UIImage?, Never> { [session] in
                guard let result = try? await session.data(from: url) else { return nil }
                return Self.decode(result.0, targetSize: targetSize, scale: scale)
            }
            inFlight[url] = new
            downloads += 1
            return new
        }()
        let image = await task.value
        lock.lock(); inFlight[url] = nil; lock.unlock()
        if let image {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            memory.setObject(image, forKey: url as NSURL, cost: cost)
        }
        return image
    }

    public func prefetch(_ urls: [URL], targetSize: CGSize? = nil) {
        for url in urls where cachedImage(for: url) == nil {
            Task(priority: .utility) { _ = await self.image(for: url, targetSize: targetSize) }
        }
    }

    public func removeAll() { memory.removeAllObjects() }

    /// ImageIO downsampling: decodes straight to the display size, which uses
    /// far less memory than decoding a full 2000px photo for a 80pt thumbnail.
    static func decode(_ data: Data, targetSize: CGSize?, scale: CGFloat) -> UIImage? {
        guard let targetSize, targetSize.width > 0,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return UIImage(data: data)?.preparingForDisplay() }
        let maxPixel = max(targetSize.width, targetSize.height) * scale
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return UIImage(data: data) }
        return UIImage(cgImage: cg)
    }
}

/// `UIImageView` that loads a remote URL through `ImagePipeline`, shows a warm
/// placeholder while loading, and cancels correctly when cells are reused.
public final class RemoteImageView: UIImageView {
    private var loadTask: Task<Void, Never>?
    private(set) var currentURL: URL?
    private let placeholderIcon = UIImageView(image: UIImage(systemName: "cup.and.saucer.fill"))

    public override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .scaleAspectFill
        clipsToBounds = true
        backgroundColor = DK.Color.skeleton
        translatesAutoresizingMaskIntoConstraints = false
        placeholderIcon.tintColor = DK.Color.textTertiary.withAlphaComponent(0.5)
        placeholderIcon.contentMode = .scaleAspectFit
        placeholderIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderIcon)
        NSLayoutConstraint.activate([
            placeholderIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholderIcon.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.3),
            placeholderIcon.heightAnchor.constraint(equalTo: placeholderIcon.widthAnchor),
        ])
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public func setImage(url: URL?, pipeline: ImagePipeline = .shared) {
        guard url != currentURL || image == nil else { return }
        loadTask?.cancel()
        currentURL = url
        guard let url else { image = nil; placeholderIcon.isHidden = false; return }

        if let cached = pipeline.cachedImage(for: url) {
            image = cached
            placeholderIcon.isHidden = true
            return
        }
        image = nil
        placeholderIcon.isHidden = false
        let size = bounds.size == .zero ? CGSize(width: 400, height: 300) : bounds.size
        loadTask = Task { [weak self] in
            let loaded = await pipeline.image(for: url, targetSize: size)
            guard let self, !Task.isCancelled, self.currentURL == url else { return }
            self.placeholderIcon.isHidden = loaded != nil
            UIView.transition(with: self, duration: DK.Motion.fast, options: .transitionCrossDissolve) { self.image = loaded }
        }
    }

    public func cancel() {
        loadTask?.cancel()
        loadTask = nil
        currentURL = nil
        image = nil
        placeholderIcon.isHidden = false
    }
}
