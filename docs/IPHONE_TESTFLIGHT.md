# iPhone vorbereiten: Was du JETZT (auch in der Arbeit) tun kannst

Diese Anleitung ist absichtlich einfach. Du brauchst **noch keinen Mac** für die ersten Schritte.

## Übersicht

| Schritt | Braucht Mac? | Kannst du in der Arbeit machen? |
|---|---|---|
| 1. Apple-Entwicklerkonto anmelden | Nein | Ja |
| 2. App in App Store Connect anlegen | Nein | Ja |
| 3. Familie/Cloud in der App vorbereiten | Nein | Ja (auf Android zum Üben) |
| 4. Share Extension in Xcode fertigstellen | Ja | Nein |
| 5. App per TestFlight aufs iPhone | Mac oder Build-Dienst | Vorbereitung ja |
| 6. Optional: iOS-Kurzbefehl „Teilen“ | Nein (nach Installation) | Später |

---

## Schritt 1 – Apple Developer Programm (jetzt)

1. Öffne auf dem iPhone oder im Browser:  
   https://developer.apple.com/programs/enroll/
2. Mit deiner **Apple-ID** anmelden
3. Persönliches Konto wählen (Individual)
4. Anmeldung abschließen  
   Kosten: ca. **99 € / Jahr** (Apple verlangt das für TestFlight)

> Ohne dieses Konto kannst du die App später nicht stabil auf dein iPhone laden.

Wenn du fertig bist, notiere dir:
- deine Apple-ID
- dass das Entwicklerkonto aktiv ist (Freigabe kann ein paar Stunden dauern)

---

## Schritt 2 – App in App Store Connect anlegen (jetzt)

1. Öffne: https://appstoreconnect.apple.com
2. **Meine Apps** → **+** → **Neue App**
3. Eintragen:
   - Plattform: **iOS**
   - Name: **Rezept Nachkochen**
   - Sprache: Deutsch
   - Bundle-ID: später `de.rezeptezumnachkochen.rezeptNachkochen`  
     (falls die Bundle-ID dort noch fehlt: unter Certificates/Identifiers zuerst anlegen)
4. Speichern

Das ist nur die „Hülle“ für TestFlight – die App ist damit noch nicht öffentlich im Store.

---

## Schritt 3 – Bundle-ID / App Group notieren

Wir nutzen in der App bereits:

- Bundle-ID: `de.rezeptezumnachkochen.rezeptNachkochen`
- App Group: `group.de.rezeptezumnachkochen.rezeptNachkochen`

In developer.apple.com → **Identifiers**:
1. App-ID für die Bundle-ID anlegen (falls nicht automatisch vorhanden)
2. **App Groups** Capability aktivieren
3. Gruppe `group.de.rezeptezumnachkochen.rezeptNachkochen` anlegen / zuordnen

Das kannst du ebenfalls schon jetzt im Browser machen.

---

## Schritt 4 – Wenn du einen Mac hast (oder jemanden mit Mac)

Die Dateien für den Teilen-Button sind schon vorbereitet unter:

- `ios/Share Extension/`
- `ios/Runner/Runner.entitlements`
- `ios/Runner/SceneDelegate.swift`

### In Xcode (ca. 10–15 Minuten)

1. Projekt öffnen: `ios/Runner.xcworkspace` oder `ios/Runner.xcodeproj`
2. Oben Menü: **File → New → Target…**
3. **Share Extension** wählen → Next
4. Name: `Share Extension`
5. Fertige Dateien aus `ios/Share Extension/` übernehmen / ersetzen
6. Bei **Runner** und **Share Extension**:
   - Signing & Capabilities → **App Groups**
   - Gruppe `group.de.rezeptezumnachkochen.rezeptNachkochen` anhaken
7. Bei beiden Targets User-Defined Setting:
   - `CUSTOM_GROUP_ID` = `group.de.rezeptezumnachkochen.rezeptNachkochen`
8. Share Extension Target → General → Frameworks:
   - `receive-sharing-intent` hinzufügen (Swift Package)
9. Team / Signing mit deinem Apple Developer Account setzen
10. Am iPhone per Kabel testen **oder** Build für TestFlight erzeugen

---

## Schritt 5 – Aufs iPhone bekommen (TestFlight)

### Variante A: Mit Mac
```bash
flutter build ipa
```
Danach in Xcode Organizer oder mit Transporter nach App Store Connect hochladen  
→ TestFlight → dich selbst als Tester einladen → auf dem iPhone installieren.

### Variante B: Ohne eigenen Mac (Build-Dienst)
Dienste wie **Codemagic** oder **GitHub Actions auf macOS** können die IPA bauen.  
Dafür brauchst du:
- Apple Developer Konto (Schritt 1)
- App Store Connect App (Schritt 2)
- ein API-Key aus App Store Connect (Users and Access → Keys)

Wenn du soweit bist, kann ich den Build-Dienst als Nächstes für dich verdrahten.

---

## Sofort-Workaround nach Installation: iOS-Kurzbefehl

Wenn die App auf dem iPhone ist, aber der offizielle Teilen-Button noch fehlt:

1. App **Kurzbefehle** öffnen
2. Neuer Kurzbefehl
3. Aktion: **URL**  
   `rezeptnachkochen://add?text=`
4. Danach Aktion: **URLs öffnen**
5. Oben auf Teilen-Symbol → **Im Teilen-Menü zeigen**
6. Beim Teilen eines Links diesen Kurzbefehl wählen

Die App versteht diese Adresse bereits.

---

## Was schon im Code vorbereitet ist

- iPhone URL-Schema `rezeptnachkochen://...`
- Share-Extension-Dateien
- App Group / Entitlements
- SceneDelegate für geteilte Links
- Familien-Sync + Einkaufsliste (gleiche Liste wie auf dem Galaxy)

## Was du mir danach schreiben kannst

Schick einfach:
1. „Apple Developer ist aktiv“
2. „App in App Store Connect ist angelegt“
3. Ob du einen **Mac** hast oder einen **Build-Dienst** willst

Dann machen wir den letzten Schritt bis zur Installations-Mail von TestFlight.
