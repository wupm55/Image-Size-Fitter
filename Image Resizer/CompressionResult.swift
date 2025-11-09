import UIKit

struct CompressionResult {
    let compressedImage: UIImage
    let compressedImageData: Data
    let originalSizeKB: Double
    let compressedSizeKB: Double
    let compressionRatio: Double
}
