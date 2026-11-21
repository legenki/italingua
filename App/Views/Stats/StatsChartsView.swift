import Charts
import SwiftUI

/// Variant B: charts first — activity and accuracy over two weeks, a donut
/// of word stages, the review forecast and mistakes by type (Swift Charts).
struct StatsChartsView: View {
    let data: StatsData

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        // iPhone: two rows of two, so no caption is cut; wider: one row.
        Group {
            if metricsInGrid {
                VStack(spacing: 12) {
                    HStack(spacing: 0) { streakMetric; Divider().frame(height: 40); todayMetric }
                    Divider().padding(.horizontal, 16)
                    HStack(spacing: 0) { accuracyMetric; Divider().frame(height: 40); dueMetric }
                }
            } else {
                HStack(spacing: 0) {
                    streakMetric
                    Divider().frame(height: 40)
                    todayMetric
                    Divider().frame(height: 40)
                    accuracyMetric
                    Divider().frame(height: 40)
                    dueMetric
                }
            }
        }
        .padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))

        Card {
            HStack {
                CardLabel(text: String(localized: "Активность за 2 недели"))
                Spacer()
                LegendDot(color: Theme.accent, title: String(localized: "верно"))
                LegendDot(color: Theme.separator, title: String(localized: "ошибки"))
            }
            Chart {
                ForEach(data.days) { day in
                    BarMark(x: .value(String(localized: "День"), day.date, unit: .day), y: .value(String(localized: "Ответы"), day.correct))
                        .foregroundStyle(Theme.accent)
                        .cornerRadius(3)
                    BarMark(x: .value(String(localized: "День"), day.date, unit: .day), y: .value(String(localized: "Ответы"), day.wrong))
                        .foregroundStyle(Theme.separator)
                        .cornerRadius(3)
                }
                RuleMark(y: .value(String(localized: "Цель"), data.dailyGoal))
                    .foregroundStyle(Theme.secondaryText)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text(String(localized: "цель \(data.dailyGoal)")).font(.s(.caption2)).foregroundStyle(Theme.secondaryText)
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                }
            }
            .frame(height: 200)
        }

        Card {
            CardLabel(text: String(localized: "Точность по дням"))
            let points = data.days.filter { $0.accuracy != nil }
            if points.count < 2 {
                Text(String(localized: "Появится после двух дней занятий.")).font(.s(.subheadline)).foregroundStyle(Theme.secondaryText)
            } else {
                Chart(points) { day in
                    AreaMark(x: .value(String(localized: "День"), day.date, unit: .day), y: .value(String(localized: "Точность"), day.accuracy ?? 0))
                        .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.25), .clear],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value(String(localized: "День"), day.date, unit: .day), y: .value(String(localized: "Точность"), day.accuracy ?? 0))
                        .foregroundStyle(Theme.accent)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                    PointMark(x: .value(String(localized: "День"), day.date, unit: .day), y: .value(String(localized: "Точность"), day.accuracy ?? 0))
                        .foregroundStyle(Theme.accent)
                        .symbolSize(24)
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.5, 1]) { value in
                        AxisGridLine()
                        AxisValueLabel { Text((value.as(Double.self) ?? 0).percent) }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                    }
                }
                .frame(height: 140)
            }
        }

        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) { stagesCard; forecastCard }
            VStack(spacing: 16) { stagesCard; forecastCard }
        }

        if !data.mistakes.isEmpty {
            Card {
                CardLabel(text: String(localized: "Ошибки по типам"))
                Chart(data.mistakes) { m in
                    BarMark(x: .value(String(localized: "Ошибки"), m.count), y: .value(String(localized: "Тип"), m.kind.titleRU))
                        .foregroundStyle(Theme.accentMid)
                        .cornerRadius(4)
                        .annotation(position: .trailing) {
                            Text("\(m.count)").font(.s(.caption).monospacedDigit()).foregroundStyle(Theme.secondaryText)
                        }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(data.mistakes.count) * 30 + 10)
            }
        }

        Card {
            CardLabel(text: String(localized: "Уроки: знакомые слова"))
            LessonProgressGrid(lessons: data.lessons)
        }
    }

    private var metricsInGrid: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    private var streakMetric: some View {
        Metric(value: "\(data.streak)", unit: dayWord(data.streak), title: String(localized: "серия"), symbol: "flame.fill",
               color: Theme.accent)
    }

    private var todayMetric: some View {
        Metric(value: "\(data.todayAnswers)", unit: String(localized: "из \(data.dailyGoal)"), title: String(localized: "сегодня"),
               symbol: "target", color: Theme.accent)
    }

    private var accuracyMetric: some View {
        Metric(value: data.accuracy7?.percent ?? "—", unit: "", title: String(localized: "точность за 7 дней"),
               symbol: "checkmark.seal.fill", color: Theme.accent)
    }

    private var dueMetric: some View {
        Metric(value: "\(data.dueToday)", unit: "", title: String(localized: "к повторению"), symbol: "clock.arrow.circlepath",
               color: Theme.accent)
    }

    private var stagesCard: some View {
        Card {
            CardLabel(text: String(localized: "Слова курса"))
            Chart(data.stages) { stage in
                SectorMark(angle: .value(String(localized: "Слова"), stage.count), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .foregroundStyle(StageStyle.color(stage.id))
                    .cornerRadius(3)
            }
            .chartBackground { _ in
                VStack(spacing: 0) {
                    Text("\(data.known)").font(.s(.title).weight(.bold).monospacedDigit())
                    Text(String(localized: "из \(data.totalWords)")).font(.s(.caption)).foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(height: 170)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(data.stages) { stage in
                    HStack(spacing: 6) {
                        Circle().fill(StageStyle.color(stage.id)).frame(width: 8, height: 8)
                        Text(stage.title)
                        Spacer()
                        Text("\(stage.count)").monospacedDigit().foregroundStyle(Theme.secondaryText)
                    }
                    .font(.s(.caption))
                }
            }
        }
        .frame(minWidth: 260)
    }

    private var forecastCard: some View {
        Card {
            CardLabel(text: String(localized: "Повторения на неделю"))
            Chart(data.forecast) { day in
                BarMark(x: .value(String(localized: "День"), day.date, unit: .day), y: .value(String(localized: "Слова"), day.count))
                    .foregroundStyle(day.id == data.forecast.first?.id ? Theme.accent : Theme.accentMid)
                    .cornerRadius(4)
                    .annotation(position: .top) {
                        if day.count > 0 {
                            Text("\(day.count)").font(.s(.caption2).monospacedDigit()).foregroundStyle(Theme.secondaryText)
                        }
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 170)
            Text(String(localized: "Сегодня — с учётом просроченных.")).font(.s(.caption)).foregroundStyle(Theme.secondaryText)
        }
        .frame(minWidth: 260)
    }
}

private struct Metric: View {
    let value: String
    let unit: String
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: symbol).foregroundStyle(color)
                Text(value).font(.s(.title2).weight(.bold).monospacedDigit())
                if !unit.isEmpty {
                    Text(unit).font(.s(.caption)).foregroundStyle(Theme.secondaryText)
                }
            }
            Text(title).font(.s(.caption)).foregroundStyle(Theme.secondaryText)
                .lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Every lesson as a small square, grouped by course section: the number on
/// a fill that darkens with the share of familiar words (one hue, light to
/// dark), a check once the lesson is done. Forty lessons stay readable on a
/// phone, where a bar chart squeezed its labels into a fence.
private struct LessonProgressGrid: View {
    let lessons: [StatsData.LessonRow]

    private static let cell: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title).font(.s(.caption).weight(.semibold)).foregroundStyle(Theme.secondaryText)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cell, maximum: Self.cell + 6), spacing: 6)],
                              alignment: .leading, spacing: 6) {
                        ForEach(section.lessons) { LessonCell(lesson: $0) }
                    }
                }
            }
            legend
        }
    }

    private var sections: [(title: String, lessons: [StatsData.LessonRow])] {
        var result: [(title: String, lessons: [StatsData.LessonRow])] = []
        for lesson in lessons {
            if result.last?.title == lesson.section {
                result[result.count - 1].lessons.append(lesson)
            } else {
                result.append((lesson.section, [lesson]))
            }
        }
        return result
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("0%")
            ForEach(0..<LessonCell.steps.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(LessonCell.steps[i])
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Theme.separator, lineWidth: i == 0 ? 1 : 0))
                    .frame(width: 14, height: 14)
            }
            Text("100%")
            Spacer(minLength: 12)
            Image(systemName: "checkmark").font(.s(.caption2).weight(.bold)).foregroundStyle(Theme.accent)
            Text(String(localized: "пройден"))
        }
        .font(.s(.caption).monospacedDigit())
        .foregroundStyle(Theme.secondaryText)
        .accessibilityHidden(true)
    }
}

private struct LessonCell: View {
    let lesson: StatsData.LessonRow

    /// Not started, then three shades of familiar words; the full accent is "done".
    static var steps: [Color] { [Theme.tile] + Array(Theme.accentRamp.prefix(3)) + [Theme.accent] }

    private var step: Int {
        switch lesson.progress.state {
        case .notStarted: 0
        case .done: 4
        case .inProgress: min(3, 1 + Int(lesson.progress.fraction * 3))
        }
    }

    var body: some View {
        let step = self.step
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Self.steps[step])
            if step == 0 {
                RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.separator, lineWidth: 1)
            }
            if step == 4 {
                Image(systemName: "checkmark").font(.s(.caption).weight(.bold)).foregroundStyle(Theme.onAccent)
            } else {
                Text("\(lesson.number)")
                    .font(.s(.caption).weight(.semibold).monospacedDigit())
                    .foregroundStyle(step >= 3 ? Theme.onAccent : step == 0 ? Theme.secondaryText : .primary)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .help("\(lesson.title) · \(lesson.progress.fraction.percent)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(lesson.section), \(lesson.number): \(lesson.title)")
        .accessibilityValue(lesson.progress.fraction.percent)
    }
}

private struct LegendDot: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.s(.caption)).foregroundStyle(Theme.secondaryText)
        }
    }
}

/// "день", "дня", "дней" for a count.
func dayWord(_ n: Int, language: String = AppLanguage.current) -> String {
    guard language == "ru" else { return n == 1 ? String(localized: "день") : String(localized: "дней") }
    let m10 = n % 10, m100 = n % 100
    if m10 == 1 && m100 != 11 { return String(localized: "день") }
    if (2...4).contains(m10) && !(12...14).contains(m100) { return String(localized: "дня") }
    return String(localized: "дней")
}

/// " подряд" ("in a row", "seguido"/"seguidos" in Spanish).
func inARowWord(_ n: Int, language: String = AppLanguage.current) -> String {
    if language == "es" && n == 1 { return " seguido" }
    return String(localized: " подряд")
}
