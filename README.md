# Rezept Nachkochen

Flutter-App, mit der du Rezeptvideos von Facebook, Instagram, TikTok und Co. über den **Teilen**-Button (oder per Link) speichern kannst.

Die App macht daraus:

- eine **Einkaufsliste / Zutatenliste**
- eine **Schritt-für-Schritt-Anleitung** zum Nachkochen

## So benutzt du die App

1. App auf dem Android-Handy installieren (Debug-APK oder `flutter run`)
2. In Facebook/Instagram/TikTok/YouTube bei einem Rezeptvideo auf **Teilen** tippen
3. **Rezept Nachkochen** auswählen
4. Auf **Anleitung erstellen** tippen

Alternativ: In der App auf **Video teilen / Link** tippen und den Link oder die Videobeschreibung einfügen.

## Bessere Ergebnisse mit KI (optional)

Unter **Einstellungen** kannst du einen eigenen [OpenAI API-Schlüssel](https://platform.openai.com/api-keys) hinterlegen. Dann erkennt die App Zutaten und Schritte deutlich besser.

Ohne Schlüssel funktioniert die App trotzdem – dann mit einfacherer Auswertung und Beispielrezept.

## Entwickeln

```bash
flutter pub get
flutter analyze
flutter build apk --debug
```

## Projektziel

Ähnlich wie bei Apps wie „Was kann ich essen“: Schnell aus Social-Media-Rezeptvideos eine klare Nachkoch-Anleitung bekommen.
