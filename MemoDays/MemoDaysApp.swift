//  MemoDaysApp.swift
//  MemoDays
//
//  Created by EricJiang1329145

import SwiftUI
import SwiftData
import Combine

@main
struct MemoDaysApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem {
                        Label("所有事件", systemImage: "list.bullet")
                    }
                
                TaggedEventsView()
                    .tabItem {
                        Label("可查看事件", systemImage: "eye")
                    }
                
                SettingsView() // 新增设置页
                    .tabItem {
                        Label("设置", systemImage: "gearshape")
                    }
            }
            .modelContainer(for: Event.self)
            .environmentObject(MidnightRefreshManager())
            .environment(EventViewModel())
        }
    }
}

// MARK: - 定时器管理类

class MidnightRefreshManager: ObservableObject{
    @Published var refreshTrigger = false
    private var timer: Timer?
    
    func scheduleMidnightRefresh() {
        let now = Date()
        guard let nextMidnight = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(hour: 0),
            matchingPolicy: .nextTime
        ) else { return }
        
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: nextMidnight.timeIntervalSince(now),
            repeats: false
        ) { [weak self] _ in
            self?.refreshTrigger.toggle()
            self?.scheduleMidnightRefresh()
        }
    }
}

// MARK: - Data Models
extension Color {
    static let mikuGreen = Color(red: 57/255.0, green: 197/255.0, blue: 187/255.0)
}

enum EventCategory: String, CaseIterable {
    case general = "常规"
    case work = "工作"
    case personal = "个人"
    case birthday = "生日"
    
    var color: Color {
        switch self {
        case .general: return .blue
        case .work: return .orange
        case .personal: return .green
        case .birthday: return .mikuGreen
        }
    }
}

@Model
final class Event {
    var title: String
    var startDate: Date
    var targetDate: Date
    var category: String
    var isRecurring: Bool
    var isPinned: Bool
    var notes: String
    var tag: String
    
    @Transient private var cachedDaysRemaining: Int?
    @Transient private var cachedNextTargetDate: Date?
    
    init(
        title: String,
        startDate: Date,
        targetDate: Date,
        category: EventCategory = .general,
        isPinned: Bool = false,
        notes: String = "",
        tag: String = "事件"
    ) {
        self.title = title
        self.startDate = startDate
        self.targetDate = targetDate
        self.category = category.rawValue
        self.isRecurring = (category == .birthday)
        self.isPinned = isPinned
        self.notes = notes
        self.tag = tag
    }
    
    var nextTargetDate: Date {
        if let cached = cachedNextTargetDate { return cached }
        let value: Date = {
            guard isRecurring else { return targetDate }
            let calendar = Calendar.current
            let components = calendar.dateComponents([.month, .day], from: startDate)
            return calendar.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) ?? startDate
        }()
        cachedNextTargetDate = value
        return value
    }
    
    var daysRemaining: Int {
        if let cached = cachedDaysRemaining { return cached }
        let value = Calendar.current.daysBetween(Date(), nextTargetDate)
        cachedDaysRemaining = value
        return value
    }
    
    var totalDaysPassed: Int {
        Calendar.current.daysBetween(startDate, Date())
    }
    
    var anniversaryYears: Int {
        Calendar.current.dateComponents([.year], from: startDate, to: Date()).year ?? 0
    }
    
    var anniversaryDays: Int {
        let years = anniversaryYears
        guard years > 0 else { return totalDaysPassed }
        guard let newDate = Calendar.current.date(byAdding: .year, value: years, to: startDate) else {
            return totalDaysPassed
        }
        return Calendar.current.daysBetween(newDate, Date())
    }
    
    var daysDisplay: String {
        switch daysRemaining {
        case 0: return "今天"
        case 1...: return "剩余\(daysRemaining)天"
        default: return "已过\(abs(daysRemaining))天"
        }
    }
    
    var categoryEnum: EventCategory {
        EventCategory(rawValue: category) ?? .general
    }
    
    func resetCache() {
        cachedNextTargetDate = nil
        cachedDaysRemaining = nil
    }
    
    func forceRefresh() {
        resetCache()
        print("\(title) 在 \(Date()) 重置缓存")
    }
}

extension Date {
    func addingYears(_ years: Int) -> Date {
        Calendar.current.date(byAdding: .year, value: years, to: self) ?? self
    }
}

extension Calendar {
    func daysBetween(_ start: Date, _ end: Date) -> Int {
        let adjustedStart = date(bySettingHour: 6, minute: 0, second: 0, of: start)!
        let adjustedEnd = date(bySettingHour: 6, minute: 0, second: 0, of: end)!
        return dateComponents([.day], from: adjustedStart, to: adjustedEnd).day!
    }
}

// MARK: - View Models
@Observable
class EventViewModel {
    private var cancellables = Set<AnyCancellable>()
    
    var searchText = "" {
        didSet { debounceSearch() }
    }
    var selectedCategory: EventCategory?
    var sortByDate = true
    
    init(selectedCategory: EventCategory? = nil) {
        self.selectedCategory = selectedCategory
    }
    
    var availableCategories: [EventCategory] {
        EventCategory.allCases
    }
    
    private func debounceSearch() {
        cancellables.removeAll()
        Just(searchText)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.selectedCategory = self?.selectedCategory
            }
            .store(in: &cancellables)
    }
    
    func filteredEvents(_ events: [Event]) -> [Event] {
        events.filter { event in
            let categoryMatch = selectedCategory == nil || event.categoryEnum == selectedCategory
            let searchMatch = searchText.isEmpty
            || event.title.localizedCaseInsensitiveContains(searchText)
            || event.notes.localizedCaseInsensitiveContains(searchText)
            
            return categoryMatch && searchMatch
        }
        .sorted(by: sortPredicate)
    }
    
    private var sortPredicate: (Event, Event) -> Bool {
        if sortByDate {
            return { $0.isPinned && !$1.isPinned || $0.targetDate < $1.targetDate }
        } else {
            return { $0.isPinned && !$1.isPinned || $0.title.localizedCompare($1.title) == .orderedAscending }
        }
    }
}

// MARK: - Main Views
struct ContentView: View {
    @EnvironmentObject private var refreshManager: MidnightRefreshManager
    @State private var viewModel = EventViewModel(selectedCategory: nil)
    @State private var showingAddView = false
    
    var body: some View {
        NavigationSplitView {
            SidebarView(selectedCategory: $viewModel.selectedCategory)
        } detail: {
            NavigationStack {
                MainContentView(
                    viewModel: viewModel,
                    showingAddView: $showingAddView
                )
            }
        }
        .environment(viewModel)
    }
}

// MARK: - Sidebar Components
struct SidebarView: View {
    @Binding var selectedCategory: EventCategory?
    @Query(sort: \Event.targetDate, order: .forward) private var events: [Event]
    
    var body: some View {
        List(selection: $selectedCategory) {
            CategoryFilterSection(selectedCategory: $selectedCategory)
            GlobalStatisticsSection(events: events)
            SortingSection()
        }
        .background(.clear)
        .scrollContentBackground(.hidden)
        .navigationTitle("分类")
        .listStyle(.sidebar)
    }
}

struct CategoryFilterSection: View {
    @Binding var selectedCategory: EventCategory?
    
    var body: some View {
        Section("分类筛选") {
            NavigationLink(value: Optional<EventCategory>.none) {
                FilterRow(
                    title: "全部事件",
                    icon: "tray.full",
                    isSelected: selectedCategory == nil
                )
            }
            .tag(Optional<EventCategory>.none)
            
            ForEach(EventCategory.allCases, id: \.self) { category in
                NavigationLink(value: category) {
                    FilterRow(
                        title: category.rawValue,
                        icon: iconName(for: category),
                        color: category.color,
                        isSelected: selectedCategory == category
                    )
                }
                .tag(category as EventCategory?)
            }
        }
    }
    
    private func iconName(for category: EventCategory) -> String {
        switch category {
        case .general: return "folder"
        case .work: return "briefcase"
        case .personal: return "person"
        case .birthday: return "gift"
        }
    }
}

struct FilterRow: View {
    let title: String
    let icon: String
    var color: Color = .blue
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(color)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(color)
            }
        }
    }
}

struct GlobalStatisticsSection: View {
    let events: [Event]
    
    var body: some View {
        Section("全局统计") {
            StatisticsRow(title: "总事件数", value: "\(events.count)")
            StatisticsRow(title: "置顶事件", value: "\(events.filter { $0.isPinned }.count)")
        }
    }
}

struct StatisticsRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
    }
}

struct SortingSection: View {
    @Environment(EventViewModel.self) private var viewModel
    
    var body: some View {
        Section("排序方式") {
            Button(action: { viewModel.sortByDate.toggle() }) {
                HStack {
                    Label(
                        viewModel.sortByDate ? "按日期排序" : "按标题排序",
                        systemImage: viewModel.sortByDate ? "calendar" : "textformat"
                    )
                    Spacer()
                    if viewModel.sortByDate {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }
}

// MARK: - Main Content Components
struct MainContentView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var refreshManager: MidnightRefreshManager
    @Bindable var viewModel: EventViewModel
    @Binding var showingAddView: Bool
    init(viewModel: EventViewModel, showingAddView: Binding<Bool>) {
        self.viewModel = viewModel
        self._showingAddView = showingAddView
    }
    @Query(sort: \Event.targetDate, order: .forward) private var events: [Event]
    private var columns = [GridItem(.adaptive(minimum: 300))]
    
    var body: some View {
        Group {
            if viewModel.filteredEvents(events).isEmpty {
                EmptyStateView(selectedCategory: viewModel.selectedCategory)
            } else {
                EventsGridView(events: viewModel.filteredEvents(events))
            }
        }
        .navigationTitle("MemoDays")
        .toolbar { TopToolbar(showingAddView: $showingAddView) }
        .searchable(text: $viewModel.searchText, prompt: "搜索事件")
        .sheet(isPresented: $showingAddView) {
            AddEventView(defaultCategory: viewModel.selectedCategory ?? .general)
                .presentationDetents([.height(900)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(20)
        }
        .refreshHandlers(context: context, refreshManager: refreshManager)
    }
}

struct EventsGridView: View {
    let events: [Event]
    private var columns: [GridItem]
    
    // 添加显式初始化方法
    init(events: [Event]) {
        self.events = events
        self.columns = [GridItem(.adaptive(minimum: 300))]
    }
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(events) { event in
                    EventCardView(event: event)
                        .equatable()
                }
            }
            .padding()
        }
    }
}

struct TopToolbar: ToolbarContent {
    @Binding var showingAddView: Bool
    
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: { showingAddView = true }) {
                Image(systemName: "plus")
            }
        }
    }
}

// MARK: - 辅助视图扩展
private extension View {
    func refreshHandlers(context: ModelContext, refreshManager: MidnightRefreshManager) -> some View {
        self
            .onReceive(refreshManager.$refreshTrigger) { _ in
                if let events = try? context.fetch(FetchDescriptor<Event>()) {
                    events.forEach { $0.forceRefresh() }
                }
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                if let events = try? context.fetch(FetchDescriptor<Event>()) {
                    events.forEach { $0.resetCache() }
                }
            }
    }
}

// MARK: - 卡片视图
struct EventCardView: View, Equatable {
    let event: Event
    @Environment(\.modelContext) private var context
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var currentDate = Date()
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    static func == (lhs: EventCardView, rhs: EventCardView) -> Bool {
        lhs.event.title == rhs.event.title &&
        lhs.event.daysRemaining == rhs.event.daysRemaining &&
        lhs.event.isPinned == rhs.event.isPinned
    }
    
    var body: some View {
        NavigationLink(value: event) {
            VStack(alignment: .leading, spacing: 12) {
                header
                dateInfo
                progress
                footer
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("编辑", systemImage: "pencil") { showingEdit = true }
            Button("删除", systemImage: "trash", role: .destructive) { showingDeleteConfirm = true }
        }
        .sheet(isPresented: $showingEdit) {
            AddEventView(editingEvent: event)
                .presentationDetents([.height(500)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(20)
        }
        .confirmationDialog("删除事件", isPresented: $showingDeleteConfirm) {
            Button("删除", role: .destructive) { context.delete(event) }
            Button("取消", role: .cancel) {}
        }
        .onReceive(timer) { _ in
            currentDate = Date()
        }
    }
    
    private var header: some View {
        HStack {
            Text(event.title)
                .font(.headline)
                .lineLimit(1)
            
            Spacer()
            
            Button(action: togglePin) {
                Image(systemName: event.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(event.isPinned ? .orange : .secondary)
                    .symbolEffect(.bounce, value: event.isPinned)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var dateInfo: some View {
        VStack(alignment: .leading) {
            Text("始于：\(event.startDate, style: .date)")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if event.categoryEnum == .birthday {
                VStack(alignment: .leading, spacing: 4) {
                    Text("下一个周年日：\(event.nextTargetDate, style: .date)")
                    Text("已持续：\(event.anniversaryYears)年\(event.anniversaryDays)天")
                    Text("总天数：\(event.totalDaysPassed)天")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
            
            if event.daysRemaining == 0 {
                Text("今天")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(4)
                    .background(Color.red.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
    }
    
    private var progress: some View {
        ProgressView(value: progressValue)
            .tint(event.categoryEnum.color)
            .scaleEffect(x: 1, y: 2, anchor: .center)
            .clipShape(Capsule())
    }
    
    private var footer: some View {
        HStack {
            Text(event.daysDisplay)
                .foregroundStyle(event.categoryEnum.color)
            
            Spacer()
            
            Text(event.category)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(event.categoryEnum.color.opacity(0.2))
                .clipShape(Capsule())
        }
    }
    
    private var progressValue: Double {
        let totalDays = max(Calendar.current.daysBetween(Date(), event.nextTargetDate), 1)
        return Double(totalDays - event.daysRemaining) / Double(totalDays)
    }
    
    private func togglePin() {
        event.isPinned.toggle()
        event.resetCache()
    }
}

// MARK: - 添加/编辑视图
struct AddEventView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let editingEvent: Event?
    
    @State private var title = ""
    @State private var selectedDate = Date()
    @State private var category: EventCategory
    @State private var notes = ""
    
    init(editingEvent: Event? = nil, defaultCategory: EventCategory = .general) {
        self.editingEvent = editingEvent
        if let event = editingEvent {
            _title = State(initialValue: event.title)
            _selectedDate = State(initialValue: event.startDate)
            _category = State(initialValue: event.categoryEnum)
            _notes = State(initialValue: event.notes)
        } else {
            _category = State(initialValue: defaultCategory)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("事件标题") {
                    TextField("输入标题", text: $title)
                }
                
                Section("事件日期") {
                    DatePicker(
                        "选择日期",
                        selection: $selectedDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                }
                
                Section("分类") {
                    Picker("选择分类", selection: $category) {
                        ForEach(EventCategory.allCases, id: \.self) { category in
                            Text(category.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("备注") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
            .scrollContentBackground(.hidden)
            .background(.ultraThinMaterial)
            .navigationTitle(editingEvent == nil ? "新建事件" : "编辑事件")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel) { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveEvent()
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
        .presentationDetents([editingEvent == nil ? .height(900) : .height(500)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(20)
    }
    
    private func saveEvent() {
        let targetDate: Date
        let startDate = selectedDate
        
        if category == .birthday {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.month, .day], from: startDate)
            targetDate = calendar.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) ?? startDate
        } else {
            targetDate = startDate
        }
        
        if let event = editingEvent {
            event.title = title
            event.startDate = startDate
            event.targetDate = targetDate
            event.category = category.rawValue
            event.notes = notes
            event.isRecurring = (category == .birthday)
            event.resetCache()
        } else {
            let newEvent = Event(
                title: title,
                startDate: startDate,
                targetDate: targetDate,
                category: category,
                notes: notes
            )
            context.insert(newEvent)
        }
        
        do {
            try context.save()
        } catch {
            print("保存失败：\(error)")
        }
    }
}

// MARK: - 详情视图
struct EventDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    let event: Event
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .compact ? 200 : 300))]
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                datesSection
                progressSection
                notesSection
            }
            .padding()
        }
        .navigationTitle("事件详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("编辑", systemImage: "pencil") { showingEdit = true }
                    Button("删除", systemImage: "trash", role: .destructive) { showingDeleteConfirm = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            AddEventView(editingEvent: event)
                .presentationDetents([.height(500)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(20)
        }
        .confirmationDialog("删除事件", isPresented: $showingDeleteConfirm) {
            Button("删除", role: .destructive) {
                context.delete(event)
                dismiss()
            }
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(event.title)
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                
                Spacer()
                
                CategoryBadge(category: event.categoryEnum)
            }
            
            Text("创建于 \(event.startDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var datesSection: some View {
        LazyVGrid(columns: gridColumns, spacing: 16) {
            InfoCard(title: "开始日期", value: event.startDate.formatted(date: .long, time: .omitted))
            InfoCard(title: "目标日期", value: event.targetDate.formatted(date: .long, time: .omitted))
            
            if event.categoryEnum == .birthday {
                InfoCard(title: "下一个周年日", value: event.nextTargetDate.formatted(date: .long, time: .omitted))
                InfoCard(title: "已持续时间", value: "\(event.anniversaryYears)年\(event.anniversaryDays)天")
                InfoCard(title: "总天数", value: "\(event.totalDaysPassed)天")
            }
        }
    }
    
    private var progressSection: some View {
        VStack(spacing: 16) {
            Text(event.daysDisplay)
                .font(.title2.weight(.medium))
                .foregroundStyle(event.categoryEnum.color)
            
            ProgressView(value: progressValue)
                .tint(event.categoryEnum.color)
                .scaleEffect(x: 1, y: 2, anchor: .center)
                .clipShape(Capsule())
            
            HStack {
                Text("已过天数")
                Spacer()
                Text("\(abs(event.totalDaysPassed))")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var notesSection: some View {
        Group {
            if !event.notes.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("备注")
                        .font(.headline)
                    Text(event.notes)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private var progressValue: Double {
        let totalDays = max(Calendar.current.daysBetween(Date(), event.nextTargetDate), 1)
        return Double(totalDays - event.daysRemaining) / Double(totalDays)
    }
}

// MARK: - 辅助组件
struct CategoryBadge: View {
    let category: EventCategory
    
    var body: some View {
        Label(category.rawValue, systemImage: iconName)
            .font(.footnote)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(category.color.opacity(0.2))
            .foregroundStyle(category.color)
            .clipShape(Capsule())
    }
    
    private var iconName: String {
        switch category {
        case .general: return "folder"
        case .work: return "briefcase"
        case .personal: return "person"
        case .birthday: return "gift"
        }
    }
}

struct InfoCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct EmptyStateView: View {
    let selectedCategory: EventCategory?
    
    var body: some View {
        ContentUnavailableView(
            label: {
                Label("无事件", systemImage: "calendar.badge.exclamationmark")
                    .symbolRenderingMode(.multicolor)
            },
            description: {
                Text(selectedCategory == nil
                     ? "当前没有事件，点击+创建新事件"
                     : "当前分类没有事件，尝试切换分类")
            }
        )
    }
}

struct TaggedEventsView: View {
    @Query(filter: #Predicate<Event> { $0.tag == "事件" })
    private var taggedEvents: [Event]
    
    @State private var viewModel = EventViewModel(selectedCategory: nil)
    private var columns = [GridItem(.adaptive(minimum: 300))]
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.filteredEvents(taggedEvents).isEmpty {
                    EmptyStateView(selectedCategory: nil)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(viewModel.filteredEvents(taggedEvents)) { event in
                                EventCardView(event: event)
                                    .equatable()
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("可查看事件")
            .searchable(text: $viewModel.searchText, prompt: "搜索事件")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Event.self)
}
