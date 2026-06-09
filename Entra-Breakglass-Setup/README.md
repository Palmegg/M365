# NetIP Entra Break Glass Configurator

Version 1 af et PowerShell 7/WPF-værktøj til konsulentvenlig opsætning og dokumentation af en Microsoft Entra break-glass baseline.

Værktøjet er designet til at være sikkert, idempotent og egnet til lab-test mod en rigtig tenant. Det bruger Microsoft Graph PowerShell, Microsoft Graph REST via `Invoke-MgGraphRequest`, Az PowerShell og ARM REST. Det bruger ikke `AzureAD` eller `MSOnline`.

## Formål

Scriptet hjælper med at konfigurere og validere:

- To cloud-only break-glass konti på tenantens `*.onmicrosoft.com` domæne.
- Role-assignable sikkerhedsgruppe til break-glass kontiene.
- Gruppemedlemskab for begge konti.
- Permanent Global Administrator assignment til den role-assignable break-glass gruppe.
- Restricted Management Administrative Unit, RMAU, som beskytter break-glass konti og gruppen.
- Separat role-assignable RMAU administratorgruppe med scoped User Administrator og Groups Administrator roller på RMAU'en.
- Custom authentication strength til FIDO2, valgfrit begrænset med AAGUIDs.
- Dedikeret Conditional Access policy, som kræver authentication strength for gruppen.
- Valgfri opt-in exclusion af break-glass gruppen fra eksisterende Conditional Access policies.
- Entra diagnostic settings til Log Analytics.
- Azure Monitor scheduled query alerts og action group.
- Manuel FIDO2 guidance og efterfølgende validering.
- HTML- og JSON-rapport.

## Krav

- Windows.
- PowerShell 7 x64.
- WPF kræver STA. Scriptet relancerer automatisk i `pwsh.exe -STA`, hvis det startes uden STA eller fra Windows PowerShell.
- Internetadgang til Microsoft Graph, Azure Resource Manager og PowerShell Gallery, hvis moduler skal installeres.
- Delegated interactive sign-in. Version 1 bruger ikke app-only authentication, client secrets eller certifikatbaseret automation.

Scriptet tjekker disse moduler og kan installere dem for `CurrentUser` efter eksplicit bekræftelse:

- `Microsoft.Graph.Authentication`
- `Microsoft.Graph.Users`
- `Microsoft.Graph.Groups`
- `Microsoft.Graph.Identity.DirectoryManagement`
- `Microsoft.Graph.Identity.SignIns`
- `Az.Accounts`
- `Az.Resources`
- `Az.OperationalInsights`
- `Az.Monitor`

## Nødvendige Microsoft Entra roller

Den indloggede operator skal have roller/rettigheder nok til at oprette brugere, grupper, CA policies, authentication strength policies, directory role assignments og administrative units.

Typisk kræves en kombination af:

- Global Administrator
- Privileged Role Administrator
- Conditional Access Administrator
- Authentication Policy Administrator
- User Administrator eller tilsvarende rettigheder

Scriptet bruger ikke PIM. Det tildeler Global Administrator permanent til den role-assignable break-glass gruppe og tildeler RMAU-scopede roller til en separat administratorgruppe.

## Nødvendige Azure roller

Hvis Azure Monitor/Log Analytics skal konfigureres, kræves rettigheder i den valgte subscription, typisk:

- Contributor eller Owner på target resource group/subscription.
- Monitoring Contributor kan være nødvendig for alert rules/action groups.
- Log Analytics Contributor kan være nødvendig for workspace-konfiguration.

Hvis monitoring slås fra i GUI'en, bruges Azure-delen ikke.

## Graph permissions/scopes

Scriptet requester disse delegated Graph scopes:

- `User.ReadWrite.All`
- `Group.ReadWrite.All`
- `Directory.ReadWrite.All`
- `RoleManagement.ReadWrite.Directory`
- `Policy.Read.All`
- `Policy.ReadWrite.ConditionalAccess`
- `Policy.ReadWrite.AuthenticationMethod`
- `UserAuthenticationMethod.Read.All`
- `Organization.Read.All`

Admin consent kan være nødvendig i kundens tenant.

## Sådan køres scriptet

Åbn en almindelig PowerShell 7 x64 konsol og kør:

```powershell
Set-Location "C:\Users\jop\OneDrive - netIP\Dokumenter\GitHub\M365\Entra-Breakglass-Setup"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\BreakGlassConfigurator.ps1
```

Du kan også starte den direkte med STA:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -STA -File .\BreakGlassConfigurator.ps1
```

Kør ikke første login/modulinstallation fra VS Code PowerShell Extension Terminal. WPF, Microsoft Graph interactive login og PowerShell Editor Services kan få VS Code extension-terminalen til at lukke. Brug en separat PowerShell 7 konsol.

Connect-knapperne starter en separat synlig PowerShell 7 connection-worker til Graph/Azure login. Det beskytter WPF GUI-processen, hvis Microsoft Graph/WAM-login crasher eller lukker PowerShell-processen.

Hvis moduler mangler, eller hvis Microsoft Graph delmoduler er installeret i blandede versioner, spørger connection-worker-vinduet om installation/opdatering for `CurrentUser`. Godkend installationen i worker-vinduet, vent til den er færdig, og gå derefter tilbage til GUI'en. Statusbaren i GUI'en viser seneste worker-status.

Graph-moduler skal være version-aligned. En blanding som `Microsoft.Graph.Authentication` 2.37 og `Microsoft.Graph.Groups` 2.31 kan give fejl som `AzureIdentityAccessTokenProvider..ctor method not found`.

Hvis `PackageManagement`/`NuGet` bootstrap fejler, forsøger worker'en at importere `PackageManagement` og `PowerShellGet` eksplicit og fortsætter med `Install-Module`, hvor det er muligt.

Til lab uden tenant-ændringer:

```powershell
.\BreakGlassConfigurator.ps1 -Mock
```

Til plan/report uden apply er `Dry-run/NoApply` slået til som standard i GUI'en. Fjern først fluebenet, når planen er gennemgået og du vil foretage ændringer.

## Wizard-flow

1. Gennemgå velkomst og sikkerhedsbekræftelse.
2. Tryk `Fortsæt` for at gå videre. Senere trin er låst, indtil de tidligere trin er gennemført.
3. Brug `Forbind til Graph + Azure` for samlet sign-in. Graph er påkrævet; Azure bruges kun til Log Analytics/Azure Monitor.
4. Hvis Azure ikke kan forbindes, kan du vælge at fortsætte uden Azure Monitor/Log Analytics for den aktuelle kørsel.
5. Kør pre-check.
6. Udfyld konfiguration.
7. Byg dry-run plan og eksporter den efter behov.
8. Apply configuration.
9. Registrer FIDO2/FIDO keys manuelt for begge konti.
10. Kør FIDO2-validering og endelig validering.
11. Åbn outputmappen og gennemgå rapporterne.

## Output

Hver kørsel skriver til:

```text
.\Output\BreakGlassConfig-<TenantId>-<yyyyMMdd-HHmmss>\
```

Mappen kan indeholde:

- `plan.json`
- `result.json`
- `report.html`
- `app.log`
- Conditional Access backups, hvis eksisterende policies patches.

Adgangskoder, tokens og secrets skrives ikke til log, JSON eller HTML-rapport.

## Manuel FIDO2 opsætning

Version 1 automatiserer ikke FIDO2/FIDO key enrollment. Konsulenten skal manuelt:

- Registrere en separat FIDO2/FIDO key for hver konto.
- Sikre at hver key er unik og fysisk adskilt.
- Følge kundens godkendte nødprocedure for opbevaring.
- Teste login for hver konto.
- Køre FIDO2-validering i værktøjet efter enrollment.

## Kendte begrænsninger

- Ingen Sentinel eller SentinelOne integration i version 1.
- Ingen PIM-konfiguration i version 1. PIM kræver Entra ID P2 eller Entra ID Governance og bruges ikke i standarddesignet.
- Ingen automatisk rollback.
- FIDO2 enrollment, PIN, fysisk key-håndtering og password manager-processer er manuelle.
- Authentication strength og enkelte diagnostic setting endpoints kan ændre sig i Graph/Azure. Scriptet logger fejl pænt og fortsætter hvor det er sikkert.
- Worker-processen kan vise separat Graph/Azure login, fordi PowerShell auth-kontekst ikke sikkert kan flyttes mellem processer.

## Foreslået lab-test

1. Start i `-Mock` mode og gennemgå hele GUI'en.
2. Kør i en testtenant med `Dry-run/NoApply` slået til.
3. Gennemgå `plan.json` og `report.html`.
4. Kør apply med CA policy state `reportOnly`.
5. Bekræft brugere, break-glass gruppe, GA assignment på gruppen, RMAU, RMAU admin-gruppe og CA policy i Entra admin center.
6. Registrer FIDO2 keys manuelt.
7. Kør FIDO2-validering.
8. Test sign-in alerts og audit/change alerts.
9. Skift først CA policy til `enabled`, når rapport og manuelle tests er godkendt.
