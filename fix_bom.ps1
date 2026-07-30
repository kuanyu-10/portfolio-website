$bytes = [System.IO.File]::ReadAllBytes('.\scripts\workflow\common.ps1')
if ($bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191) {
    $content = [System.IO.File]::ReadAllText('.\scripts\workflow\common.ps1', [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText('.\scripts\workflow\common.ps1', $content, [System.Text.Encoding]::UTF8)
}
