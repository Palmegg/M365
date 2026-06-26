# GetOrganized – Intune Win32 deployment

MSI-baseret udrulning af **GetOrganized** via Microsoft Intune (Win32-app).
Pakken indeholder en installer og en detection-script, der begge er versions-styret
ud fra MSI'ens `ProductVersion`.

## Indhold / mappestruktur

Installeren forventer, at MSI'en ligger i en **undermappe der hedder det samme som versionen**:

```
Getorganized/
├── MainInstaller.ps1          # Installerer/opgraderer MSI
├── MainDetector.ps1           # Intune detection rule
├── README.md
└── 6.33.0712/                 # Versionsmappe (= $VersionFolder)
    └── setup.msi              # = $MsiName
```

> ⚠️ Versionsmappen og `setup.msi` er **ikke** i git (binær). De skal lægges i mappen
> manuelt, før der pakkes en `.intunewin`.

## Sådan virker det

- **MainInstaller.ps1**
  1. Finder MSI'en i versionsmappen (`<ScriptRoot>\<VersionFolder>\setup.msi`).
  2. Læser `ProductVersion` + `ProductCode` direkte fra MSI'en.
  3. Læser den aktuelt installerede version fra registry (Uninstall-nøgler, matcher `DisplayName` på "GetOrganized").
  4. Sammenligner versioner:
     - Samme version → springer over (gør intet).
     - Forskellig / ikke installeret → kører `msiexec /i` (in-place upgrade).
  5. Accepterede exit codes: `0` (ok), `3010` (ok, kræver genstart), `1638` (anden version findes – accepteret).
- **MainDetector.ps1**
  Læser installeret version fra registry og sammenligner med `$ExpectedVersion`.
  Match → exit 0 (detected). Ellers → exit 1 (not detected → Intune geninstallerer).

Logning sker i `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\#GetOrganized.log`
plus en detaljeret MSI-log pr. installation (`GetOrganized-MSI-Install-<timestamp>.log`).

---

## Flow: opgradering til en ny version

Det er **versions-numrene i scripts + versionsmappen** der styrer det hele. Detection
fejler, så snart en maskine ikke har præcis `$ExpectedVersion`, hvorefter Intune kører
installeren, som laver en in-place MSI-upgrade.

1. **Hent den nye MSI** og find dens version (fx via *Get-MsiProductVersion* eller højreklik → detaljer).
   Eksempel: ny version `6.34.0101`.

2. **Opret en ny versionsmappe** ved siden af scripts og læg MSI'en ind som `setup.msi`:
   ```
   Getorganized/6.34.0101/setup.msi
   ```
   (Behold evt. den gamle mappe – kun den, scripts peger på, bruges.)

3. **Opdater versionsnummeret i begge scripts:**

   `MainInstaller.ps1`
   ```powershell
   [string]$TargetVersion   = "6.34.0101"
   [string]$VersionFolder   = "6.34.0101"
   ```
   `MainDetector.ps1`
   ```powershell
   [string]$ExpectedVersion = "6.34.0101"
   ```
   > Vigtigt: `$VersionFolder` SKAL matche mappenavnet, og `$ExpectedVersion` (detector)
   > SKAL matche MSI'ens reelle `ProductVersion` (den som står i registry efter installation),
   > ellers vil detection aldrig blive grøn.

4. **Pak en ny `.intunewin`** med Microsoft Win32 Content Prep Tool
   (`-s MainInstaller.ps1` som setup-fil, så HELE mappen inkl. versionsmappen kommer med):
   ```powershell
   IntuneWinAppUtil.exe -c "C:\...\Application deployments\Getorganized" -s "MainInstaller.ps1" -o "C:\Output"
   ```

5. **Opdater app'en i Intune** (Apps → Windows → GetOrganized):
   - Erstat pakken: **Properties → App package file → Upload** den nye `.intunewin`.
   - Sæt **App version** til den nye version (kosmetisk).
   - Behold install/uninstall/detection-kommandoerne (se nedenfor) – de ændrer sig ikke.

6. **Deploy.** Klienterne kører detection → finder gammel version → mismatch → installer kører
   in-place upgrade → detection grøn på næste tjek.

> Intune-udrulning af samme app-objekt erstatter automatisk den gamle version, så du behøver
> ikke lave en ny app eller en separat uninstall først.

---

## Intune-kommandoer

### Install command
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File MainInstaller.ps1
```

### Uninstall command
Pakken har ikke et dedikeret uninstall-script – brug MSI-produktkoden. Find `ProductCode`
i MSI'en (logges af installeren) og brug den:
```
msiexec.exe /x {PRODUCT-CODE-GUID} /qn /norestart
```
Alternativt, en script-baseret uninstall der finder produktet i registry:
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' | ForEach-Object { $p=Get-ItemProperty $_.PSPath; if ($p.DisplayName -match 'GetOrganized') { Start-Process msiexec.exe -ArgumentList ('/x ' + $p.PSChildName + ' /qn /norestart') -Wait } }"
```

### Detection rule
- **Rule type:** Use a custom detection script
- **Script file:** Upload `MainDetector.ps1`
- **Run script as 32-bit:** No
- **Enforce signature check:** No

---

## Parametre

### MainInstaller.ps1
| Variabel | Standard | Beskrivelse |
|----------|----------|-------------|
| `$TargetVersion` | `6.33.0712` | Mål-version (reference/log) |
| `$VersionFolder` | `6.33.0712` | **Skal matche undermappens navn** med MSI'en |
| `$MsiName` | `setup.msi` | Filnavn på MSI i versionsmappen |
| `$Prefix` / `$ProductName` | `GetOrganized` | Bruges til log/registry-matchning |

### MainDetector.ps1
| Variabel | Standard | Beskrivelse |
|----------|----------|-------------|
| `$ExpectedVersion` | `6.33.0712` | **Skal matche MSI'ens `ProductVersion`** (som vist i registry) |
| `$Prefix` / `$ProductName` | `GetOrganized` | Log/registry-matchning |

---

## Fejlfinding

- **Detection bliver aldrig grøn:** `$ExpectedVersion` matcher ikke `DisplayVersion` i registry.
  Installér manuelt og tjek `HKLM:\SOFTWARE\...\Uninstall\*` for den faktiske version,
  og sæt `$ExpectedVersion` til præcis den værdi.
- **"Version folder not found":** `$VersionFolder` matcher ikke mappenavnet, eller mappen
  blev ikke pakket med i `.intunewin` (sørg for at pakke hele mappen).
- **Installer-log:** `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\#GetOrganized.log`
  og `GetOrganized-MSI-Install-<timestamp>.log` i samme mappe.
</content>
</invoke>
