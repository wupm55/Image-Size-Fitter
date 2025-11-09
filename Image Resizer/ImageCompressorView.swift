import SwiftUI
import PhotosUI
import Photos

/// SwiftUI版本的图像压缩界面
struct ImageCompressorView: View {
    @State private var selectedImage: UIImage?
    @State private var compressedImage: UIImage?
    @State private var originalImageSize: Double = 0
    @State private var isCompressing = false
    @State private var originalFileName: String = "image"
    @State private var customFileName: String = ""
    
    @State private var compressionResult: CompressionResult?
    @State private var showImagePicker = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @AppStorage("appLanguage") private var appLanguage: String = Locale.current.language.languageCode?.identifier ?? "en"
    
    // 压缩模式
    @State private var compressionQuality: Double = 0.7
    @State private var useTargetSize = false
    @State private var targetSizeKB: Double = 500
    
    // 屏幕方向状态
    @State private var isLandscape = false
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    // 判断是否为iPad
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    // 判断是否为iPad横屏
    private var isIPadLandscape: Bool {
        isIPad && isLandscape
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // 背景渐变 - 适配深色和浅色模式
                LinearGradient(
                    colors: colorScheme == .dark ? 
                        [Color(red: 0.1, green: 0.1, blue: 0.15), Color(red: 0.15, green: 0.15, blue: 0.2)] :
                        [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                if isIPadLandscape {
                    // iPad横屏：三列横向排列
                    iPadLandscapeLayout
                } else {
                    // iPhone布局 & iPad竖屏：垂直滚动
                    iPhoneLayout
                }
            }
            .navigationTitle(localizedString("app.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    languageSwitchButton
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $selectedImage, fileName: $originalFileName)
            }
            .alert(localizedString("alert.title"), isPresented: $showAlert) {
                Button(localizedString("ok"), role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .onChange(of: selectedImage) { newImage in
                if let image = newImage {
                    // 更新原始图片大小
                    originalImageSize = ImageCompressor.estimateImageSize(image)
                    // 重置压缩结果
                    compressedImage = nil
                    compressionResult = nil
                    // 设置默认文件名
                    customFileName = localizedString("compressed.suffix")
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            updateOrientation()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateOrientation()
        }
    }
    
    // 更新屏幕方向
    private func updateOrientation() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                let width = window.bounds.width
                let height = window.bounds.height
                self.isLandscape = width > height
                print("屏幕方向更新: 宽度=\(width), 高度=\(height), 横屏=\(self.isLandscape)")
            }
        }
    }
    
    // MARK: - 语言切换按钮
    private var languageSwitchButton: some View {
        Button(action: {
            appLanguage = appLanguage == "zh" ? "en" : "zh"
        }) {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                Text(appLanguage == "zh" ? "EN" : "中")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    // MARK: - iPhone布局（垂直滚动）
    private var iPhoneLayout: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 图像选择区域
                imageSelectionSection
                
                // 参数设置区域
                if selectedImage != nil {
                    parameterSection
                    
                    // 压缩按钮
                    compressButton
                    
                    // 结果显示
                    if let result = compressionResult {
                        resultSection(result: result)
                    }
                    
                    // 压缩后的图像
                    if let compressed = compressedImage {
                        compressedImageSection(image: compressed)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - iPad横屏布局（三列横向）
    private var iPadLandscapeLayout: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                // 左列：原始图像
                VStack(spacing: 16) {
                    originalImageColumn
                }
                .frame(maxWidth: .infinity)
                
                // 中列：控制面板
                VStack(spacing: 16) {
                    controlColumn
                }
                .frame(maxWidth: .infinity)
                
                // 右列：压缩后图像
                VStack(spacing: 16) {
                    compressedImageColumn
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }
    
    // MARK: - iPad左列：原始图像
    private var originalImageColumn: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "photo.stack")
                    .font(.title3)
                    .foregroundColor(.blue)
                Text(localizedString("select.image"))
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
            }
            
            if let image = selectedImage {
                VStack(spacing: 12) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 500)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                    
                    if originalImageSize > 0 {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.secondary)
                            Text(String(format: localizedString("original.size"), originalImageSize / 1024))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            colorScheme == .dark ? 
                                Color.white.opacity(0.1) : 
                                Color.gray.opacity(0.1)
                        )
                        .cornerRadius(8)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark ?
                                [Color.blue.opacity(0.15), Color.purple.opacity(0.15)] :
                                [Color.blue.opacity(0.05), Color.purple.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 400)
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 60))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text(localizedString("tap.to.select"))
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    )
            }
            
            Button(action: {
                showImagePicker = true
            }) {
                Label(localizedString("select.image"), systemImage: "photo.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }
        }
        .padding(16)
        .background(
            colorScheme == .dark ? 
                Color(red: 0.18, green: 0.18, blue: 0.22) : 
                Color.white
        )
        .cornerRadius(16)
        .shadow(color: colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - iPad中列：控制面板
    private var controlColumn: some View {
        VStack(spacing: 16) {
            if selectedImage != nil {
                parameterSection
                compressButton
                
                if let result = compressionResult {
                    resultSection(result: result)
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(localizedString("compression.settings"))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
                .background(
                    colorScheme == .dark ? 
                        Color(red: 0.18, green: 0.18, blue: 0.22) : 
                        Color.white
                )
                .cornerRadius(16)
                .shadow(color: colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
            }
        }
    }
    
    // MARK: - iPad右列：压缩后图像
    private var compressedImageColumn: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "photo.badge.checkmark")
                    .font(.title3)
                    .foregroundColor(.purple)
                Text(localizedString("compressed.image"))
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
            }
            
            if let compressed = compressedImage {
                VStack(spacing: 12) {
                    Image(uiImage: compressed)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 500)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                    
                    // 文件名编辑区域
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundColor(.blue)
                            Text(localizedString("file.name"))
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        
                        HStack(spacing: 8) {
                            TextField(localizedString("enter.filename"), text: $customFileName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.body)
                            
                            Text(".jpg")
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                    .padding(12)
                    .background(
                        colorScheme == .dark ? 
                            Color.white.opacity(0.08) : 
                            Color.gray.opacity(0.05)
                    )
                    .cornerRadius(10)
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            saveToPhotoLibrary(compressed)
                        }) {
                            Label(localizedString("save.to.album"), systemImage: "arrow.down.to.line.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    LinearGradient(
                                        colors: [Color.blue, Color.blue.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        
                        Button(action: {
                            shareImage(compressed)
                        }) {
                            Label(localizedString("share"), systemImage: "square.and.arrow.up.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    LinearGradient(
                                        colors: [Color.orange, Color.orange.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .shadow(color: Color.orange.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark ?
                                [Color.purple.opacity(0.15), Color.blue.opacity(0.15)] :
                                [Color.purple.opacity(0.05), Color.blue.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 400)
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "photo.badge.arrow.down")
                                .font(.system(size: 60))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.purple, .blue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text(localizedString("compressing"))
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    )
            }
        }
        .padding(16)
        .background(
            colorScheme == .dark ? 
                Color(red: 0.18, green: 0.18, blue: 0.22) : 
                Color.white
        )
        .cornerRadius(16)
        .shadow(color: colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - 图像选择区域
    private var imageSelectionSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "photo.stack")
                    .font(.title3)
                    .foregroundColor(.blue)
                Text(localizedString("select.image"))
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
            }
            
            if let image = selectedImage {
                VStack(spacing: 12) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 250)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                    
                    if originalImageSize > 0 {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.secondary)
                            Text(String(format: localizedString("original.size"), originalImageSize / 1024))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            colorScheme == .dark ? 
                                Color.white.opacity(0.1) : 
                                Color.gray.opacity(0.1)
                        )
                        .cornerRadius(8)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark ?
                                [Color.blue.opacity(0.15), Color.purple.opacity(0.15)] :
                                [Color.blue.opacity(0.05), Color.purple.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 180)
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 60))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text(localizedString("tap.to.select"))
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    )
            }
            
            Button(action: {
                showImagePicker = true
            }) {
                Label(localizedString("select.image"), systemImage: "photo.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }
        }
        .padding(16)
        .background(
            colorScheme == .dark ? 
                Color(red: 0.18, green: 0.18, blue: 0.22) : 
                Color.white
        )
        .cornerRadius(16)
        .shadow(color: colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - 参数设置区域
    private var parameterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .foregroundColor(.blue)
                Text(localizedString("compression.settings"))
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
            }
            
            // 模式选择
            Picker("Mode", selection: $useTargetSize) {
                Text(localizedString("mode.manual")).tag(false)
                Text(localizedString("mode.target")).tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 8)
            
            if useTargetSize {
                targetSizeSection
            } else {
                qualityAdjustSection
            }
        }
        .padding(16)
        .background(
            colorScheme == .dark ? 
                Color(red: 0.18, green: 0.18, blue: 0.22) : 
                Color.white
        )
        .cornerRadius(16)
        .shadow(color: colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - 目标大小设置
    private var targetSizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(localizedString("target.size"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(String(format: "%.0f KB", targetSizeKB))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            
            Slider(value: $targetSizeKB, in: 50...2000, step: 50)
                .tint(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            
            HStack(spacing: 10) {
                QuickButton(title: "100KB", action: { targetSizeKB = 100 })
                QuickButton(title: "200KB", action: { targetSizeKB = 200 })
                QuickButton(title: "500KB", action: { targetSizeKB = 500 })
                QuickButton(title: "1MB", action: { targetSizeKB = 1000 })
            }
            
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue.opacity(0.7))
                    .font(.caption)
                Text(localizedString("target.size.hint"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
            
            // 专业解释
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.orange.opacity(0.8))
                        .font(.caption2)
                    Text(localizedString("技术说明"))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange.opacity(0.8))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizedString("• JPEG压缩算法基于离散余弦变换(DCT)和量化，文件大小与图像内容复杂度密切相关"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text(localizedString("• 相同质量参数下，纹理复杂的图像比简单图像占用更多空间"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Text(localizedString("• 系统采用二分搜索算法在±10KB容差范围内寻找最优质量参数"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 16)
            }
            .padding(.top, 6)
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: colorScheme == .dark ?
                    [Color.blue.opacity(0.15), Color.purple.opacity(0.15)] :
                    [Color.blue.opacity(0.05), Color.purple.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(10)
    }
    
    // MARK: - 质量调整设置
    private var qualityAdjustSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(localizedString("jpeg.quality"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(String(format: "%.0f%%", compressionQuality * 100))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            
            Slider(value: $compressionQuality, in: 0.1...1.0)
                .tint(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            
            HStack(spacing: 10) {
                QuickButton(title: "30%", action: { compressionQuality = 0.3 })
                QuickButton(title: "50%", action: { compressionQuality = 0.5 })
                QuickButton(title: "70%", action: { compressionQuality = 0.7 })
                QuickButton(title: "90%", action: { compressionQuality = 0.9 })
            }
            
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue.opacity(0.7))
                    .font(.caption)
                Text(localizedString("quality.hint"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: colorScheme == .dark ?
                    [Color.blue.opacity(0.15), Color.purple.opacity(0.15)] :
                    [Color.blue.opacity(0.05), Color.purple.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(10)
    }
    
    // MARK: - 压缩按钮
    private var compressButton: some View {
        Button(action: performCompression) {
            HStack(spacing: 12) {
                if isCompressing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text(localizedString("compressing"))
                        .font(.headline)
                } else {
                    Image(systemName: "bolt.circle.fill")
                        .font(.title3)
                    Text(localizedString("start.compression"))
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                isCompressing ? 
                LinearGradient(
                    colors: [Color.gray, Color.gray.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                ) :
                LinearGradient(
                    colors: [Color.blue, Color.blue.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(14)
            .shadow(color: isCompressing ? Color.clear : Color.blue.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .disabled(isCompressing)
        .padding(.horizontal)
    }
    
    // MARK: - 结果显示区域
    private func resultSection(result: CompressionResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundColor(.green)
                Text(localizedString("compression.result"))
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
            }
            
            VStack(spacing: 10) {
                ResultCard(
                    icon: "doc.text",
                    label: localizedString("result.original"),
                    value: String(format: "%.2f KB", result.originalSizeKB),
                    color: .blue
                )
                ResultCard(
                    icon: "doc.badge.arrow.up",
                    label: localizedString("result.compressed"),
                    value: String(format: "%.2f KB", result.compressedSizeKB),
                    color: .green
                )
                ResultCard(
                    icon: "chart.bar.fill",
                    label: localizedString("result.ratio"),
                    value: String(format: "%.2fx", result.compressionRatio),
                    color: .purple
                )
            }
        }
        .padding(16)
        .background(
            colorScheme == .dark ? 
                Color(red: 0.18, green: 0.18, blue: 0.22) : 
                Color.white
        )
        .cornerRadius(16)
        .shadow(color: colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    
    // MARK: - 压缩后图像区域
    private func compressedImageSection(image: UIImage) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "photo.badge.checkmark")
                    .font(.title3)
                    .foregroundColor(.purple)
                Text(localizedString("compressed.image"))
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
            }
            
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 250)
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
            
            // 文件名编辑区域
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "pencil.circle.fill")
                        .foregroundColor(.blue)
                    Text(localizedString("file.name"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                HStack(spacing: 8) {
                    TextField(localizedString("enter.filename"), text: $customFileName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.body)
                    
                    Text(".jpg")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(6)
                }
            }
            .padding(12)
            .background(
                colorScheme == .dark ? 
                    Color.white.opacity(0.08) : 
                    Color.gray.opacity(0.05)
            )
            .cornerRadius(10)
            
            HStack(spacing: 12) {
                Button(action: {
                    saveToPhotoLibrary(image)
                }) {
                    Label(localizedString("save.to.album"), systemImage: "arrow.down.to.line.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                
                Button(action: {
                    shareImage(image)
                }) {
                    Label(localizedString("share"), systemImage: "square.and.arrow.up.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [Color.orange, Color.orange.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: Color.orange.opacity(0.3), radius: 8, x: 0, y: 4)
                }
            }
        }
        .padding(16)
        .background(
            colorScheme == .dark ? 
                Color(red: 0.18, green: 0.18, blue: 0.22) : 
                Color.white
        )
        .cornerRadius(16)
        .shadow(color: colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - 压缩功能
    private func performCompression() {
        guard let image = selectedImage else { return }
        
        isCompressing = true
        compressedImage = nil
        compressionResult = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            let result: CompressionResult?
            
            if useTargetSize {
                // 目标大小模式：使用二分搜索自动调整JPEG质量
                result = ImageCompressor.compressToTargetSize(
                    image,
                    targetKB: targetSizeKB
                )
            } else {
                // 手动模式：使用用户设置的JPEG质量
                result = ImageCompressor.compressImage(
                    image,
                    jpegQuality: compressionQuality
                )
            }
            
            DispatchQueue.main.async {
                isCompressing = false
                
                if let result = result {
                    compressedImage = result.compressedImage
                    compressionResult = result
                    ImageCompressor.printCompressionResult(result)
                    // 自动设置文件名为“压缩至XXX KB”
                    let sizeKB = Int(result.compressedSizeKB)
                    customFileName = String(format: localizedString("compressed.to.size"), sizeKB)
                } else {
                    alertMessage = localizedString("compression.failed")
                    showAlert = true
                }
            }
        }
    }
    
    // MARK: - 保存到相册
    private func saveToPhotoLibrary(_ image: UIImage) {
        // 检查权限
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        
        switch status {
        case .authorized, .limited:
            // 已授权，直接保存
            performSave(image)
        case .notDetermined:
            // 请求权限
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        performSave(image)
                    } else {
                        alertMessage = "需要相册访问权限才能保存图片\n请在设置中允许访问"
                        showAlert = true
                    }
                }
            }
        case .denied, .restricted:
            // 权限被拒绝
            alertMessage = "需要相册访问权限才能保存图片\n请在设置 → 隐私与安全性 → 照片中允许访问"
            showAlert = true
        @unknown default:
            alertMessage = "无法保存图片"
            showAlert = true
        }
    }
    
    private func performSave(_ image: UIImage) {
        // 优先使用保存的JPEG数据，确保文件大小与显示的完全一致
        let jpegData: Data
        if let savedData = compressionResult?.compressedImageData {
            jpegData = savedData
        } else {
            // 如果没有保存的数据，使用高质量编码
            guard let encodedData = image.jpegData(compressionQuality: 1.0) else {
                alertMessage = "无法转换图片格式"
                showAlert = true
                return
            }
            jpegData = encodedData
        }
        
        // 创建临时文件，使用自定义文件名
        let fileName = customFileName.isEmpty ? localizedString("compressed.suffix") : customFileName
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).jpg")
        
        do {
            try jpegData.write(to: tempURL)
            
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: tempURL)
            }) { success, error in
                // 删除临时文件
                try? FileManager.default.removeItem(at: tempURL)
                
                DispatchQueue.main.async {
                    if success {
                        let sizeKB = Double(jpegData.count) / 1024.0
                        alertMessage = String(format: "已成功保存到相册\nJPEG文件大小: %.2f KB", sizeKB)
                        showAlert = true
                    } else {
                        alertMessage = "保存失败: \(error?.localizedDescription ?? "未知错误")"
                        showAlert = true
                    }
                }
            }
        } catch {
            alertMessage = "保存失败: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    // MARK: - 分享图像
    private func shareImage(_ image: UIImage) {
        // 优先使用保存的JPEG数据，确保文件大小与显示的完全一致
        let jpegData: Data
        if let savedData = compressionResult?.compressedImageData {
            jpegData = savedData
        } else {
            // 如果没有保存的数据，使用高质量编码
            guard let encodedData = image.jpegData(compressionQuality: 1.0) else {
                alertMessage = "无法转换图片格式"
                showAlert = true
                return
            }
            jpegData = encodedData
        }
        
        // 创建临时JPEG文件，使用自定义文件名
        let fileName = customFileName.isEmpty ? localizedString("compressed.suffix") : customFileName
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).jpg")
        
        do {
            try jpegData.write(to: tempURL)
            
            let activityVC = UIActivityViewController(
                activityItems: [tempURL],  // 分享文件URL而不是UIImage
                applicationActivities: nil
            )
            
            // 分享完成后删除临时文件
            activityVC.completionWithItemsHandler = { _, _, _, _ in
                try? FileManager.default.removeItem(at: tempURL)
            }
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                rootVC.present(activityVC, animated: true)
            }
        } catch {
            alertMessage = "分享失败: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    // MARK: - 本地化字符串函数
    private func localizedString(_ key: String) -> String {
        let bundle = Bundle.main
        if let path = bundle.path(forResource: appLanguage, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            return NSLocalizedString(key, bundle: langBundle, comment: "")
        }
        return NSLocalizedString(key, comment: "")
    }
}

// MARK: - 图像选择器
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Binding var fileName: String
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
                
                // 尝试获取原始文件名
                if let imageURL = info[.imageURL] as? URL {
                    let originalName = imageURL.deletingPathExtension().lastPathComponent
                    parent.fileName = originalName
                } else if let asset = info[.phAsset] as? PHAsset {
                    // 从PHAsset获取文件名
                    let resources = PHAssetResource.assetResources(for: asset)
                    if let resource = resources.first {
                        let originalName = (resource.originalFilename as NSString).deletingPathExtension
                        parent.fileName = originalName
                    }
                } else {
                    // 使用默认名称
                    parent.fileName = "image"
                }
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// MARK: - 快捷按钮组件
struct QuickButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(colorScheme == .dark ? .blue.opacity(0.9) : .blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    colorScheme == .dark ? 
                        Color.blue.opacity(0.2) : 
                        Color.blue.opacity(0.1)
                )
                .cornerRadius(8)
        }
    }
}

// MARK: - 结果卡片组件
struct ResultCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(colorScheme == .dark ? color.opacity(0.9) : color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.body)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            colorScheme == .dark ? 
                color.opacity(0.2) : 
                color.opacity(0.08)
        )
        .cornerRadius(10)
    }
}

// MARK: - 预览
struct ImageCompressorView_Previews: PreviewProvider {
    static var previews: some View {
        ImageCompressorView()
    }
}
