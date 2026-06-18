# Entra Break Glass Configurator

PowerShell 7/WPF værktøj til en simpel Microsoft Graph-baseret v1 opsætning af break-glass konti.

## Hvad værktøjet gør

- Forbinder til Microsoft Graph med standard Microsoft Graph PowerShell `Connect-MgGraph`.
- Login køres direkte på WPF-værktøjets egen PowerShell/UI-runspace med `Connect-MgGraph -Scopes ... -NoWelcome`, så Microsofts eget loginvindue/account picker styrer konto- og tenantvalg.
- Før login kaldes `Disconnect-MgGraph`, Graph PowerShell cache under `$HOME\.mg` flyttes til backup under `Output`, og Graph MSAL cachefiler `mg.msal.cache*` flyttes til backup. Derefter forsøger værktøjet at deaktivere WAM-login med `Set-MgGraphOption -DisableLoginByWAM $true`, så login ikke bare genbruger den seneste Windows/WAM session.
- Efter succesfuldt Graph-login forsøger værktøjet at flytte fokus tilbage til WPF-vinduet.
- WPF-vinduet minimeres kort mens Microsoft Graph-login åbnes, så Microsofts loginvindue ikke skjules bag konfiguratoren. Efter login restore'r værktøjet WPF-vinduet.
- Discovery, plan og Phase 1a kører på WPF/UI-runspacet, fordi Microsoft Graph PowerShell i nogle tenants hænger på Graph-kald fra background-runspace. UI-status opdateres mellem hvert Graph-kald.
- Finder tenantens `*.onmicrosoft.com` domæne.
- Kontrollerer de eksakte target UPNs for to break-glass konti.
- Phase 1a opretter manglende cloud-only brugere, hvis valgt.
- Genererer stærke midlertidige passwords for nyoprettede konti.
- Viser passwords én gang i GUI'en.
- Opretter eller genbruger security group `CA-BreakGlass-Exclude`.
- Tilføjer kontiene til gruppen, hvis valgt.
- Kan deaktivere administrator-SSPR tenant-wide, hvis valgt. Ændringen kan tage op til 60 minutter.
- Phase 1a opretter Temporary Access Pass for begge konti med `one-time use = No` og `duration = 2 hours` før Global Administrator rollen tildeles.
- Phase 1a sikrer at FIDO2/passkey Authentication Method policy er enabled og inkluderer `CA-BreakGlass-Exclude`, så kontiene kan registrere security keys under Phase 1b.
- Phase 1a ekskluderer `CA-BreakGlass-Exclude` fra Authentication Methods registration campaign, så break-glass kontiene ikke bliver nudged til Authenticator/passkey onboarding ud over den kontrollerede FIDO2-proces.
- Tildeler begge break-glass konti direkte `Global Administrator` på tenant scope (`/`).
- Phase 1a kan ekskludere gruppen fra eksisterende Conditional Access-politikker.
- Phase 1b er manuel: konsulenten logger ind med TAP og registrerer to FIDO2 security keys pr. konto.
- Phase 2 understøtter et FIDO2 pre-provision source-flow: indtast UPN på en kildebruger, der allerede har registreret den fysiske FIDO2/passkey model, hent AAGUID fra den bruger, og brug AAGUID'en i `BreakGlass-FIDO2` authentication strength.
- Phase 2 refresher også break-glass kontiene, henter eventuelle AAGUIDs fra deres registrerede FIDO2/passkey methods og kan slette TAP.
- Phase 2 opretter/opdaterer custom authentication strength `BreakGlass-FIDO2` med FIDO2 og tilladte AAGUIDs.
- Phase 2 opretter en dedikeret Conditional Access-politik, der kræver `BreakGlass-FIDO2` for de to break-glass konti. Politikken oprettes som `disabled`.
- Backupper CA policies før valgfri patching.
- Genererer `plan.json`, `result.json`, `handoff.html` og `app.log`.

## Hvad værktøjet ikke gør

Det bruger ikke Azure login, Az-moduler, PIM, RMAU, Log Analytics, Azure Monitor, Sentinel, Intune, app registrations, service principals eller cleanup/delete workflows.

Værktøjet kan ikke attach'e en allerede pre-registreret fysisk FIDO2/passkey direkte til en anden bruger. Microsoft Graph FIDO2 create-flow kræver en WebAuthn registration ceremony og Microsoft dokumenterer, at provisioning af pre-registered passkeys ikke er understøttet. Det understøttede flow i dette værktøj er derfor at bruge en pre-provision/kildebruger til at hente AAGUID, som derefter enforce'es via authentication strength.

## Hvorfor kun Microsoft Graph

Version 1 skal være enkel, testbar og egnet til almindelige Microsoft 365 tenants uden Entra ID P2. Derfor bruges kun Microsoft Graph delegated permissions til bruger-, gruppe- og Conditional Access-opgaver.

## Kørsel

Kompilér fra source:

```powershell
Set-Location ".\Entra-BreakGlass"
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
- `UserAuthenticationMethod.ReadWrite.All`
- `UserAuthMethod-TAP.ReadWrite.All`
- `RoleManagement.ReadWrite.Directory`
- `Policy.Read.All`
- `Policy.ReadWrite.AuthenticationMethod`
- `Policy.ReadWrite.Authorization`
- `Policy.ReadWrite.ConditionalAccess`

Admin consent kan være nødvendig i kundens tenant.

## Krævede roller

Den indloggede konto skal have rettigheder til at oprette brugere/grupper, tildele directory roles, oprette Temporary Access Pass, læse FIDO2 authentication methods, læse/opdatere authentication strengths, læse/opdatere authorization policy hvis Admin SSPR deaktiveres og, hvis CA vælges, læse og opdatere Conditional Access-politikker.

Microsoft Graph kræver delegated scope `UserAuthMethod-TAP.ReadWrite.All` med admin consent samt `Authentication Administrator` eller `Privileged Authentication Administrator` for at oprette Temporary Access Pass på andre brugere. Hvis target-kontiene allerede har en privilegeret administratorrolle, skal operatoren typisk bruge `Privileged Authentication Administrator`. Phase 1a pre-checker dette før ændringer. Nye Phase 1a-runs opretter TAP før Global Administrator rollen tildeles.

## Password og TAP-håndtering

Passwords genereres kun for nyoprettede konti. Eksisterende konti genbruges uden password reset.

Passwords og TAP-koder:

- vises én gang i GUI'en
- skrives ikke til log
- skrives ikke til `plan.json`
- skrives ikke til `result.json`
- TAP-koder kan skrives til `handoff.html`, som markeres `CONFIDENTIAL`, så konsulenten kan gennemføre Phase 1b

## Conditional Access advarsel

Den dedikerede BreakGlass FIDO2 CA-policy oprettes som `disabled`. Sæt den først til enabled, når begge break-glass konti har registreret og testet de ønskede FIDO2 keys.

CA exclusion patching er valgfri og slået til som standard i Phase 1. Hvis funktionen vælges, backuppes policies til `ca-policies-before.json`, og værktøjet tilføjer kun gruppens object ID til `conditions.users.excludeGroups`. Eksisterende exclusions og øvrige policy-indstillinger bevares.

## Handoff dokument

`handoff.html` indeholder tenant, konti, Global Administrator rolle assignments, Admin SSPR status, TAP-status, gruppemedlemskab, CA exclusion status, policy backup path, authentication strength, dedikeret CA-policy, warnings/errors og manuelle næste steps. Det kan indeholde TAP-koder fra Phase 1 og skal behandles som confidential.

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
