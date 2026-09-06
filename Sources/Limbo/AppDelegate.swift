import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pannello: NotchPanel?
    private let appunti = Appunti()
    private lazy var deposito = Deposito()
    private lazy var stato = StatoNotch(appunti: appunti, deposito: deposito)
    private let impostazioni = Impostazioni()

    func applicationDidFinishLaunching(_ notifica: Notification) {
        let pannello = NotchPanel(stato: stato)
        pannello.apriImpostazioni = { [weak self] in
            guard let self else { return }
            self.impostazioni.mostra(stato: self.stato)
        }
        pannello.orderFrontRegardless()
        self.pannello = pannello

        // La voce nella barra dei menu NON si monta più (sua scelta del
        // 19/08): impostazioni ed uscita vivono nel clic destro sul notch.
        let quante = UserDefaults.standard.integer(forKey: "quanteCopie")
        if quante > 0 { appunti.tetto = quante }
        appunti.avvia()
        deposito.potaSpariti()
        deposito.potaScadute()
        deposito.raccogliOrfani()

        // Si apre da sola quando accendi il Mac (sua richiesta del 18/08).
        // SOLO dal bundle installato: registrare la copia di sviluppo in
        // .build farebbe partire al login un binario che domani non c'è più
        // (parente stretto della trappola LaunchServices di MacAppRules §4).
        // La guardia è «non è acceso», NON «== notRegistered»: un'app mai
        // registrata risponde `.notFound` (sondato il 18/08 — con il confronto
        // stretto la registrazione non partiva mai). Registrare due volte è
        // un no-op, quindi il costo del criterio largo è zero.
        if Bundle.main.bundlePath.hasPrefix("/Applications"),
           SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
    }

    func applicationWillTerminate(_ notifica: Notification) {
        appunti.ferma()
    }

}
