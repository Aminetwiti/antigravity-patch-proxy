$path = 'C:\Users\amine\.gemini\antigravity\brain\e7e59f3a-342c-480e-8587-104674f56d4f\.system_generated\logs\transcript.jsonl'
$lines = Get-Content $path
# Find the MODEL response right after the recommendations user request (step 819)
for ($i = 820; $i -lt 830; $i++) {
    $l = $lines[$i]
    if ($l) {
        if ($l.Length -gt 8000) { $l.Substring(0, 8000) } else { $l }
        Write-Output '====='
    }
}
