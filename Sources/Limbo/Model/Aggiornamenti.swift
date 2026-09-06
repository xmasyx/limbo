import Foundation

/// Le decisioni pure dell'aggiornamento: niente rete, niente processi, niente
/// interfaccia. Sta qui perché un banco possa interrogarle senza aprire nulla.
///
/// La forma è quella di Otium e T4A, e non per pigrizia: le app di casa si
/// installano e si aggiornano tutte allo stesso modo (`brew install --cask
/// xmasyx/tap/<nome>`), quindi la logica che decide fra «tira l'aggiornamento
/// da brew» e «aprigli la pagina della release» deve rispondere uguale in
/// tutte, altrimenti la stessa mossa dà esiti diversi a seconda dell'app.
enum Aggiornamenti {
    /// Il repo GitHub da cui si legge l'ultima release.
    static let repo = "xmasyx/limbo"
    /// Il token del cask nel tap.
    static let token = "limbo"
    /// Il tap Homebrew della famiglia (`brew tap xmasyx/tap`).
    static let tap = "xmasyx/tap"

    /// Come l'app è arrivata sul Mac: dal cask, o a mano (zip o DMG).
    enum Provenienza: Equatable {
        case homebrew
        case aMano
    }

    /// Cosa fa il tasto quando c'è una versione nuova.
    enum Azione: Equatable {
        /// Lancia `brew` con questi argomenti (senza il binario), poi riapre l'app.
        case aggiornaERiapri(argomenti: [String])
        /// Apre la pagina della release nel browser.
        case apriLaPagina(URL)
    }

    /// La versione nuova ("0.7.0") se `tagRemoto` (`v0.7.0` o `0.7.0`) è più
    /// recente di `installata`; `nil` se è uguale, più vecchia, o illeggibile.
    /// Il confronto è numerico per componente: 0.10.0 batte 0.9.0, che è il
    /// caso in cui un confronto fra stringhe darebbe la risposta sbagliata.
    static func versionePiuNuova(installata: String, tagRemoto: String) -> String? {
        func pezzi(_ grezzo: String, accettaLaV: Bool) -> [Int]? {
            let versione: Substring
            if accettaLaV, grezzo.first == "v" {
                versione = grezzo.dropFirst()
            } else {
                versione = grezzo[...]
            }
            guard !versione.isEmpty else { return nil }
            let parti = versione.split(separator: ".", omittingEmptySubsequences: false)
            guard !parti.isEmpty else { return nil }
            let numeri = parti.compactMap { parte -> Int? in
                guard !parte.isEmpty, parte.allSatisfy(\.isNumber) else { return nil }
                return Int(parte)
            }
            return numeri.count == parti.count ? numeri : nil
        }

        guard let qui = pezzi(installata, accettaLaV: false),
              let la = pezzi(tagRemoto, accettaLaV: true) else { return nil }
        for indice in 0..<max(qui.count, la.count) {
            let vecchio = indice < qui.count ? qui[indice] : 0
            let nuovo = indice < la.count ? la[indice] : 0
            if nuovo != vecchio {
                return nuovo > vecchio ? la.map(String.init).joined(separator: ".") : nil
            }
        }
        return nil
    }

    /// `true` se non c'è mai stato un controllo, o se è passato `intervallo`.
    /// Un orologio che va indietro (fuso, sincronizzazione) conta come scaduto:
    /// altrimenti una data futura spegnerebbe il controllo per sempre.
    static func eOra(ultimoControllo: Date?, adesso: Date,
                     intervallo: TimeInterval = 86_400) -> Bool {
        guard let ultimoControllo else { return true }
        let passato = adesso.timeIntervalSince(ultimoControllo)
        return passato < 0 || passato >= intervallo
    }

    /// `.homebrew` quando esiste `<radice>/<token>/` in una delle radici del
    /// Caskroom E il bundle sta in `/Applications` o `~/Applications`;
    /// altrimenti `.aMano`. `esiste` è iniettato così il banco non tocca il disco.
    static func provenienza(percorsoBundle: String,
                            radiciCaskroom: [String],
                            casa: String,
                            token: String = token,
                            esiste: (String) -> Bool) -> Provenienza {
        let bundle = URL(fileURLWithPath: percorsoBundle).standardized.path
        let nome = URL(fileURLWithPath: bundle).lastPathComponent
        let diSistema = URL(fileURLWithPath: "/Applications")
            .appendingPathComponent(nome).standardized.path
        let dellUtente = URL(fileURLWithPath: casa)
            .appendingPathComponent("Applications")
            .appendingPathComponent(nome).standardized.path
        guard bundle == diSistema || bundle == dellUtente else { return .aMano }

        let installata = radiciCaskroom.contains { radice in
            esiste(URL(fileURLWithPath: radice).appendingPathComponent(token).standardized.path)
        }
        return installata ? .homebrew : .aMano
    }

    /// Gli argomenti per `brew`, senza il binario.
    static func argomentiAggiornamento(token: String = token, tap: String = tap) -> [String] {
        // Homebrew 6 non ha più `--no-quarantine`: il contrassegno lo toglie
        // l'app dal proprio bundle, e soltanto dopo un `brew` uscito zero.
        ["upgrade", "--cask", "\(tap)/\(token)"]
    }

    /// L'azione per una versione nuova, data la provenienza.
    static func azione(per provenienza: Provenienza, versione: String,
                       repo: String = repo) -> Azione {
        switch provenienza {
        case .homebrew:
            return .aggiornaERiapri(argomenti: argomentiAggiornamento())
        case .aMano:
            return .apriLaPagina(
                URL(string: "https://github.com/\(repo)/releases/tag/v\(versione)")!)
        }
    }

    /// Il `tag_name` dal JSON di `GET /repos/<repo>/releases/latest`; `nil` se
    /// manca o non è JSON.
    static func tagUltimaRelease(dalJSON dati: Data) -> String? {
        struct Release: Decodable { let tagName: String }
        let lettore = JSONDecoder()
        lettore.keyDecodingStrategy = .convertFromSnakeCase
        return try? lettore.decode(Release.self, from: dati).tagName
    }
}
