$path = 'C:\Users\amine\.gemini\antigravity\brain\e7e59f3a-342c-480e-8587-104674f56d4f\.system_generated\logs\transcript.jsonl'
$lines = Get-Content $path
foreach ($line in $lines) {
    if ($line -match 'Sauter en bas|sauter en bas|Recommandations|recommandations propos|P0-1|priorit') {
        if ($line -match '"type":"PLANNER_RESPONSE"') {
            $l = $line
            if ($l.Length -gt 10000) { $l.Substring(0, 10000) } else { $l }
            Write-Output '====='
        }
    }
}
