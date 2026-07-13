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

## Lokal testen (am PC)

```bash
flutter pub get
flutter run -d chrome
# oder:
flutter build web --release
```
