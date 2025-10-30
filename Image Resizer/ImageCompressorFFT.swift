import UIKit
import Accelerate

/// 图像压缩结果
struct CompressionResult {
    let compressedImage: UIImage
    let compressedImageData: Data  // 保存实际的JPEG数据，用于精确保存
    let originalSizeKB: Double
    let compressedSizeKB: Double
    let compressionRatio: Double
}

// 注意：此文件仅保留 CompressionResult 定义
// 实际的压缩功能请使用 ImageCompressor.swift
// 此文件可以在确认项目正常运行后删除

/// FFT图像压缩器（已废弃，请使用 ImageCompressor）
@available(*, deprecated, message: "请使用 ImageCompressor 类")
class ImageCompressorFFT {
    
    /// 使用FFT压缩图像（支持任意尺寸，自动padding）
    /// - Parameters:
    ///   - image: 原始UIImage
    ///   - keepRatio: 保留的频域系数比例 (0.0-1.0)
    ///   - jpegQuality: JPEG压缩质量 (0.0-1.0)，默认0.85
    /// - Returns: 压缩结果，如果失败返回nil
    static func compressImage(
        _ image: UIImage,
        keepRatio: Double,
        jpegQuality: CGFloat = 0.85
    ) -> CompressionResult? {
        
        guard keepRatio > 0 && keepRatio <= 1.0 else {
            print("错误: keepRatio 必须在 0 到 1 之间")
            return nil
        }
        
        // 转换为CGImage
        guard let cgImage = image.cgImage else {
            print("错误: 无法获取CGImage")
            return nil
        }
        
        let originalWidth = cgImage.width
        let originalHeight = cgImage.height
        
        // 计算padding后的尺寸（2的幂次方）
        let paddedWidth = nextPowerOfTwo(originalWidth)
        let paddedHeight = nextPowerOfTwo(originalHeight)
        
        // 提取RGB通道数据
        guard let (redChannel, greenChannel, blueChannel) = extractRGBChannels(from: cgImage) else {
            print("错误: 无法提取RGB通道")
            return nil
        }
        
        // 并行处理RGB通道以提升速度
        var compressedRed: (normalizedData: [Float], coefficientsKept: Int)!
        var compressedGreen: (normalizedData: [Float], coefficientsKept: Int)!
        var compressedBlue: (normalizedData: [Float], coefficientsKept: Int)!
        
        let dispatchGroup = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)
        
        dispatchGroup.enter()
        queue.async {
            compressedRed = compressChannel(redChannel, originalWidth: originalWidth, originalHeight: originalHeight, paddedWidth: paddedWidth, paddedHeight: paddedHeight, keepRatio: keepRatio)
            dispatchGroup.leave()
        }
        
        dispatchGroup.enter()
        queue.async {
            compressedGreen = compressChannel(greenChannel, originalWidth: originalWidth, originalHeight: originalHeight, paddedWidth: paddedWidth, paddedHeight: paddedHeight, keepRatio: keepRatio)
            dispatchGroup.leave()
        }
        
        dispatchGroup.enter()
        queue.async {
            compressedBlue = compressChannel(blueChannel, originalWidth: originalWidth, originalHeight: originalHeight, paddedWidth: paddedWidth, paddedHeight: paddedHeight, keepRatio: keepRatio)
            dispatchGroup.leave()
        }
        
        dispatchGroup.wait()
        
        // 合并通道并创建图像，保留原始方向
        guard let compressedImage = createImage(
            red: compressedRed.normalizedData,
            green: compressedGreen.normalizedData,
            blue: compressedBlue.normalizedData,
            width: originalWidth,
            height: originalHeight,
            orientation: image.imageOrientation
        ) else {
            print("错误: 无法创建压缩后的图像")
            return nil
        }
        
        // 计算文件大小并保存JPEG数据
        let originalSize = estimateImageSize(image)
        guard let compressedData = compressedImage.jpegData(compressionQuality: jpegQuality) else {
            print("错误: 无法生成JPEG数据")
            return nil
        }
        let compressedSize = Double(compressedData.count)
        
        let result = CompressionResult(
            compressedImage: compressedImage,
            compressedImageData: compressedData,
            originalSizeKB: originalSize / 1024.0,
            compressedSizeKB: compressedSize / 1024.0,
            compressionRatio: originalSize / compressedSize
        )
        
        return result
    }
    
    /// 计算下一个2的幂次方
    private static func nextPowerOfTwo(_ n: Int) -> Int {
        var power = 1
        while power < n {
            power *= 2
        }
        return power
    }
    
    /// 压缩单个颜色通道（优化版）
    private static func compressChannel(
        _ channel: [Float],
        originalWidth: Int,
        originalHeight: Int,
        paddedWidth: Int,
        paddedHeight: Int,
        keepRatio: Double
    ) -> (normalizedData: [Float], coefficientsKept: Int) {
        
        // Padding到2的幂次方
        var paddedChannel = [Float](repeating: 0, count: paddedWidth * paddedHeight)
        for y in 0..<originalHeight {
            for x in 0..<originalWidth {
                paddedChannel[y * paddedWidth + x] = channel[y * originalWidth + x]
            }
        }
        
        let count = paddedWidth * paddedHeight
        
        // 执行2D FFT
        var real = paddedChannel
        var imaginary = [Float](repeating: 0, count: count)
        
        perform2DFFT(real: &real, imaginary: &imaginary, width: paddedWidth, height: paddedHeight)
        
        // 使用vDSP加速计算幅值的平方（避免开方）
        var magnitudes = [Float](repeating: 0, count: count)
        var realSquared = [Float](repeating: 0, count: count)
        var imagSquared = [Float](repeating: 0, count: count)
        
        vDSP_vsq(real, 1, &realSquared, 1, vDSP_Length(count))
        vDSP_vsq(imaginary, 1, &imagSquared, 1, vDSP_Length(count))
        vDSP_vadd(realSquared, 1, imagSquared, 1, &magnitudes, 1, vDSP_Length(count))
        
        // 找到阈值
        let keepCount = Int(Double(count) * keepRatio)
        let dropCount = count - keepCount
        
        var coefficientsKept = count
        if dropCount > 0 && dropCount < count {
            var sortedMagnitudes = magnitudes
            sortedMagnitudes.sort()
            let threshold = sortedMagnitudes[dropCount]
            
            // 应用阈值
            coefficientsKept = 0
            for i in 0..<count {
                if magnitudes[i] >= threshold {
                    coefficientsKept += 1
                } else {
                    real[i] = 0
                    imaginary[i] = 0
                }
            }
        }
        
        // 执行逆FFT
        performInverse2DFFT(real: &real, imaginary: &imaginary, width: paddedWidth, height: paddedHeight)
        
        // 裁剪回原始尺寸
        var croppedChannel = [Float](repeating: 0, count: originalWidth * originalHeight)
        for y in 0..<originalHeight {
            for x in 0..<originalWidth {
                croppedChannel[y * originalWidth + x] = real[y * paddedWidth + x]
            }
        }
        
        // 归一化到 [0, 1]
        let minVal = croppedChannel.min() ?? 0
        let maxVal = croppedChannel.max() ?? 1
        let range = maxVal - minVal
        
        var normalized = [Float](repeating: 0, count: originalWidth * originalHeight)
        if range > 0 {
            for i in 0..<(originalWidth * originalHeight) {
                normalized[i] = (croppedChannel[i] - minVal) / range
            }
        }
        
        return (normalized, coefficientsKept)
    }
    
    /// 执行2D FFT（要求尺寸为2的幂次方）
    private static func perform2DFFT(real: inout [Float], imaginary: inout [Float], width: Int, height: Int) {
        let log2Width = vDSP_Length(log2(Float(width)))
        let log2Height = vDSP_Length(log2(Float(height)))
        
        guard let fftSetup = vDSP_create_fftsetup(max(log2Width, log2Height), FFTRadix(kFFTRadix2)) else {
            return
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }
        
        // 对每一行执行FFT
        for row in 0..<height {
            let offset = row * width
            var rowReal = Array(real[offset..<offset + width])
            var rowImag = Array(imaginary[offset..<offset + width])
            
            rowReal.withUnsafeMutableBufferPointer { realPtr in
                rowImag.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                    vDSP_fft_zip(fftSetup, &splitComplex, 1, log2Width, FFTDirection(FFT_FORWARD))
                }
            }
            
            real.replaceSubrange(offset..<offset + width, with: rowReal)
            imaginary.replaceSubrange(offset..<offset + width, with: rowImag)
        }
        
        // 对每一列执行FFT
        for col in 0..<width {
            var colReal = [Float](repeating: 0, count: height)
            var colImag = [Float](repeating: 0, count: height)
            
            for row in 0..<height {
                colReal[row] = real[row * width + col]
                colImag[row] = imaginary[row * width + col]
            }
            
            colReal.withUnsafeMutableBufferPointer { realPtr in
                colImag.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                    vDSP_fft_zip(fftSetup, &splitComplex, 1, log2Height, FFTDirection(FFT_FORWARD))
                }
            }
            
            for row in 0..<height {
                real[row * width + col] = colReal[row]
                imaginary[row * width + col] = colImag[row]
            }
        }
    }
    
    /// 执行逆2D FFT（要求尺寸为2的幂次方）
    private static func performInverse2DFFT(real: inout [Float], imaginary: inout [Float], width: Int, height: Int) {
        let log2Width = vDSP_Length(log2(Float(width)))
        let log2Height = vDSP_Length(log2(Float(height)))
        
        guard let fftSetup = vDSP_create_fftsetup(max(log2Width, log2Height), FFTRadix(kFFTRadix2)) else {
            return
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }
        
        // 对每一行执行逆FFT
        for row in 0..<height {
            let offset = row * width
            var rowReal = Array(real[offset..<offset + width])
            var rowImag = Array(imaginary[offset..<offset + width])
            
            rowReal.withUnsafeMutableBufferPointer { realPtr in
                rowImag.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                    vDSP_fft_zip(fftSetup, &splitComplex, 1, log2Width, FFTDirection(FFT_INVERSE))
                }
            }
            
            // 归一化
            var scale = Float(1.0) / Float(width)
            vDSP_vsmul(rowReal, 1, &scale, &rowReal, 1, vDSP_Length(width))
            vDSP_vsmul(rowImag, 1, &scale, &rowImag, 1, vDSP_Length(width))
            
            real.replaceSubrange(offset..<offset + width, with: rowReal)
            imaginary.replaceSubrange(offset..<offset + width, with: rowImag)
        }
        
        // 对每一列执行逆FFT
        for col in 0..<width {
            var colReal = [Float](repeating: 0, count: height)
            var colImag = [Float](repeating: 0, count: height)
            
            for row in 0..<height {
                colReal[row] = real[row * width + col]
                colImag[row] = imaginary[row * width + col]
            }
            
            colReal.withUnsafeMutableBufferPointer { realPtr in
                colImag.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                    vDSP_fft_zip(fftSetup, &splitComplex, 1, log2Height, FFTDirection(FFT_INVERSE))
                }
            }
            
            // 归一化
            var scale = Float(1.0) / Float(height)
            vDSP_vsmul(colReal, 1, &scale, &colReal, 1, vDSP_Length(height))
            vDSP_vsmul(colImag, 1, &scale, &colImag, 1, vDSP_Length(height))
            
            for row in 0..<height {
                real[row * width + col] = colReal[row]
                imaginary[row * width + col] = colImag[row]
            }
        }
    }
    
    /// 从CGImage提取RGB通道
    private static func extractRGBChannels(from cgImage: CGImage) -> ([Float], [Float], [Float])? {
        let width = cgImage.width
        let height = cgImage.height
        let count = width * height
        
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        
        var pixelData = [UInt8](repeating: 0, count: count * 4)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var red = [Float](repeating: 0, count: count)
        var green = [Float](repeating: 0, count: count)
        var blue = [Float](repeating: 0, count: count)
        
        for i in 0..<count {
            let offset = i * 4
            red[i] = Float(pixelData[offset]) / 255.0
            green[i] = Float(pixelData[offset + 1]) / 255.0
            blue[i] = Float(pixelData[offset + 2]) / 255.0
        }
        
        return (red, green, blue)
    }
    
    /// 从RGB通道创建图像，保留方向信息
    private static func createImage(
        red: [Float],
        green: [Float],
        blue: [Float],
        width: Int,
        height: Int,
        orientation: UIImage.Orientation = .up
    ) -> UIImage? {
        let count = width * height
        var pixelData = [UInt8](repeating: 0, count: count * 4)
        
        for i in 0..<count {
            let offset = i * 4
            pixelData[offset] = UInt8(max(0, min(255, red[i] * 255)))
            pixelData[offset + 1] = UInt8(max(0, min(255, green[i] * 255)))
            pixelData[offset + 2] = UInt8(max(0, min(255, blue[i] * 255)))
            pixelData[offset + 3] = 255
        }
        
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        guard let cgImage = context.makeImage() else { return nil }
        
        // 使用原始图片的方向信息创建UIImage
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
    }
    
    /// 估算图像大小（字节）
    static func estimateImageSize(_ image: UIImage, quality: CGFloat = 1.0) -> Double {
        guard let data = image.jpegData(compressionQuality: quality) else {
            return 0
        }
        return Double(data.count)
    }
    
    /// 保存压缩后的图像到相册
    static func saveToPhotoLibrary(_ image: UIImage, completion: @escaping (Bool, Error?) -> Void) {
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        completion(true, nil)
    }
    
    /// 快速压缩图像（仅通过JPEG质量压缩，不使用FFT）
    /// - Parameters:
    ///   - image: 原始UIImage
    ///   - jpegQuality: JPEG压缩质量 (0.0-1.0)
    /// - Returns: 压缩结果，如果失败返回nil
    static func quickCompressImage(
        _ image: UIImage,
        jpegQuality: CGFloat
    ) -> CompressionResult? {
        
        guard jpegQuality > 0 && jpegQuality <= 1.0 else {
            print("错误: jpegQuality 必须在 0 到 1 之间")
            return nil
        }
        
        // 直接使用JPEG压缩，不进行FFT处理
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
    
    /// 快速压缩到目标文件大小（使用二分搜索自动调整JPEG质量）
    /// - Parameters:
    ///   - image: 原始UIImage
    ///   - targetKB: 目标文件大小（KB）
    ///   - tolerance: 容差范围（KB），默认10KB
    ///   - maxIterations: 最大迭代次数，默认15次
    /// - Returns: 压缩结果，如果失败返回nil
    static func quickCompressToTargetSize(
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
        
        print("开始快速压缩到目标大小: \(targetKB) KB")
        
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
        
        print("完成快速压缩，最接近目标的大小: \(String(format: "%.2f", bestResult?.compressedSizeKB ?? 0)) KB")
        return bestResult
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

// MARK: - 使用示例

/*
// 在ViewController中使用:

import UIKit

class ViewController: UIViewController {
    
    @IBOutlet weak var originalImageView: UIImageView!
    @IBOutlet weak var compressedImageView: UIImageView!
    @IBOutlet weak var resultLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 加载图像
        guard let image = UIImage(named: "dog") else { return }
        originalImageView.image = image
        
        // 压缩图像
        compressImage(image, keepRatio: 0.05)
    }
    
    func compressImage(_ image: UIImage, keepRatio: Double) {
        // 在后台线程执行压缩
        DispatchQueue.global(qos: .userInitiated).async {
            guard let result = ImageCompressorFFT.compressImage(
                image,
                keepRatio: keepRatio,
                jpegQuality: 0.85
            ) else {
                print("压缩失败")
                return
            }
            
            // 在主线程更新UI
            DispatchQueue.main.async {
                self.compressedImageView.image = result.compressedImage
                
                let text = String(format: """
                    保留比例: %.1f%%
                    原始大小: %.2f KB
                    压缩后: %.2f KB
                    压缩比: %.2fx
                    """,
                    result.keepRatio * 100,
                    result.originalSizeKB,
                    result.compressedSizeKB,
                    result.compressionRatio
                )
                
                self.resultLabel.text = text
                
                // 打印详细信息
                ImageCompressorFFT.printCompressionResult(result)
            }
        }
    }
    
    // 保存到相册
    @IBAction func saveButtonTapped(_ sender: UIButton) {
        guard let image = compressedImageView.image else { return }
        
        ImageCompressorFFT.saveToPhotoLibrary(image) { success, error in
            if success {
                print("保存成功")
            } else {
                print("保存失败: \(error?.localizedDescription ?? "")")
            }
        }
    }
}
*/
