# VLMEval iOS UI设计优化文档

## 📋 文档信息

- **项目**: mlx-swift-examples - VLMEval
- **平台**: iOS / visionOS
- **目标**: 优化iOS平台的用户界面设计
- **日期**: 2025年10月5日

---

## 1. 当前UI设计问题分析

### 1.1 布局适配问题

#### 问题描述
当前UI使用固定高度,缺乏对不同iOS设备的响应式适配。

**具体问题:**

```swift
// 问题代码位置: ContentView.swift
.frame(height: 300)  // 硬编码的固定高度
```

**影响的设备:**
- iPhone SE (4.7" 屏幕): 300px占屏幕比例过大
- iPhone 12 mini (5.4"): 布局拥挤
- iPhone 15 Pro Max (6.7"): 空间利用不充分
- iPad: 显示效果不佳

#### 解决方案

**方案1: 动态高度计算**

```swift
// 推荐实现
private var imageDisplayHeight: CGFloat {
    let screenHeight = UIScreen.main.bounds.height
    
    // 根据设备类型动态计算
    switch UIDevice.current.userInterfaceIdiom {
    case .phone:
        // iPhone: 屏幕高度的25-30%
        return screenHeight * 0.28
    case .pad:
        // iPad: 固定较大高度
        return min(400, screenHeight * 0.35)
    default:
        return 300
    }
}

// 使用方式
.frame(height: imageDisplayHeight)
.frame(maxHeight: 400)  // 设置最大高度限制
```

**方案2: 几何读取器方案**

```swift
GeometryReader { geometry in
    VStack {
        // 图片/视频显示区
        if let player {
            VideoPlayer(player: player)
                .frame(height: geometry.size.height * 0.3)
                .cornerRadius(12)
        } else if let selectedImage {
            Image(uiImage: selectedImage)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: geometry.size.height * 0.35)
                .cornerRadius(12)
        }
    }
}
```

---

### 1.2 输入框样式不一致

#### 问题描述
TextField在iOS和visionOS上样式不一致,iOS缺少圆角边框。

**当前代码:**
```swift
TextField("prompt", text: Bindable(llm).prompt)
    .onSubmit(generate)
    .disabled(llm.running)
    #if os(visionOS)
        .textFieldStyle(.roundedBorder)  // 只有visionOS有样式
    #endif
```

#### 解决方案

```swift
// 统一的文本框样式
TextField("输入提示词...", text: Bindable(llm).prompt)
    .textFieldStyle(.roundedBorder)  // 移除条件编译
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(Color(.systemGray6))
    .cornerRadius(10)
    .overlay(
        RoundedRectangle(cornerRadius: 10)
            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
    )
    .onSubmit(generate)
    .disabled(llm.running)
```

---

### 1.3 键盘处理缺失

#### 问题描述
输入框获得焦点时,键盘可能遮挡输入区域和按钮。

#### 解决方案

**添加键盘管理器:**

```swift
// 在ContentView中添加
@State private var keyboardHeight: CGFloat = 0

var body: some View {
    VStack {
        // ... 现有内容
    }
    .padding(.bottom, keyboardHeight)  // 根据键盘高度调整底部边距
    .animation(.easeOut(duration: 0.3), value: keyboardHeight)
    .onAppear {
        setupKeyboardObservers()
    }
    .onDisappear {
        removeKeyboardObservers()
    }
}

// 键盘观察方法
private func setupKeyboardObservers() {
    NotificationCenter.default.addObserver(
        forName: UIResponder.keyboardWillShowNotification,
        object: nil,
        queue: .main
    ) { notification in
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        keyboardHeight = keyboardFrame.height
    }
    
    NotificationCenter.default.addObserver(
        forName: UIResponder.keyboardWillHideNotification,
        object: nil,
        queue: .main
    ) { _ in
        keyboardHeight = 0
    }
}

private func removeKeyboardObservers() {
    NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
    NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
}
```

---

### 1.4 ScrollView高度固定

#### 问题描述
输出区域的ScrollView使用固定最小高度,在小屏设备上空间浪费。

**当前代码:**
```swift
ScrollView(.vertical) {
    // ...
}
.frame(minHeight: 200)  // 固定最小高度
```

#### 解决方案

```swift
// 动态计算ScrollView高度
private var outputAreaHeight: CGFloat {
    let screenHeight = UIScreen.main.bounds.height
    let baseHeight = screenHeight - 600  // 减去其他组件高度
    return max(150, baseHeight)  // 最小150,避免过小
}

ScrollView(.vertical) {
    ScrollViewReader { sp in
        Text(llm.output)
            .textSelection(.enabled)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: llm.output) { _, _ in
                sp.scrollTo("bottom")
            }
        
        Spacer()
            .frame(width: 1, height: 1)
            .id("bottom")
    }
}
.frame(minHeight: outputAreaHeight)
.background(Color(.systemGray6).opacity(0.3))
.cornerRadius(8)
```

---

### 1.5 按钮交互反馈不足

#### 问题描述
生成/停止按钮状态切换缺少视觉反馈和动画。

#### 解决方案

```swift
// 改进的按钮设计
Button(action: llm.running ? cancel : generate) {
    HStack {
        if llm.running {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(0.8)
            Text("停止生成")
        } else {
            Image(systemName: "sparkles")
            Text("开始生成")
        }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .background(
        LinearGradient(
            colors: llm.running ? [.red, .orange] : [.blue, .purple],
            startPoint: .leading,
            endPoint: .trailing
        )
    )
    .foregroundColor(.white)
    .cornerRadius(10)
    .shadow(color: llm.running ? .red.opacity(0.3) : .blue.opacity(0.3), radius: 5)
}
.disabled(llm.prompt.isEmpty && selectedImage == nil && selectedVideoURL == nil)
.animation(.easeInOut(duration: 0.3), value: llm.running)
```

---

## 2. 优化的完整UI布局

### 2.1 推荐的新布局结构

```swift
struct ContentView: View {
    @State var llm = VLMEvaluator()
    @Environment(DeviceStat.self) private var deviceStat
    
    // ... 其他State变量
    
    @State private var keyboardHeight: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // 1. 顶部信息栏
                topInfoBar
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                
                Divider()
                
                // 2. 媒体显示区
                mediaDisplaySection(geometry: geometry)
                    .padding(.horizontal)
                    .padding(.top, 12)
                
                // 3. 输出显示区
                outputSection
                    .padding(.horizontal)
                    .padding(.top, 12)
                
                // 4. 底部输入栏
                inputSection
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6).opacity(0.5))
            }
            .padding(.bottom, keyboardHeight)
            .animation(.easeOut(duration: 0.3), value: keyboardHeight)
        }
        .toolbar { toolbarContent }
        .onAppear(perform: setup)
    }
    
    // MARK: - UI组件
    
    private var topInfoBar: some View {
        HStack(spacing: 12) {
            // 模型信息
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text(llm.modelInfo)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            
            Spacer()
            
            // 性能统计
            if !llm.stat.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "speedometer")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Text(llm.stat)
                        .font(.caption)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
    
    private func mediaDisplaySection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 12) {
            // 媒体显示
            Group {
                if let player {
                    VideoPlayer(player: player)
                        .frame(height: geometry.size.height * 0.25)
                        .cornerRadius(12)
                        .shadow(radius: 2)
                } else if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: geometry.size.height * 0.3)
                        .cornerRadius(12)
                        .shadow(radius: 2)
                } else if let imageURL = currentImageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(height: 200)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(12)
                                .frame(height: 200)
                        case .failure:
                            VStack {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.largeTitle)
                                    .foregroundColor(.red)
                                Text("加载失败")
                                    .font(.caption)
                            }
                            .frame(height: 200)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // 媒体选择按钮
            HStack(spacing: 12) {
                PhotosPicker(
                    selection: $selectedItem,
                    matching: PHPickerFilter.any(of: [.images, .videos])
                ) {
                    Label("选择图片/视频", systemImage: "photo.badge.plus")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                }
                .onChange(of: selectedItem) {
                    Task { await handleMediaSelection() }
                }
                
                if selectedImage != nil || selectedVideoURL != nil {
                    Button(role: .destructive) {
                        clearMedia()
                    } label: {
                        Label("清除", systemImage: "trash")
                            .font(.subheadline)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(8)
                    }
                }
            }
        }
    }
    
    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("生成结果")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if llm.running {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("生成中...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            ScrollView(.vertical) {
                ScrollViewReader { sp in
                    Text(llm.output.isEmpty ? "输入提示词开始生成..." : llm.output)
                        .font(.body)
                        .foregroundColor(llm.output.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .onChange(of: llm.output) { _, _ in
                            withAnimation {
                                sp.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    
                    Spacer(minLength: 0)
                        .frame(width: 1, height: 1)
                        .id("bottom")
                }
            }
            .frame(minHeight: 150)
            .background(Color(.systemBackground))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
    }
    
    private var inputSection: some View {
        VStack(spacing: 12) {
            // 输入框
            HStack(spacing: 12) {
                TextField("输入提示词,如:描述这张图片", text: Bindable(llm).prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
                    .disabled(llm.running)
                    .onSubmit(generate)
                
                // 生成按钮
                Button(action: llm.running ? cancel : generate) {
                    HStack(spacing: 6) {
                        if llm.running {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(llm.running ? "停止" : "生成")
                            .fontWeight(.semibold)
                    }
                    .frame(width: 80)
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
                }
                .disabled(llm.prompt.isEmpty && selectedImage == nil && selectedVideoURL == nil)
                .animation(.easeInOut(duration: 0.2), value: llm.running)
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // 内存使用信息
        ToolbarItem(placement: .topBarLeading) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "memorychip")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("内存")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                Text(deviceStat.gpuUsage.activeMemory.formatted(.byteCount(style: .memory)))
                    .font(.caption2)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(6)
        }
        
        // 复制输出按钮
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                copyToClipboard(llm.output)
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .disabled(llm.output.isEmpty)
        }
    }
    
    // MARK: - 辅助方法
    
    private func setup() {
        setupKeyboardObservers()
        Task {
            _ = try? await llm.load()
        }
    }
    
    private func clearMedia() {
        selectedImage = nil
        selectedVideoURL = nil
        selectedItem = nil
        player = nil
    }
    
    private func handleMediaSelection() async {
        if let video = try? await selectedItem?.loadTransferable(type: TransferableVideo.self) {
            selectedVideoURL = video.url
        } else if let data = try? await selectedItem?.loadTransferable(type: Data.self) {
            selectedImage = PlatformImage(data: data)
        }
    }
    
    // ... 其他方法保持不变
}
```

---

## 3. 可访问性改进

### 3.1 VoiceOver支持

```swift
// 为关键元素添加辅助功能标签
Image(uiImage: selectedImage)
    .resizable()
    .accessibilityLabel("已选择的图片")
    .accessibilityHint("双击可以选择新图片")

Button("generate") {
    // ...
}
.accessibilityLabel(llm.running ? "停止生成" : "开始生成")
.accessibilityHint(llm.running ? "停止当前生成任务" : "开始根据提示词生成内容")
```

### 3.2 Dynamic Type支持

```swift
Text(llm.output)
    .font(.body)
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)  // 限制最大字号
```

---

## 4. 深色模式优化

```swift
// 确保所有颜色支持深色模式
.background(Color(.systemBackground))  // 自动适配
.foregroundColor(.primary)             // 自动适配

// 自定义颜色
Color("CustomBlue")  // 在Assets.xcassets中定义深浅两种颜色
```

---

## 5. 实施优先级

### 高优先级(立即实施)
1. ✅ 修复TextField样式不一致
2. ✅ 添加键盘处理
3. ✅ 动态高度适配

### 中优先级(近期优化)
4. ⚡ 改进按钮交互反馈
5. ⚡ 优化ScrollView布局
6. ⚡ 添加基础可访问性支持

### 低优先级(长期改进)
7. 🔄 完整的VoiceOver支持
8. 🔄 动画和过渡效果
9. 🔄 主题自定义

---

## 6. 测试检查清单

- [ ] iPhone SE (小屏): 布局不拥挤
- [ ] iPhone 15 Pro Max (大屏): 空间充分利用
- [ ] iPad: 显示效果良好
- [ ] 横屏模式: 布局合理
- [ ] 键盘弹出: 不遮挡输入区域
- [ ] 深色模式: 颜色正确显示
- [ ] VoiceOver: 可正常导航
- [ ] Dynamic Type: 字号调整正确

---

## 7. 参考资料

- [Apple Human Interface Guidelines - iOS](https://developer.apple.com/design/human-interface-guidelines/ios)
- [SwiftUI Layout System](https://developer.apple.com/documentation/swiftui/building-layouts-with-stack-views)
- [Accessibility in SwiftUI](https://developer.apple.com/documentation/accessibility/swiftui)
