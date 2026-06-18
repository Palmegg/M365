# Entra Break Glass Configurator

PowerShell 7/WPF værktøj til en simpel Microsoft Graph-baseret v1 opsætning af break-glass konti.

## Hvad værktøjet gør

- Forbinder til Microsoft Graph med delegated interactive sign-in.
- Finder tenantens `*.onmicrosoft.com` domæne.
- Kontrollerer de eksakte target UPNs for to break-glass konti.
- Opretter manglende cloud-only brugere, hvis valgt.
- Genererer stærke midlertidige passwords for nyoprettede konti.
- Viser passwords én gang i GUI'en.
- Opretter eller genbruger security group `CA-BreakGlass-Exclude`.
- Tilføjer kontiene til gruppen, hvis valgt.
- Tildeler begge break-glass konti direkte `Global Administrator` på tenant scope (`/`).
- Kan deaktivere administrator-SSPR tenant-wide, hvis valgt. Dette kan ikke begrænses til kun de to break-glass konti.
- Kan hente AAGUID fra en allerede registreret FIDO2/passkey på en valgt bruger.
- Kan oprette/opdatere custom authentication strength `BreakGlass-FIDO2` med FIDO2 og tilladte AAGUIDs.
- Kan oprette en dedikeret Conditional Access-politik, der kræver `BreakGlass-FIDO2` for `CA-BreakGlass-Exclude`.
- Kan valgfrit ekskludere gruppen fra eksisterende Conditional Access-politikker.
- Backupper CA policies før valgfri patching.
- Genererer `plan.json`, `result.json`, `handoff.html` og `app.log`.

## Hvad værktøjet ikke gør

Det bruger ikke Azure login, Az-moduler, PIM, RMAU, Log Analytics, Azure Monitor, Sentinel, Intune, app registrations, service principals eller cleanup/delete workflows.

## Hvorfor kun Microsoft Graph

Version 1 skal være enkel, testbar og egnet til almindelige Microsoft 365 tenants uden Entra ID P2. Derfor bruges kun Microsoft Graph delegated permissions til bruger-, gruppe- og Conditional Access-opgaver.

## Kørsel

Kompilér fra source:

```powershell
Set-Location "C:\Users\jop\OneDrive - netIP\Dokumenter\GitHub\M365\NetIP-BreakGlass"
.\Compile.ps1
```

Kør compiled version:

```powershell
.\BreakGlassConfigurator.ps1
```

Kompilér og kør direkte:

```powershell
.\Compile.ps1 -Run
```

Mock mode uden Graph:

```powershell
.\BreakGlassConfigurator.ps1 -Mock
```

## Graph permissions

Default scopes ligger i `config/graphScopes.json`:

- `User.ReadWrite.All`
- `Group.ReadWrite.All`
- `Directory.Read.All`
- `Organization.Read.All`
- `UserAuthenticationMethod.Read.All`
- `RoleManagement.ReadWrite.Directory`
- `Policy.Read.All`
- `Policy.ReadWrite.AuthenticationMethod`
- `Policy.ReadWrite.Authorization`
- `Policy.ReadWrite.ConditionalAccess`

Admin consent kan være nødvendig i kundens tenant.

## Krævede roller

Den indloggede konto skal have rettigheder til at oprette brugere/grupper, tildele directory roles, læse FIDO2 authentication methods, læse/opdatere authentication strengths, læse/opdatere authorization policy hvis Admin SSPR deaktiveres og, hvis CA vælges, læse og opdatere Conditional Access-politikker. Typisk kræves Global Administrator eller en kombination med Privileged Role Administrator, Authentication Administrator, Security Administrator, User Administrator, Groups Administrator og Conditional Access Administrator.

## Password-håndtering

Passwords genereres kun for nyoprettede konti. Eksisterende konti genbruges uden password reset.

Passwords:

- vises én gang i GUI'en
- skrives ikke til log
- skrives ikke til `plan.json`
- skrives ikke til `result.json`
- skrives ikke til `handoff.html`

## Conditional Access advarsel

Den dedikerede BreakGlass FIDO2 CA-policy oprettes som report-only som standard. Sæt den først til enabled, når begge break-glass konti har registreret og testet de ønskede FIDO2 keys.

CA exclusion patching er valgfri og slået fra som standard. Hvis funktionen vælges, backuppes policies til `ca-policies-before.json`, og værktøjet tilføjer kun gruppens object ID til `conditions.users.excludeGroups`. Eksisterende exclusions og øvrige policy-indstillinger bevares.

## Handoff dokument

`handoff.html` indeholder tenant, konti, Global Administrator rolle assignments, Admin SSPR status, gruppemedlemskab, CA exclusion status, policy backup path, warnings/errors og manuelle næste steps. Det indeholder ikke passwords eller tokens.

## Arkitektur

Projektet er modulært:

- `scripts/start.ps1`
- `scripts/main.ps1`
- `functions/private`
- `functions/public`
- `config/*.json`
- `xaml/inputXML.xaml`
- `Compile.ps1`

`BreakGlassConfigurator.ps1` er genereret output og må ikke redigeres direkte.

Arkitekturen er inspireret af ChrisTitusTech/winutil, som er MIT-licenseret. Se `docs/NOTICE.md`.
