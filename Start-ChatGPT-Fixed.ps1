# Temporary launcher for the Microsoft Store ChatGPT app's blank-root-route bug.
# It starts the official OpenAI.Codex package and redirects only its main renderer
# from the broken empty route to a valid initial route.

$ErrorActionPreference = 'Stop'

function Start-PackagedChatGPT {
    param(
        [Parameter(Mandatory)]
        [string]$ApplicationUserModelId,

        [Parameter(Mandatory)]
        [string[]]$ArgumentList
    )

    if (-not ('OpenAIChatGPTPackageActivation' -as [type])) {
        Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[Flags]
public enum OpenAIChatGPTActivateOptions
{
    None = 0x00000000
}

[ComImport]
[Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
internal class OpenAIChatGPTApplicationActivationManager
{
}

[ComImport]
[Guid("2E941141-7F97-4756-BA1D-9DECDE894A3D")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IOpenAIChatGPTApplicationActivationManager
{
    [PreserveSig]
    int ActivateApplication(
        [MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
        [MarshalAs(UnmanagedType.LPWStr)] string arguments,
        OpenAIChatGPTActivateOptions options,
        out uint processId);

    void ActivateForFile(IntPtr appUserModelId, IntPtr itemArray, IntPtr verb, out uint processId);
    void ActivateForProtocol(IntPtr appUserModelId, IntPtr itemArray, out uint processId);
}

public static class OpenAIChatGPTPackageActivation
{
    public static uint Activate(string appUserModelId, string arguments)
    {
        var manager = (IOpenAIChatGPTApplicationActivationManager)
            new OpenAIChatGPTApplicationActivationManager();
        uint processId;
        int result = manager.ActivateApplication(
            appUserModelId,
            arguments,
            OpenAIChatGPTActivateOptions.None,
            out processId);

        if (result < 0)
        {
            Marshal.ThrowExceptionForHR(result);
        }

        return processId;
    }
}
'@
    }

    $arguments = $ArgumentList -join ' '
    return [OpenAIChatGPTPackageActivation]::Activate(
        $ApplicationUserModelId,
        $arguments
    )
}

function Show-LauncherError {
    param([string]$Message)

    try {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show(
            $Message,
            'ChatGPT 실행 오류',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    }
    catch {
        # The shortcut runs without a console; there is no safer fallback UI here.
    }
}

function Get-FreeLoopbackPort {
    $listener = [System.Net.Sockets.TcpListener]::new(
        [System.Net.IPAddress]::Loopback,
        0
    )
    $listener.Start()
    try {
        return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    }
    finally {
        $listener.Stop()
    }
}

function Send-DevToolsCommand {
    param(
        [Parameter(Mandatory)]
        [string]$WebSocketUrl,

        [Parameter(Mandatory)]
        [hashtable]$Command
    )

    $socket = [System.Net.WebSockets.ClientWebSocket]::new()
    $cancellationSource = [System.Threading.CancellationTokenSource]::new(
        [TimeSpan]::FromSeconds(10)
    )
    $cancellation = $cancellationSource.Token

    try {
        $null = $socket.ConnectAsync(
            [Uri]$WebSocketUrl,
            $cancellation
        ).GetAwaiter().GetResult()
        $json = $Command | ConvertTo-Json -Depth 10 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $segment = [ArraySegment[byte]]::new($bytes)

        $null = $socket.SendAsync(
            $segment,
            [System.Net.WebSockets.WebSocketMessageType]::Text,
            $true,
            $cancellation
        ).GetAwaiter().GetResult()

        while ($true) {
            $stream = [System.IO.MemoryStream]::new()
            try {
                do {
                    $buffer = [byte[]]::new(65536)
                    $result = $socket.ReceiveAsync(
                        [ArraySegment[byte]]::new($buffer),
                        $cancellation
                    ).GetAwaiter().GetResult()

                    if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                        throw 'ChatGPT가 화면 전환 응답 전에 디버깅 연결을 닫았습니다.'
                    }

                    $stream.Write($buffer, 0, $result.Count)
                } while (-not $result.EndOfMessage)

                $responseText = [System.Text.Encoding]::UTF8.GetString(
                    $stream.ToArray()
                )
                $response = $responseText | ConvertFrom-Json

                if ($response.id -eq $Command.id) {
                    if ($response.error) {
                        throw "ChatGPT 화면 전환 실패: $($response.error.message)"
                    }
                    return $response
                }
            }
            finally {
                $stream.Dispose()
            }
        }
    }
    finally {
        $socket.Dispose()
        $cancellationSource.Dispose()
    }
}

try {
    $package = Get-AppxPackage -Name 'OpenAI.Codex' |
        Sort-Object -Property Version -Descending |
        Select-Object -First 1

    if (-not $package) {
        throw 'Microsoft Store의 ChatGPT 앱(OpenAI.Codex)을 찾을 수 없습니다.'
    }

    $chatGptExe = Join-Path $package.InstallLocation 'app\ChatGPT.exe'
    if (-not (Test-Path -LiteralPath $chatGptExe)) {
        throw "ChatGPT 실행 파일을 찾을 수 없습니다: $chatGptExe"
    }

    # Close only the stable Store package. ChatGPT Beta and Classic are untouched.
    $normalizedExe = [System.IO.Path]::GetFullPath($chatGptExe)
    Get-CimInstance -ClassName Win32_Process -Filter "Name='ChatGPT.exe'" |
        Where-Object {
            $_.ExecutablePath -and
            ([System.IO.Path]::GetFullPath($_.ExecutablePath) -eq $normalizedExe) -and
            $_.CommandLine -notlike '*--type=*'
        } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }

    # Electron's single-instance lock can outlive the main process briefly. Starting
    # too early hands the new request to a dying instance and leaves no renderer.
    $shutdownDeadline = [DateTime]::UtcNow.AddSeconds(8)
    do {
        $remainingProcesses = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='ChatGPT.exe'" |
            Where-Object {
                $_.ExecutablePath -and
                ([System.IO.Path]::GetFullPath($_.ExecutablePath) -eq $normalizedExe)
            })

        if ($remainingProcesses.Count -eq 0) {
            break
        }
        Start-Sleep -Milliseconds 250
    } while ([DateTime]::UtcNow -lt $shutdownDeadline)

    Start-Sleep -Seconds 1

    $port = Get-FreeLoopbackPort
    $arguments = @(
        '--remote-debugging-address=127.0.0.1'
        "--remote-debugging-port=$port"
    )

    # Windows 10 can reject a direct CreateProcess call for a Store-packaged
    # executable with ERROR_ACCESS_DENIED. Activate the registered package
    # identity instead while preserving the Chromium debugging arguments.
    $appUserModelId = "$($package.PackageFamilyName)!App"
    $null = Start-PackagedChatGPT `
        -ApplicationUserModelId $appUserModelId `
        -ArgumentList $arguments

    $deadline = [DateTime]::UtcNow.AddSeconds(25)
    $mainTarget = $null

    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 250
        try {
            $requestParameters = @{
                Uri = "http://127.0.0.1:$port/json/list"
                TimeoutSec = 2
            }
            $targets = Invoke-RestMethod @requestParameters

            $mainTarget = @($targets | Where-Object {
                $_.type -eq 'page' -and
                $_.url -eq 'app://-/index.html'
            })[0]

            if ($mainTarget) {
                break
            }
        }
        catch {
            # The local debugging endpoint is not ready yet.
        }
    }

    if (-not $mainTarget) {
        throw 'ChatGPT 기본 창이 제한 시간 안에 준비되지 않았습니다.'
    }

    # The target is advertised before the Electron window has finished wiring its
    # IPC handlers. Navigating during that interval destroys the renderer.
    Start-Sleep -Seconds 5

    $devToolsParameters = @{
        WebSocketUrl = $mainTarget.webSocketDebuggerUrl
        Command = @{
            id = 1
            method = 'Page.navigate'
            params = @{
                url = 'app://-/index.html?initialRoute=%2Fsettings'
            }
        }
    }
    $null = Send-DevToolsCommand @devToolsParameters

    # The first valid route loads the missing route modules and host listeners.
    # Reload the same route once those modules are ready; a single early load can
    # leave the shell visible but the route body empty.
    Start-Sleep -Seconds 6

    $settingsTargets = Invoke-RestMethod @requestParameters
    $settingsTarget = @($settingsTargets | Where-Object {
        $_.type -eq 'page' -and
        $_.url -eq 'app://-/index.html?initialRoute=%2Fsettings'
    })[0]

    if (-not $settingsTarget) {
        throw 'ChatGPT 설정 라우트가 준비되지 않았습니다.'
    }

    $secondNavigationParameters = @{
        WebSocketUrl = $settingsTarget.webSocketDebuggerUrl
        Command = @{
            id = 2
            method = 'Page.navigate'
            params = @{
                url = 'app://-/index.html?initialRoute=%2Fsettings'
            }
        }
    }
    $null = Send-DevToolsCommand @secondNavigationParameters

    $renderDeadline = [DateTime]::UtcNow.AddSeconds(20)
    $routeRendered = $false
    do {
        Start-Sleep -Milliseconds 500
        $renderCheckParameters = @{
            WebSocketUrl = $settingsTarget.webSocketDebuggerUrl
            Command = @{
                id = 3
                method = 'Runtime.evaluate'
                params = @{
                    expression = "(document.body?.innerText||'').length"
                    returnByValue = $true
                }
            }
        }
        $renderResult = Send-DevToolsCommand @renderCheckParameters
        $routeRendered = [int]$renderResult.result.result.value -gt 100
    } while (-not $routeRendered -and [DateTime]::UtcNow -lt $renderDeadline)

    if (-not $routeRendered) {
        throw 'ChatGPT 화면 구성 요소를 불러오지 못했습니다.'
    }

    # Use the app's own host-navigation event so the initialized shell stays
    # mounted while switching from Settings to the ChatGPT home screen.
    $homeNavigationExpression = @"
window.dispatchEvent(new MessageEvent('message', {
  data: {
    type: 'navigate-to-route',
    path: '/',
    state: { focusComposerNonce: Date.now() }
  }
}))
"@
    $homeNavigationParameters = @{
        WebSocketUrl = $settingsTarget.webSocketDebuggerUrl
        Command = @{
            id = 4
            method = 'Runtime.evaluate'
            params = @{
                expression = $homeNavigationExpression
                returnByValue = $true
            }
        }
    }
    $null = Send-DevToolsCommand @homeNavigationParameters
}
catch {
    Show-LauncherError -Message $_.Exception.Message
    exit 1
}
