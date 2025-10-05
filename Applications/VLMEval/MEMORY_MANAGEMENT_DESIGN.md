# VLMEval 内存管理设计文档

## 📋 文档信息

- **项目**: mlx-swift-examples - VLMEval
- **平台**: iOS (重点4GB RAM设备)
- **目标**: 优化内存管理策略
- **日期**: 2025年10月5日
- **测试设备**: 4GB RAM iOS设备

---

## 1. 当前内存管理问题分析

### 1.1 设备分类过于激进

#### 问题描述
当前代码将4GB RAM判定为"低内存设备"，触发了过度的内存限制策略。

**当前逻辑:**
```swift
/// Helper to check if device has low memory
private var isLowMemoryDevice: Bool {
    ProcessInfo.processInfo.physicalMemory <= 4 * 1024 * 1024 * 1024 // 4GB
}

/// Ultra low memory device (iPhone 13 mini class)
private var isUltraLowMemoryDevice: Bool {
    ProcessInfo.processInfo.physicalMemory <= 3 * 1024 * 1024 * 1024 // 3GB
}
```

**影响的设备:**
- **4GB RAM设备** (被判定为低内存):
  - iPhone 13 mini (4GB)
  - iPhone 12 系列 (4GB)
  - iPhone 11 Pro 系列 (4GB)
  
- **3GB RAM设备** (被判定为超低内存):
  - iPhone XR (3GB)
  - iPhone X (3GB)
  - iPhone 8 Plus (3GB)

**问题:**
1. 现代iPhone (iPhone 12+) 都有4GB+内存
2. SmolVLM是小型模型 (~500MB-1GB)
3. 4GB足够运行该模型
4. 过度限制损害用户体验

---

### 1.2 GPU内存限制过严

#### 当前配置

```swift
func load() async throws -> ModelContainer {
    if isUltraLowMemoryDevice {
        MLX.GPU.set(cacheLimit: 1 * 1024 * 1024)      // 1MB
        MLX.GPU.set(memoryLimit: 1_200 * 1024 * 1024) // 1.2GB
    } else if isLowMemoryDevice {
        MLX.GPU.set(cacheLimit: 3 * 1024 * 1024)      // 3MB
        MLX.GPU.set(memoryLimit: 1_800 * 1024 * 1024) // 1.8GB
    }
}
```

#### 问题分析

**4GB设备当前限制:**
- ❌ 缓存: 仅3MB (太小)
- ❌ GPU内存: 1.8GB限制 (过于保守)
- ❌ 结果: 频繁cache miss，性能下降

**理想配置 (4GB设备):**
- ✅ 缓存: 15-20MB
- ✅ GPU内存: 2.5GB
- ✅ 系统保留: 1.5GB
- ✅ 性能提升: 显著

---

### 1.3 生成参数限制过度

#### 当前配置

```swift
var generateParameters: MLXLMCommon.GenerateParameters {
    if isUltraLowMemoryDevice {
        return MLXLMCommon.GenerateParameters(
            maxTokens: 50, temperature: 0.7, topP: 0.9)
    } else if isLowMemoryDevice {
        return MLXLMCommon.GenerateParameters(
            maxTokens: 300, temperature: 0.7, topP: 0.9)
    } else {
        return MLXLMCommon.GenerateParameters(
            maxTokens: 600, temperature: 0.7, topP: 0.9)
    }
}
```

#### 问题分析

**4GB设备影响:**
- 当前: 最多300 tokens (~150-200字)
- 标准: 最多600 tokens (~300-400字)
- 差距: 生成长度减半

**实际需求:**
- 图像描述通常需要200-400 tokens
- 300 tokens经常不够完整描述
- 用户体验受损

---

### 1.4 图像分辨率限制

#### 当前配置

```swift
if isUltraLowMemoryDevice {
    userInput.processing.resize = .init(width: 160, height: 160)
} else if isLowMemoryDevice {
    userInput.processing.resize = .init(width: 224, height: 224)
} else {
    userInput.processing.resize = .init(width: 448, height: 448)
}
```

#### 问题分析

**4GB设备当前配置:**
- 分辨率: 224×224 (50,176 像素)
- 标准: 448×448 (200,704 像素)
- 差距: 像素数减少75%

**影响:**
- 视觉细节丢失
- 识别准确度下降
- 小文字无法识别
- 复杂场景理解困难

---

### 1.5 模型缓存策略问题

#### 当前逻辑

```swift
func load() async throws -> ModelContainer {
    // ...加载模型
    
    if isLowMemoryDevice {
        // 4GB设备不缓存模型
        return modelContainer
    } else {
        loadState = .loaded(modelContainer)
        return modelContainer
    }
}

// 生成后立即卸载 (超低内存设备)
if isUltraLowMemoryDevice {
    unloadModel()
}
```

#### 问题分析

**4GB设备影响:**
- ❌ 模型不缓存在内存中
- ❌ 每次生成可能需要重新加载部分组件
- ❌ 响应时间增加
- ❌ 用户体验下降

**3GB设备更严重:**
- ❌ 每次生成后立即卸载整个模型
- ❌ 下次生成需要完全重新加载 (3-8秒)
- ❌ 严重影响可用性

---

### 1.6 过度的内存清理

#### 当前实现

```swift
func cancelGeneration() {
    generationTask?.cancel()
    running = false
    
    // 4GB设备: 每次取消都清理
    if isLowMemoryDevice || isUltraLowMemoryDevice {
        GPU.clearCache()
        
        // 3GB设备: 额外卸载模型
        if isUltraLowMemoryDevice {
            unloadModel()
        }
    }
}

func unloadModel() {
    if case .loaded = loadState {
        loadState = .idle
        GPU.clearCache()
        
        // 超低内存: 多次强制清理
        if isUltraLowMemoryDevice {
            for _ in 0..<5 {
                autoreleasepool {
                    eval()
                    GPU.clearCache()
                    Thread.sleep(forTimeInterval: 0.01) // ⚠️ 阻塞主线程!
                }
            }
        }
    }
}
```

#### 问题分析

**性能问题:**
1. `Thread.sleep` 阻塞主线程
2. 循环5次清理 (总计50ms延迟)
3. 频繁的 `GPU.clearCache()` 降低性能
4. 不必要的 `eval()` 调用

**用户体验问题:**
1. UI冻结
2. 响应延迟
3. 操作不流畅

---

## 2. 内存使用实际分析

### 2.1 SmolVLM模型内存占用

**模型组成:**
- 权重参数: ~500-800MB
- KV缓存: ~100-200MB (依赖序列长度)
- 中间激活: ~50-100MB
- **总计**: 约650-1100MB

### 2.2 4GB设备内存分配

**系统内存使用:**
```
总内存: 4096MB
├── 系统保留: ~800-1000MB (iOS系统)
├── 应用基础: ~100-200MB (UI + 框架)
├── 可用内存: ~2900-3200MB
└── 缓冲区: ~500MB (安全边际)
```

**SmolVLM运行所需:**
```
模型 + 推理: ~1500-2000MB
├── 模型权重: 800MB
├── KV缓存: 400MB
├── 推理缓冲: 300-500MB
└── 临时数据: 200MB
```

**结论:** 
- 4GB设备有 **充足内存** 运行SmolVLM
- 当前限制 **过于保守**
- 可以安全提高内存使用上限

---

## 3. 优化方案设计

### 3.1 新的设备分类策略

#### 方案A: 调整阈值 (快速修复)

```swift
/// Helper to check if device has low memory
private var isLowMemoryDevice: Bool {
    // 改为3GB: 只有真正低内存设备才限制
    ProcessInfo.processInfo.physicalMemory <= 3 * 1024 * 1024 * 1024
}

/// Ultra low memory device
private var isUltraLowMemoryDevice: Bool {
    // 改为2GB: 只有极端情况才严格限制
    ProcessInfo.processInfo.physicalMemory <= 2 * 1024 * 1024 * 1024
}
```

**效果:**
- ✅ 4GB设备按标准设备处理
- ✅ 3GB设备仍有适当限制
- ✅ 2GB及以下设备才严格限制
- ✅ 快速实施，风险低

---

#### 方案B: 细粒度分类 (推荐)

```swift
enum DeviceMemoryTier {
    case ultraLow    // ≤2GB
    case low         // 2-3GB
    case standard    // 3-6GB (包括4GB)
    case high        // >6GB
    
    static var current: DeviceMemoryTier {
        let memory = ProcessInfo.processInfo.physicalMemory
        let gb = Double(memory) / (1024 * 1024 * 1024)
        
        switch gb {
        case ...2.0:
            return .ultraLow
        case 2.0...3.0:
            return .low
        case 3.0...6.0:
            return .standard
        default:
            return .high
        }
    }
}

struct MemoryConfiguration {
    let cacheLimit: Int
    let memoryLimit: Int?
    let maxTokens: Int
    let imageSize: Int
    let keepModelLoaded: Bool
    let aggressiveCleanup: Bool
    
    static func forTier(_ tier: DeviceMemoryTier) -> MemoryConfiguration {
        switch tier {
        case .ultraLow:
            return MemoryConfiguration(
                cacheLimit: 3 * 1024 * 1024,       // 3MB
                memoryLimit: 1_500 * 1024 * 1024,  // 1.5GB
                maxTokens: 300,
                imageSize: 192,
                keepModelLoaded: false,
                aggressiveCleanup: true
            )
            
        case .low:
            return MemoryConfiguration(
                cacheLimit: 8 * 1024 * 1024,       // 8MB
                memoryLimit: 2_000 * 1024 * 1024,  // 2GB
                maxTokens: 500,
                imageSize: 256,
                keepModelLoaded: false,
                aggressiveCleanup: false
            )
            
        case .standard:  // 4GB设备这里
            return MemoryConfiguration(
                cacheLimit: 20 * 1024 * 1024,      // 20MB
                memoryLimit: 2_500 * 1024 * 1024,  // 2.5GB
                maxTokens: 800,
                imageSize: 384,
                keepModelLoaded: true,
                aggressiveCleanup: false
            )
            
        case .high:
            return MemoryConfiguration(
                cacheLimit: 50 * 1024 * 1024,      // 50MB
                memoryLimit: nil,                  // 不限制
                maxTokens: 1000,
                imageSize: 448,
                keepModelLoaded: true,
                aggressiveCleanup: false
            )
        }
    }
}
```

**使用方式:**

```swift
class VLMEvaluator {
    private let memoryTier = DeviceMemoryTier.current
    private lazy var config = MemoryConfiguration.forTier(memoryTier)
    
    func load() async throws -> ModelContainer {
        // 应用内存配置
        if let limit = config.memoryLimit {
            MLX.GPU.set(memoryLimit: limit)
        }
        MLX.GPU.set(cacheLimit: config.cacheLimit)
        
        // ...加载模型
        
        if config.keepModelLoaded {
            loadState = .loaded(modelContainer)
        }
        
        return modelContainer
    }
    
    var generateParameters: MLXLMCommon.GenerateParameters {
        MLXLMCommon.GenerateParameters(
            maxTokens: config.maxTokens,
            temperature: 0.7,
            topP: 0.9
        )
    }
}
```

---

### 3.2 智能内存监控

#### 实现动态内存管理

```swift
@Observable
class MemoryMonitor {
    static let shared = MemoryMonitor()
    
    enum MemoryPressure {
        case normal      // < 70% 使用
        case warning     // 70-85% 使用
        case critical    // > 85% 使用
    }
    
    @MainActor
    private(set) var currentPressure: MemoryPressure = .normal
    
    private var monitorTimer: Timer?
    
    func startMonitoring() {
        // iOS系统内存警告
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        // 定期检查
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkMemoryPressure()
        }
    }
    
    @objc private func handleMemoryWarning() {
        Task { @MainActor in
            currentPressure = .critical
            performEmergencyCleanup()
        }
    }
    
    private func checkMemoryPressure() {
        let usage = getMemoryUsagePercentage()
        
        Task { @MainActor in
            if usage > 85 {
                currentPressure = .critical
                performAggressiveCleanup()
            } else if usage > 70 {
                currentPressure = .warning
                performLightCleanup()
            } else {
                currentPressure = .normal
            }
        }
    }
    
    private func getMemoryUsagePercentage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return 0 }
        
        let used = UInt64(info.resident_size)
        let total = ProcessInfo.processInfo.physicalMemory
        
        return Double(used) / Double(total) * 100
    }
    
    private func performLightCleanup() {
        GPU.clearCache()
    }
    
    private func performAggressiveCleanup() {
        GPU.clearCache()
        eval()
    }
    
    private func performEmergencyCleanup() {
        // 只在真正紧急情况下卸载模型
        GPU.clearCache()
        eval()
        
        NotificationCenter.default.post(
            name: .memoryEmergency,
            object: nil
        )
    }
    
    func canKeepModelLoaded() -> Bool {
        return currentPressure != .critical
    }
}

extension Notification.Name {
    static let memoryEmergency = Notification.Name("MemoryEmergency")
}
```

#### 集成到VLMEvaluator

```swift
class VLMEvaluator {
    private let memoryMonitor = MemoryMonitor.shared
    
    init() {
        memoryMonitor.startMonitoring()
        
        // 监听内存紧急情况
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryEmergency),
            name: .memoryEmergency,
            object: nil
        )
    }
    
    @objc private func handleMemoryEmergency() {
        // 只在紧急情况下卸载模型
        if case .loaded = loadState {
            unloadModel()
        }
    }
    
    func cancelGeneration() {
        generationTask?.cancel()
        running = false
        
        // 根据内存压力决定是否清理
        switch memoryMonitor.currentPressure {
        case .critical:
            GPU.clearCache()
            unloadModel()
        case .warning:
            GPU.clearCache()
        case .normal:
            // 不清理，保持性能
            break
        }
    }
}
```

---

### 3.3 优化的清理策略

#### 移除主线程阻塞

```swift
func unloadModel() {
    guard case .loaded = loadState else { return }
    
    loadState = .idle
    
    // 异步清理，不阻塞主线程
    Task.detached(priority: .utility) {
        await self.performAsyncCleanup()
    }
}

private func performAsyncCleanup() async {
    // 在后台线程清理
    autoreleasepool {
        GPU.clearCache()
        eval()
    }
    
    // 只有超低内存设备才需要额外清理
    if memoryTier == .ultraLow {
        for _ in 0..<2 {  // 减少到2次
            autoreleasepool {
                GPU.clearCache()
                // 移除 Thread.sleep
            }
        }
    }
}
```

---

## 4. 推荐配置 (4GB设备)

### 4.1 内存配置

```swift
// 4GB设备推荐配置
let config = MemoryConfiguration(
    cacheLimit: 20 * 1024 * 1024,       // 20MB 缓存
    memoryLimit: 2_500 * 1024 * 1024,   // 2.5GB GPU内存
    maxTokens: 800,                      // 800 tokens输出
    imageSize: 384,                      // 384x384 图像
    keepModelLoaded: true,               // 保持模型加载
    aggressiveCleanup: false             // 不激进清理
)
```

### 4.2 预期性能

| 指标 | 当前 (错误分类) | 优化后 | 提升 |
|------|----------------|--------|------|
| GPU缓存 | 3MB | 20MB | +566% |
| GPU内存限制 | 1.8GB | 2.5GB | +39% |
| 最大Tokens | 300 | 800 | +166% |
| 图像分辨率 | 224² | 384² | +192% |
| 生成速度 | 8-12 t/s | 18-25 t/s | +100% |
| 模型加载 | 每次 | 缓存 | 持久化 |
| 响应时间 | 5-8秒 | <1秒 | -85% |

---

## 5. 具体实施步骤

### Step 1: 快速修复 (立即实施)

修改设备判断阈值:

```swift
// 在 VLMEvaluator 类中修改
private var isLowMemoryDevice: Bool {
    ProcessInfo.processInfo.physicalMemory <= 3 * 1024 * 1024 * 1024  // 改为3GB
}

private var isUltraLowMemoryDevice: Bool {
    ProcessInfo.processInfo.physicalMemory <= 2 * 1024 * 1024 * 1024  // 改为2GB
}
```

### Step 2: 调整GPU限制

```swift
func load() async throws -> ModelContainer {
    switch loadState {
    case .idle:
        if isUltraLowMemoryDevice {
            // ≤2GB: 严格限制
            MLX.GPU.set(cacheLimit: 3 * 1024 * 1024)
            MLX.GPU.set(memoryLimit: 1_500 * 1024 * 1024)
        } else if isLowMemoryDevice {
            // 2-3GB: 中等限制
            MLX.GPU.set(cacheLimit: 8 * 1024 * 1024)
            MLX.GPU.set(memoryLimit: 2_000 * 1024 * 1024)
        } else {
            // ≥3GB (包括4GB): 标准配置
            MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
            // 不设置memoryLimit，让系统自动管理
        }
        
        // ...加载模型代码
```

### Step 3: 优化生成参数

```swift
var generateParameters: MLXLMCommon.GenerateParameters {
    let physicalMemory = ProcessInfo.processInfo.physicalMemory
    
    if physicalMemory <= 2 * 1024 * 1024 * 1024 {
        // ≤2GB
        return MLXLMCommon.GenerateParameters(
            maxTokens: 300, temperature: 0.7, topP: 0.9)
    } else if physicalMemory <= 3 * 1024 * 1024 * 1024 {
        // 2-3GB
        return MLXLMCommon.GenerateParameters(
            maxTokens: 500, temperature: 0.7, topP: 0.9)
    } else {
        // ≥3GB (包括4GB)
        return MLXLMCommon.GenerateParameters(
            maxTokens: 800, temperature: 0.7, topP: 0.9)
    }
}
```

### Step 4: 调整图像分辨率

```swift
// 在 generate 函数中
var userInput = UserInput(chat: chat)

let physicalMemory = ProcessInfo.processInfo.physicalMemory
if physicalMemory <= 2 * 1024 * 1024 * 1024 {
    // ≤2GB: 小分辨率
    userInput.processing.resize = .init(width: 192, height: 192)
} else if physicalMemory <= 3 * 1024 * 1024 * 1024 {
    // 2-3GB: 中等分辨率
    userInput.processing.resize = .init(width: 256, height: 256)
} else {
    // ≥3GB (包括4GB): 高分辨率
    userInput.processing.resize = .init(width: 384, height: 384)
}
```

### Step 5: 优化模型缓存

```swift
func load() async throws -> ModelContainer {
    switch loadState {
    case .idle:
        // ...设置GPU限制
        
        let modelContainer = try await VLMModelFactory.shared.loadContainer(
            configuration: modelConfiguration
        ) { [modelConfiguration] progress in
            Task { @MainActor in
                self.modelInfo = "Downloading \(modelConfiguration.name): \(Int(progress.fractionCompleted * 100))%"
            }
        }
        
        // ...
        
        // ≥3GB设备: 缓存模型
        if !isLowMemoryDevice {  // 现在isLowMemoryDevice = 3GB
            self.modelInfo = "\(modelName) • \(weightsMB)M"
            loadState = .loaded(modelContainer)
        } else {
            self.modelInfo = "\(modelName) • \(weightsMB)M • Low Memory"
        }
        
        return modelContainer
        
    case .loaded(let modelContainer):
        return modelContainer
    }
}
```

### Step 6: 简化清理逻辑

```swift
func cancelGeneration() {
    generationTask?.cancel()
    running = false
    
    // 只有真正低内存设备才清理
    if isUltraLowMemoryDevice {
        GPU.clearCache()
    }
    // 4GB设备不需要清理
}

func unloadModel() {
    guard case .loaded = loadState else { return }
    loadState = .idle
    
    // 异步清理，不阻塞主线程
    Task.detached(priority: .utility) {
        GPU.clearCache()
        
        // 只有≤2GB设备才额外清理
        if ProcessInfo.processInfo.physicalMemory <= 2 * 1024 * 1024 * 1024 {
            autoreleasepool {
                eval()
                GPU.clearCache()
            }
        }
    }
}

func emergencyMemoryReset() {
    unloadModel()
    GPU.clearCache()
    eval()
    
    // 移除不必要的循环和Thread.sleep
}
```

---

## 6. 进阶优化 (可选)

### 6.1 实施内存监控系统

```swift
// 添加到 VLMEvaluator
private let memoryMonitor = MemoryMonitor.shared

init() {
    memoryMonitor.startMonitoring()
    
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleMemoryEmergency),
        name: .memoryEmergency,
        object: nil
    )
}

@objc private func handleMemoryEmergency() {
    // 只在真正的内存紧急情况下卸载
    if case .loaded = loadState {
        unloadModel()
    }
}
```

### 6.2 智能清理策略

```swift
private func performSmartCleanup() {
    switch memoryMonitor.currentPressure {
    case .normal:
        // 不清理
        break
        
    case .warning:
        // 轻量清理
        GPU.clearCache()
        
    case .critical:
        // 激进清理
        GPU.clearCache()
        eval()
        unloadModel()
    }
}
```

---

## 7. 测试与验证

### 7.1 性能测试

**测试场景:**
1. 首次加载模型
2. 连续生成5次
3. 切换不同图片
4. 长时间运行 (30分钟)

**监控指标:**
- 内存峰值 (应 <2.5GB)
- 生成速度 (应 >15 t/s)
- 响应时间 (应 <2秒)
- 稳定性 (无崩溃)

### 7.2 内存压力测试

```swift
// 测试代码
func stressTest() async {
    for i in 1...20 {
        print("测试轮次 \(i)")
        
        // 生成
        await generate(prompt: "描述这张图片", image: testImage, videoURL: nil)
        
        // 检查内存
        let usage = getMemoryUsage()
        print("内存使用: \(usage)MB")
        
        // 等待
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒
    }
}
```

### 7.3 检查清单

- [ ] 4GB设备被正确分类为标准设备
- [ ] GPU缓存≥15MB
- [ ] 生成速度≥15 tokens/秒
- [ ] 图像分辨率≥384×384
- [ ] maxTokens≥800
- [ ] 模型正确缓存在内存中
- [ ] 无不必要的清理操作
- [ ] 无主线程阻塞
- [ ] 长时间运行稳定
- [ ] 内存峰值<2.5GB

---

## 8. 对比总结

### 8.1 4GB设备优化前后对比

| 项目 | 优化前 | 优化后 | 说明 |
|------|--------|--------|------|
| **设备分类** | 低内存设备 | 标准设备 | 正确分类 |
| **GPU缓存** | 3MB | 20MB | 缓存充足 |
| **GPU内存限制** | 1.8GB | 2.5GB | 更合理 |
| **最大Tokens** | 300 | 800 | 完整输出 |
| **图像分辨率** | 224² | 384² | 更高质量 |
| **模型缓存** | 否 | 是 | 持久化 |
| **生成速度** | 8-12 t/s | 18-25 t/s | 显著提升 |
