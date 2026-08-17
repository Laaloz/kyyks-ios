import SwiftUI

/// Yksi sarjarivi treeninäkymässä.
///
/// Järjestys vasemmalta oikealle seuraa tekemisen järjestystä: sarjan numero
/// kertoo missä mennään, sen jälkeen kirjataan lukema, ja kuittaus on
/// viimeisenä oikeassa reunassa. Kuittaus oli aiemmin vasemmalla, jolloin
/// palaute välähti ruudun toisella laidalla kuin mihin käyttäjä juuri koski —
/// ja oikea reuna on myös peukalolle helpoin.
struct SetRow: View {
    let log: WorkoutSetLog
    /// Tavoite rivillä vain kun liikkeen sarjat eroavat toisistaan; muuten se
    /// on liikkeen otsikossa eikä toistu joka rivillä.
    var showsTarget: Bool = true
    /// Edellisen kerran tulos tälle sarjalle. Näkyy myös kirjatulla rivillä:
    /// vertailu on juuri se mitä sarjan jälkeen katsotaan, ja "viimeksi"-etuliite
    /// erottaa sen tämän päivän lukemasta. Samalla se täyttää rivin vasemman
    /// puolen, joka jäi tyhjäksi kun tavoite siirtyi liikkeen otsikkoon.
    var previous: PreviousSet?
    let onToggle: () -> Void
    let onEdit: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Saavutettavuuskooissa rivi taittuu pystyyn, ettei kirjauschip
        // ahtaudu tekstin päälle.
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    setNumber
                    content
                }
                toggleButton
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: log.isLogged)
        } else {
            // Sisältö vasemmalle yhteen ryhmään, kuittaus oikeaan reunaan.
            // Aiemmin lukema oli työnnetty oikeaan laitaan, jolloin numeron ja
            // lukeman väliin jäi koko rivin levyinen tyhjä — vaikka ne ovat
            // saman asian kaksi osaa. Väli kuuluu sisällön ja kontrollin
            // väliin, kuten iOS-listoissa muutenkin.
            HStack(spacing: 12) {
                setNumber
                content
                Spacer(minLength: 8)
                toggleButton
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: log.isLogged)
        }
    }

    /// Sarjan numero omana kapeana sarakkeenaan, jotta lukemat asettuvat
    /// samaan linjaan riveittäin.
    private var setNumber: some View {
        Text(log.setLabel)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .frame(minWidth: 16, alignment: .leading)
            .accessibilityHidden(true)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 1) {
            editChip
            if showsTarget || previous != nil {
                HStack(spacing: 6) {
                    if showsTarget {
                        Text(targetText)
                            .foregroundStyle(.secondary)
                    }
                    if let previousText = previous?.summary {
                        Text("viimeksi \(previousText)")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
                .monospacedDigit()
                .lineLimit(1)
            }
        }
    }

    private var label: some View {
        Text(log.setLabel)
            .accessibilityLabel(labelAccessibilityText)
    }

    private var labelAccessibilityText: String {
        var parts = ["Sarja \(log.setLabel)"]
        if showsTarget { parts.append("tavoite \(targetText)") }
        if let previousText = previous?.summary {
            parts.append("viimeksi \(previousText)")
        }
        return parts.joined(separator: ", ")
    }

    // Kuittaus ja muokkaus ovat erilliset kosketusalueet: lukema avaa
    // muokkauksen, ympyrä kirjaa sarjan tavoitteen mukaisena.
    private var toggleButton: some View {
        Button(action: onToggle) {
            // Kuittaus on korostusvärillä, ei vihreällä. Vihreä on
            // arvosana, ja kun se on lähes joka rivillä, se ei kerro
            // mitään — samalla se veisi huomion siltä värilliseltä
            // merkiltä, joka oikeasti kantaa tiedon (tavoitteen alitus).
            // Väri varataan arvioinnille, muoto kertoo tilan.
            Image(systemName: log.isLogged ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(log.isLogged ? Color.accentColor : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sarja \(log.setLabel)")
        .accessibilityValue(log.isLogged ? "Kirjattu" : "Kirjaamatta")
        .accessibilityHint(log.isLogged ? "Poista kirjaus kaksoisnapauttamalla" : "Kirjaa sarja tavoitteen mukaisena kaksoisnapauttamalla")
    }

    private var editChip: some View {
        Button(action: onEdit) {
            HStack(spacing: 4) {
                if let reps = log.actualReps {
                    // Nuoli ei ole koriste vaan värin pari: väri yksin ei
                    // erotu värisokealle eikä kirkkaassa auringossa, ja
                    // suunta kertoo saman asian ilman väriä.
                    if let mark = outcomeMark {
                        Image(systemName: mark.symbol)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(mark.color)
                    }
                    Text(loggedText(reps: reps))
                        .foregroundStyle(outcomeMark?.color ?? (log.isLogged ? Color.primary : Color.secondary))
                } else {
                    Text("Kirjaa")
                        .foregroundStyle(.tint)
                }
            }
            .font(.body.weight(.medium))
            .monospacedDigit()
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityValueLabel)
        .accessibilityHint("Avaa toistojen ja kuorman muokkauksen")
    }

    /// Merkki vain poikkeukselle: tavoitealueella pysynyt sarja on tavallinen
    /// tapaus eikä ansaitse väriä. Molemmat poikkeamat ovat yhtä toimintaan
    /// ohjaavia — alitus kertoo että kuorma oli liian kova, ylitys että se on
    /// aika nostaa.
    private var outcomeMark: (symbol: String, color: Color)? {
        switch log.outcome {
        case .onTarget: nil
        case .below: ("arrow.down", .orange)
        case .above: ("arrow.up", .green)
        }
    }

    /// Poikkeama sanotaan myös ääneen: väri ja nuoli eivät välity
    /// ruudunlukijalle.
    private var accessibilityValueLabel: String {
        guard let reps = log.actualReps else { return "Kirjaa toistot ja kuorma" }
        var text = "Toteuma \(loggedText(reps: reps))"
        switch log.outcome {
        case .below: text += ", alle tavoitteen \(log.targetRepsLabel)"
        case .above: text += ", yli tavoitteen \(log.targetRepsLabel)"
        case .onTarget: break
        }
        return text
    }

    private var targetText: String {
        var parts = ["\(log.targetRepsLabel) toistoa"]
        if let load = log.targetLoad, load > 0 {
            parts.append("\(formatLoad(load))")
        }
        return parts.joined(separator: " · ")
    }

    /// "9 × 23 kg", tai pelkkä toistomäärä kun kuormaa ei ole. Kehonpaino- ja
    /// laiteliikkeissä ohjelmassa ei aina ole kuormaa, ja "5 × —" näytti
    /// rikkinäiseltä siinä missä "5" on täysi tieto.
    private func loggedText(reps: Double) -> String {
        guard let load = log.actualLoad, load > 0 else { return "\(Int(reps))" }
        return "\(Int(reps)) × \(WorkoutSetLog.loadText(load))"
    }

    private func formatLoad(_ load: Double?) -> String {
        guard let load, load > 0 else { return "—" }
        return WorkoutSetLog.loadText(load)
    }
}
