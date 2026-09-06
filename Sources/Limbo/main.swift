import AppKit
import SwiftUI
import ServiceManagement

// I banchi girano PRIMA di NSApplication, così `build-app.sh` li esegue senza
// aprire finestre e senza toccare gli appunti veri (MacAppRules §7: la sonda
// visiva di un'app si fa senza finestre, perché le finestre di prova compaiono
// sullo Space attivo, cioè sotto le mani di chi sta usando il Mac).
let argomenti = CommandLine.arguments
if argomenti.contains("--selftest-stringhe") {
    exit(SelfTests.stringhe())
}
if argomenti.contains("--selftest-geometria") {
    exit(SelfTests.geometria())
}
if argomenti.contains("--selftest-movimento") {
    exit(SelfTests.movimento())
}
if argomenti.contains("--selftest-nuove") {
    exit(MainActor.assumeIsolated { SelfTests.nuove() })
}
if argomenti.contains("--selftest-deposito") {
    exit(MainActor.assumeIsolated { SelfTests.deposito() })
}
if argomenti.contains("--selftest-chat") {
    exit(MainActor.assumeIsolated { SelfTests.chat() })
}
// La sonda della sentinella, da eseguire SUL BINARIO DENTRO IL BUNDLE: da lì
// dipende il permesso Scrivania, che è legato al bundle e non al codice.
// Serve a distinguere «la sentinella è rotta» da «macOS non ci fa leggere».
// La sonda visiva della X del deposito (6/09): una scheda sola, con lo stato
// «puntatore sopra» forzato, salvata in PNG. Serve perché il passaggio del
// puntatore non esiste dentro un `ImageRenderer`.
if let i = argomenti.firstIndex(of: "--sonda-x"), argomenti.count > i + 1 {
    let uscita = URL(fileURLWithPath: argomenti[i + 1])
    let esito = MainActor.assumeIsolated { () -> Int32 in
        // La sonda si costruisce la sua immagine: non deve dipendere da cosa
        // c'è nel deposito vero di nessuno.
        let finta = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sonda-x-\(UUID().uuidString).png")
        let disegno = NSImage(size: NSSize(width: 320, height: 200))
        disegno.lockFocus()
        NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.30, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 320, height: 200).fill()
        disegno.unlockFocus()
        if let tiff = disegno.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: finta)
        }
        let voce = VoceDeposito(id: UUID(), url: finta,
                                nome: "Screenshot 2026-09-06 alle 02.55.00.png",
                                quando: Date(), fissata: false, nostra: true)
        let deposito = Deposito(perSonda: [voce])
        let stato = StatoNotch(appunti: Appunti(perSonda: []), deposito: deposito)
        let vista = SchedaDeposito(voce: voce, stato: stato, perSonda: true,
                                   sfiorataPerSonda: true)
            .padding(24)
            .background(Livrea.guscio)
        let renderer = ImageRenderer(content: vista)
        renderer.scale = 3
        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return 1 }
        try? png.write(to: uscita)
        print(uscita.path)
        return 0
    }
    exit(esito)
}
if argomenti.contains("--sonda-schermate") {
    let cartella = SentinellaSchermate.cartellaDiCattura()
    let elenco = (try? FileManager.default.contentsOfDirectory(
        at: cartella, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))
    let fd = open(cartella.path, O_EVTONLY)
    print("cartella: \(cartella.path)")
    print("elenco: \(elenco.map { "\($0.count) file" } ?? "NEGATO")")
    print("schermate viste: \(elenco?.filter(SentinellaSchermate.eSchermata).count ?? -1)")
    print("descrittore: \(fd >= 0 ? "aperto" : "NEGATO")")
    if fd >= 0 { close(fd) }
    exit(0)
}
if argomenti.contains("--selftest-schermate") {
    exit(SelfTests.schermate())
}
if argomenti.contains("--selftest-aggiornamenti") {
    exit(SelfTests.aggiornamenti())
}
// Il banco vivo dell'aggiornamento: parla con GitHub (o col rubinetto locale
// LIMBO_API_AGGIORNAMENTI) e, se c'è una versione nuova, esegue davvero
// l'azione. Non gira in `build-app.sh`: tocca la rete.
if argomenti.contains("--banco-aggiornamenti") {
    let codice = MainActor.assumeIsolated { () -> Int32 in
        let aggiornatore = Aggiornatore()
        let semaforo = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var uscita: Int32 = 1
        Task { @MainActor in
            uscita = await aggiornatore.giraIlBanco()
            semaforo.signal()
        }
        while semaforo.wait(timeout: .now() + 0.02) == .timedOut {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        return uscita
    }
    exit(codice)
}
if argomenti.contains("--selftest-grazia") {
    exit(MainActor.assumeIsolated { SelfTests.grazia() })
}
// Lo stato dell'avvio al login, leggibile da fuori: è la sonda della claim
// C9, e va interrogato sul binario DENTRO il bundle installato.
if argomenti.contains("--stato-login") {
    let parola = switch SMAppService.mainApp.status {
    case .enabled: "registrato"
    case .requiresApproval: "in attesa del suo permesso nelle Impostazioni"
    case .notFound: "non trovato (il bundle non è registrabile da qui)"
    default: "non registrato"
    }
    print(parola)
    exit(0)
}
// Una prova di conversione dalla riga di comando: converte e stampa i numeri
// veri (prima/dopo, risoluzione, codec). Serve a rispondere «quanto risparmio
// davvero?» con una misura invece che con una teoria.
if let indice = argomenti.firstIndex(of: "--prova-conversione"), argomenti.count > indice + 1 {
    exit(ProvaConversione.esegui(percorso: argomenti[indice + 1]))
}
// La misura dei fotogrammi persi in una registrazione dello schermo (C12).
if let indice = argomenti.firstIndex(of: "--fotogrammi"), argomenti.count > indice + 1 {
    exit(Fotogrammi.misura(percorso: argomenti[indice + 1]))
}
if argomenti.contains("--banco-fluidita") {
    exit(MainActor.assumeIsolated { Scatta.fluidita(giri: 40) })
}
if let indice = argomenti.firstIndex(of: "--scatta"), argomenti.count > indice + 1 {
    exit(MainActor.assumeIsolated { Scatta.esegui(cartella: argomenti[indice + 1]) })
}

let app = NSApplication.shared
// Il codice in cima a main.swift non è isolato all'attore principale, ma qui
// ci siamo davvero: `NSApplication.shared` gira sul thread principale per
// costruzione. `assumeIsolated` lo dichiara al compilatore invece di allentare
// l'isolamento del delegato, che è la protezione vera.
let delegato = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegato
// Accessorio: vive nel notch e nella barra dei menu, non nel Dock.
app.setActivationPolicy(.accessory)
app.run()
