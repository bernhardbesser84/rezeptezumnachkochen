# Vercel einrichten (optional)

Du brauchst **entweder** GitHub Pages **oder** Vercel – nicht beides.

Wenn du Vercel nutzen willst (einfach und kostenlos für Privatprojekte):

## 1. Repo mit Vercel verbinden

1. Öffne https://vercel.com und melde dich an
2. **Add New… → Project**
3. GitHub-Repo `rezeptezumnachkochen` auswählen
4. **Import**

## 2. Einstellungen prüfen

Die Datei `vercel.json` im Projekt erledigt das meiste.

Falls Vercel nachfragt:
- **Framework Preset:** Other
- **Build Command:** (aus vercel.json, nicht ändern)
- **Output Directory:** `build/web`
- **Install Command:** leer lassen / Default

## 3. Deploy

Auf **Deploy** tippen.

Danach bekommst du eine Adresse wie:
`https://rezeptezumnachkochen.vercel.app`

## 4. Auf dem iPhone

1. Diese Adresse in **Safari** öffnen
2. Teilen → **Zum Home-Bildschirm**
3. Caption unter dem Video kopieren und in der App einfügen

## Hinweis

- Für Vercel reicht die kostenlose Stufe
- Kein Apple-Abo nötig
