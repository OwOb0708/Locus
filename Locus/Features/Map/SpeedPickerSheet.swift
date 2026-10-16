import CoreLocation
import SwiftUI

/// Shared "pick a travel mode, or dial in an exact speed" sheet used by every
/// move-along-a-route action (navigate / multi-stop / GPX / drawn path).
struct SpeedPickerSheet: View {
    var title: String
    @Binding var mode: TravelMode
    @Binding var speedMPS: CLLocationSpeed
    @Binding var isCustom: Bool
    var onConfirm: () -> Void
    var onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let speedRange: ClosedRange<Double> = 0.3...30

    private var speedKmh: Double { speedMPS * 3.6 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(title)
                    .font(.headline)
                    .padding(.top, 4)

                HStack(spacing: 10) {
                    ForEach(TravelMode.allCases) { m in
                        let selected = mode == m && !isCustom
                        Button {
                            mode = m
                            speedMPS = m.baseSpeed
                            isCustom = false
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: m.icon)
                                    .font(.title3.weight(.semibold))
                                Text(m.title)
                                    .font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(selected ? .black : .primary)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(selected ? LocusTheme.accent : Color.primary.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(spacing: 14) {
                    HStack {
                        Text(isCustom ? "自訂速度" : "速度")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(String(format: "%.1f 公里/時", speedKmh))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { speedMPS },
                            set: { newValue in
                                speedMPS = newValue
                                isCustom = true
                            }
                        ),
                        in: speedRange
                    )
                    HStack {
                        Text("輸入精確數值（公里/時）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        TextField(
                            "",
                            value: Binding(
                                get: { speedKmh },
                                set: { newValue in
                                    let clampedMPS = max(speedRange.lowerBound, min(speedRange.upperBound, newValue / 3.6))
                                    speedMPS = clampedMPS
                                    isCustom = true
                                }
                            ),
                            format: .number.precision(.fractionLength(1))
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                        .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(16)
                .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Spacer(minLength: 0)

                Button {
                    dismiss()
                    onConfirm()
                } label: {
                    Text("開始")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(LocusTheme.accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                        onCancel()
                    }
                }
            }
        }
        .presentationDetents([.height(440)])
    }
}
