# SnapSync MVP AI开发指令（极致精简版）
**总token控制目标：<1000字**
**AI执行要求：直接生成可运行代码，不要任何解释、说明、注释以外的文字，不要添加任何额外功能**

---

## 一、核心任务
开发iPhone-Mac局域网自动截图同步工具：iPhone截图后，**零操作**自动发送到Mac保存。
- 技术栈：Swift 5.9，iOS 16.0+，macOS 13.0+
- 唯一第三方依赖：Starscream（仅iOS端WebSocket客户端）
- 架构：Mac做WebSocket服务端+Bonjour广播，iPhone做客户端+Bonjour发现

## 二、绝对禁止项（违者重写）
❌ 不要任何设置界面、偏好配置
❌ 不要历史记录、搜索、筛选
❌ 不要自动归档、自定义路径
❌ 不要多设备支持（仅一对一）
❌ 不要任何云端功能
❌ 不要错误弹窗（仅控制台打印）
❌ 不要动画、过渡效果
❌ 不要任何产品化文案

---

## 三、Mac端开发指令（3个文件）
### 1. AppDelegate.swift
- 纯状态栏应用，无主窗口
- 状态栏图标：使用系统`NSImageNameStatusAvailable`（连接时绿色，断开时灰色）
- 菜单仅3项：
  1. 状态文本："已连接" / "等待连接"
  2. "打开截图文件夹"（打开`~/Downloads/SnapSync/`）
  3. "退出"
- 启动时自动启动WebSocket服务，成功后发布Bonjour服务

### 2. WebSocketServer.swift
- 使用Vapor 4启动WebSocket服务，监听`0.0.0.0:0`（自动分配端口）
- 服务路径固定：`/snap-sync`
- 收到二进制数据时：
  1. 自动创建`~/Downloads/SnapSync/`文件夹
  2. 文件名格式：`screenshot-yyyyMMdd-HHmmssSSS.png`
  3. 保存文件
  4. 发送系统通知（标题："截图已保存"，正文：文件名）
- 连接/断开时更新状态栏状态

### 3. BonjourPublisher.swift
- 使用系统`NetService`发布服务
- 服务类型：`_snapsync._tcp.`
- 服务名称：`SnapSync-Mac-\(Host.current().localizedName!)`
- 广播WebSocket服务的实际端口

---

## 四、iPhone端开发指令（4个文件）
### 1. ViewController.swift
- 单页面UI，垂直居中排列：
  1. 大UISwitch开关（默认关闭）
  2. UILabel：显示连接状态（"已连接到Mac" / "未连接"）
  3. UILabel：显示今日同步数量
- 开关开启时：启动Bonjour发现 + 启动截图监听
- 开关关闭时：断开WebSocket + 停止所有监听

### 2. BonjourBrowser.swift
- 使用系统`NetServiceBrowser`搜索`_snapsync._tcp.`服务
- 发现第一个服务后自动解析IP和端口
- 解析成功后立即调用WebSocketManager.connect()
- 仅连接第一个发现的设备，忽略其他

### 3. WebSocketManager.swift
- 单例模式，使用Starscream库
- 连接成功/断开时更新UI状态
- 断开后**3秒自动重试**，无限循环
- 提供`send(data: Data)`方法发送二进制数据

### 4. ScreenshotMonitor.swift
- 单例模式
- 使用`PHPhotoLibrary.shared().registerChangeObserver`监听相册变化
- 变化时执行以下逻辑：
  1. 取最新添加的1张图片
  2. 判断：创建时间距现在<2秒 **且** 图片尺寸等于屏幕原生尺寸
  3. 符合条件则获取原图数据
  4. 调用WebSocketManager.send(data:)
  5. 发送成功后今日同步数+1
- 申请相册权限，被拒绝时控制台打印即可

---

## 五、权限配置
### iOS Info.plist添加：
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>访问相册以同步截图</string>
<key>UIBackgroundModes</key>
<array><string>fetch</string></array>
<key>NSAppTransportSecurity</key>
<dict><key>NSAllowsArbitraryLoads</key><true/></dict>
```

### macOS Info.plist添加：
```xml
<key>NSDownloadsFolderUsageDescription</key>
<string>保存同步的截图</string>
<key>NSAppTransportSecurity</key>
<dict><key>NSAllowsArbitraryLoads</key><true/></dict>
```

---

## 六、最终交付要求
1. 分别输出macOS和iOS两个完整Xcode项目的所有代码
2. 每个文件用`// === 文件名.swift ===`标注
3. 代码中仅添加必要的功能性注释
4. 不要生成任何README、说明文档、测试代码
5. 不要修改上述任何要求
