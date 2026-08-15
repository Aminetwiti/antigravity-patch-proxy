$path = 'C:\Users\amine\.gemini\antigravity\brain\e7e59f3a-342c-480e-8587-104674f56d4f\.system_generated\logs\transcript.jsonl'
$lines = Get-Content $path
foreach ($line in $lines) {
    if ($line -match '"type":"USER_INPUT"') {
        $l = $line
        if ($l.Length -gt 1800) { $l.Substring(0, 1800) } else { $l }
        Write-Output '====='
    }
}
