import UIKit

/// 图像压缩器（仅JPEG质量压缩）
class ImageCompressor {
    
    /// 快速压缩图像（通过JPEG质量压缩）
    /// - Parameters:
    ///   - image: 原始UIImage
    ///   - jpegQuality: JPEG压缩质量 (0.0-1.0)
    /// - Returns: 压缩结果，如果失败返回nil
    static func compressImage(
        _ image: UIImage,
        jpegQuality: CGFloat
    ) -> CompressionResult? {
        
        guard jpegQuality > 0 && jpegQuality <= 1.0 else {
            print("错误: jpegQuality 必须在 0 到 1 之间")
            return nil
        }
        
        // 使用JPEG压缩
        guard let jpegData = image.jpegData(compressionQuality: jpegQuality),
              let compressedImage = UIImage(data: jpegData) else {
            print("错误: 无法进行JPEG压缩")
            return nil
        }
        
        // 计算文件大小
        let originalSize = estimateImageSize(image, quality: 1.0)
        let compressedSize = Double(jpegData.count)
        
        let result = CompressionResult(
            compressedImage: compressedImage,
            compressedImageData: jpegData,
            originalSizeKB: originalSize / 1024.0,
            compressedSizeKB: compressedSize / 1024.0,
            compressionRatio: originalSize / compressedSize
        )
        
        return result
    }
    
    /// 压缩到目标文件大小（使用二分搜索自动调整JPEG质量）
    /// - Parameters:
    ///   - image: 原始UIImage
    ///   - targetKB: 目标文件大小（KB）
    ///   - tolerance: 容差范围（KB），默认10KB
    ///   - maxIterations: 最大迭代次数，默认15次
    /// - Returns: 压缩结果，如果失败返回nil
    static func compressToTargetSize(
        _ image: UIImage,
        targetKB: Double,
        tolerance: Double = 10.0,
        maxIterations: Int = 15
    ) -> CompressionResult? {
        
        guard targetKB > 0 else {
            print("错误: targetKB 必须大于 0")
            return nil
        }
        
        let targetBytes = targetKB * 1024.0
        let toleranceBytes = tolerance * 1024.0
        
        // 二分搜索的质量范围
        var minQuality: CGFloat = 0.01
        var maxQuality: CGFloat = 1.0
        var bestResult: CompressionResult?
        var bestDifference = Double.infinity
        
        print("开始压缩到目标大小: \(targetKB) KB")
        
        for iteration in 0..<maxIterations {
            let currentQuality = (minQuality + maxQuality) / 2.0
            
            guard let jpegData = image.jpegData(compressionQuality: currentQuality) else {
                print("错误: 无法进行JPEG压缩")
                return bestResult
            }
            
            let currentSize = Double(jpegData.count)
            let difference = abs(currentSize - targetBytes)
            
            print("迭代 \(iteration + 1): 质量=\(String(format: "%.3f", currentQuality)), 大小=\(String(format: "%.2f", currentSize/1024.0)) KB, 目标=\(targetKB) KB")
            
            // 保存最接近目标的结果
            if difference < bestDifference {
                if let compressedImage = UIImage(data: jpegData) {
                    let originalSize = estimateImageSize(image, quality: 1.0)
                    
                    bestResult = CompressionResult(
                        compressedImage: compressedImage,
                        compressedImageData: jpegData,
                        originalSizeKB: originalSize / 1024.0,
                        compressedSizeKB: currentSize / 1024.0,
                        compressionRatio: originalSize / currentSize
                    )
                    bestDifference = difference
                }
            }
            
            // 如果在容差范围内，提前返回
            if difference <= toleranceBytes {
                print("达到目标大小（在容差范围内）")
                return bestResult
            }
            
            // 调整搜索范围
            if currentSize > targetBytes {
                // 文件太大，降低质量
                maxQuality = currentQuality
            } else {
                // 文件太小，提高质量
                minQuality = currentQuality
            }
            
            // 如果搜索范围太小，停止迭代
            if maxQuality - minQuality < 0.001 {
                print("质量范围收敛，停止迭代")
                break
            }
        }
        
        print("完成压缩，最接近目标的大小: \(String(format: "%.2f", bestResult?.compressedSizeKB ?? 0)) KB")
        return bestResult
    }
    
    /// 估算图像大小（字节）
    static func estimateImageSize(_ image: UIImage, quality: CGFloat = 1.0) -> Double {
        guard let data = image.jpegData(compressionQuality: quality) else {
            return 0
        }
        return Double(data.count)
    }
    
    /// 打印压缩结果
    static func printCompressionResult(_ result: CompressionResult) {
        print("============================================================")
        print("图像压缩结果")
        print("============================================================")
        print(String(format: "原始文件大小:        %10.2f KB", result.originalSizeKB))
        print("------------------------------------------------------------")
        print(String(format: "压缩后文件大小:      %10.2f KB", result.compressedSizeKB))
        print(String(format: "压缩比:              %.2fx", result.compressionRatio))
        print("============================================================")
    }
}
