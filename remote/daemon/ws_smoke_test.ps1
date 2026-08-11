# Smoke test : envoie send_prompt au daemon local et affiche les messages
# jusqu'a stream_end (verifie l'outcome structure pour la notification mobile).
param(
    [string]$Uri = 'ws://127.0.0.1:8090/ws?token=demo123'
)

Add-Type -AssemblyName System.Net.WebSockets.Client

$ws = [System.Net.WebSockets.ClientWebSocket]::new()
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync([Uri]$Uri, $ct).Wait()
Write-Host "WS_STATE=$($ws.State)"

$payload = '{"type":"send_prompt","requestId":"t1","cascadeId":"casc-1","prompt":"test notification"}'
$bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
$seg = [ArraySegment[byte]]::new($bytes)
$ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

$buf = New-Object byte[] 65536
for ($i = 0; $i -lt 10; $i++) {
    $res = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $ct).Result
    $s = [System.Text.Encoding]::UTF8.GetString($buf, 0, $res.Count)
    Write-Host "MSG: $s"
    if ($s -match 'stream_end') { break }
}

$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, 'done', $ct).Wait()
Write-Host 'WS_CLOSED'
