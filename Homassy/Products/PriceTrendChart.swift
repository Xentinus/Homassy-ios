import Charts
import HomassyCore
import SwiftUI

/// The product detail's inline price chart (P2-07a): unit price over the last six months across stores, an area
/// under the line and a point on the latest purchase. VoiceOver offers the audio graph.
struct PriceTrendChart: View {
    let trend: PriceTrend
    let model: ProductDetailModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Chart(trend.points) { point in
            AreaMark(x: .value(Text("price.axis.date"), point.date),
                     yStart: .value(Text("price.axis.unitPrice"), trend.yDomain.lowerBound),
                     yEnd: .value(Text("price.axis.unitPrice"), Self.value(point)))
                .foregroundStyle(Palette.accent.opacity(0.15))
                .interpolationMethod(.monotone)
            LineMark(x: .value(Text("price.axis.date"), point.date),
                     y: .value(Text("price.axis.unitPrice"), Self.value(point)))
                .foregroundStyle(Palette.accent)
                .interpolationMethod(.monotone)
            if point.id == trend.points.last?.id {
                PointMark(x: .value(Text("price.axis.date"), point.date),
                          y: .value(Text("price.axis.unitPrice"), Self.value(point)))
                    .foregroundStyle(Palette.accent)
                    .symbolSize(40)
            }
        }
        .chartXScale(domain: trend.window)
        .chartYScale(domain: trend.yDomain)
        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
        .chartPlotStyle { $0.clipped() }
        .frame(height: 86)
        .transaction { if reduceMotion { $0.animation = nil } }
        .accessibilityChartDescriptor(self)
        .accessibilityIdentifier("price.trend.chart")
    }

    fileprivate static func value(_ point: PriceEntry) -> Double { NSDecimalNumber(decimal: point.unitPrice).doubleValue }
}

extension PriceTrendChart: @MainActor AXChartDescriptorRepresentable {
    func makeChartDescriptor() -> AXChartDescriptor {
        let dates = trend.points.map(\.date.timeIntervalSince1970)
        let values = trend.points.map(Self.value)
        let title = String(localized: "product.detail.priceTrend")
        let xAxis = AXNumericDataAxisDescriptor(title: String(localized: "price.axis.date"),
                                                range: trend.window.lowerBound.timeIntervalSince1970...trend.window.upperBound.timeIntervalSince1970,
                                                gridlinePositions: []) {
            Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .omitted)
        }
        let yAxis = AXNumericDataAxisDescriptor(title: String(localized: "price.axis.unitPrice"),
                                                range: trend.yDomain,
                                                gridlinePositions: []) { [trend, model] in
            model.unitPriceText(Decimal($0), currency: trend.currency, unit: trend.unit)
        }
        let series = AXDataSeriesDescriptor(name: title, isContinuous: true,
                                            dataPoints: zip(dates, values).map { AXDataPoint(x: $0, y: $1) })
        return AXChartDescriptor(title: title, summary: nil, xAxis: xAxis, yAxis: yAxis, additionalAxes: [],
                                 series: [series])
    }
}
