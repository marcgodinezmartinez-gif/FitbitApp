import SwiftUI
import FaceKit

// App de Recupera para el Apple Watch (doc. 19): tus esferas a pantalla completa. Apple no deja instalar esferas del
// sistema, así que se ven dentro de la app; con «Volver al reloj: después de 1 hora» se quedan puestas.

@main
struct RecuperaWatchApp: App {
    init() {
        PhoneLink.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            FacesPager()
        }
    }
}
