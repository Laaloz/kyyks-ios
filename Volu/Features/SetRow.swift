import SwiftUI

/// Yksi sarjarivi treeninäkymässä: vasen puoli kuittaa, oikean puolen
/// lukema avaa toistojen ja kuorman muokkauksen.
struct SetRow: View {
    let log: WorkoutSetLog
    let onToggle: () -> Void
    let onEdit: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Saavutettavuuskooissa rivi taittuu pystyyn, ettei kirjauschip
        // ahtaudu tekstin päälle.
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                toggleArea
                editChip
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: log.done)
        } else {
            HStack(spacing: 12) {
                toggleArea
                editChip
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: log.done)
        }
    }

    // Kuittaus ja muokkaus ovat erilliset kosketusalueet: vasen puoli
    // kuittaa, oikean puolen lukema avaa toistojen/kuorman muokkauksen.
    private var toggleArea: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: log.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(log.done ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))

                VStack(alignment: .leading, spacing: 2) {
                    Text(log.setLabel)
                        .font(.subheadline.weight(.medium))
                    Text(targetText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sarja \(log.setLabel), tavoite \(targetText)")
        .accessibilityValue(log.done ? "Kuitattu" : "Kuittaamatta")
        .accessibilityHint(log.done ? "Poista kuittaus kaksoisnapauttamalla" : "Kuittaa sarja kaksoisnapauttamalla")
    }

    private var editChip: some View {
        Button(action: onEdit) {
            Group {
                if let reps = log.actualReps {
                    Text("\(Int(reps)) × \(formatLoad(log.actualLoad))")
                        .foregroundStyle(log.done ? Color.primary : Color.secondary)
                } else {
                    Text("Kirjaa")
                        .foregroundStyle(.tint)
                }
            }
            .font(.subheadline)
            .monospacedDigit()
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            log.actualReps.map { "Toteuma \(Int($0)) toistoa, \(formatLoad(log.actualLoad))" }
                ?? "Kirjaa toistot ja kuorma"
        )
        .accessibilityHint("Avaa toistojen ja kuorman muokkauksen")
    }

    private var targetText: String {
        var parts = ["\(log.targetRepsLabel) toistoa"]
        if let load = log.targetLoad, load > 0 {
            parts.append("\(formatLoad(load))")
        }
        return parts.joined(separator: " · ")
    }

    private func formatLoad(_ load: Double?) -> String {
        guard let load, load > 0 else { return "—" }
        let text = load.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(load))
            : String(format: "%.1f", load).replacingOccurrences(of: ".", with: ",")
        return "\(text) kg"
    }
}
