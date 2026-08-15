$path = 'C:\Users\amine\.gemini\antigravity\brain\e7e59f3a-342c-480e-8587-104674f56d4f\.system_generated\logs\transcript.jsonl'
$lines = Get-Content $path
$start = 818
$end = 822
for ($i = $start; $i -le $end; $i++) {
    $l = $lines[$i]
    if ($l -and $l.Length -gt 6000) { $l.Substring(0, 6000) } else { $l }
    Write-Output '====='
}
