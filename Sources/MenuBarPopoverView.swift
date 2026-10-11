import AppKit
import SwiftUI

/// Selection and formatting are kept independent of the popover lifecycle.
enum MenuBarMemoryPresentation {
    static func topApplications(in snapshot: MemorySnapshot?, limit: Int = 10) -> [AppMemory] {
        guard let snapshot, limit > 0 else { return [] }
        return Array(snapshot.groups.filter { $0.isApplication && $0.bytes > 0 }
            .sorted {
                if $0.bytes != $1.bytes { return $0.bytes > $1.bytes }
                return $0.id < $1.id
            }.prefix(min(10, limit)))
    }

    static func percentage(_ bytes: UInt64, total: UInt64) -> Double {
        total > 0 ? Double(bytes) / Double(total) * 100 : 0
    }

    static func amount(_ bytes: UInt64) -> String {
        if bytes >= 1_073_741_824 { return String(format: "%.1f GB", Double(bytes) / 1_073_741_824) }
        return String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }

    static func groupPercentage(_ group: AppMemory, total: UInt64) -> String {
        let partial = group.processes.contains { $0.metric == "unavailable" }
        return (partial ? "≥" : "") + String(format: "%.1f%%", percentage(group.bytes, total: total))
    }

    static func pressureName(_ pressure: String?) -> String {
        switch pressure {
        case "normal": "压力正常"
        case "warning": "压力偏高"
        case "critical": "压力紧张"
        default: "压力未知"
        }
    }

    static func samplingState(snapshotDate: Date?, isPaused: Bool, errorMessage: String?,
                              refreshInterval: TimeInterval, now: Date) -> String {
        if isPaused { return "已暂停 · 上次读数" }
        if errorMessage != nil { return "采样异常 · 上次读数" }
        guard let snapshotDate else { return "正在读取" }
        if now.timeIntervalSince(snapshotDate) > max(15, refreshInterval * 3) { return "数据已过期" }
        return "实时更新"
    }
}

/// Owned by the status item, so closing the transient popover cannot lose an
/// in-flight operation or associate another window's result with this request.
@MainActor
final class PopoverTerminationState: ObservableObject {
    @Published private(set) var request: TerminationRequest?
    @Published private(set) var hasSubmitted = false
    @Published private(set) var report: TerminationReport?

    @discardableResult
    func begin(_ request: TerminationRequest, isBusy: Bool) -> Bool {
        guard self.request == nil, !isBusy,
              request.processes.contains(where: { ProcessTerminator.blockedReason(for: $0) == nil }) else { return false }
        self.request = request
        hasSubmitted = false
        report = nil
        return true
    }

    /// Returns the frozen targets only once; the store independently serializes
    /// execution across the popover and the full dashboard.
    func submit(isBusy: Bool) -> TerminationRequest? {
        guard let request, !hasSubmitted, !isBusy else { return nil }
        hasSubmitted = true
        return request
    }

    func receive(_ report: TerminationReport?) {
        guard hasSubmitted, self.report == nil, let request, let report,
              report.requestID == request.id else { return }
        self.report = report
    }

    func dismiss() {
        guard !hasSubmitted || report != nil else { return }
        request = nil
        hasSubmitted = false
        report = nil
    }

    func popoverDidClose() {
        if !hasSubmitted { dismiss() }
    }
}

enum PopoverTerminationPresentation {
    static func blockedReason(for group: AppMemory) -> String? {
        if group.processes.isEmpty { return "没有可确认的进程。" }
        let reasons = group.processes.compactMap { ProcessTerminator.blockedReason(for: $0) }
        guard reasons.count == group.processes.count else { return nil }
        return Array(Set(reasons)).sorted().joined(separator: "\n")
    }

    static func resultLabel(_ outcome: TerminationOutcome) -> String {
        switch outcome {
        case .terminated: "已确认退出"
        case .alreadyExited: "原进程已退出"
        case .identityChanged: "身份已变化"
        case .permissionDenied: "没有权限"
        case .protected: "已保护"
        case .failed: "需检查"
        case .stillRunning: "未确认退出"
        }
    }
}

private struct PopoverGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct MenuBarPopoverView: View {
    @ObservedObject var store: MemoryStore
    @ObservedObject var loginItem: LoginItemManager
    @ObservedObject var termination: PopoverTerminationState
    let height: CGFloat
    let openDashboard: () -> Void
    let quit: () -> Void

    private var applications: [AppMemory] { MenuBarMemoryPresentation.topApplications(in: store.snapshot) }
    private var pressureColor: Color {
        switch store.snapshot?.pressure {
        case "normal": .green
        case "warning": .orange
        case "critical": .red
        default: .secondary
        }
    }

    var body: some View {
        Group {
            if let request = termination.request {
                terminationContent(request)
            } else {
                VStack(spacing: 0) {
                    summary.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 17)
                    Divider().padding(.horizontal, 20)
                    applicationList
                    Divider()
                    controls
                }
            }
        }
        .frame(width: 384, height: height)
        .background(PopoverGlass())
        .tint(.accentColor)
        .onAppear { loginItem.refreshStatus() }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("Memory Glass", systemImage: "memorychip")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(MenuBarMemoryPresentation.samplingState(snapshotDate: store.snapshot?.timestamp,
                         isPaused: store.isPaused, errorMessage: store.errorMessage,
                         refreshInterval: store.refreshInterval, now: context.date))
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(store.snapshot.map { String(format: "%.1f", $0.usedPercent) } ?? "—")
                    .font(.system(size: 39, weight: .light, design: .rounded)).monospacedDigit()
                Text("%").font(.system(size: 21, weight: .light)).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(pressureColor).frame(width: 6, height: 6)
                    Text(MenuBarMemoryPresentation.pressureName(store.snapshot?.pressure))
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(pressureColor.opacity(0.09), in: Capsule())
            }
            VStack(alignment: .leading, spacing: 7) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.07))
                        Capsule().fill(LinearGradient(colors: [.accentColor, .cyan], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geometry.size.width * min(1, max(0, (store.snapshot?.usedPercent ?? 0) / 100)))
                    }
                }.frame(height: 5)
                HStack {
                    Text(store.snapshot.map { "已用 \(MenuBarMemoryPresentation.amount($0.usedBytes))" } ?? "正在读取内存")
                    Spacer()
                    Text(store.snapshot.map { "共 \(MenuBarMemoryPresentation.amount($0.totalBytes))" } ?? "")
                }.font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2).help(error)
            }
        }
    }

    private var applicationList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("内存占用前 10").font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("应用 · 占物理内存").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 7)
            ScrollView {
                if applications.isEmpty {
                    VStack(spacing: 9) {
                        Image(systemName: "square.stack.3d.up").font(.system(size: 25, weight: .light))
                        Text(store.snapshot == nil ? "正在读取运行中的应用…" : "暂无可读取的应用内存数据")
                            .font(.system(size: 12))
                    }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 45)
                } else {
                    LazyVStack(spacing: 1) {
                        ForEach(applications) { group in applicationRow(group) }
                    }.padding(.horizontal, 12)
                }
            }.scrollIndicators(.hidden)
            if applications.contains(where: { $0.processes.contains { $0.metric == "unavailable" || $0.metric == "rss" } }) {
                Text(measurementNote)
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
                    .padding(.horizontal, 20).padding(.top, 5)
            }
        }.padding(.bottom, 12)
    }

    private var measurementNote: String {
        let processes = applications.flatMap(\.processes)
        let hasRSS = processes.contains { $0.metric == "rss" }
        let hasPartial = processes.contains { $0.metric == "unavailable" }
        return [hasRSS ? "含 RSS 估算" : nil,
                hasPartial ? "≥ 表示部分进程不可读" : nil].compactMap { $0 }.joined(separator: "；")
    }

    private func applicationRow(_ group: AppMemory) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 9) {
                if let path = group.bundlePath {
                    Image(nsImage: AppIconCache.shared.icon(for: path)).resizable().frame(width: 27, height: 27)
                } else {
                    Image(systemName: "app.fill").font(.system(size: 24)).foregroundStyle(.secondary)
                        .frame(width: 27, height: 27)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text(MenuBarMemoryPresentation.amount(group.bytes))
                        .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: 2)
                Text(MenuBarMemoryPresentation.groupPercentage(group, total: store.snapshot?.totalBytes ?? 0))
                    .font(.system(size: 12, weight: .medium)).monospacedDigit().frame(width: 52, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .help(rowDetail(group))
            forceQuitButton(group)
        }
        .padding(.horizontal, 8).frame(height: 42)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    private func forceQuitButton(_ group: AppMemory) -> some View {
        let blocked = PopoverTerminationPresentation.blockedReason(for: group)
        let tooltip = store.isTerminating ? "正在处理退出请求，请稍候。" :
            (blocked ?? "强制退出“\(group.name)”；点击后确认所选进程。")
        return Button {
            let request = TerminationRequest(name: group.name, processes: group.processes, isGroup: true)
            if termination.begin(request, isBusy: store.isTerminating) { store.prepareTermination() }
        } label: {
            Image(systemName: blocked == nil ? "xmark.circle" : "lock.fill")
                .font(.system(size: blocked == nil ? 15 : 12))
                .foregroundStyle(blocked != nil || store.isTerminating ? Color.secondary.opacity(0.45) : Color.red.opacity(0.8))
                .frame(width: 24, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(blocked != nil || store.isTerminating)
        .help(tooltip)
        .accessibilityLabel(blocked == nil ? "强制退出\(group.name)" : "\(group.name)，无法强制退出")
        .accessibilityHint(tooltip)
    }

    private func terminationContent(_ request: TerminationRequest) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            if let report = termination.report {
                terminationResult(report)
            } else {
                terminationConfirmation(request)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand { termination.dismiss() }
    }

    @ViewBuilder
    private func terminationConfirmation(_ request: TerminationRequest) -> some View {
        let protectedCount = request.processes.filter { ProcessTerminator.blockedReason(for: $0) != nil }.count
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "xmark.octagon.fill").font(.system(size: 28)).foregroundStyle(.red.opacity(0.85))
            VStack(alignment: .leading, spacing: 5) {
                Text(termination.hasSubmitted ? "正在强制退出…" : "确认强制退出？")
                    .font(.system(size: 19, weight: .semibold))
                Text(request.name).font(.system(size: 13, weight: .medium)).lineLimit(2)
                Text("已选定 \(request.processes.count) 个进程")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        Text("未保存的内容可能丢失。只会处理下列已选定的进程，之后新启动的进程不会加入。")
            .font(.system(size: 12)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(request.processes.sorted { $0.pid < $1.pid }) { process in
                    let reason = ProcessTerminator.blockedReason(for: process)
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: reason == nil ? "app.dashed" : "lock.fill")
                            .foregroundStyle(.secondary).frame(width: 16)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(process.name).font(.system(size: 12, weight: .medium)).lineLimit(2)
                            if let reason {
                                Text("将跳过：\(reason)").font(.system(size: 10)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 4)
                        Text("PID \(process.pid)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }.padding(11)
                    Divider().opacity(0.45)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
        if protectedCount > 0 {
            Label("\(protectedCount) 个受保护或身份不完整的进程将跳过。", systemImage: "lock.fill")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Divider()
        if termination.hasSubmitted {
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text("正在核对进程身份与退出结果…").font(.system(size: 11)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        } else {
            HStack(spacing: 10) {
                Button("取消") { termination.dismiss() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.bordered)
                Spacer()
                Button("强制退出", role: .destructive) {
                    if let frozenRequest = termination.submit(isBusy: store.isTerminating) {
                        store.performTermination(frozenRequest)
                    }
                }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(store.isTerminating || protectedCount == request.processes.count)
            }.controlSize(.regular).frame(height: 30)
            if store.isTerminating {
                Text("另一个退出请求正在处理中，请稍候。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func terminationResult(_ report: TerminationReport) -> some View {
        let hasIssue = report.results.contains { $0.outcome != .terminated && $0.outcome != .alreadyExited }
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: hasIssue ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 28)).foregroundStyle(hasIssue ? Color.orange : .green)
            VStack(alignment: .leading, spacing: 5) {
                Text(report.title).font(.system(size: 19, weight: .semibold))
                Text(report.name).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        Text(report.message).font(.system(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(report.results) { result in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(result.name).font(.system(size: 12, weight: .medium)).lineLimit(2)
                            Spacer(minLength: 2)
                            Text("PID \(result.pid)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Text(PopoverTerminationPresentation.resultLabel(result.outcome))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(result.outcome == .terminated || result.outcome == .alreadyExited ? Color.green : .orange)
                        Text(result.message).font(.system(size: 10)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }.padding(11)
                    Divider().opacity(0.45)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
        Text("列表正在刷新；后台服务可能自动重新启动。")
            .font(.system(size: 10)).foregroundStyle(.secondary)
        Divider()
        HStack {
            Spacer()
            Button("返回应用列表") { termination.dismiss() }
                .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
        }.frame(height: 30)
    }

    private func rowDetail(_ group: AppMemory) -> String {
        var detail = "\(group.name) · \(group.processes.count) 个进程"
        if group.processes.contains(where: { $0.metric == "rss" }) { detail += " · 含 RSS 估算" }
        if group.processes.contains(where: { $0.metric == "unavailable" }) { detail += " · 部分内存不可读，占比为下限" }
        return detail
    }

    private var controls: some View {
        VStack(spacing: 11) {
            HStack {
                Label("登录时启动", systemImage: "power")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Toggle("登录时启动", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    .disabled(!loginItem.canEnable)
            }
            if let message = loginItem.statusMessage {
                Text(message).font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).lineLimit(3).help(message)
            }
            if loginItem.requiresApproval {
                Button("在系统设置中允许") { loginItem.openSystemSettings() }
                    .buttonStyle(.link).font(.system(size: 10))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 9) {
                Button(action: openDashboard) {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.inset.filled")
                        Text("打开完整面板")
                    }.frame(maxWidth: .infinity).frame(height: 28)
                }.buttonStyle(.borderedProminent).controlSize(.small)
                Button { store.isPaused.toggle() } label: {
                    Image(systemName: store.isPaused ? "play.fill" : "pause.fill")
                        .frame(width: 24, height: 28)
                }.buttonStyle(.bordered).controlSize(.small)
                    .help(store.isPaused ? "继续实时采样" : "暂停实时采样")
                    .accessibilityLabel(store.isPaused ? "继续实时采样" : "暂停实时采样")
                Button(action: quit) {
                    Image(systemName: "power").frame(width: 24, height: 28)
                }.buttonStyle(.bordered).controlSize(.small)
                    .help("退出 Memory Glass").accessibilityLabel("退出 Memory Glass")
            }
        }.padding(.horizontal, 20).padding(.vertical, 13)
    }
}
