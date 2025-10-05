// Copyright 2024 Apple Inc.

import AVKit
import AsyncAlgorithms
import CoreImage
import MLX
import MLXLMCommon
import MLXVLM
import PhotosUI
import SwiftUI

#if os(iOS) || os(visionOS)
    typealias PlatformImage = UIImage
#else
    typealias PlatformImage = NSImage
#endif

let videoSystemPrompt =
    "Focus only on describing the key dramatic action or notable event occurring in this video segment. Skip general context or scene-setting details unless they are crucial to understanding the main action."
let imageSystemPrompt =
    "You are an image understanding model capable of describing the salient features of any image."

// Prompt template data structure
struct PromptTemplate: Identifiable {
    let id = UUID()
    let title: String
    let prompt: String
    let icon: String
    let category: String
}

struct ContentView: View {

    @State var llm = VLMEvaluator()
    @Environment(DeviceStat.self) private var deviceStat

    @State private var keyboardHeight: CGFloat = 0
    @State private var showPromptTemplates = false
    
    // Prompt templates
    private let promptTemplates = [
        // 基础功能
        PromptTemplate(title: "详细描述", prompt: "请详细描述这张图片中的所有内容，包括场景、物体、人物、颜色和氛围。", icon: "doc.text", category: "基础"),
        PromptTemplate(title: "简短总结", prompt: "用一句话简短总结这张图片的主要内容。", icon: "text.quote", category: "基础"),
        
        // 实用功能
        PromptTemplate(title: "识别文字", prompt: "请识别并提取图片中的所有文字内容，保持原有格式。", icon: "doc.plaintext", category: "实用"),
        PromptTemplate(title: "物体识别", prompt: "列出图片中的所有物体，并说明它们的位置关系。", icon: "square.grid.3x3", category: "实用"),
        
        // 分析功能
        PromptTemplate(title: "情感分析", prompt: "分析这张图片传达的情感、氛围和意境。", icon: "heart", category: "分析"),
        PromptTemplate(title: "艺术风格", prompt: "描述这张图片的艺术风格、构图技巧和色彩运用。", icon: "paintbrush", category: "分析"),
        
        // 高级功能
        PromptTemplate(title: "场景理解", prompt: "分析这个场景的地点、时间、天气和整体环境特征。", icon: "map", category: "高级"),
        PromptTemplate(title: "动作描述", prompt: "描述图片中人物或物体的动作和姿态。", icon: "figure.walk", category: "高级"),
    ]

    // Responsive height calculation
    private var imageDisplayHeight: CGFloat {
        #if os(iOS) || os(visionOS)
        let screenHeight = UIScreen.main.bounds.height

        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            return screenHeight * 0.28  // iPhone: 28% of screen height
        case .pad:
            return min(400, screenHeight * 0.35)  // iPad: max 400px or 35% height
        default:
            return 300  // Default fallback
        }
        #else
        // macOS: use screen size or fixed height
        if let screen = NSScreen.main {
            let screenHeight = screen.visibleFrame.height
            return min(400, screenHeight * 0.3)  // max 400px or 30% height
        } else {
            return 300  // Default fallback
        }
        #endif
    }

    private var outputAreaHeight: CGFloat {
        #if os(iOS) || os(visionOS)
        let screenHeight = UIScreen.main.bounds.height
        let baseHeight = screenHeight - 600  // Subtract other components
        return max(150, baseHeight)  // Minimum 150px
        #else
        // macOS: use screen size or fixed height
        if let screen = NSScreen.main {
            let screenHeight = screen.visibleFrame.height
            let baseHeight = screenHeight - 400  // Subtract other components (less on macOS)
            return max(200, baseHeight)  // Minimum 200px
        } else {
            return 300  // Default fallback
        }
        #endif
    }

    @State private var selectedImage: PlatformImage? = nil {
        didSet {
            if selectedImage != nil {
                selectedVideoURL = nil
                player = nil
            }
        }
    }
    @State private var selectedVideoURL: URL? {
        didSet {
            if let selectedVideoURL {
                player = AVPlayer(url: selectedVideoURL)
                selectedImage = nil
            }
        }
    }
    @State private var showingImagePicker = false
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var player: AVPlayer? = nil

    private var currentImageURL: URL? {
        selectedImage == nil && selectedVideoURL == nil
            ? URL(
                string:
                    "https://huggingface.co/datasets/huggingface/documentation-images/resolve/main/bee.jpg"
            ) : nil
    }

    var body: some View {
        VStack(alignment: .leading) {
            VStack(spacing: 8) {
                HStack {
                    Text(llm.modelInfo)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer()

                    if !llm.stat.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "speedometer")
                                .font(.caption2)
                                .foregroundColor(.blue)
                            Text(llm.stat)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(8)
                    }
                }

                VStack {
                    if let player {
                        VideoPlayer(player: player)
                            .frame(height: imageDisplayHeight)
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                            .accessibilityLabel("视频播放器")
                            .accessibilityHint("正在播放选中的视频")
                    } else if let selectedImage {
                        Group {
                            #if os(iOS) || os(visionOS)
                                Image(uiImage: selectedImage)
                                    .resizable()
                            #else
                                Image(nsImage: selectedImage)
                                    .resizable()
                            #endif
                        }
                        .scaledToFit()
                        .frame(maxHeight: imageDisplayHeight)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        .accessibilityLabel("已选择的图片")
                        .accessibilityHint("双击可以选择新图片")
                    } else if let imageURL = currentImageURL {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .empty:
                                VStack(spacing: 12) {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                        .accessibilityLabel("正在加载")
                                    Text("加载图片中...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(height: imageDisplayHeight * 0.6)
                                .accessibilityLabel("正在加载图片")
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: imageDisplayHeight)
                                    .cornerRadius(12)
                                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                            case .failure:
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.badge.exclamationmark")
                                        .font(.largeTitle)
                                        .foregroundColor(.red)
                                        .accessibilityLabel("加载失败")
                                    Text("图片加载失败")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .frame(height: imageDisplayHeight * 0.6)
                                .accessibilityLabel("图片加载失败")
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }

                    HStack {
                        #if os(iOS) || os(visionOS)
                            PhotosPicker(
                                selection: $selectedItem,
                                matching: PHPickerFilter.any(of: [
                                    PHPickerFilter.images, PHPickerFilter.videos,
                                ])
                            ) {
                                Label("选择图片/视频", systemImage: "photo.badge.plus")
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(8)
                                    .accessibilityLabel("选择图片或视频")
                                    .accessibilityHint("点击选择要分析的图片或视频文件")
                            }
                            .onChange(of: selectedItem) {
                                Task {
                                    if let video = try? await selectedItem?.loadTransferable(
                                        type: TransferableVideo.self)
                                    {
                                        selectedVideoURL = video.url
                                    } else if let data = try? await selectedItem?.loadTransferable(
                                        type: Data.self)
                                    {
                                        selectedImage = PlatformImage(data: data)
                                    }
                                }
                            }
                        #else
                            Button("Select Image/Video") {
                                showingImagePicker = true
                            }
                            .fileImporter(
                                isPresented: $showingImagePicker,
                                allowedContentTypes: [.image, .movie]
                            ) { result in
                                switch result {
                                case .success(let file):
                                    Task { @MainActor in
                                        do {
                                            let data = try loadData(from: file)
                                            if let image = PlatformImage(data: data) {
                                                selectedImage = image
                                            } else if let fileType = UTType(
                                                filenameExtension: file.pathExtension),
                                                fileType.conforms(to: .movie)
                                            {
                                                if let sandboxURL = try? loadVideoToSandbox(
                                                    from: file)
                                                {
                                                    selectedVideoURL = sandboxURL
                                                }
                                            } else {
                                                print("Failed to create image from data")
                                            }
                                        } catch {
                                            print(
                                                "Failed to load image: \(error.localizedDescription)"
                                            )
                                        }
                                    }
                                case .failure(let error):
                                    print(error.localizedDescription)
                                }
                            }
                        #endif

                        if selectedImage != nil {
                            Button(role: .destructive) {
                                selectedImage = nil
                                selectedItem = nil
                                player = nil
                                selectedVideoURL = nil
                            } label: {
                                Label("清除", systemImage: "trash")
                                    .font(.subheadline)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                    .background(Color.red.opacity(0.1))
                                    .foregroundColor(.red)
                                    .cornerRadius(8)
                                    .accessibilityLabel("清除选择的图片")
                                    .accessibilityHint("点击清除当前选择的图片或视频")
                            }
                        }
                    }
                }
                .padding()

                HStack {
                    Spacer()
                    if llm.running {
                        ProgressView()
                            .frame(maxHeight: 20)
                        Spacer()
                    }
                }
            }

            // Generation Progress View
            if llm.running && llm.currentTokens > 0 {
                GenerationProgressView(
                    currentTokens: llm.currentTokens,
                    maxTokens: llm.maxTokens,
                    tokensPerSecond: llm.tokensPerSecond
                )
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Model Loading Progress View
            if llm.isLoading {
                ModelLoadingProgressView(progress: llm.loadingProgress)
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollView(.vertical) {
                ScrollViewReader { sp in
                    VStack(alignment: .leading, spacing: 16) {
                        Text(llm.output.isEmpty ? "输入提示词开始生成..." : llm.output)
                            .textSelection(.enabled)
                            .font(.body)
                            .foregroundColor(llm.output.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(llm.output.isEmpty ? "等待输入" : "生成结果")
                            .accessibilityHint(llm.output.isEmpty ? "输入提示词后点击生成按钮" : "可以复制生成的文本")
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        
                        // Error retry button
                        if llm.output.hasPrefix("❌") && !llm.running {
                            Button {
                                llm.retryLastGeneration()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 14, weight: .medium))
                                    Text("重试")
                                        .fontWeight(.semibold)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(
                                    LinearGradient(
                                        colors: [.orange, .red],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .shadow(color: .orange.opacity(0.3), radius: 4, x: 0, y: 2)
                            }
                            .accessibilityLabel("重试生成")
                            .accessibilityHint("点击重新尝试上次失败的生成任务")
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding()
                    .onChange(of: llm.output) { _, _ in
                        withAnimation(.easeOut(duration: 0.3)) {
                            sp.scrollTo("bottom", anchor: .bottom)
                        }
                    }

                    Spacer(minLength: 0)
                        .frame(width: 1, height: 1)
                        .id("bottom")
                }
            }
            .frame(minHeight: outputAreaHeight)
            #if os(iOS) || os(visionOS)
            .background(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
            #else
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
            #endif
            .cornerRadius(8)

            HStack {
                // Prompt template button
                Button {
                    showPromptTemplates.toggle()
                } label: {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.blue)
                        .padding(12)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
                .accessibilityLabel("提示词模板")
                .accessibilityHint("点击查看预设的提示词模板")
                .sheet(isPresented: $showPromptTemplates) {
                    PromptTemplateSheet(
                        templates: promptTemplates,
                        onSelect: { template in
                            llm.prompt = template.prompt
                            showPromptTemplates = false
                        }
                    )
                }
                
                TextField("输入提示词，如：描述这张图片...", text: Bindable(llm).prompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    #if os(iOS) || os(visionOS)
                    .background(Color(.systemBackground))
                    #else
                    .background(Color(NSColor.textBackgroundColor))
                    #endif
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
                    .accessibilityLabel("提示词输入框")
                    .accessibilityHint("输入描述图片或视频的提示词，按回车键生成")
                    .onSubmit(generate)
                    .disabled(llm.running)
                Button(action: llm.running ? cancel : generate) {
                    HStack(spacing: 6) {
                        if llm.running {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .medium))
                        }
                        Text(llm.running ? "停止" : "生成")
                            .fontWeight(.semibold)
                            .font(.system(size: 14))
                    }
                    .frame(minWidth: 80)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(
                            colors: llm.running ? [.red, .orange] : [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .shadow(color: llm.running ? .red.opacity(0.3) : .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                    .scaleEffect(llm.running ? 0.95 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: llm.running)
                }
                .accessibilityLabel(llm.running ? "停止生成" : "开始生成")
                .accessibilityHint(llm.running ? "点击停止当前生成任务" : "点击开始根据提示词生成内容")
                .disabled(llm.prompt.isEmpty && selectedImage == nil && selectedVideoURL == nil)
                .opacity((llm.prompt.isEmpty && selectedImage == nil && selectedVideoURL == nil) ? 0.6 : 1.0)
            }
        }
        .onAppear {
            selectedVideoURL = URL(
                string:
                    "https://videos.pexels.com/video-files/4066325/4066325-uhd_2560_1440_24fps.mp4")!
        }
        #if os(visionOS)
            .padding(40)
        #else
            .padding()
        #endif
        .toolbar {
            ToolbarItem {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Memory")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    Text(deviceStat.gpuUsage.activeMemory.formatted(.byteCount(style: .memory)))
                        .font(.caption2)
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
                .help(
                    Text(
                        """
                        Active: \(deviceStat.gpuUsage.activeMemory.formatted(.byteCount(style: .memory)))/\(GPU.memoryLimit.formatted(.byteCount(style: .memory)))
                        Cache: \(deviceStat.gpuUsage.cacheMemory.formatted(.byteCount(style: .memory)))/\(GPU.cacheLimit.formatted(.byteCount(style: .memory)))
                        Peak: \(deviceStat.gpuUsage.peakMemory.formatted(.byteCount(style: .memory)))
                        """
                    )
                )
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        copyToClipboard(llm.output)
                    }
                } label: {
                    Label("Copy Output", systemImage: "doc.on.doc.fill")
                }
                .disabled(llm.output == "")
                .labelStyle(.titleAndIcon)
            }
        }
        .padding(.bottom, keyboardHeight)
        .animation(.easeOut(duration: 0.3), value: keyboardHeight)
        .task {
            _ = try? await llm.load()
        }
        #if os(iOS) || os(visionOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            // Handle memory warning on iOS - emergency response
            llm.emergencyMemoryReset()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                keyboardHeight = keyboardFrame.height
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.3)) {
                keyboardHeight = 0
            }
        }
        #endif
    }

    private func generate() {
        Task {
            if let selectedImage = selectedImage {
                #if os(iOS) || os(visionOS)
                    // Convert UIImage to CIImage with validation
                    guard let ciImage = createValidCIImage(from: selectedImage) else {
                        await MainActor.run {
                            self.llm.output = "❌ 图像格式无效，请尝试其他图片（支持JPG, PNG等常见格式）"
                        }
                        return
                    }
                    llm.generate(image: ciImage, videoURL: nil)
                #else
                    if let cgImage = selectedImage.cgImage(
                        forProposedRect: nil, context: nil, hints: nil)
                    {
                        let ciImage = CIImage(cgImage: cgImage)
                        llm.generate(image: ciImage, videoURL: nil)
                    }
                #endif
            } else if let imageURL = currentImageURL {
                do {
                    let (data, _) = try await URLSession.shared.data(from: imageURL)
                    if let ciImage = createValidCIImage(from: data) {
                        llm.generate(image: ciImage, videoURL: nil)
                    } else {
                        await MainActor.run {
                            self.llm.output = "❌ 下载的图像格式无效，请尝试其他图片"
                        }
                    }
                } catch {
                    print("Failed to load image: \(error.localizedDescription)")
                    await MainActor.run {
                        self.llm.output = "❌ 图像加载失败: \(error.localizedDescription)"
                    }
                }
            } else {
                if let videoURL = selectedVideoURL {
                    llm.generate(image: nil, videoURL: videoURL)
                }
            }
        }
    }

    #if os(iOS) || os(visionOS)
    private func createValidCIImage(from image: UIImage) -> CIImage? {
        // Always convert to ensure valid format
        return convertToValidFormat(image: image)
    }

    private func convertToValidFormat(image: UIImage) -> CIImage? {
        // Force convert to standard RGBA8 format to avoid MLX validation errors
        let size = image.size
        let rect = CGRect(origin: .zero, size: size)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // Ensure 1x scale to avoid validation issues
        format.opaque = false
        format.preferredRange = .standard // Use standard range

        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let convertedImage = renderer.image { ctx in
            // Set standard color space
            ctx.cgContext.setFillColor(UIColor.clear.cgColor)
            ctx.cgContext.fill(rect)

            // Draw image in standard format
            image.draw(in: rect)
        }

        guard let finalCGImage = convertedImage.cgImage else { return nil }

        // Final validation
        let bitsPerComponent = finalCGImage.bitsPerComponent
        let bitsPerPixel = finalCGImage.bitsPerPixel
        let bytesPerRow = finalCGImage.bytesPerRow

        print("Image format: \(bitsPerComponent)bpc, \(bitsPerPixel)bpp, \(bytesPerRow)bpr")

        // Ensure we have valid parameters
        guard bitsPerComponent == 8 && (bitsPerPixel == 32 || bitsPerPixel == 24) else {
            print("Warning: Image format still invalid after conversion, proceeding anyway")
            // Continue anyway as the conversion should have handled most issues
            return CIImage(cgImage: finalCGImage)
        }

        return CIImage(cgImage: finalCGImage)
    }
    #endif

    private func createValidCIImage(from data: Data) -> CIImage? {
        guard let ciImage = CIImage(data: data) else { return nil }

        // Convert to UIImage to ensure proper format validation
        #if os(iOS) || os(visionOS)
        if let uiImage = UIImage(data: data) {
            return createValidCIImage(from: uiImage)
        }
        #endif

        // Fallback for other platforms or if UIImage conversion fails
        return ciImage
    }

    private func cancel() {
        llm.cancelGeneration()
    }

    #if os(macOS)
        private func loadData(from url: URL) throws -> Data {
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(
                    domain: "FileAccess", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to access the file."])
            }
            defer { url.stopAccessingSecurityScopedResource() }
            return try Data(contentsOf: url)
        }

        private func loadVideoToSandbox(from url: URL) throws -> URL {
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(
                    domain: "FileAccess", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to access the file."])
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let sandboxURL = try SandboxFileTransfer.transferFileToTemp(from: url)
            return sandboxURL
        }
    #endif

    private func copyToClipboard(_ string: String) {
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        #else
            UIPasteboard.general.string = string
        #endif
    }
}

@Observable
@MainActor
class VLMEvaluator {

    var running = false

    var prompt = ""
    var output = ""
    var modelInfo = ""
    var stat = ""
    
    // Generation progress tracking
    var currentTokens: Int = 0
    var maxTokens: Int = 0
    var tokensPerSecond: Double = 0
    
    // Model loading progress
    var loadingProgress: Double = 0
    var isLoading: Bool = false
    private var loadStartTime: Date?

    /// This controls which model loads. `smolvlm` is very small even unquantized, so it will fit on
    /// more devices.
    let modelConfiguration = VLMRegistry.smolvlm

    /// parameters controlling the output – use values appropriate for the model selected above
    var generateParameters: MLXLMCommon.GenerateParameters {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let isUltraLowMemoryDevice = physicalMemory <= 3 * 1024 * 1024 * 1024 // 3GB
        let isLowMemoryDevice = physicalMemory <= 4 * 1024 * 1024 * 1024 // 4GB

        if isUltraLowMemoryDevice {
            // Emergency minimal parameters for critical memory situations
            return MLXLMCommon.GenerateParameters(
                maxTokens: 50, temperature: 0.7, topP: 0.9)
        } else if isLowMemoryDevice {
            // Reduced parameters for low-memory devices
            return MLXLMCommon.GenerateParameters(
                maxTokens: 300, temperature: 0.7, topP: 0.9)
        } else {
            // Standard parameters for other devices
            return MLXLMCommon.GenerateParameters(
                maxTokens: 600, temperature: 0.7, topP: 0.9)
        }
    }
    let updateInterval = Duration.seconds(0.25)

    /// A task responsible for handling the generation process.
    var generationTask: Task<Void, Error>?

    enum LoadState {
        case idle
        case loaded(ModelContainer)
    }

    var loadState = LoadState.idle

    /// Helper to check if device has low memory
    private var isLowMemoryDevice: Bool {
        ProcessInfo.processInfo.physicalMemory <= 4 * 1024 * 1024 * 1024 // 4GB
    }

    /// Ultra low memory device (iPhone 12 mini class)
    private var isUltraLowMemoryDevice: Bool {
        ProcessInfo.processInfo.physicalMemory <= 3 * 1024 * 1024 * 1024 // 3GB
    }

    /// load and return the model -- can be called multiple times, subsequent calls will
    /// just return the loaded model
    func load() async throws -> ModelContainer {
        switch loadState {
        case .idle:
            isLoading = true
            loadStartTime = Date()
            loadingProgress = 0
            
            if isUltraLowMemoryDevice {
                // Emergency limits for critical memory situations
                MLX.GPU.set(cacheLimit: 1 * 1024 * 1024) // 1MB cache
                MLX.GPU.set(memoryLimit: 1_200 * 1024 * 1024) // 1.2GB limit
            } else if isLowMemoryDevice {
                // Aggressive memory limits for low-memory devices
                MLX.GPU.set(cacheLimit: 3 * 1024 * 1024) // 3MB cache
                MLX.GPU.set(memoryLimit: 1_800 * 1024 * 1024) // 1.8GB limit
            } else {
                // Conservative limits for other devices
                MLX.GPU.set(cacheLimit: 10 * 1024 * 1024) // 10MB cache
            }

            let modelContainer: ModelContainer
            do {
                modelContainer = try await VLMModelFactory.shared.loadContainer(
                    configuration: modelConfiguration
                ) { [modelConfiguration] progress in
                    Task { @MainActor in
                        let progressPercent = progress.fractionCompleted * 100
                        self.loadingProgress = progress.fractionCompleted
                        
                        // Calculate estimated time remaining
                        let estimatedTime = self.estimateRemainingTime(progress: progress.fractionCompleted)
                        self.modelInfo = "下载 \(modelConfiguration.name): \(Int(progressPercent))% · \(estimatedTime)"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    switch error as NSError {
                    case let error where error.localizedDescription.contains("download"):
                        self.modelInfo = "❌ 下载失败: \(error.localizedDescription)"
                    case let error where error.localizedDescription.contains("memory"):
                        self.modelInfo = "❌ 内存不足: \(error.localizedDescription)"
                    default:
                        self.modelInfo = "❌ 模型加载失败: \(error.localizedDescription)"
                    }
                }
                throw error // Re-throw to stop processing
            }
            
            isLoading = false

            let numParams = await modelContainer.perform { context in
                context.model.numParameters()
            }

            self.prompt = modelConfiguration.defaultPrompt

            let modelName = "SmolVLM" // Simplified name for display
            let weightsMB = numParams / (1024*1024)

            if isUltraLowMemoryDevice {
                // For ultra low-memory devices, don't cache the model to prevent memory buildup
                self.modelInfo = "\(modelName) • \(weightsMB)M • Ultra Low Memory"
                return modelContainer
            } else if isLowMemoryDevice {
                // For low-memory devices, don't cache the model to prevent memory buildup
                self.modelInfo = "\(modelName) • \(weightsMB)M • Low Memory"
                return modelContainer
            } else {
                self.modelInfo = "\(modelName) • \(weightsMB)M"
                loadState = .loaded(modelContainer)
                return modelContainer
            }

        case .loaded(let modelContainer):
            return modelContainer
        }
    }

    private func generate(prompt: String, image: CIImage?, videoURL: URL?) async {

        self.output = ""

        do {
            let modelContainer = try await load()

            // each time you generate you will get something new
            MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))

            // Aggressive memory cleanup before generation
            if isLowMemoryDevice || isUltraLowMemoryDevice {
                GPU.clearCache()
                eval() // Force immediate evaluation

                // Additional emergency cleanup for ultra low memory
                if isUltraLowMemoryDevice {
                    // Force garbage collection multiple times
                    for _ in 0..<3 {
                        autoreleasepool {
                            eval()
                            GPU.clearCache()
                        }
                    }
                }
            }

            try await modelContainer.perform { (context: ModelContext) -> Void in
                let images: [UserInput.Image] = if let image { [.ciImage(image)] } else { [] }
                let videos: [UserInput.Video] = if let videoURL { [.url(videoURL)] } else { [] }

                let systemPrompt =
                    if !videos.isEmpty {
                        videoSystemPrompt
                    } else if !images.isEmpty {
                        imageSystemPrompt
                    } else { "You are a helpful assistant." }

                let chat: [Chat.Message] = [
                    .system(systemPrompt),
                    .user(prompt, images: images, videos: videos),
                ]

                let physicalMemory = ProcessInfo.processInfo.physicalMemory
                let isUltraLowMemoryDevice = physicalMemory <= 3 * 1024 * 1024 * 1024 // 3GB
                let isLowMemoryDevice = physicalMemory <= 4 * 1024 * 1024 * 1024 // 4GB

                var generateParams: MLXLMCommon.GenerateParameters
                if isUltraLowMemoryDevice {
                    generateParams = MLXLMCommon.GenerateParameters(
                        maxTokens: 200, temperature: 0.7, topP: 0.9)
                } else if isLowMemoryDevice {
                    generateParams = MLXLMCommon.GenerateParameters(
                        maxTokens: 400, temperature: 0.7, topP: 0.9)
                } else {
                    generateParams = MLXLMCommon.GenerateParameters(
                        maxTokens: 800, temperature: 0.7, topP: 0.9)
                }

                var userInput = UserInput(chat: chat)

                // Aggressive image size reduction for memory constraints
                if isUltraLowMemoryDevice {
                    userInput.processing.resize = .init(width: 160, height: 160) // Ultra small for critical memory
                } else if isLowMemoryDevice {
                    userInput.processing.resize = .init(width: 224, height: 224) // Small for low memory
                } else {
                    userInput.processing.resize = .init(width: 448, height: 448) // Standard size
                }

                let lmInput = try await context.processor.prepare(input: userInput)

                let stream = try MLXLMCommon.generate(
                    input: lmInput, parameters: generateParams, context: context)

                // Reset token counter
                Task { @MainActor in
                    self.currentTokens = 0
                    self.maxTokens = generateParams.maxTokens ?? 600 // Default fallback
                }

                // generate and output in batches
                for await batch in stream._throttle(
                    for: updateInterval, reducing: Generation.collect)
                {
                    let output = batch.compactMap { $0.chunk }.joined(separator: "")
                    if !output.isEmpty {
                        Task { @MainActor [output] in
                            self.output += output
                        }
                    }

                    if let completion = batch.compactMap({ $0.info }).first {
                        Task { @MainActor in
                            let speed = String(format: "%.1f", completion.tokensPerSecond)
                            self.stat = "\(speed) t/s"
                            
                            // Update progress - estimate based on current output
                            let currentOutputLength = self.output.count
                            let estimatedTokens = max(0, currentOutputLength / 4) // Rough estimate: 1 token ≈ 4 chars
                            self.currentTokens = min(estimatedTokens, self.maxTokens)
                            self.tokensPerSecond = completion.tokensPerSecond
                        }
                    }
                }
            }

            // Emergency cleanup: immediately unload model after generation
            if isUltraLowMemoryDevice {
                unloadModel()
            }

        } catch {
            await MainActor.run {
                switch error as NSError {
                case let error where error.domain == "MLXError":
                    self.output = "❌ 模型推理失败: \(error.localizedDescription)"
                case let error where error.domain == "VLMError":
                    self.output = "❌ 视觉模型错误: \(error.localizedDescription)"
                case let error where error.localizedDescription.contains("memory"):
                    self.output = "❌ 内存不足: \(error.localizedDescription)"
                default:
                    self.output = "❌ 生成失败: \(error.localizedDescription)"
                }
            }
        }
    }

    // Store last generation parameters for retry
    private var lastPrompt: String = ""
    private var lastImage: CIImage? = nil
    private var lastVideoURL: URL? = nil
    
    func generate(image: CIImage?, videoURL: URL?) {
        guard !running else { return }
        let currentPrompt = prompt
        prompt = ""
        
        // Store for retry
        lastPrompt = currentPrompt
        lastImage = image
        lastVideoURL = videoURL
        
        generationTask = Task {
            running = true
            await generate(prompt: currentPrompt, image: image, videoURL: videoURL)
            running = false
        }
    }
    
    /// Retry the last failed generation
    func retryLastGeneration() {
        guard !running else { return }
        guard !lastPrompt.isEmpty else { return }
        
        generationTask = Task {
            running = true
            await generate(prompt: lastPrompt, image: lastImage, videoURL: lastVideoURL)
            running = false
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        running = false

        // Clear memory after cancellation on low-memory devices
        if isLowMemoryDevice || isUltraLowMemoryDevice {
            GPU.clearCache()

            // Additional cleanup for ultra low memory devices
            if isUltraLowMemoryDevice {
                unloadModel()
            }
        }
    }

    /// Clear model from memory to free up space (called on low-memory devices)
    func unloadModel() {
        if case .loaded = loadState {
            loadState = .idle
            GPU.clearCache()

            // Force garbage collection on ultra low memory devices
            if isUltraLowMemoryDevice {
                // Maximum cleanup effort
                for _ in 0..<5 {
                    autoreleasepool {
                        eval()
                        GPU.clearCache()
                        // Small delay to allow cleanup
                        Thread.sleep(forTimeInterval: 0.01)
                    }
                }
            }
        }
    }

    /// Emergency memory reset function
    func emergencyMemoryReset() {
        unloadModel()
        GPU.clearCache()
        eval()

        // Additional emergency cleanup
        if isUltraLowMemoryDevice {
            for _ in 0..<3 {
                autoreleasepool {
                    eval()
                    GPU.clearCache()
                    Thread.sleep(forTimeInterval: 0.01)
                }
            }
        }
    }
    
    /// Estimate remaining time for model loading
    private func estimateRemainingTime(progress: Double) -> String {
        guard let startTime = loadStartTime else { return "计算中..." }
        guard progress > 0.01 else { return "计算中..." }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let estimatedTotal = elapsed / progress
        let remaining = estimatedTotal - elapsed
        
        if remaining < 1 {
            return "即将完成"
        } else if remaining < 60 {
            return "约\(Int(remaining))秒"
        } else {
            let minutes = Int(remaining / 60)
            let seconds = Int(remaining.truncatingRemainder(dividingBy: 60))
            if seconds == 0 {
                return "约\(minutes)分钟"
            } else {
                return "约\(minutes)分\(seconds)秒"
            }
        }
    }
}

#if os(iOS) || os(visionOS)
    struct TransferableVideo: Transferable {
        let url: URL

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(contentType: .movie) { movie in
                SentTransferredFile(movie.url)
            } importing: { received in
                let sandboxURL = try SandboxFileTransfer.transferFileToTemp(from: received.file)
                return .init(url: sandboxURL)
            }
        }
    }
#endif

struct SandboxFileTransfer {
    static func transferFileToTemp(from sourceURL: URL) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let sandboxURL = tempDir.appendingPathComponent(sourceURL.lastPathComponent)

        if FileManager.default.fileExists(atPath: sandboxURL.path()) {
            try FileManager.default.removeItem(at: sandboxURL)
        }

        try FileManager.default.copyItem(at: sourceURL, to: sandboxURL)
        return sandboxURL
    }
}

// Prompt Template Selection Sheet
struct PromptTemplateSheet: View {
    let templates: [PromptTemplate]
    let onSelect: (PromptTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    
    // Group templates by category
    private var groupedTemplates: [String: [PromptTemplate]] {
        Dictionary(grouping: templates, by: { $0.category })
    }
    
    private let categories = ["基础", "实用", "分析", "高级"]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("快速提示词模板")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("选择预设模板快速开始")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Templates by category
                    ForEach(categories, id: \.self) { category in
                        if let categoryTemplates = groupedTemplates[category], !categoryTemplates.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(category)
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                                
                                LazyVGrid(columns: [
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)
                                ], spacing: 12) {
                                    ForEach(categoryTemplates) { template in
                                        TemplateCard(template: template) {
                                            onSelect(template)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }
}

// Template Card Component
struct TemplateCard: View {
    let template: PromptTemplate
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                // Icon and Title
                HStack(spacing: 12) {
                    Image(systemName: template.icon)
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 32, height: 32)
                    
                    Text(template.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                
                // Prompt preview
                Text(template.prompt)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            #if os(iOS) || os(visionOS)
            .background(Color(.secondarySystemBackground))
            #else
            .background(Color(NSColor.controlBackgroundColor))
            #endif
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(template.title)模板")
        .accessibilityHint("点击使用: \(template.prompt)")
    }
}

// Generation Progress View Component
struct GenerationProgressView: View {
    let currentTokens: Int
    let maxTokens: Int
    let tokensPerSecond: Double
    
    private var progress: Double {
        guard maxTokens > 0 else { return 0 }
        return Double(currentTokens) / Double(maxTokens)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)
                    
                    // Progress Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 6)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 6)
            
            // Progress Info
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Text("\(currentTokens)/\(maxTokens) tokens")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.caption2)
                        .foregroundColor(.purple)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                
                if tokensPerSecond > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "speedometer")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Text(String(format: "%.1f t/s", tokensPerSecond))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
        .accessibilityLabel("生成进度")
        .accessibilityValue("\(Int(progress * 100))%已完成，已生成\(currentTokens)个token，共\(maxTokens)个")
    }
}

// Model Loading Progress View Component  
struct ModelLoadingProgressView: View {
    let progress: Double
    
    var body: some View {
        VStack(spacing: 12) {
            // Progress Bar with animation
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)
                    
                    // Animated Progress Fill
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [.green, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 8)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                        .overlay(
                            // Shimmer effect
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0),
                                            Color.white.opacity(0.3),
                                            Color.white.opacity(0)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 60)
                                .offset(x: -30 + (geometry.size.width * progress))
                        )
                }
            }
            .frame(height: 8)
            
            // Loading Info
            HStack {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("正在加载模型...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.green.opacity(0.05))
        .cornerRadius(10)
        .accessibilityLabel("模型加载进度")
        .accessibilityValue("\(Int(progress * 100))%已完成")
    }
}
