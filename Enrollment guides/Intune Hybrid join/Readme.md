# Windows 11 Hybrid Azure AD Join + Intune Enrollment Guide

> Audience: IT personnel preparing and enrolling a new (or repurposed) Windows 11 laptop into On-Prem Active Directory (AD) and Microsoft Intune (Hybrid Azure AD Join scenario).
>
> Goal: Clean install Windows 11, join on-prem AD, enable Hybrid Azure AD Join, register device in Intune, and verify compliance.

---

## Table of Contents

- [Windows 11 Hybrid Azure AD Join + Intune Enrollment Guide](#windows-11-hybrid-azure-ad-join--intune-enrollment-guide)
  - [Table of Contents](#table-of-contents)
  - [Prerequisites Checklist](#prerequisites-checklist)
  - [Prepare Installation Media](#prepare-installation-media)
  - [Clean Install Windows 11](#clean-install-windows-11)
  - [(Optional) Windows Autopilot Pre-Provision (White Glove)](#optional-windows-autopilot-pre-provision-white-glove)
    - [Completion](#completion)

---

## Prerequisites Checklist

| Item                  | Description                                                           | Verified |
| --------------------- | --------------------------------------------------------------------- | -------- |
| Installation USB      | Latest Windows 11 image (22H2/23H2 or newer)                          | ☐        |
| Network Access        | Able to reach Domain Controllers + Internet + Azure endpoints         | ☐        |
| Domain Credentials    | AD account with rights to join computers (or delegated OU permission) | ☐        |
| Device Object Cleanup | Old computer account for same hostname removed/disabled               | ☐        |
| AD Connect Sync       | Azure AD Connect running & healthy (Hybrid Join enabled)              | ☐        |
| Intune Licensing      | User has appropriate Intune / EMS / M365 license                      | ☐        |
| GPO / SCP Config      | Service Connection Point (SCP) configured for Hybrid Join             | ☐        |
| Naming Convention     | Decide final computer name (if not auto-generated)                    | ☐        |

> Tip: Print or export this checklist before going onsite.

---

## Prepare Installation Media

1. Download latest Windows 11 ISO from official source (VLSC / MS Endpoint / MS Download).
2. Use the Media Creation Tool or Rufus (GPT + UEFI) to create a bootable USB.
3. Safely eject and label it clearly.

---

## Clean Install Windows 11

Boot from the Windows 11 USB. Follow the language/region prompts.

![Choose Locale](./images/ChooseLocale.png)

When you reach the partition selection screen:

1. Select each existing OS / data partition and click **Delete** until only **Unallocated space** remains.
2. DO NOT delete:
   - Your USB installation media
   - OEM recovery partitions (if you intentionally want to keep them)
3. You should end with one line: **Drive 0 Unallocated Space**.

![Delete Partitions](./images/DeletePartitions.png)

Select the unallocated space and click **Next**.

![Choose Partition](./images/ChoosePartition.png)

Windows will now copy files, install features, and reboot several times. No action needed until the Out-of-Box Experience (OOBE) reappears.

---

## (Optional) Windows Autopilot Pre-Provision (White Glove)

After the device has rebooted several times and OOBE starts again:

1. Choose/confirm your preferred **language** and **keyboard layout(s)**.
2. When you reach the screen **"Let's name your device"**, click **Skip for now**.

![Skip Device Rename](./images/SkipDeviceRename.png)

3. Continue until you see **"Set up for work or school"** (wording can vary slightly such as _Configure for work/school or private account_).
4. Press the **Windows key 5 times** in quick succession. This launches the **Pre-provisioning (Autopilot) environment**.

![Enter Pre-Provisioning](./images/PreProvisioning2.png)

5. Select **"Pre-provision with Windows Autopilot"**.
6. Click **Next** to start the pre-provision workflow.

![Pre-Provisioning Progress](./images/PreProvisioning3.png)


### Completion

When the process reports **Success**, click **Reseal**. The device reboots back to the ready state and is now prepared for handoff to the end user (user phase sign-in will be faster because core provisioning already ran).

> If failure occurs, photograph/log the error details before exiting. Common causes: missing assignment, network restrictions, or required app install failure.

---
