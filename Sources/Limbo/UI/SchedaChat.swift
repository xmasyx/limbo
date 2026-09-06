import AppKit
import SwiftUI

/// La scheda «Chat»: le chat Claude aperte nel terminale, una per riga —
/// pallino del colore di stato, descrizione, avanzamento, età dell'ultimo
/// movimento. Il clic sulla riga porta iTerm2 davanti, su quella sessione.
struct SchedaChat: View {
    @ObservedObject var chat: SessioniChat
    let stato: StatoNotch
    var perSonda = false
    /// Iniettabile per la sonda: le età nelle fotografie devono essere stabili.
    var adesso = Date()

    var body: some View {
        Group {
            if chat.voci.isEmpty {
                Text(S.chatVuota)
                    .font(.system(size: 12))
                    .foregroundStyle(Livrea.sopraGuscio.opacity(0.45))
                    .frame(maxWidth: .infinity)
            } else {
                elenco
            }
        }
        .frame(height: NotchPanel.altezzaFila)
    }

    private var elenco: some View {
        let colonna = VStack(spacing: 4) {
            ForEach(chat.voci) { sessione in
                RigaChat(sessione: sessione, adesso: adesso) { apri(sessione) }
            }
        }
        return Group {
            // `ScrollView` esce vuoto in `ImageRenderer` (stessa dichiarazione
            // di NotchView): la sonda fotografa la colonna nuda.
            if perSonda {
                colonna.frame(maxHeight: .infinity, alignment: .top).clipped()
            } else {
                ScrollView(.vertical, showsIndicators: false) { colonna }
            }
        }
    }

    private func apri(_ sessione: SessioneChat) {
        if !chat.porta(inPrimoPiano: sessione) {
            stato.soffia(S.chatSparita)
        }
    }
}

/// Una riga: alta fissa, cliccabile su TUTTO il rettangolo, con l'evidenza
/// del passaggio come le schede (stessa forma di casa, mai una nuova).
private struct RigaChat: View {
    let sessione: SessioneChat
    let adesso: Date
    let apri: () -> Void

    @State private var sfiorata = false

    var body: some View {
        Button(action: apri) {
            HStack(spacing: 10) {
                Circle()
                    .fill(sessione.colore)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sessione.descrizione)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Livrea.sopraGuscio.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(sottotitolo)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(Livrea.sopraGuscio.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                destra
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Raggi.scheda, style: .continuous)
                    .fill(Color.white.opacity(sfiorata ? 0.14 : 0.07))
            }
            .contentShape(RoundedRectangle(cornerRadius: Raggi.scheda, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { dentro in sfiorata = dentro }
        .animation(Movimento.sfiora, value: sfiorata)
        .help(S.chatPorta)
    }

    /// «Limbo · Ascending · 12/24 · 3 min» — solo i pezzi che esistono.
    private var sottotitolo: String {
        var pezzi: [String] = []
        if !sessione.progetto.isEmpty { pezzi.append(sessione.progetto) }
        if !sessione.etichetta.isEmpty { pezzi.append(sessione.etichetta) }
        if let avanzamento = sessione.avanzamento { pezzi.append(avanzamento) }
        pezzi.append(sessione.eta(adesso: adesso))
        return pezzi.joined(separator: " · ")
    }

    @ViewBuilder
    private var destra: some View {
        switch sessione.attivita {
        case .aspetta:
            // L'unica riga che chiede qualcosa a te: l'unica accesa.
            Text(sessione.dettaglio ?? S.aspettaTe)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .frame(maxWidth: 190, alignment: .trailing)
                .background(Capsule().fill(Livrea.penna))
        case .finita:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Livrea.sopraGuscio.opacity(0.7))
        case .lavora:
            if sessione.inSonno(adesso: adesso) {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 11))
                    .foregroundStyle(Livrea.sopraGuscio.opacity(0.45))
            } else {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Livrea.sopraGuscio.opacity(0.7))
            }
        }
    }
}
