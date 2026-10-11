import AppKit
import Charts
import SwiftUI

private enum PanelPage: String, CaseIterable {
    case overview = "内存总览"
    case applications = "应用与进程"
    case history = "内存趋势"
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .applications: "square.stack.3d.up.fill"
        case .history: "chart.xyaxis.line"
        }
    }
}

private enum MemoryStyle {
    static let ink = Color(red: 0.13, green: 0.16, blue: 0.20)
    static let secondary = Color(red: 0.46, green: 0.49, blue: 0.54)
    static let blue = Color(red: 0.12, green: 0.46, blue: 0.97)
    static let teal = Color(red: 0.22, green: 0.66, blue: 0.69)
    static let purple = Color(red: 0.63, green: 0.55, blue: 0.87)
    static let background = Color(red: 0.966, green: 0.972, blue: 0.982)
    static let border = Color.black.opacity(0.055)
}

private enum MemoryFormat {
    static func amount(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value >= 1_073_741_824 { return String(format: "%.2f GB", value / 1_073_741_824) }
        if value >= 1_048_576 { return String(format: "%.1f MB", value / 1_048_576) }
        if bytes == 0 { return "0 MB" }
        return String(format: "%.0f KB", value / 1024)
    }
    static func groupAmount(_ group: AppMemory, annotatePartial: Bool = true) -> String {
        if group.processes.allSatisfy({ $0.metric == "unavailable" }) { return "不可读" }
        let partial = group.processes.contains { $0.metric == "unavailable" }
        return amount(group.bytes) + (partial && annotatePartial ? " · 部分不可读" : "")
    }
    static func groupPercentage(_ group: AppMemory, total: UInt64) -> String {
        if group.processes.allSatisfy({ $0.metric == "unavailable" }) { return "—" }
        let partial = group.processes.contains { $0.metric == "unavailable" }
        return (partial ? "≥" : "") + String(format: "%.1f%%", percentage(group.bytes, total: total))
    }
    static func gigabytes(_ bytes: UInt64) -> String { String(format: "%.1f", Double(bytes) / 1_073_741_824) }
    static func percentage(_ bytes: UInt64, total: UInt64) -> Double { total == 0 ? 0 : Double(bytes) / Double(total) * 100 }
    static func pressureName(_ pressure: String) -> String {
        switch pressure {
        case "normal": "正常"
        case "warning": "偏高"
        case "critical": "紧张"
        default: "未知"
        }
    }
    static func pressureColor(_ pressure: String) -> Color {
        switch pressure {
        case "normal": Color(red: 0.19, green: 0.67, blue: 0.43)
        case "warning": .orange
        case "critical": .red
        default: .gray
        }
    }
    static func pressureDescription(_ pressure: String) -> String {
        switch pressure {
        case "normal": "系统内存压力处于正常范围。"
        case "warning": "内存压力偏高，可关注占用较大的应用。"
        case "critical": "内存压力较大，系统可能正在频繁交换内存。"
        default: "暂时无法获取系统内存压力等级。"
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var store: MemoryStore
    @State private var page: PanelPage = .overview
    @State private var showsDetails = false
    @State private var pendingTermination: TerminationRequest?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(MemoryStyle.border).frame(width: 1)
            VStack(spacing: 0) {
                header
                if let snapshot = store.snapshot {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            if let error = store.errorMessage { errorBanner(error) }
                            switch page {
                            case .overview:
                                overview(snapshot)
                            case .applications:
                                AppListPanel(snapshot: snapshot, onRequestQuit: beginTermination)
                            case .history:
                                historyPage(snapshot)
                            }
                        }
                        .padding(.horizontal, 30)
                        .padding(.top, 10)
                        .padding(.bottom, 30)
                    }
                } else {
                    initialState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MemoryStyle.background)
        }
        .foregroundStyle(MemoryStyle.ink)
        .tint(MemoryStyle.blue)
        .sheet(isPresented: $showsDetails) { detailsSheet }
        .sheet(item: $pendingTermination) { request in
            TerminationFlowSheet(request: request) { pendingTermination = nil }
                .environmentObject(store)
        }
    }

    private func beginTermination(_ request: TerminationRequest) {
        guard !store.isTerminating else { return }
        store.prepareTermination()
        pendingTermination = request
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13).fill(MemoryStyle.blue.gradient)
                    Image(systemName: "memorychip").font(.system(size: 23, weight: .medium)).foregroundStyle(.white)
                }.frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Memory Glass").font(.system(size: 16, weight: .semibold))
                    Text("内存监测").font(.system(size: 11)).foregroundStyle(MemoryStyle.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 48)
            .padding(.bottom, 36)

            Text("工作空间").font(.system(size: 10, weight: .semibold)).foregroundStyle(MemoryStyle.secondary).padding(.horizontal, 24).padding(.bottom, 10)
            VStack(spacing: 5) {
                ForEach(PanelPage.allCases, id: \.self) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { page = item }
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: item.symbol).font(.system(size: 15, weight: .medium)).frame(width: 20)
                            Text(item.rawValue).font(.system(size: 13, weight: page == item ? .semibold : .medium))
                            Spacer()
                        }
                        .foregroundStyle(page == item ? MemoryStyle.blue : MemoryStyle.ink.opacity(0.78))
                        .padding(.horizontal, 12)
                        .frame(height: 41)
                        .background(page == item ? MemoryStyle.blue.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(page == item ? .isSelected : [])
                }
            }.padding(.horizontal, 12)

            Spacer(minLength: 25)

            if let snapshot = store.snapshot {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "macmini").font(.system(size: 25, weight: .light)).foregroundStyle(MemoryStyle.secondary)
                    Text(snapshot.deviceName).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                    Text("\(snapshot.chipName)\n\(MemoryFormat.gigabytes(snapshot.totalBytes)) GB 统一内存")
                        .font(.system(size: 11)).foregroundStyle(MemoryStyle.secondary).lineSpacing(4)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(MemoryStyle.border))
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
            Button { showsDetails = true } label: {
                Label("数据说明", systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(MemoryStyle.secondary)
            }.buttonStyle(.plain).padding(.leading, 24).padding(.bottom, 22)
        }
        .frame(width: 210)
        .background(Color(red: 0.94, green: 0.952, blue: 0.969))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(page.rawValue).font(.system(size: 27, weight: .bold, design: .rounded))
                Text(page == .overview ? "看清每一份内存，让工作从容一些。" : page == .applications ? "找到内存的去向，展开查看每一个进程。" : "记录此刻到过去 30 分钟的内存变化。")
                    .font(.system(size: 12)).foregroundStyle(MemoryStyle.secondary)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 9) {
                HStack(spacing: 8) {
                    Picker("刷新频率", selection: $store.refreshInterval) {
                        Text("每 1 秒").tag(1.0)
                        Text("每 2 秒").tag(2.0)
                        Text("每 5 秒").tag(5.0)
                    }.labelsHidden().frame(width: 88).controlSize(.small).help("选择自动采样间隔")
                    Button { store.isPaused.toggle() } label: {
                        Image(systemName: store.isPaused ? "play.fill" : "pause.fill").font(.system(size: 12, weight: .semibold)).frame(width: 15, height: 16)
                    }.buttonStyle(.bordered).controlSize(.small).help(store.isPaused ? "恢复实时采样" : "暂停实时采样").accessibilityLabel(store.isPaused ? "恢复实时采样" : "暂停实时采样")
                    Button { store.refresh() } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold)).frame(width: 15, height: 16)
                    }.buttonStyle(.bordered).controlSize(.small).disabled(store.isCollecting || store.isTerminating).help("立即刷新 · ⌘R").accessibilityLabel("立即刷新")
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let age = store.snapshot.map { context.date.timeIntervalSince($0.timestamp) } ?? 0
                    let stale = age > max(15, store.refreshInterval * 3)
                    HStack(spacing: 5) {
                        Circle().fill(store.isPaused ? .gray : (store.errorMessage != nil || stale) ? .orange : Color.green).frame(width: 5, height: 5)
                        Text(store.isPaused ? "已暂停 · 数据停留在上次采样" : store.errorMessage != nil ? "采样异常 · 保留上次数据" : stale ? "等待新数据" : "实时更新")
                        if !store.isPaused, let stamp = store.snapshot?.timestamp { Text(stamp, style: .time).monospacedDigit() }
                    }.font(.system(size: 10)).foregroundStyle(MemoryStyle.secondary)
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 29)
        .padding(.bottom, 22)
    }

    private func overview(_ snapshot: MemorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 21) {
            SummaryPanel(snapshot: snapshot)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 11), count: 5), spacing: 11) {
                MetricTile(title: "应用内存", value: MemoryFormat.amount(snapshot.appBytes), symbol: "app.fill", color: MemoryStyle.blue)
                MetricTile(title: "系统常驻", value: MemoryFormat.amount(snapshot.wiredBytes), symbol: "lock.fill", color: MemoryStyle.teal)
                MetricTile(title: "已压缩", value: MemoryFormat.amount(snapshot.compressedBytes), symbol: "arrow.down.right.and.arrow.up.left", color: MemoryStyle.purple)
                MetricTile(title: "缓存文件", value: MemoryFormat.amount(snapshot.cachedBytes), symbol: "doc.on.doc.fill", color: .gray)
                MetricTile(title: "已用交换", value: snapshot.swapAvailable ? MemoryFormat.amount(snapshot.swapUsedBytes) : "不可读取", symbol: "arrow.left.arrow.right", color: Color(red: 0.75, green: 0.53, blue: 0.27))
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 17) {
                    HStack {
                        Text("占用较多的应用").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Button("查看全部") { page = .applications }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(MemoryStyle.blue)
                    }
                    let apps = snapshot.groups.filter(\.isApplication).sorted { $0.bytes > $1.bytes }.prefix(5)
                    if apps.isEmpty {
                        Text("本次没有读取到应用程序。可在“应用与进程”查看后台服务。")
                            .font(.system(size: 12)).foregroundStyle(MemoryStyle.secondary).padding(.vertical, 18)
                    }
                    ForEach(Array(apps)) { app in
                        HStack(spacing: 10) {
                            AppIcon(group: app, size: 30)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Text(MemoryFormat.groupAmount(app)).font(.system(size: 10)).foregroundStyle(MemoryStyle.secondary).monospacedDigit()
                            }
                            Spacer(minLength: 8)
                            Text(MemoryFormat.groupPercentage(app, total: snapshot.totalBytes))
                                .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                            ForceQuitButton(request: TerminationRequest(name: app.name, processes: app.processes, isGroup: true), isBusy: store.isTerminating, onRequest: beginTermination)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .panel()
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("内存趋势").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text("本次运行").font(.system(size: 10)).foregroundStyle(MemoryStyle.secondary)
                    }
                    MemoryTrendChart(samples: store.samples, compact: true).frame(height: 148)
                    HStack {
                        Text("保留最近 30 分钟").font(.system(size: 10)).foregroundStyle(MemoryStyle.secondary)
                        Spacer()
                        Button("查看趋势") { page = .history }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(MemoryStyle.blue)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .panel()
            }
            Text("应用占比以 \(MemoryFormat.gigabytes(snapshot.totalBytes)) GB 物理内存为分母；按应用包与父子关系合并辅助进程。")
                .font(.system(size: 10)).foregroundStyle(MemoryStyle.secondary).padding(.horizontal, 2)
        }
    }

    private func historyPage(_ snapshot: MemorySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 15) {
                MetricTile(title: "当前占用", value: String(format: "%.1f%%", snapshot.usedPercent), symbol: "memorychip", color: MemoryStyle.blue)
                MetricTile(title: "记录峰值", value: String(format: "%.1f%%", store.samples.map(\.percent).max() ?? snapshot.usedPercent), symbol: "arrow.up.right", color: MemoryStyle.teal)
                MetricTile(title: "记录平均", value: String(format: "%.1f%%", store.samples.isEmpty ? snapshot.usedPercent : store.samples.map(\.percent).reduce(0, +) / Double(store.samples.count)), symbol: "waveform.path", color: MemoryStyle.purple)
            }
            VStack(alignment: .leading, spacing: 25) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("物理内存使用率").font(.system(size: 17, weight: .semibold))
                        Text("\(store.samples.count) 次真实采样 · 仅保存在当前运行期间")
                            .font(.system(size: 12)).foregroundStyle(MemoryStyle.secondary)
                    }
                    Spacer()
                    PressureBadge(pressure: snapshot.pressure)
                }
                MemoryTrendChart(samples: store.samples, compact: false).frame(height: 300)
            }.padding(24).panel()
            VStack(alignment: .leading, spacing: 9) {
                Label("理解内存使用率", systemImage: "lightbulb").font(.system(size: 13, weight: .semibold))
                Text("macOS 会利用空闲内存加速工作。判断是否需要关闭应用时，优先关注“内存压力”，再结合使用率与交换内存。暂停采样后，图表不会补造数据；重新打开应用会开始新的记录。")
                    .font(.system(size: 12)).foregroundStyle(MemoryStyle.secondary).lineSpacing(5)
            }.padding(22).panel()
        }
    }

    private var initialState: some View {
        VStack(spacing: 17) {
            if let error = store.errorMessage {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 34, weight: .light)).foregroundStyle(.orange)
                Text("暂时无法读取内存").font(.system(size: 20, weight: .semibold))
                Text(error).font(.system(size: 12)).foregroundStyle(MemoryStyle.secondary).multilineTextAlignment(.center).frame(maxWidth: 450)
                Button("重新读取") { store.refresh() }.buttonStyle(.borderedProminent)
            } else {
                ProgressView().controlSize(.large)
                Text("正在读取这台 Mac 的内存…").font(.system(size: 15, weight: .medium))
                Text("首次采样完成后，将自动开始实时更新。")
                    .font(.system(size: 12)).foregroundStyle(MemoryStyle.secondary)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBanner(_ error: String) -> some View {
        Label("采样未完成：\(error) · 以下为上次成功读取的数据。", systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12)).foregroundStyle(Color.orange).padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var detailsSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("关于这些数字").font(.system(size: 23, weight: .bold))
                Spacer()
                Button("完成") { showsDetails = false }.keyboardShortcut(.defaultAction)
            }
            VStack(alignment: .leading, spacing: 17) {
                detail("百分比的分母", "所有应用与进程的占比，均以这台 Mac 的物理内存总量为分母。显示单位采用 1024 进制（1 GB = 1024³ 字节）。")
                detail("应用与辅助进程", "应用列表按应用包和父子进程关系合并。展开应用可查看本次采样中读取到的进程及 PID。无法确定归属的共享服务（包括部分 WebKit 进程）单独显示在“全部程序”中。")
                detail("为什么总和不一定相等", "整体内存与进程内存使用不同的 macOS 统计口径。进程优先显示 physical footprint；读取受限时回退到 RSS，无法读取则标记“不可读”。共享内存、压缩内存与内核记账会使进程相加结果不同于整体已用内存。")
                detail("整体内存与压力", "整体已用内存按系统 VM 计数估算，含应用、常驻与压缩部分。系统常驻（wired）是系统必须保留在内存中的部分，缓存文件可回收。各 VM 分类受记账影响，不保证与物理总量精确相加。内存压力直接读取系统等级；交换内存是磁盘上已使用的交换空间。")
                detail("实时采样与隐私", "数据直接从当前 Mac 读取。记录只保存在本次运行的内存中，最多保留 30 分钟；应用不上传数据。强制退出仅在你确认具体目标后执行，不使用管理员权限；受保护的系统进程和本应用不会被结束。")
            }
            if let snapshot = store.snapshot {
                Text("本次读取 \(snapshot.processCount) 个进程 · \(snapshot.rssCount) 个使用 RSS · \(snapshot.unavailableCount) 个不可读 · 耗时 \(Int(snapshot.collectionDurationMS)) ms")
                    .font(.system(size: 11)).foregroundStyle(MemoryStyle.secondary)
                if !snapshot.warnings.isEmpty {
                    Text(snapshot.warnings.joined(separator: "\n")).font(.system(size: 11)).foregroundStyle(.orange)
                }
            }
        }.padding(30).frame(width: 600)
    }

    private func detail(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(text).font(.system(size: 12)).foregroundStyle(MemoryStyle.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SummaryPanel: View {
    let snapshot: MemorySnapshot
    var body: some View {
        HStack(spacing: 32) {
            ZStack {
                Circle().stroke(MemoryStyle.blue.opacity(0.075), lineWidth: 17)
                Circle().trim(from: 0, to: min(1, max(0, snapshot.usedPercent / 100)))
                    .stroke(MemoryStyle.blue.gradient, style: StrokeStyle(lineWidth: 17, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.45), value: snapshot.usedPercent)
                VStack(spacing: 5) {
                    Text("已使用").font(.system(size: 12)).foregroundStyle(MemoryStyle.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(String(format: "%.1f", snapshot.usedPercent)).font(.system(size: 43, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("%").font(.system(size: 19, weight: .medium, design: .rounded)).foregroundStyle(MemoryStyle.secondary)
                    }
                    Text("\(MemoryFormat.gigabytes(snapshot.usedBytes)) / \(MemoryFormat.gigabytes(snapshot.totalBytes)) GB")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(MemoryStyle.secondary).monospacedDigit()
                }
            }.frame(width: 184, height: 184).padding(10)
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("这台 Mac 的内存").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    PressureBadge(pressure: snapshot.pressure)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(MemoryFormat.gigabytes(snapshot.usedBytes)).font(.system(size: 37, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("GB 已使用").font(.system(size: 14)).foregroundStyle(MemoryStyle.secondary)
                    }
                    Text(MemoryFormat.pressureDescription(snapshot.pressure)).font(.system(size: 12)).foregroundStyle(MemoryStyle.secondary).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 11) {
                    GeometryReader { geometry in
                        HStack(spacing: 2) {
                            segment(snapshot.appBytes, total: snapshot.totalBytes, width: geometry.size.width, color: MemoryStyle.blue)
                            segment(snapshot.wiredBytes, total: snapshot.totalBytes, width: geometry.size.width, color: MemoryStyle.teal)
                            segment(snapshot.compressedBytes, total: snapshot.totalBytes, width: geometry.size.width, color: MemoryStyle.purple)
                            Spacer(minLength: 0)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 9).background(MemoryStyle.blue.opacity(0.065)).clipShape(Capsule())
                    HStack(spacing: 15) {
                        legend("应用", MemoryStyle.blue)
                        legend("常驻", MemoryStyle.teal)
                        legend("压缩", MemoryStyle.purple)
                        Spacer(minLength: 0)
                        Text("可用 \(MemoryFormat.amount(snapshot.totalBytes > snapshot.usedBytes ? snapshot.totalBytes - snapshot.usedBytes : 0))")
                            .font(.system(size: 10)).foregroundStyle(MemoryStyle.secondary).monospacedDigit()
                    }
                }
            }
        }.padding(25).panel()
    }
    private func segment(_ bytes: UInt64, total: UInt64, width: Double, color: Color) -> some View {
        color.frame(width: max(0, (width - 6) * min(1, MemoryFormat.percentage(bytes, total: total) / 100)))
    }
    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 5, height: 5); Text(title).font(.system(size: 10)).foregroundStyle(MemoryStyle.secondary) }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(color)
                Text(title).font(.system(size: 11)).foregroundStyle(MemoryStyle.secondary).lineLimit(1)
            }
            Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).panel()
    }
}

private struct PressureBadge: View {
    let pressure: String
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(MemoryFormat.pressureColor(pressure)).frame(width: 6, height: 6)
            Text("压力\(MemoryFormat.pressureName(pressure))").font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(MemoryFormat.pressureColor(pressure))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(MemoryFormat.pressureColor(pressure).opacity(0.09), in: Capsule())
        .accessibilityLabel("内存压力\(MemoryFormat.pressureName(pressure))")
    }
}

private struct MemoryTrendChart: View {
    let samples: [MemorySample]
    let compact: Bool
    private var start: Date { samples.first?.date ?? Date() }
    private var end: Date { max(samples.last?.date ?? Date(), start.addingTimeInterval(60)) }
    var body: some View {
        Chart {
            ForEach(samples) { sample in
                AreaMark(x: .value("时间", sample.date), yStart: .value("零", 0), yEnd: .value("使用率", sample.percent))
                    .foregroundStyle(LinearGradient(colors: [MemoryStyle.blue.opacity(0.17), MemoryStyle.blue.opacity(0.005)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.linear)
                LineMark(x: .value("时间", sample.date), y: .value("使用率", sample.percent))
                    .foregroundStyle(MemoryStyle.blue).lineStyle(StrokeStyle(lineWidth: compact ? 2 : 2.5))
                    .interpolationMethod(.linear)
            }
            if let last = samples.last {
                PointMark(x: .value("时间", last.date), y: .value("使用率", last.percent))
                    .foregroundStyle(MemoryStyle.blue).symbolSize(25)
            }
        }
        .chartXScale(domain: start...end)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine().foregroundStyle(MemoryStyle.border)
                AxisValueLabel { if let number = value.as(Int.self) { Text("\(number)%").font(.system(size: 9)).foregroundStyle(MemoryStyle.secondary) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: compact ? 2 : 5)) { _ in
                AxisValueLabel(format: .dateTime.hour().minute().second()).font(.system(size: 9)).foregroundStyle(MemoryStyle.secondary)
            }
        }
        .accessibilityLabel("内存使用率趋势，\(samples.count) 次采样")
    }
}

private struct AppIcon: View {
    let group: AppMemory
    let size: CGFloat
    var body: some View {
        if let path = group.bundlePath {
            Image(nsImage: AppIconCache.shared.icon(for: path)).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.24).fill(Color.gray.opacity(0.09))
                Image(systemName: "gearshape.fill").font(.system(size: size * 0.52)).foregroundStyle(MemoryStyle.secondary.opacity(0.8))
            }.frame(width: size, height: size)
        }
    }
}

private struct AppListPanel: View {
    @EnvironmentObject private var store: MemoryStore
    let snapshot: MemorySnapshot
    let onRequestQuit: (TerminationRequest) -> Void
    @State private var query = ""
    @State private var applicationsOnly = true
    @State private var sortByName = false
    @State private var expanded: Set<String> = []

    private var visibleGroups: [AppMemory] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return snapshot.groups.filter { group in
            (!applicationsOnly || group.isApplication) && (needle.isEmpty || group.name.localizedCaseInsensitiveContains(needle) || group.processes.contains { $0.name.localizedCaseInsensitiveContains(needle) || String($0.pid).contains(needle) })
        }.sorted { first, second in
            if sortByName { return first.name.localizedStandardCompare(second.name) == .orderedAscending }
            if first.bytes == second.bytes { return first.name.localizedStandardCompare(second.name) == .orderedAscending }
            return first.bytes > second.bytes
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Picker("显示范围", selection: $applicationsOnly) {
                    Text("应用程序").tag(true)
                    Text("全部程序").tag(false)
                }.pickerStyle(.segmented).frame(width: 205)
                Spacer(minLength: 0)
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(MemoryStyle.secondary)
                    TextField("搜索名称或 PID", text: $query).textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(MemoryStyle.secondary) }.buttonStyle(.plain).accessibilityLabel("清除搜索")
                    }
                }.font(.system(size: 12)).padding(.horizontal, 11).frame(width: 185, height: 30)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MemoryStyle.border))
            }
            VStack(spacing: 0) {
                HStack {
                    Text("\(visibleGroups.count) \(applicationsOnly ? "个应用" : "个程序与服务")").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Picker("排序", selection: $sortByName) {
                        Text("占用从高到低").tag(false)
                        Text("按名称排序").tag(true)
                    }.labelsHidden().controlSize(.small).frame(width: 130)
                }.padding(.horizontal, 20).padding(.vertical, 17)
                Divider().opacity(0.5)
                HStack {
                    Text("名称 / 进程数")
                    Spacer()
                    Text("内存").frame(width: 85, alignment: .trailing)
                    Text("占物理内存").frame(width: 110, alignment: .trailing)
                    Text("操作").frame(width: 26)
                }.font(.system(size: 10, weight: .medium)).foregroundStyle(MemoryStyle.secondary).padding(.horizontal, 22).padding(.vertical, 11)
                    .background(MemoryStyle.background.opacity(0.6))
                if visibleGroups.isEmpty {
                    VStack(spacing: 9) {
                        Image(systemName: "magnifyingglass").font(.system(size: 24)).foregroundStyle(MemoryStyle.secondary)
                        Text("没有找到匹配的程序").font(.system(size: 14, weight: .medium))
                        Text("试试其他名称，或切换到“全部程序”。").font(.system(size: 12)).foregroundStyle(MemoryStyle.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 50)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleGroups) { group in
                            groupRow(group)
                            Divider().opacity(0.4).padding(.leading, 64)
                        }
                    }
                }
            }.panel()
            VStack(alignment: .leading, spacing: 6) {
                Text("占比以 \(MemoryFormat.gigabytes(snapshot.totalBytes)) GB 物理内存为分母，按应用包与父子关系合并；无法确定归属的共享服务单列。展开查看各进程。")
                Text("\(snapshot.processCount) 个进程 · \(snapshot.rssCount) 个使用 RSS 回退值 · \(snapshot.unavailableCount) 个不可读。不同口径与共享记账会使应用总和不同于整体已用内存。")
            }.font(.system(size: 10)).foregroundStyle(MemoryStyle.secondary).lineSpacing(3).padding(.horizontal, 2)
        }
    }

    private func groupRow(_ group: AppMemory) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    if expanded.contains(group.id) { expanded.remove(group.id) } else { expanded.insert(group.id) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: expanded.contains(group.id) ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(MemoryStyle.secondary).frame(width: 9)
                        AppIcon(group: group, size: 31)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text("\(group.processes.count) 个进程\(group.isApplication ? "" : " · 后台服务")")
                                .font(.system(size: 10)).foregroundStyle(MemoryStyle.secondary)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(MemoryFormat.groupAmount(group, annotatePartial: false))
                                .font(.system(size: 12, weight: .medium)).monospacedDigit()
                            if group.processes.contains(where: { $0.metric == "unavailable" }) && !group.processes.allSatisfy({ $0.metric == "unavailable" }) {
                                Text("部分不可读").font(.system(size: 9)).foregroundStyle(.orange)
                            }
                        }.frame(width: 85, alignment: .trailing)
                        HStack(spacing: 8) {
                            GeometryReader { geometry in
                                Capsule().fill(MemoryStyle.blue.opacity(0.08))
                                Capsule().fill(MemoryStyle.blue.opacity(0.7)).frame(width: geometry.size.width * min(1, MemoryFormat.percentage(group.bytes, total: snapshot.totalBytes) / 100))
                            }.frame(width: 44, height: 4)
                            Text(MemoryFormat.groupPercentage(group, total: snapshot.totalBytes))
                                .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().frame(width: 54, alignment: .trailing)
                        }.frame(width: 110, alignment: .trailing)
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(group.name)，\(MemoryFormat.groupAmount(group))，\(expanded.contains(group.id) ? "收起" : "展开")进程")
                ForceQuitButton(request: TerminationRequest(name: group.name, processes: group.processes, isGroup: true), isBusy: store.isTerminating, onRequest: onRequestQuit)
            }.padding(.horizontal, 20).padding(.vertical, 12)
            if expanded.contains(group.id) {
                VStack(spacing: 0) {
                    ForEach(group.processes.sorted { $0.bytes > $1.bytes }) { process in
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.turn.down.right").font(.system(size: 9)).foregroundStyle(MemoryStyle.secondary.opacity(0.6))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(process.name).font(.system(size: 11)).lineLimit(1).help(process.executablePath)
                                Text("PID \(process.pid) · \(metricLabel(process.metric))").font(.system(size: 9)).foregroundStyle(process.metric == "unavailable" ? Color.orange : MemoryStyle.secondary).monospacedDigit()
                            }
                            Spacer(minLength: 7)
                            Text(process.metric == "unavailable" ? "不可读" : MemoryFormat.amount(process.bytes))
                                .font(.system(size: 11)).monospacedDigit().frame(width: 85, alignment: .trailing)
                            Text(process.metric == "unavailable" ? "—" : String(format: "%.2f%%", MemoryFormat.percentage(process.bytes, total: snapshot.totalBytes)))
                                .font(.system(size: 11)).monospacedDigit().frame(width: 110, alignment: .trailing)
                            ForceQuitButton(request: TerminationRequest(name: process.name, processes: [process], isGroup: false), isBusy: store.isTerminating, onRequest: onRequestQuit)
                        }.padding(.leading, 43).padding(.trailing, 20).padding(.vertical, 9)
                    }
                }.background(MemoryStyle.background.opacity(0.7))
            }
        }
    }
    private func metricLabel(_ metric: String) -> String {
        switch metric {
        case "footprint": "physical footprint"
        case "rss": "RSS 驻留内存"
        default: "无法读取内存"
        }
    }
}

private extension View {
    func panel() -> some View {
        background(.white, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(MemoryStyle.border))
            .shadow(color: Color.black.opacity(0.018), radius: 8, x: 0, y: 3)
    }
}

private struct ForceQuitButton: View {
    let request: TerminationRequest
    let isBusy: Bool
    let onRequest: (TerminationRequest) -> Void

    private var reasons: [String] { request.processes.compactMap { ProcessTerminator.blockedReason(for: $0) } }
    private var isBlocked: Bool { request.processes.isEmpty || reasons.count == request.processes.count }
    private var tooltip: String {
        if isBusy { return "正在处理退出请求，请稍候。" }
        if request.processes.isEmpty { return "没有可确认的进程。" }
        if isBlocked { return Array(Set(reasons)).sorted().joined(separator: "\n") }
        let protectedText = reasons.isEmpty ? "" : "；\(reasons.count) 个受保护的进程将跳过"
        return "强制退出“\(request.name)”\(request.isGroup ? "的 \(request.processes.count) 个进程" : "（PID \(request.processes[0].pid)）")\(protectedText)"
    }

    var body: some View {
        Button { onRequest(request) } label: {
            Image(systemName: isBlocked ? "lock.fill" : "xmark.circle")
                .font(.system(size: isBlocked ? 12 : 16, weight: .regular))
                .foregroundStyle(isBlocked || isBusy ? MemoryStyle.secondary.opacity(0.42) : Color.red.opacity(0.77))
                .frame(width: 26, height: 27)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBlocked || isBusy)
        .help(tooltip)
        .accessibilityLabel(isBlocked ? "\(request.name)，无法强制退出：\(tooltip)" : "强制退出\(request.name)")
        .accessibilityHint(tooltip)
    }
}

private struct TerminationFlowSheet: View {
    @EnvironmentObject private var store: MemoryStore
    let request: TerminationRequest
    let onClose: () -> Void

    private var protectedCount: Int { request.processes.filter { ProcessTerminator.blockedReason(for: $0) != nil }.count }
    private var eligibleCount: Int { request.processes.count - protectedCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            if let report = store.terminationReport {
                resultContent(report)
            } else {
                confirmationContent
            }
        }
        .padding(27)
        .frame(width: 620, height: 570)
        .foregroundStyle(MemoryStyle.ink)
        .background(MemoryStyle.background)
        .interactiveDismissDisabled(store.isTerminating)
        .onExitCommand { if !store.isTerminating { onClose() } }
    }

    private var confirmationContent: some View {
        Group {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "xmark.octagon.fill").font(.system(size: 30)).foregroundStyle(Color.red.opacity(0.85))
                VStack(alignment: .leading, spacing: 7) {
                    Text(store.isTerminating ? "正在处理退出请求…" : "强制退出“\(request.name)”？")
                        .font(.system(size: 21, weight: .semibold)).lineLimit(2)
                    Text("\(request.isGroup ? "程序组" : "单个进程") · 已固定 \(request.processes.count) 个确认目标")
                        .font(.system(size: 12)).foregroundStyle(MemoryStyle.secondary)
                }
            }
            Text("强制退出可能导致未保存的内容丢失。确认后将处理下列目标；之后新产生的进程不会自动加入。")
                .font(.system(size: 12)).foregroundStyle(MemoryStyle.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(request.processes.sorted { $0.pid < $1.pid }) { process in
                        confirmationRow(process)
                        Divider().opacity(0.45)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MemoryStyle.border))
            if protectedCount > 0 {
                Label("\(eligibleCount) 个进程可尝试退出；\(protectedCount) 个受保护或身份不完整的进程将跳过。", systemImage: "lock.fill")
                    .font(.system(size: 11)).foregroundStyle(MemoryStyle.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("部分后台服务可能被 macOS 或所属应用自动重新启动。")
                .font(.system(size: 11)).foregroundStyle(MemoryStyle.secondary)
            Divider().opacity(0.5)
            HStack(spacing: 12) {
                if store.isTerminating {
                    ProgressView().controlSize(.small)
                    Text("正在核对进程身份与退出结果…").font(.system(size: 12)).foregroundStyle(MemoryStyle.secondary)
                    Spacer()
                } else {
                    Spacer()
                    Button("取消", action: onClose)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.bordered)
                    Button("强制退出", role: .destructive) { store.performTermination(request) }
                        .buttonStyle(.borderedProminent).tint(.red)
                        .disabled(eligibleCount == 0 || store.isTerminating)
                }
            }.frame(height: 30)
        }
    }

    private func confirmationRow(_ process: ProcessMemory) -> some View {
        let reason = ProcessTerminator.blockedReason(for: process)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: reason == nil ? "app.dashed" : "lock.fill")
                .font(.system(size: 13)).foregroundStyle(reason == nil ? MemoryStyle.blue : MemoryStyle.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 5) {
                Text(process.name).font(.system(size: 12, weight: .medium)).lineLimit(2)
                if let reason {
                    Text("将跳过：\(reason)").font(.system(size: 10)).foregroundStyle(MemoryStyle.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text("PID \(process.pid)").font(.system(size: 11, design: .monospaced)).foregroundStyle(MemoryStyle.secondary)
        }.padding(12)
    }

    private func resultContent(_ report: TerminationReport) -> some View {
        Group {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.clipboard").font(.system(size: 28)).foregroundStyle(MemoryStyle.blue)
                VStack(alignment: .leading, spacing: 6) {
                    Text("退出结果").font(.system(size: 22, weight: .semibold))
                    Text(report.name).font(.system(size: 13)).foregroundStyle(MemoryStyle.secondary).lineLimit(1)
                }
            }
            Text(report.message).font(.system(size: 12)).foregroundStyle(MemoryStyle.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(report.results) { result in
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: resultSymbol(result.outcome)).foregroundStyle(resultColor(result.outcome)).frame(width: 18)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(result.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text("PID \(result.pid)").font(.system(size: 10, design: .monospaced)).foregroundStyle(MemoryStyle.secondary)
                                }
                                Text(result.message).font(.system(size: 10)).foregroundStyle(MemoryStyle.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Text(resultLabel(result.outcome)).font(.system(size: 10, weight: .medium)).foregroundStyle(resultColor(result.outcome))
                        }.padding(12)
                        Divider().opacity(0.45)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MemoryStyle.border))
            Text("已请求刷新列表。后台服务可能自动重新启动；“未确认退出”表示在本次检查结束时仍未确认退出。")
                .font(.system(size: 11)).foregroundStyle(MemoryStyle.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            Divider().opacity(0.5)
            HStack {
                Spacer()
                Button("完成", action: onClose).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }.frame(height: 30)
        }
    }

    private func resultLabel(_ outcome: TerminationOutcome) -> String {
        switch outcome {
        case .terminated: "已确认终止"
        case .alreadyExited: "原进程已退出"
        case .identityChanged: "身份已变化"
        case .permissionDenied: "无权限"
        case .protected: "已跳过"
        case .failed: "需检查"
        case .stillRunning: "未确认退出"
        }
    }
    private func resultSymbol(_ outcome: TerminationOutcome) -> String {
        switch outcome {
        case .terminated, .alreadyExited: "checkmark.circle.fill"
        case .protected, .permissionDenied: "lock.fill"
        case .identityChanged, .failed, .stillRunning: "exclamationmark.circle.fill"
        }
    }
    private func resultColor(_ outcome: TerminationOutcome) -> Color {
        switch outcome {
        case .terminated, .alreadyExited: .green
        case .protected, .permissionDenied: MemoryStyle.secondary
        case .identityChanged, .failed, .stillRunning: .orange
        }
    }
}
