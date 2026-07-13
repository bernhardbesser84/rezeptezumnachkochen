# Rezept Nachkochen

Familien-App: Rezeptvideo teilen → Einkaufsliste + Schritt-für-Schritt-Anleitung + Video.

## Euer Tagesablauf

1. **Bernhard am iPhone**: Rezeptvideo finden → Teilen → App → Anleitung erstellen  
2. **Zuhause am Samsung-Tablett**: Rezept öffnen → „Am Tablett nachkochen“ + Video anschauen  
3. **Frau am Samsung Galaxy**: Einkaufsliste öffnen → im Laden abhaken, was schon im Korb ist  

Alle Geräte brauchen denselben **Familien-Code** und dieselbe **Cloud-Verbindung**.

## Muss das über den App Store?

**Nein.** Für euch privat reicht:

- **Samsung Galaxy + Tablett**: APK installieren (kein Google Store nötig)
- **iPhone**: App einmal mit einem Mac / Flutter bauen (oder später TestFlight). Store ist optional.

## Familie & Cloud einrichten (einmalig, kostenlos)

1. Konto auf [supabase.com](https://supabase.com) erstellen  
2. Neues Projekt anlegen  
3. Links **SQL** → Editor → Inhalt aus `supabase/schema.sql` einfügen → **Run**  
4. Links **Project Settings → API**:
   - Project URL kopieren
   - `anon` `public` Key kopieren  
5. In der App: **Familie** öffnen  
   - Geräte-Name z. B. `Bernhard iPhone`  
   - Familien-Code erstellen (z. B. `KOCH-4F2A`)  
   - URL + Key eintragen  
   - **Verbinden & Sync** tippen  
6. Denselben Code + URL + Key auf Tablett und Galaxy eintragen  

## Funktionen

- Teilen von Facebook & Co. (Android jetzt, iPhone vorbereitet)
- Zutatenliste / Einkaufsliste mit Abhaken
- Schritt-für-Schritt-Anleitung + Kochmodus fürs Tablett
- Video-Link am Rezept
- Optional: OpenAI-Schlüssel für bessere Auswertung

## Entwickeln

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

## iPhone-Hinweis

Der Teilen-Button auf dem iPhone braucht zusätzlich eine **Share Extension** in Xcode
(siehe `receive_sharing_intent` Doku). Bis dahin: Link kopieren und in der App einfügen.

## Wichtig

Ohne Cloud sehen die Geräte **nicht** dieselbe Liste.  
Mit Cloud (Supabase) synchronisieren sich Rezepte und Einkaufsabhaken in wenigen Sekunden.
