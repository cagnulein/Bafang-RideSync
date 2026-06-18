# BikeGo / EKD01-BF BLE protocol notes

Analisi dei file PacketLogger iOS:

- `bluetoothd-hci-latest.pklg`
- `bluetoothd-hci-2026-06-18_09-52-04.pklg`

Il log contiene molto traffico non relativo alla e-bike, in particolare Garmin/ANCS/meteo/notifiche iOS. Il dispositivo rilevante e' il display e-bike:

- Nome GATT: `EKD01-BF `
- Indirizzo BLE osservato: `70:de:f9:d6:ab:5f`
- Modello letto nel protocollo applicativo: `EKD01_CAN_BF_N22`

Le note sotto distinguono tra:

- **Certo**: direttamente visibile nel dump.
- **Probabile**: inferito da andamento dei byte durante la pedalata breve.
- **Da validare**: serve una cattura piu' lunga o una variazione controllata.

## GATT

### Servizi standard

Il display espone almeno questi servizi:

| Servizio | UUID | Note |
|---|---:|---|
| Generic Access | `0x1800` | contiene Device Name `EKD01-BF ` |
| Device Information | `0x180a` | presenza rilevata |
| Battery | `0x180f` | presenza rilevata, ma BikeGo usa soprattutto il canale UART custom |
| Current Time | `0x1805` | espone Current Time `0x2a2b` e Local Time Information `0x2a0f`; nel log il sync orario reale avviene sul protocollo UART, non con una write standard a `0x2a2b` |

### Servizio dati custom / Nordic UART-like

Handle osservati in questa cattura:

| Handle | Direzione | UUID caratteristica | Proprietà | Uso |
|---:|---|---|---|---|
| `0x0102` | telefono -> display | `6e400002-b5a3-f393-e0a9-e50e24dcca9e` | Write, Read | comando applicativo |
| `0x0104` | display -> telefono | `6e400003-b5a3-f393-e0a9-e50e24dcca9e` | Notify | risposte, init, telemetria |
| `0x0105` | telefono -> display | CCCD di `0x0104` | Write | scrivere `01 00` per abilitare notify |

Il service UUID mostrato da Wireshark per questo blocco e' `7dfc9000-7d1c-4951-86aa-8d9728f8d66c`. Non hardcodare gli handle: su Garmin/Connect IQ si deve scoprire il servizio e cercare le caratteristiche per UUID/proprieta'.

## Sequenza di connessione

Sequenza minima osservata:

1. Connettersi a `EKD01-BF `.
2. Eseguire discovery GATT.
3. Abilitare le notifiche su `0x0104`, scrivendo `01 00` sul CCCD `0x0105`.
4. Inviare i frame init su `0x0102`.
5. Leggere le notifiche su `0x0104`.
6. Durante la sessione, aggiornare l'orario con i comandi UART indicati sotto.

## Framing applicativo

Tutti i payload applicativi osservati hanno questa struttura:

```text
55 aa LEN SRC DST OP REG DATA[LEN] CHECKSUM_LE16
```

| Campo | Byte | Significato |
|---|---:|---|
| Magic | 0..1 | sempre `55 aa` |
| `LEN` | 2 | lunghezza di `DATA`, non lunghezza totale frame |
| `SRC` | 3 | nodo logico sorgente |
| `DST` | 4 | nodo logico destinazione |
| `OP` | 5 | operazione |
| `REG` | 6 | registro/pagina/sottocomando |
| `DATA` | 7.. | `LEN` byte |
| `CHECKSUM_LE16` | ultimi 2 | complemento a uno della somma byte da `LEN` fino all'ultimo byte di `DATA`, little-endian |

Lunghezza totale frame:

```text
total_len = 9 + LEN
```

Checksum:

```text
sum = 0
for each byte in frame[2 : 7 + LEN]:
    sum += byte
checksum = (~sum) & 0xffff
append low_byte(checksum), high_byte(checksum)
```

Esempio:

```text
55 aa 15 10 11 06 01 ... 5b fe
LEN = 0x15
checksum = 0xfe5b, scritto little-endian come 5b fe
```

### Nodi logici osservati

| Nodo | Direzione/ruolo probabile |
|---:|---|
| `0x11` | telefono/app |
| `0x10` | display/controller canale realtime |
| `0xa5` | display/configurazione/modello |
| `0xf1` | blocco configurazione secondario |

### Operazioni osservate

| OP | Ruolo osservato |
|---:|---|
| `0x01` | richiesta/read breve |
| `0x02` | set/write valore a 32 bit o breve |
| `0x04` | risposta dati a richiesta `0x01` |
| `0x05` | ack a set/write |
| `0x06` | telemetria periodica |
| `0x20` | init/session blob, probabilmente autenticazione o chiave sessione |

## Init osservato

Dopo `CCCD = 01 00`, BikeGo invia questi frame su `0x0102`.

| Frame | Direzione | Payload UART | Risposta osservata | Note |
|---:|---|---|---|---|
| 46336 | app -> bike | `55 aa 01 11 10 01 00 04 d8 ff` | `55 aa 04 10 11 04 00 c9 31 f5 6b 7c fd` | richiesta stato iniziale a nodo `0x10`, registro `0x00`; risposta 4 byte non ancora mappata |
| 46342 | app -> bike | `55 aa 10 11 10 20 00 ac 8f 09 2a fb aa 90 e7 92 c9 f8 dc ff 88 6d 58 a9 f5` | `55 aa 01 10 11 20 00 00 bd ff` | blob init da 16 byte; probabile token/handshake |
| 46348 | app -> bike | `55 aa 01 11 a5 01 18 18 17 ff` | `55 aa 18 a5 11 04 18 45 4b 44 30 31 5f 43 41 4e 5f 42 46 5f 4e 32 32 00 00 00 00 00 00 00 00 b7 fa` | read modello, ASCII `EKD01_CAN_BF_N22` |
| 46376 | app -> bike | `55 aa 01 11 f1 01 01 1a e0 fe` | `55 aa 1a f1 11 04 01 00 00 55 07 00 00 0a a8 8b 8b 07 40 14 64 00 2c 01 01 02 32 00 f4 01 01 09 3c 5e fa` | blocco config secondario |
| 46402 | app -> bike | `55 aa 01 11 a5 02 e1 01 64 fe` | `55 aa 01 a5 11 05 e1 00 62 fe` | set config `a5/e1 = 01`, ack |
| 46412 | app -> bike | `55 aa 01 11 a5 01 e0 01 66 fe` | `55 aa 01 a5 11 04 e0 00 64 fe` | read config `a5/e0` |
| 46420, 46427 | app -> bike | `55 aa 01 11 a5 01 18 18 17 ff` | modello ripetuto | BikeGo ripete la lettura modello |

Per una prima implementazione, replicare almeno: abilita notify, richiesta modello, sync orario, poi ascolto telemetria. Il blob `OP=0x20` potrebbe essere richiesto dal firmware per abilitare lo stream; va mantenuto fino a prova contraria.

## Sync orario

Il display espone Current Time Service, ma nel log BikeGo aggiorna l'orario con frame UART `OP=0x02` sul nodo `0x10`.

Durante la cattura:

- UTC cattura: `2026-06-18T11:23:27Z`
- Offset locale Italia estiva: `+7200` secondi

Frame osservati:

| Frame | Payload UART | Interpretazione |
|---:|---|---|
| 46385 | `55 aa 04 11 10 02 3e 0f b9 33 6a 35 fe` | set registro `0x3e`, uint32 LE `0x6a33b90f` = UTC - 7200 s |
| 46391 | `55 aa 04 11 10 02 42 20 1c 00 00 5a ff` | set registro `0x42`, uint32 LE `7200`, offset timezone in secondi |
| 46396 | `55 aa 04 11 10 02 46 2f d5 33 6a f1 fd` | set registro `0x46`, uint32 LE `0x6a33d52f` = UTC epoch della cattura |

Ack:

| Registro | Ack |
|---:|---|
| `0x3e` | `55 aa 01 10 11 05 3e 00 9a ff` |
| `0x42` | `55 aa 01 10 11 05 42 00 96 ff` |
| `0x46` | `55 aa 01 10 11 05 46 00 92 ff` |

Implementazione suggerita:

```text
utc = current Unix epoch seconds
tz = local offset seconds, e.g. +7200 in Italy summer time
write reg 0x3e = utc - tz
write reg 0x42 = tz
write reg 0x46 = utc
```

Questa sequenza va validata in inverno/UTC+1 e su un secondo display, per capire se `0x3e` e' davvero "local-adjusted epoch" o un campo legacy.

## Telemetria realtime

Dopo init compaiono notifiche periodiche su `0x0104` con `OP=0x06`. Sono stati osservati due sottotipi:

- `REG=0x01`: frame lungo, molto probabilmente metriche realtime principali.
- `REG=0x09`: frame corto, stato/config/metriche secondarie.

### Frame `06 01`

Formato:

```text
55 aa 15 10 11 06 01 DATA[21] CHECKSUM_LE16
```

Esempio a riposo:

```text
55 aa 15 10 11 06 01
00 00 00 01 00 01 09 51 00 00 00 39 2d 00 00 37 6e 00 00 00 00
5b fe
```

Esempio durante pedalata:

```text
55 aa 15 10 11 06 01
00 00 00 01 00 01 09 51 00 1f 10 3c 2d 00 00 3a 6e 00 00 00 00
26 fe
```

Mappa byte osservata:

| Offset DATA | Tipo | Valori osservati | Campo probabile | Stato |
|---:|---|---|---|---|
| 0 | u8 | `00` | riservato/status | da validare |
| 1 | u8 | `00` | riservato/status | da validare |
| 2 | u8 | `00` | riservato/status | da validare |
| 3 | u8 | `01` | modalita'/stato display acceso | da validare |
| 4 | u8 | `00` | riservato/status | da validare |
| 5 | u8 | `01` | livello PAS/assistenza | confermato: in cattura la bici era in PAS 1 |
| 6 | u8 | `09` | pagina/profilo/unita' | da validare |
| 7 | u8 | `4e..52`, tipico `51` | batteria percentuale | confermato: `0x51 = 81%` |
| 8 | u8 | `00` | riservato/separatore | da validare |
| 9..10 | u16 LE | `0..4156` | velocita' istantanea in `0.01 km/h` | confermato dalla dinamica: picco `41.56 km/h` a ruota sollevata |
| 11..14 | u32 LE | `11577..11582` | trip/odometro parziale in `0.01 km` | confermato: circa `115.77..115.82 km` |
| 15..18 | u32 LE | `28215..28220` | odometro totale in `0.01 km` | confermato: circa `282.15..282.20 km` |
| 19..20 | bytes | `00 00` | riservato o campi non attivi | da validare |

Andamento durante la pedalata breve:

| Istante logico | Batteria | Velocita' `DATA[9..10]` | Trip `DATA[11..14]` | Odometer `DATA[15..18]` |
|---|---:|---:|---:|---:|
| riposo iniziale | 81 | `0.00 km/h` | `115.77 km` | `282.15 km` |
| avvio | 79 | `2.41 km/h` | `115.77 km` | `282.15 km` |
| accelerazione | 78..80 | `13.37..41.56 km/h` | `115.77..115.78 km` | `282.15 km` |
| rotazione stabile | 81 | `35.89..41.27 km/h` | `115.80..115.82 km` | `282.18..282.20 km` |
| arresto | 81 | `0.00 km/h` | `115.82 km` | `282.20 km` |

La scala `0.01 km/h` per la velocita' e `0.01 km` per gli odometri e' coerente con batteria/PAS/odometri confermati e con la ruota sollevata.

### Frame `06 09`

Formato:

```text
55 aa 10 10 11 06 09 DATA[16] CHECKSUM_LE16
```

Esempio:

```text
55 aa 10 10 11 06 09
07 52 00 00 c1 07 5a 11 18 01 de 03 55 00 01 05
de fc
```

Mappa byte osservata:

| Offset DATA | Tipo | Valori osservati | Campo probabile | Stato |
|---:|---|---|---|---|
| 0..1 | u16 LE | `0x51fd..0x5207` | contatore progressivo, probabilmente tick/rotazione/eventi ruota | probabile; cresce durante la rotazione e poi si ferma |
| 2..3 | u16 LE | `0` | riservato | da validare |
| 4..5 | u16 LE | `1985` | valore statico, plausibile circonferenza ruota in mm oppure parametro ruota | da validare |
| 6..7 | u16 LE | `4442` | metrica statica | da validare |
| 8..9 | u16 LE | `280` | metrica statica | da validare |
| 10..11 | u16 LE | `990` | metrica statica | da validare |
| 12 | u8 | `85` | percentuale/stato | da validare |
| 13 | u8 | `0` | riservato | da validare |
| 14 | u8 | `1` | flag | da validare |
| 15 | u8 | `5` | flag/livello | da validare |

Questo frame e' troppo stabile nella cattura per associare con certezza potenza o cadenza. Il primo u16 e' quasi certamente un contatore: passa da `0x51fd` a `0x5207`, cioe' +10, durante la rotazione e poi resta fermo. Non ha l'aspetto di una potenza in watt o di una cadenza in rpm.

## Campi utente attesi

Per una app Garmin data field, il mapping pratico consigliato e':

| Campo da mostrare/scrivere | Sorgente attuale | Fiducia |
|---|---|---|
| Batteria e-bike | `06 01` DATA[7] | alta |
| PAS/livello assistenza | `06 01` DATA[5] | alta |
| Velocita' istantanea | `06 01` DATA[9..10] u16 LE / 100 | alta |
| Trip/odometro parziale | `06 01` DATA[11..14] u32 LE / 100 km | alta |
| Odometer totale | `06 01` DATA[15..18] u32 LE / 100 km | alta |
| Contatore rotazione/tick | `06 09` DATA[0..1] u16 LE | media |
| Potenza istantanea | non identificata con certezza | bassa |
| Cadenza | non identificata con certezza | bassa |
| Velocita' media/max | non identificata con certezza nel giro da 5 s | bassa |

## Implementazione parser

Pseudo codice:

```text
onNotify(bytes):
    if len(bytes) < 9: reject
    if bytes[0] != 0x55 or bytes[1] != 0xaa: reject

    payloadLen = bytes[2]
    expectedLen = 9 + payloadLen
    if len(bytes) != expectedLen: reject

    checksumRead = bytes[expectedLen-2] | (bytes[expectedLen-1] << 8)
    checksumCalc = onesComplement16(sum(bytes[2 : expectedLen-2]))
    if checksumRead != checksumCalc: reject

    src = bytes[3]
    dst = bytes[4]
    op = bytes[5]
    reg = bytes[6]
    data = bytes[7 : 7 + payloadLen]

    if op == 0x06 and reg == 0x01:
        battery = data[7]
        speedKmh = u16le(data[9:11]) / 100.0
        tripKm = u32le(data[11:15]) / 100.0
        odometerKm = u32le(data[15:19]) / 100.0

    if op == 0x06 and reg == 0x09:
        rotationOrTickCounter = u16le(data[0:2])
```

Frame builder:

```text
buildFrame(src, dst, op, reg, data):
    out = [0x55, 0xaa, len(data), src, dst, op, reg] + data
    checksum = (~sum(out[2:])) & 0xffff
    out += [checksum & 0xff, checksum >> 8]
    return out
```

## Note per Garmin Connect IQ

Obiettivo data field:

- connettersi al display BLE;
- fare discovery delle caratteristiche UART;
- abilitare notify;
- inviare init e sync orario;
- parsare notifiche in real time;
- mostrare batteria, velocita', distanza/odometro e altri campi quando validati;
- scrivere i valori nella sessione come custom fields/data fields dove consentito da Connect IQ.

Vincoli da verificare prima dello sviluppo:

- il modello Garmin deve supportare Connect IQ BLE central/client;
- il prodotto deve poter essere pubblicato e venduto nel Garmin Connect IQ Store;
- un data field ha limiti di lifecycle/UI diversi da una app/widget: va verificato se la connessione BLE continua in modo affidabile durante l'attivita';
- testare almeno un dispositivo reale target prima di definire la lista compatibilita'.

## Catture consigliate per completare la mappa

Per assegnare con certezza potenza, cadenza, media, massimo e odometro:

1. Cattura pulita solo con BikeGo e display acceso, senza Garmin watch e notifiche iOS.
2. Annotare su video o a voce i valori mostrati da BikeGo/display ogni secondo.
3. Sessioni separate:
   - fermo 30 s;
   - ruota sollevata a velocita' bassa costante;
   - accelerazione/decelerazione;
   - cambio livello assistenza;
   - pedalata con cadenza diversa;
   - batteria nota o schermata app con percentuale/tensione;
   - reset trip/lettura odometro prima e dopo.
4. Ripetere sync orario in timezone diversa o simulando UTC+1/UTC+2 per confermare i registri `0x3e`, `0x42`, `0x46`.
