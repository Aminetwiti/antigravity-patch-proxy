$path = 'C:\Users\amine\.gemini\antigravity\brain\e7e59f3a-342c-480e-8587-104674f56d4f\.system_generated\logs\transcript.jsonl'
$lines = Get-Content $path
foreach ($line in $lines) {
    if ($line -match 'Sauter en bas' -and $line -match 'content') {
        $start = $line.IndexOf('"content":"')
        if ($start -ge 0) {
            $snippet = $line.Substring($start, [Math]::Min(14000, $line.Length - $start))
            Write-Output $snippet
            Write-Output '====='
            break
        }
    }
}
