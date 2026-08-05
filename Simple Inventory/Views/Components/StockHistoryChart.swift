//
//  StockHistoryChart.swift
//  Simple Inventory
//

import SwiftUI
import Charts

/// Step chart of stock level over time, computed from the QuantityRecord
/// ledger, with dashed rules marking the low and critical limits.
struct StockHistoryChart: View {
    let records: [QuantityRecord]
    let yellowLimit: Int
    let redLimit: Int

    private struct LevelPoint: Identifiable {
        let id: Int
        let date: Date
        let level: Int
    }

    private var series: [LevelPoint] {
        var running = 0
        var points: [LevelPoint] = []
        for (index, record) in records.sorted(by: { $0.date < $1.date }).enumerated() {
            running += record.amount
            points.append(LevelPoint(id: index, date: record.date, level: max(0, running)))
        }
        // Extend the last level to now so the line reaches the trailing edge.
        if let last = points.last, last.date < Date() {
            points.append(LevelPoint(id: points.count, date: Date(), level: last.level))
        }
        return points
    }

    var body: some View {
        Chart {
            ForEach(series) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Stock", point.level)
                )
                .interpolationMethod(.stepEnd)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Stock", point.level)
                )
                .interpolationMethod(.stepEnd)
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }

            RuleMark(y: .value("Low", yellowLimit))
                .foregroundStyle(.orange.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            RuleMark(y: .value("Critical", redLimit))
                .foregroundStyle(.red.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .chartYScale(domain: 0...Double(max(series.map(\.level).max() ?? 1, yellowLimit + 1)))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3))
        }
        .frame(height: 140)
    }
}
