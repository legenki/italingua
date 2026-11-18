import Charts
import SwiftUI

/// Variant B: charts first — activity and accuracy over two weeks, a donut
/// of word stages, the review forecast and mistakes by type (Swift Charts).
struct StatsChartsView: View {
    let data: StatsData

    var body: some View {
        HStack(spacing: 0) {
            Metric(value: "\(data.streak)", unit: dayWord(data.streak), title: "серия", symbol: "flame.fill",
                   color: Theme.newBadge)
            Divider().frame(height: 40)
            Metric(value: "\(data.todayAnswers)", unit: "из \(data.dailyGoal)", title: "сегодня",
                   symbol: "target", color: Theme.accent)
            Divider().frame(height: 40)
            Metric(value: data.accuracy7?.percent ?? "—", unit: "", title: "точность за 7 дней",
                   symbol: "checkmark.seal.fill", color: Theme.masculine)
            Divider().frame(height: 40)
            Metric(value: "\(data.dueToday)", unit: "", title: "к повторению", symbol: "clock.arrow.circlepath",
                   color: Theme.warningText)
        }
        .padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))

        Card {
            HStack {
                CardLabel(text: "Активность за 2 недели")
                Spacer()
                LegendDot(color: Theme.accent, title: "верно")
                LegendDot(color: Theme.feminine.opacity(0.75), title: "ошибки")
            }
            Chart {
                ForEach(data.days) { day in
                    BarMark(x: .value("День", day.date, unit: .day), y: .value("Ответы", day.correct))
                        .foregroundStyle(Theme.accent)
                        .cornerRadius(3)
                    BarMark(x: .value("День", day.date, unit: .day), y: .value("Ответы", day.wrong))
                        .foregroundStyle(Theme.feminine.opacity(0.75))
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Цель", data.dailyGoal))
                    .foregroundStyle(Theme.secondaryText)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("цель \(data.dailyGoal)").font(.caption2).foregroundStyle(Theme.secondaryText)
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
            CardLabel(text: "Точность по дням")
            let points = data.days.filter { $0.accuracy != nil }
            if points.count < 2 {
                Text("Появится после двух дней занятий.").font(.subheadline).foregroundStyle(Theme.secondaryText)
            } else {
                Chart(points) { day in
                    AreaMark(x: .value("День", day.date, unit: .day), y: .value("Точность", day.accuracy ?? 0))
                        .foregroundStyle(LinearGradient(colors: [Theme.masculine.opacity(0.25), .clear],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("День", day.date, unit: .day), y: .value("Точность", day.accuracy ?? 0))
                        .foregroundStyle(Theme.masculine)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                    PointMark(x: .value("День", day.date, unit: .day), y: .value("Точность", day.accuracy ?? 0))
                        .foregroundStyle(Theme.masculine)
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
                CardLabel(text: "Ошибки по типам")
                Chart(data.mistakes) { m in
                    BarMark(x: .value("Ошибки", m.count), y: .value("Тип", m.kind.titleRU))
                        .foregroundStyle(Theme.feminine.gradient)
                        .cornerRadius(4)
                        .annotation(position: .trailing) {
                            Text("\(m.count)").font(.caption.monospacedDigit()).foregroundStyle(Theme.secondaryText)
                        }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(data.mistakes.count) * 30 + 10)
            }
        }

        Card {
            CardLabel(text: "Уроки: знакомые слова")
            Chart(data.lessons) { lesson in
                BarMark(x: .value("Урок", lesson.label), y: .value("Знакомо", lesson.progress.fraction))
                    .foregroundStyle(lesson.progress.state == .done ? Theme.accent : Theme.masculine)
                    .cornerRadius(3)
            }
            .chartYScale(domain: 0...1)
            .chartYAxis {
                AxisMarks(values: [0, 0.5, 1]) { value in
                    AxisGridLine()
                    AxisValueLabel { Text((value.as(Double.self) ?? 0).percent) }
                }
            }
            .frame(height: 150)
            Text("В — вводный курс, У — основной.").font(.caption).foregroundStyle(Theme.secondaryText)
        }
    }

    private var stagesCard: some View {
        Card {
            CardLabel(text: "Слова курса")
            Chart(data.stages) { stage in
                SectorMark(angle: .value("Слова", stage.count), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .foregroundStyle(StageStyle.color(stage.id))
                    .cornerRadius(3)
            }
            .chartBackground { _ in
                VStack(spacing: 0) {
                    Text("\(data.known)").font(.title.weight(.bold).monospacedDigit())
                    Text("из \(data.totalWords)").font(.caption).foregroundStyle(Theme.secondaryText)
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
                    .font(.caption)
                }
            }
        }
        .frame(minWidth: 260)
    }

    private var forecastCard: some View {
        Card {
            CardLabel(text: "Повторения на неделю")
            Chart(data.forecast) { day in
                BarMark(x: .value("День", day.date, unit: .day), y: .value("Слова", day.count))
                    .foregroundStyle(day.id == data.forecast.first?.id ? Theme.warningText : Theme.warningText.opacity(0.45))
                    .cornerRadius(4)
                    .annotation(position: .top) {
                        if day.count > 0 {
                            Text("\(day.count)").font(.caption2.monospacedDigit()).foregroundStyle(Theme.secondaryText)
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
            Text("Сегодня — с учётом просроченных.").font(.caption).foregroundStyle(Theme.secondaryText)
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
                Text(value).font(.title2.weight(.bold).monospacedDigit())
                if !unit.isEmpty {
                    Text(unit).font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            Text(title).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LegendDot: View {
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.caption).foregroundStyle(Theme.secondaryText)
        }
    }
}
