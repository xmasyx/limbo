import SwiftUI

// Le curve del movimento, misurate — non scelte a occhio.
//
// Provenienza (Fase 0, 2026-08-17): lette dal sorgente di Atoll
// (`Ebullioscopic/Atoll`, GPL-3.0), che è il ramo vivo di boring.notch. Sono
// PARAMETRI, non codice: qui non c'è una riga loro, c'è il numero che avevano
// trovato e la ragione per cui regge.
//
// Il dato che conta e che decide tutto il resto: **lo smorzamento è 1.0** su
// apertura e chiusura. Uno smorzamento pieno vuol dire che la molla arriva e
// si ferma, senza oltrepassare il bersaglio e tornare indietro. Il rimbalzo
// esiste, ma è riservato al passaggio del puntatore, dove è un ammiccamento e
// non un ballonzolìo sotto un pannello alto tre centimetri.
//
// Perché non ci si mette una durata secca: una molla interrotta a metà
// riparte da dove sta, con la velocità che ha. Una `easeInOut` interrotta
// salta. Con un pannello che si apre e si chiude al passaggio della mano, le
// interruzioni sono la norma, non l'eccezione.
enum Movimento {
    // I numeri stanno fuori dalle `Animation` perché `Animation` non li
    // restituisce: un banco non può chiedere a una molla com'è fatta. Tenuti
    // qui, il banco li legge e la regola diventa verificabile invece che
    // scritta in un commento.
    static let rispostaApre: Double = 0.42
    static let rispostaChiude: Double = 0.45
    /// Smorzamento pieno: la molla arriva e si ferma. È l'invariante del
    /// progetto, non una preferenza — cambiarlo cambia il carattere dell'app.
    static let smorzamento: Double = 1.0

    /// L'apertura del guscio. Leggermente più svelta della chiusura: aprire è
    /// una risposta a un gesto, e una risposta lenta si legge come esitazione.
    static let apre = Animation.spring(
        response: rispostaApre, dampingFraction: smorzamento, blendDuration: 0)

    /// La chiusura. Un filo più lenta, così il pannello non «scatta via»
    /// quando esci con il puntatore di striscio.
    static let chiude = Animation.spring(
        response: rispostaChiude, dampingFraction: smorzamento, blendDuration: 0)

    /// Il passaggio del puntatore sul guscio chiuso: qui il rimbalzo ci sta,
    /// perché il movimento è di due punti e dura un lampo.
    static let sfiora = Animation.bouncy.speed(1.2)

    /// Il contenuto DENTRO il pannello già aperto: cambio di scheda, una voce
    /// nuova che entra, una che se ne va. Non è una molla: qui il bersaglio
    /// non si supera mai, e la durata corta tiene il pannello calmo mentre il
    /// guscio è fermo.
    static let contenuto = Animation.smooth(duration: 0.25)

    /// Le micro-transizioni: un'icona che cambia, un'opacità, una selezione.
    static let micro = Animation.easeInOut(duration: 0.2)

    /// La molla giusta per lo stato del guscio, aperto o chiuso.
    static func guscio(aperto: Bool) -> Animation { aperto ? apre : chiude }
}

// I raggi. Atoll usa 10, 12 e 14, tutti `.continuous`; il guscio del notch sta
// a 24 in basso, che è il raggio con cui macOS disegna il notch stesso.
//
// Regola 14 del gusto: i raggi annidati sono concentrici, `esterno = interno
// + padding`. Su macOS la formula è aritmeticamente giusta ma va GUARDATA,
// perché l'angolo continuo a parità di numero legge più ampio del cerchio.
enum Raggi {
    /// Il guscio nel notch: solo gli angoli bassi, come l'hardware.
    static let guscio: CGFloat = 24
    /// Una scheda dentro il pannello.
    static let scheda: CGFloat = 12
    /// Padding fra scheda e contenuto: il raggio interno viene da qui.
    static let respiro: CGFloat = 4
    /// Il raggio interno concentrico alla scheda: 12 − 4 = 8.
    static let dentro: CGFloat = scheda - respiro
}
