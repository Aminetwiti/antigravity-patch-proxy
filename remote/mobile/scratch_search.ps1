$path = 'C:\Users\amine\.gemini\antigravity\brain\e7e59f3a-342c-480e-8587-104674f56d4f\.system_generated\logs\transcript.jsonl'
$matches = Select-String -Path $path -Pattern 'Sauter en bas','recommandation','slash','Recommandation'
$matches | Select-Object -Last 6 | ForEach-Object {
    $l = $_.Line
    if ($l.Length -gt 2500) { $l.Substring(0, 2500) } else { $l }
    Write-Output '-----'
}
