# Operator checklist

1. Start værktøjet fra PowerShell 7.
2. Gennemgå velkomst og sæt sikkerhedsbekræftelsen.
3. Forbind til Microsoft Graph.
4. Bekræft tenant navn, tenant ID og `.onmicrosoft.com` domæne.
5. Kør discovery.
6. Udfyld eller bekræft display names og UPN prefixes.
7. Vurder om CA exclusion patching skal vælges.
8. Generér plan og gennemgå alle ændringer.
9. Kør Udfør, hvis planen er korrekt.
10. Kopiér de viste passwords til godkendt password manager eller nødprocedure.
11. Åbn `handoff.html`.
12. Verificér i Entra admin center:
    - begge konti findes
    - begge konti er medlem af `CA-BreakGlass-Exclude`
    - CA exclusions er sat, hvis funktionen blev valgt
13. Tildel administratorroller manuelt efter kundens break-glass procedure.
14. Konfigurer MFA/FIDO2/passkey manuelt, hvis det indgår i kundens standard.
15. Test login og dokumentér hvor credentials opbevares.
