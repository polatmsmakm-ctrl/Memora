import UIKit

/// Stores item images (dual coding / image-based recall) as JPEG files on disk.
enum ImageStore {
    static let maxDimension: CGFloat = 1600

    static func url(for name: String) -> URL {
        FileLocations.imagesDirectory.appendingPathComponent(name)
    }

    @discardableResult
    static func save(_ image: UIImage) -> String? {
        let resized = downscale(image)
        guard let data = resized.jpegData(compressionQuality: 0.82) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: url(for: name), options: [.atomic])
            return name
        } catch {
            return nil
        }
    }

    static func save(data: Data, name: String) {
        try? data.write(to: url(for: name), options: [.atomic])
    }

    static func load(_ name: String?) -> UIImage? {
        guard let name else { return nil }
        return UIImage(contentsOfFile: url(for: name).path)
    }

    static func data(_ name: String) -> Data? {
        try? Data(contentsOf: url(for: name))
    }

    static func delete(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }

    static func downscale(_ image: UIImage) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
