import SwiftUI

/// Energiamäärä ja makrojen osuus siitä, samassa muodossa kuin webin reseptikortissa:
/// iso kcal-luku, sen alla energiajakauma palkkina ja selite grammoina.
///
/// Palkki jakautuu **energian** eikä grammojen mukaan (P ja H 4 kcal/g, R 9 kcal/g).
/// Grammoista piirretty palkki aliarvioisi rasvan osuuden yli puolella, mikä on juuri
/// se luku jota katsotaan kun mietitään mistä reseptin energia tulee.
///
/// Värit ovat samat kuin Ravinto-välilehden päiväkoosteessa (sininen, vihreä,
/// violetti). Sama makro samalla värillä joka näkymässä — eri sävy samasta asiasta
/// olisi virhe, ei vaihtelua.
struct MacroEnergySplit: View {
    let macros: RecipeMacros
    /// Selite kcal-luvun perässä, esim. "kcal / annos".
    var caption: String

    private var proteinEnergy: Double { macros.proteinG * 4 }
    private var carbEnergy: Double { macros.carbsG * 4 }
    private var fatEnergy: Double { macros.fatG * 9 }
    private var totalEnergy: Double { max(proteinEnergy + carbEnergy + fatEnergy, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(macros.kcal.rounded()))")
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                Text(caption)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                HStack(spacing: 2) {
                    segment(proteinEnergy, in: geometry.size.width, color: .blue)
                    segment(carbEnergy, in: geometry.size.width, color: .green)
                    segment(fatEnergy, in: geometry.size.width, color: .purple)
                }
            }
            .frame(height: 8)

            HStack(spacing: 16) {
                legend("P", grams: macros.proteinG, color: .blue)
                legend("H", grams: macros.carbsG, color: .green)
                legend("R", grams: macros.fatG, color: .purple)
            }
        }
        .padding(.vertical, 4)
        // Palkki ja pallot eivät kerro ruudunlukijalle mitään, ja väri ei saa olla
        // ainoa tiedon kantaja.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(Int(macros.kcal.rounded())) \(caption), proteiinia \(Int(macros.proteinG.rounded())) grammaa, "
            + "hiilihydraatteja \(Int(macros.carbsG.rounded())) grammaa, rasvaa \(Int(macros.fatG.rounded())) grammaa"
        )
    }

    private func segment(_ energy: Double, in width: CGFloat, color: Color) -> some View {
        // Vähintään kapea kaistale: nollaosuus katoaisi kokonaan, ja katoava palkki
        // näyttää piirtovirheeltä eikä nollalta.
        let share = max(0.02, energy / totalEnergy)
        return Capsule()
            .fill(color)
            .frame(width: max(2, width * share))
    }

    private func legend(_ letter: String, grams: Double, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(letter) \(Int(grams.rounded())) g")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
