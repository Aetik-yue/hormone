// CourseWidget.swift
// iOS 桌面小组件（WidgetKit）。读取 App Group 中由 Flutter 侧写入的
// 「今日课程」数据并展示。需作为独立的 Widget Extension 目标加入工程，
// 详见仓库根目录 WIDGET_SETUP.md。
//
// 注意：此文件位于 native_templates/ios/Runner/Widgets/，请复制到
// ios/Runner/Widgets/ 后再在 Xcode 中把该目录加入 Widget Extension 目标。

import WidgetKit
import SwiftUI

struct CourseItem: Identifiable {
    let id = UUID()
    let name: String
    let time: String
    let location: String
    let color: UInt

    enum CodingKeys: String, CodingKey {
        case name, time, location, color
    }
}

extension CourseItem: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        time = try c.decode(String.self, forKey: .time)
        location = try c.decode(String.self, forKey: .location)
        color = try c.decode(UInt.self, forKey: .color)
    }
}

struct CourseEntry: TimelineEntry {
    let date: Date
    let title: String
    let courses: [CourseItem]
}

struct Provider: TimelineProvider {
    let appGroup = "group.hormone"

    func placeholder(in context: Context) -> CourseEntry {
        CourseEntry(date: Date(), title: "今天", courses: Self.sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (CourseEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CourseEntry>) -> Void) {
        let entry = load()
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    func load() -> CourseEntry {
        let defaults = UserDefaults(suiteName: appGroup)
        let title = defaults?.string(forKey: "widget_title") ?? "今天"
        let raw = defaults?.string(forKey: "courses") ?? "[]"
        return CourseEntry(date: Date(), title: title, courses: parse(raw))
    }

    func parse(_ json: String) -> [CourseItem] {
        guard let data = json.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        if let arr = try? decoder.decode([CourseItem].self, from: data) {
            return Array(arr.prefix(6))
        }
        return []
    }

    static func sample() -> [CourseItem] {
        [CourseItem(name: "高等数学", time: "08:00-08:45", location: "教三 301", color: 0xFF5B8DEF)]
    }
}

struct CourseWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.headline)
                .foregroundColor(.primary)
            if entry.courses.isEmpty {
                Text("今天没有课 🎉")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(entry.courses) { c in
                    HStack(alignment: .top, spacing: 6) {
                        Text(c.time)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 64, alignment: .leading)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(c.name).font(.caption).lineLimit(1)
                            if !c.location.isEmpty {
                                Text(c.location)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .widgetBackground(Color(.systemBackground))
    }
}

extension View {
    func widgetBackground(_ color: Color) -> some View {
        if #available(iOS 17.0, *) {
            return self.containerBackground(color, for: .widget)
        } else {
            return self.background(color)
        }
    }
}

struct CourseWidget: Widget {
    let kind = "CourseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CourseWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("今日课程")
        .description("显示今天有哪些课")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct CourseWidgetBundle: WidgetBundle {
    var body: some Widget {
        CourseWidget()
    }
}
