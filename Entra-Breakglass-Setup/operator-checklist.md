# Operator Checklist

## Før kørsel

- Bekræft at kunden har godkendt break-glass designet.
- Aktiver relevante PIM-roller for operatoren.
- Aftal navngivning for konti, gruppe, RMAU, CA policy og monitoring.
- Aftal hvor FIDO2 keys og credentials skal opbevares.
- Aftal hvem der skal modtage Azure Monitor alerts.

## Under kørsel

- Kør først `Dry-run/NoApply`.
- Gennemgå `plan.json`.
- Kør apply med Conditional Access state `reportOnly`.
- Patch kun eksisterende CA policies, hvis kunden eksplicit har godkendt det.
- Gem outputmappen efter kundens dokumentationskrav.

## Efter kørsel

- Registrer en separat FIDO2/FIDO key for hver break-glass konto.
- Kør FIDO2-validering i værktøjet.
- Bekræft Global Administrator assignments.
- Bekræft gruppemedlemskab.
- Bekræft RMAU medlemskab.
- Bekræft Log Analytics diagnostic settings.
- Bekræft sign-in alert.
- Bekræft audit/change alert.
- Test login for begge konti.
- Flyt credentials til godkendt password manager eller fysisk nødprocedure.
- Fjern lokale kopier af midlertidige passwords, hvis de er noteret manuelt.

## Periodisk drift

- Test kontiene efter kundens faste kontrolinterval.
- Verificer at FIDO2 keys stadig findes og er fysisk tilgængelige.
- Verificer at alerting stadig virker.
- Brug aldrig kontiene til daglig administration.
