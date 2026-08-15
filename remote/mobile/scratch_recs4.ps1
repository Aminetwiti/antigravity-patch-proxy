$path = 'C:\Users\amine\.gemini\antigravity\brain\e7e59f3a-342c-480e-8587-104674f56d4f\.system_generated\logs\transcript.jsonl'
$lines = Get-Content $path
for ($i = $lines.Length - 1; $i -ge 0; $i--) {
    $l = $lines[$i]
    if ($l -match 'Sauter en bas') {
        $snippet = $l.Substring(0, [Math]::Min(12000, $l.Length))
        Write-Output "FOUND at line $i"
        Write-Output $snippet
        Write-Output '====='
        break
    }
}
