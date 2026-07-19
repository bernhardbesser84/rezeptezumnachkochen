# iPhone als kostenlose Web-App (ohne 99 €)

Diese Variante braucht **kein Apple Developer Abo** und **keinen Mac**.

## Empfohlen: über Vercel

Du hast schon ein Vercel-Konto → nutze das.

👉 [`docs/VERCEL.md`](VERCEL.md)

Danach öffnest du den Vercel-Link in **Safari** und wählst
**Zum Home-Bildschirm**.

## So nutzt du sie auf dem iPhone

1. Öffne den Vercel-Link in **Safari** (nicht Chrome)
2. Tippe auf **Teilen** (Quadrat mit Pfeil)
3. Wähle **Zum Home-Bildschirm**
4. Fertig – Icon liegt neben deinen anderen Apps

## Rezept hinzufügen (ohne Facebook-Teilen-Button)

1. Rezeptvideo öffnen → Link **kopieren**
2. Web-App öffnen → **Link einfügen**
3. **Anleitung erstellen**

## Damit Galaxy + Tablett dasselbe sehen

In der App unter **Familie** denselben Familien-Code und dieselben Cloud-Daten eintragen.

## Wenn die Home-Bildschirm-App „hängt“ (alte Version)

Safari und die App vom Home-Bildschirm können unterschiedliche
Caches haben. Nach einem Update:

1. App einmal komplett schließen (aus dem App-Umschalter wischen)
2. Neu öffnen — oben erscheint ggf. **„Update verfügbar“**
3. Oder unter **Einstellungen → App-Cache leeren & neu laden**

Falls weiterhin Probleme: denselben Link einmal in Safari öffnen,
dann die Home-Bildschirm-App erneut starten.

## Lokal testen (am PC)

```bash
flutter pub get
flutter run -d chrome
# oder:
flutter build web --release
```
