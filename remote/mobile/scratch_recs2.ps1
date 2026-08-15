$path = 'C:\Users\amine\.gemini\antigravity\brain\e7e59f3a-342c-480e-8587-104674f56d4f\.system_generated\logs\transcript.jsonl'
$lines = Get-Content $path
for ($i = 815; $i -le 821; $i++) {
    $l = $lines[$i]
    if ($l) {
        if ($l.Length -gt 9000) { $l.Substring(0, 9000) } else { $l }
        Write-Output '====='
    }
}
