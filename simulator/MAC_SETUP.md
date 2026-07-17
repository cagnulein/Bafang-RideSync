# Setup Flutter su Mac (prima volta)

Guida completa per chi non ha mai usato Flutter su quel Mac.

---

## 1. Installa Xcode (se non ce l'hai già)

```bash
# Controlla se è installato
xcode-select -p
# Se risponde un path tipo /Applications/Xcode.app/Contents/Developer, ok.
# Altrimenti installalo dall'App Store oppure:
xcode-select --install
```

Apri Xcode almeno una volta e accetta la licenza.

---

## 2. Installa Flutter

```bash
# Con Homebrew (il modo più semplice):
brew install --cask flutter

# Oppure manualmente:
#   1. Scarica l'SDK da https://docs.flutter.dev/get-started/install/macos
#   2. Decomprimi in ~/development/flutter
#   3. Aggiungi al PATH in ~/.zshrc:
#      export PATH="$HOME/development/flutter/bin:$PATH"
```

Riapri il terminale dopo l'installazione, poi verifica:

```bash
flutter --version
# es: Flutter 3.x.x • channel stable
```

---

## 3. Abilita il target macOS

```bash
flutter config --enable-macos-desktop
flutter doctor
```

`flutter doctor` ti dice se manca qualcosa. L'unico warning che puoi ignorare per questo progetto è "Android toolchain" e "Chrome".  
Quello che deve essere verde: **Flutter**, **Xcode**, **macOS**.

---

## 4. Clona il repo (se non l'hai già) e vai nella cartella

```bash
# Se devi clonare:
git clone <url-del-repo> "Bafang RideSync"

cd "Bafang RideSync/simulator"
```

---

## 5. Setup una-tantum dell'app

```bash
bash setup_macos.sh
```

Lo script fa:
- `flutter create . --platforms=macos` — genera il boilerplate macOS (Xcode project, entitlements, ecc.)
- Patcha `macos/Runner/Info.plist` con il permesso Bluetooth
- `flutter pub get` — scarica le dipendenze

---

## 6. Avvia l'app

```bash
flutter run -d macos
```

La prima volta Xcode compila tutto (può volerci 1-2 minuti).  
macOS ti chiederà il permesso Bluetooth al primo avvio: clicca **OK**.

Per le volte successive è molto più veloce (solo hot-reload).

---

## Workflow di debug

### Testare offline (senza la bici)
1. Avvia l'app
2. Clicca **⚗** in alto a destra → inietta i frame di test hardcoded
3. Verifica che batteria/PAS/velocità/trip/odo siano corretti

### Testare con la bici reale
1. Accendi il display EKD01-BF
2. L'app scansiona automaticamente (status = `SCAN`)
3. Appena trova il device si connette e fa l'handshake (status: `CONN` → `INIT` → `OK`)
4. Tab **BLE log** per vedere ogni frame TX/RX con timestamp

### Replay di catture esistenti
1. Vai su tab **Hex inject**
2. Copia i byte da `ekd01_payloads.txt` o da qualsiasi cattura
3. Incolla e clicca **Inject**
- Frame completo `55 aa …` → verifica checksum e fa il dispatch automatico
- 21 byte raw → trattati come DATA di 06 01
- 16 byte raw → trattati come DATA di 06 09

---

## Hot-reload e hot-restart

Con l'app in esecuzione nel terminale:
- `r` → hot reload (aggiorna il codice senza perdere lo stato)
- `R` → hot restart (riavvia da zero)
- `q` → esci

In alternativa puoi aprire il progetto in VS Code con l'estensione Flutter e usare il debugger grafico.

---

## Struttura file (solo i file Dart che contano)

```
simulator/lib/
  frame_parser.dart   ← port 1:1 di FrameParser.mc
  frame_builder.dart  ← port 1:1 di FrameBuilder.mc
  bafang_data.dart    ← port 1:1 di BafangData.mc + injectHex()
  ble_service.dart    ← port 1:1 di BafangBleDelegate.mc
  home_screen.dart    ← UI (Data / Hex inject / BLE log)
  main.dart           ← entry point
```

**Regola d'oro:** se trovi un bug o aggiungi logica qui, riporta la stessa modifica nel file `.mc` corrispondente prima di flashare sul Garmin.

---

## Troubleshooting

| Problema | Soluzione |
|---|---|
| `flutter: command not found` | Riapri il terminale o aggiungi Flutter al PATH |
| `No macOS device detected` | `flutter config --enable-macos-desktop` poi riprova |
| Bluetooth non funziona | Controlla System Settings → Privacy → Bluetooth → abilita l'app |
| Build fallisce su Xcode | `cd macos && pod install` poi riprova |
| `flutter pub get` fallisce su versione dipendenza | Modifica `pubspec.yaml`: cambia la versione di `flutter_blue_plus` con quella più recente su pub.dev |
