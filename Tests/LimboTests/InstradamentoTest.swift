//  InstradamentoTest.swift — dove porta il clic su una riga della scheda Agents.
//
//  Il difetto che questi poli esistono per prendere (25/08): una chat aperta
//  in T4A finiva sul disco senza tesserino, perché T4A cancella le variabili
//  di iTerm e non ne pubblicava di proprie. Limbo sapeva parlare solo con
//  iTerm, quindi il clic non portava da nessuna parte.

import Foundation
import Testing
@testable import Limbo

@MainActor
private func decodifica(_ campi: [String: Any]) -> SessioneChat? {
    var radice: [String: Any] = [
        "description": "Ripara le notifiche",
        "activity": "working",
        "ascent": ["icon": "🥾", "label": "Traverse", "color": "#abb2bf"],
        "updatedAt": ISO8601DateFormatter().string(from: Date()),
    ]
    for (k, v) in campi { radice[k] = v }
    let dati = try! JSONSerialization.data(withJSONObject: radice)
    return SessioniChat.decodifica(dati, id: "prova", adesso: Date())
}

@MainActor
@Suite("Instradamento del salto alla chat")
struct InstradamentoTest {
    @Test("una chat in T4A si raggiunge con il tesserino di T4A")
    func t4a() {
        let sessione = decodifica(["host": "T4A",
                                   "terminalSession": "1B950D38-F532-46D9-93F9-DA5440701920",
                                   "iterm": nil as Any? as Any])
        #expect(sessione?.terminale == .t4a("1B950D38-F532-46D9-93F9-DA5440701920"))
    }

    @Test("in iTerm si tiene solo l'UUID, non il prefisso della scheda")
    func iterm() {
        let sessione = decodifica(["host": "iTerm.app",
                                   "terminalSession": "w0t3p0:52BB854F-6B6B-4892-A316-E397CCAF77AA"])
        #expect(sessione?.terminale == .iterm("52BB854F-6B6B-4892-A316-E397CCAF77AA"))
    }

    @Test("un record vecchio, senza ospite, resta una chat di iTerm")
    func vecchio() {
        let sessione = decodifica(["iterm": "w0t0p0:B588DC8A-584E-4EAD-8B70-8B79EF924F5C"])
        #expect(sessione?.terminale == .iterm("B588DC8A-584E-4EAD-8B70-8B79EF924F5C"))
    }

    @Test("polo negativo: senza tesserino non si salta da nessuna parte")
    func senzaTesserino() {
        #expect(decodifica(["host": "T4A"])?.terminale == nil)
    }

    @Test("polo negativo: un terminale che non sappiamo interrogare non diventa iTerm")
    func terzoTerminale() {
        let sessione = decodifica(["host": "Ghostty",
                                   "terminalSession": "52BB854F-6B6B-4892-A316-E397CCAF77AA"])
        #expect(sessione?.terminale == nil)
    }
}
