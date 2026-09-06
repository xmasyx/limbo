import Foundation

// Tutto il testo che si legge vive QUI e solo qui (MacAppRules §5):
// `Scripts/build-app.sh` estrae questo file e lo passa dal cancello italiano
// prima di compilare, perché NoSleep è uscita in traduttese quando il cancello
// copriva i documenti e non le stringhe dell'interfaccia.
//
// Il metro è suo: si scrive **che cosa succede al Mac**, non che cosa fa il
// programma. «Trascina qui quello che stai spostando», non «rilascia l'item
// nella drop zone».
enum S {
    // Il menu del clic destro sul notch (la barra dei menu non c'è più:
    // sua scelta del 19/08, «lo togliamo da lì»)
    static let impostazioni = "Impostazioni…"
    static let svuotaDeposito = "Svuota il deposito"
    static let esci = "Esci"
    static let titoloImpostazioni = "Impostazioni di Limbo"

    // Le quattro schede
    static let appunti = "Appunti"
    static let deposito = "Deposito"
    static let convertitore = "Converti"
    // La scheda si chiama come il tuo assistente (sua richiesta del 19/08).
    // La linguetta si chiama «Agents», non col nome del tuo assistente (quel nome è tuo,
    // assistente è suo, e sullo schermo lo leggono anche gli altri) e non
    // «Terminale», che sarebbe una bugia: qui dentro non c'è un terminale,
    // ci sono le chat degli agenti che stanno lavorando alle sue task. La
    // scheda mostra QUELLE, e niente altro di quello che gira nel terminale.
    static let chat = "Agents"

    // La scheda Agents: le chat aperte nel terminale
    static let chatVuota = "Qui compaiono le chat aperte nel terminale."
    static let aspettaTe = "Aspetta te"
    static let adesso = "adesso"
    static let chatPorta = "Ti porto a questa chat nel terminale"
    static let chatSparita = "Quella chat non c'è più."
    static func chatQuante(_ n: Int) -> String { n == 1 ? "1 chat" : "\(n) chat" }
    // Il testo del braccio: il progetto, e quando c'è il titolo corto della
    // chat. NIENTE VERBO (sua correzione del 20/08: «non deve dire Kalamos
    // aspetta te, mi dice solo Kalamos»): se aspetta te o ha finito lo dice
    // il glifo accanto, che costa dodici punti invece di una frase.
    static func braccio(progetto: String, titolo: String?) -> String {
        // UNA cosa sola, e la sceglie l'hook: qui non si compone niente.
        // «Kalamos», non «Kalamos · macOS app»; «dashboard» quando il progetto
        // sarebbe solo «LifeOS» (sua regola del 20/08). Le due parole
        // arrivano già unite quando due chat vive condividono il progetto.
        if let corto = titolo?.trimmingCharacters(in: .whitespaces), !corto.isEmpty {
            return corto
        }
        let nome = progetto.trimmingCharacters(in: .whitespaces)
        return nome.isEmpty ? "Claude" : nome
    }

    // Le schermate assorbite (6/09)
    /// **L'unica riga inglese dell'app, e ci sta per una decisione sua del
    /// 6/09.** Il braccio deve dire due cose in 210 punti: cosa è successo e
    /// cosa fa il clic. «Depositata · clic per la Scrivania» ne chiede 233 e
    /// «click for desktop» 218; con l'uguale spaziato si sta in **210 esatti**,
    /// misurati col carattere vero del braccio. Il segno costa meno delle due
    /// parole che sostituisce. Ripiego se un giorno esce troncato:
    /// `Depositata · click=desktop`, 204 punti.
    static let braccioSchermata = "Depositata · click"
    static let assorbiSchermate = "Porta le schermate nel deposito"
    static let notaAssorbiSchermate = "La miniatura di Apple resta: se la prendi al volo non entra qui. Entra solo quella che lasci sparire."

    // Il convertitore
    static let trascinaDaConvertire = "Trascina qui un'immagine o un video"
    static let notaConversione = "L'originale resta dov'è. Quello che esce va nel deposito."
    static let convertito = "Fatto"
    static let immagini = "Immagini"
    static let video = "Video"
    static let leggero = "Leggero"
    static let fedele = "Fedele"
    static let documenti = "Documenti"
    static let inPdf = "in PDF"
    static let comprimoVideo = "Comprimo il video"
    static let convertoImmagine = "Converto l'immagine"
    static let nonSoConvertire = "Questo non so convertirlo."

    // La lettura del testo nelle immagini
    static let copiaIlTesto = "Copia il testo"
    static let leggiTesto = "Leggi il testo nelle immagini"
    static let notaLeggiTesto = "Appena entra un'immagine ne leggo il testo, sul Mac e basta. Poi lo copi dal tasto destro."

    // Zona di rilascio
    static let trascinaQui = "Trascina qui quello che stai spostando"
    static let lascialoAndare = "Lascia andare"
    static let tienilodaParte = "Tienilo da parte"
    static let alleggerisci = "Alleggerisci"
    static let notaAlleggerisci = "Più leggero, o in PDF"
    static let mandaloVia = "Mandalo a un altro dispositivo"
    static let depositoVuoto = "Qui resta quello che trascini, finché non ti serve."
    static let appuntiVuoti = "Qui compare quello che copi. Basta copiare qualcosa."

    // Azioni su una voce
    static let copia = "Copia"
    static let apri = "Apri"
    static let mostraNelFinder = "Mostra nel Finder"
    static let condividi = "Condividi"
    static let airdrop = "AirDrop"
    static let converti = "Converti"
    static let fissa = "Tieni fermo"
    static let libera = "Non tenerlo più fermo"
    static let togliDalDeposito = "Togli dal deposito"
    static let anteprima = "Anteprima"

    // Il tastino del deposito
    static let svuota = "Svuota"
    static let svuotaAppunti = "Svuota gli appunti"
    static let svuotati = "Svuotati"
    static let nelCestino = "Nel Cestino"

    // Esiti
    static let copiato = "Copiato"
    static let fileSparito = "Questo file non è più dov'era."
    static let nonPreso = "Questo non riesco a prenderlo."
    static let nienteDaCondividere = "Non c'è niente da condividere."

    // Conteggi
    static func voci(_ n: Int) -> String { n == 1 ? "1 voce" : "\(n) voci" }

    // Impostazioni
    static let scadenzaDeposito = "Quanto dura il deposito"
    static let notaScadenzaDeposito = "Passati questi giorni le voci vanno nel Cestino da sole. Quelle che tieni ferme non scadono mai."
    static let mai = "Mai"
    static let quanteVoci = "Quante copie tenere"
    static let notaQuanteVoci = "Le più vecchie spariscono da sole quando arrivi al limite."
    static let apriConIlPuntatore = "Apri passandoci sopra"
    static let notaApriConIlPuntatore = "Spento, il pannello si apre con un clic o trascinandoci qualcosa."
    static let avvioAlLogin = "Apri quando accendi il Mac"
    static let notaAvvioAlLogin = "Limbo compare nel notch a ogni accensione, senza aprirti niente."
    static let avvisaChat = "Avvisami delle chat dal notch"
    static let notaAvvisaChat = "Quando una chat del terminale finisce o aspetta una tua decisione, il notch si apre da solo un momento."
    static let acceso = "Sì"
    static let spento = "No"

    // Aggiornamenti (il tasto nelle Impostazioni, come nelle altre app di casa)
    static let aggiornamenti = "Aggiornamenti"
    static let notaAggiornamenti = "Quando apri questa pagina Limbo guarda se c'è una versione nuova. Se l'hai presa da brew la tira giù e si riapre da sola."
    static let verificaAggiornamenti = "Verifica aggiornamenti"
    static let aggiornamentoGuardo = "Guardo…"
    static let aggiornamentoUltima = "È l'ultima"
    static let aggiornamentoPreparo = "Preparo…"
    static let aggiornamentoInCorso = "Aggiorno…"
    static let aggiornamentoRiprova = "Riprova"
    static let aggiornamentoSenzaBrew = "Su questo Mac non c'è Homebrew: ti apro la pagina della versione nuova."
    static let aggiornamentoFallito = "L'aggiornamento si è fermato a metà."
    static func aggiornamentoCe(_ versione: String) -> String { "C'è la \(versione)" }
}
