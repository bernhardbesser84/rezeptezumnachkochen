# iPhone als kostenlose Web-App (ohne 99 €)

Diese Variante braucht **kein Apple Developer Abo** und **keinen Mac**.

## So nutzt du sie auf dem iPhone

1. Öffne die Web-App-Adresse in **Safari**  
   (nach dem Deploy typisch: `https://bernhardbesser84.github.io/rezeptezumnachkochen/`)
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
flutter build web --release --pwa-strategy offline-first
```

## Automatisches Veröffentlichen

GitHub Action: `.github/workflows/deploy-web.yml`

In GitHub unter dem Repo:
1. **Settings → Pages**
2. Source: **GitHub Actions**

Nach dem Merge/Push erscheint die Seite unter GitHub Pages.
