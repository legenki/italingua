import Charts
import SwiftUI

/// Variant A: a dashboard of native gauges — circular gauges for today's
/// goal, accuracy and the course, linear capacity gauges for lessons.
struct StatsGaugesView: View {
    let data: StatsData

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            GaugeTile(title: "Цель дня", caption: "\(data.todayAnswers) из \(data.dailyGoal) ответов") {
                Gauge(value: Double(min(data.todayAnswers, data.dailyGoal)), in: 0...Double(data.dailyGoal)) {
                    Image(systemName: "target")
                } currentValueLabel: {
                    Text("\(data.todayAnswers)")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(Theme.accent)
            }
            GaugeTile(title: "Точность · 7 дней",
                      caption: data.accuracy7 == nil ? "Пока нет ответов" : "Доля верных ответов") {
                Gauge(value: data.accuracy7 ?? 0) {
                    Text("%")
                } currentValueLabel: {
                    Text(data.accuracy7.map { "\(Int(($0 * 100).rounded()))" } ?? "—")
                } minimumValueLabel: {
                    Text("0")
                } maximumValueLabel: {
                    Text("100")
                }
                .gaugeStyle(.accessoryCircular)
                .tint(Gradient(colors: [Theme.feminine, Theme.warningText, Theme.accent]))
            }
            GaugeTile(title: "Курс A1", caption: "\(data.known) из \(data.totalWords) слов знакомо") {
                Gauge(value: Double(data.known), in: 0...Double(max(data.totalWords, 1))) {
                    Image(systemName: "book")
                } currentValueLabel: {
                    Text(data.totalWords == 0 ? "—" : "\(data.known * 100 / data.totalWords)%")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(Theme.masculine)
            }
            StreakTile(streak: data.streak, due: data.dueToday)
        }

        Card {
            HStack {
                CardLabel(text: "Слова по стадиям")
                Spacer()
                Text("\(data.learned) выучено").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
            }
            // One stacked bar: how the course words spread over the stages.
            Chart(data.stages) { stage in
                BarMark(x: .value("Слова", stage.count), stacking: .normalized)
                    .foregroundStyle(StageStyle.color(stage.id))
            }
            .chartXAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: 26)
            .clipShape(Capsule())
            HStack(spacing: 14) {
                ForEach(data.stages) { stage in
                    HStack(spacing: 5) {
                        Circle().fill(StageStyle.color(stage.id)).frame(width: 8, height: 8)
                        Text(stage.title).foregroundStyle(Theme.secondaryText)
                        Text("\(stage.count)").monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        }

        Card {
            CardLabel(text: "Уроки")
            ForEach(data.lessons) { lesson in
                HStack(spacing: 12) {
                    LessonBadge(number: Int(lesson.label.dropFirst()) ?? 0, progress: lesson.progress, size: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(lesson.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Spacer()
                            Text("\(lesson.progress.known)/\(lesson.progress.total)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Gauge(value: lesson.progress.fraction) { EmptyView() }
                            .gaugeStyle(.linearCapacity)
                            .tint(lesson.progress.state == .done ? Theme.accent : Theme.masculine)
                            .labelsHidden()
                    }
                }
            }
        }

        if !data.mistakes.isEmpty {
            Card {
                CardLabel(text: "Где ошибаюсь")
                let top = data.mistakes.first?.count ?? 1
                ForEach(data.mistakes) { m in
                    HStack(spacing: 12) {
                        Text(m.kind.titleRU).font(.subheadline).frame(width: 120, alignment: .leading)
                        Gauge(value: Double(m.count), in: 0...Double(top)) { EmptyView() }
                            .gaugeStyle(.accessoryLinearCapacity)
                            .tint(Theme.feminine)
                            .labelsHidden()
                        Text("\(m.count)").font(.subheadline.monospacedDigit()).frame(width: 32, alignment: .trailing)
                    }
                }
            }
        }
    }
}

private struct GaugeTile<G: View>: View {
    let title: String
    let caption: String
    @ViewBuilder var gauge: G

    var body: some View {
        VStack(spacing: 10) {
            CardLabel(text: title)
            gauge
                .scaleEffect(1.5)
                .frame(width: 92, height: 92)
            Text(caption)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

private struct StreakTile: View {
    let streak: Int
    let due: Int

    var body: some View {
        VStack(spacing: 10) {
            CardLabel(text: "Серия")
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(streak > 0 ? Theme.newBadge : Theme.separator)
                    .symbolEffect(.bounce, value: streak)
                Text("\(streak)").font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
            }
            .frame(height: 92)
            Text("\(dayWord(streak)) подряд · \(due) к повторению")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// "день", "дня", "дней" for a count.
func dayWord(_ n: Int) -> String {
    let m10 = n % 10, m100 = n % 100
    if m10 == 1 && m100 != 11 { return "день" }
    if (2...4).contains(m10) && !(12...14).contains(m100) { return "дня" }
    return "дней"
}
