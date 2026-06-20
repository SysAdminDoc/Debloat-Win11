# Medical Imaging Preset - Optimized for DICOM/PACS workstations
# Preserves: Office (if licensed), critical system components
# Adds: Medical imaging Defender exclusions, DICOM firewall rules, vendor bookmarks
# Usage: .\Debloat-Win11.ps1 -ConfigPath .\presets\medical.psd1

@{
    DefenderExclusions = @(
        "C:\images",
        "C:\MTU",
        "C:\Maven",
        "C:\Program Files\Voyance",
        "C:\Program Files\VPACS",
        "C:\Program Files\Minipacs",
        "C:\ProgramData\Voyance",
        "C:\ProgramData\VPACS",
        "C:\ProgramData\Minipacs",
        "C:\drtech",
        "C:\ecali1"
    )

    EdgeBookmarks = @(
        @{ name = "Support"; url = "https://www.mavenimaging.com/support" }
        @{ name = "Patient Image"; url = "https://app.patientimage.ai/login" }
        @{ name = "Google"; url = "https://www.google.com" }
    )
}
