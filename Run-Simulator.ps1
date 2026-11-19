#Requires -Version 5.1
<#
.SYNOPSIS
    Discord Games Simulator — локальная имитация запуска игр для проверки
    обнаружения активности в Discord.

.DESCRIPTION
    Скрипт НЕ входит в аккаунт Discord и не скачивает игры: он берёт имена
    исполняемых файлов из публичного каталога Discord, создаёт файлы-заглушки
    с такими же именами и запускает их по таймеру.

    Зачёт значка Discord НЕ гарантирован: это эксперимент.

.PARAMETER Count
    Сколько игр использовать (1..100).

.PARAMETER Seconds
    Сколько секунд показывать каждую игру (5..3600).

.PARAMETER Menu
    Показать интерактивное меню.

.PARAMETER PrepareOnly
    Только подготовить файлы заглушек, ничего не запускать.

.PARAMETER Parallel
    Запустить все окна одновременно (все игры разом).

.PARAMETER Resume
    Пропустить игры, которые уже успешно отработали (по history.csv за 72 часа).

.PARAMETER Force
    Не спрашивать подтверждение перед длинным прогоном.

.PARAMETER Language
    Язык интерфейса: ru или en. Запоминается в simulator-data\settings.json.

.EXAMPLE
    .\Run-Simulator.ps1 -Menu

.EXAMPLE
    .\Run-Simulator.ps1 -Count 3 -Seconds 60 -Force

.EXAMPLE
    .\Run-Simulator.ps1 -Count 100 -Seconds 6 -Resume -Force
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 100)]
    [int]$Count = 100,

    [ValidateRange(5, 3600)]
    [int]$Seconds = 120,

    [switch]$Menu,
    [switch]$PrepareOnly,
    [switch]$Parallel,
    [switch]$Resume,
    [switch]$Force,

    [ValidateSet('ru', 'en')]
    [string]$Language
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Пути объявляются ДО любого использования: под Set-StrictMode чтение
# неинициализированной переменной — это исключение, а не $null.
$script:Root = Join-Path $PSScriptRoot 'simulator-data'
$script:LibDir = Join-Path $PSScriptRoot 'lib'
$script:HistoryPath = Join-Path $script:Root 'history.csv'

# Версия заглушки: смена версии заставляет пересобрать exe после обновления.
$script:PlaceholderVersion = '4'
$script:CatalogApi = 'https://discord.com/api/v9/applications/detectable'
$script:DiscordCheckIntervalSeconds = 5
# Инициализируется в Initialize-RunEnvironment; заранее объявлено для StrictMode.
$script:LogPath = $null
$script:CsvEncoding = 'UTF8'

function Write-Log {
    <#
    .SYNOPSIS
        Пишет строку в журнал simulator-data\logs\*.log (для разбора проблем).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )

    if ([string]::IsNullOrEmpty($script:LogPath)) { return }
    $line = '{0} [{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level, $Message
    # Журнал не должен ломать основной сценарий.
    try { Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}

function Initialize-RunEnvironment {
    <#
    .SYNOPSIS
        Создаёт каталоги, снимает блокировку Windows и открывает журнал.
    #>
    [CmdletBinding()]
    param()

    foreach ($dir in @($script:Root,
            (Join-Path $script:Root 'logs'),
            (Join-Path $script:Root 'catalog'))) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }

    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $script:LogPath = Join-Path $script:Root ('logs\run-' + $stamp + '.log')

    # Файлы из ZIP имеют «метку из интернета»; снимаем её, чтобы не зависеть
    # от ExecutionPolicy RemoteSigned (см. Start.cmd).
    try {
        Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue |
            Unblock-File -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.psm1' -Recurse -ErrorAction SilentlyContinue |
            Unblock-File -ErrorAction SilentlyContinue
    } catch {
        Write-Log ('Unblock-File failed: ' + $_.Exception.Message) -Level 'DEBUG'
    }

    $startInfo = 'Start. PSVersion={0} OS={1} Count={2} Seconds={3} Parallel={4} Resume={5}' -f `
        $PSVersionTable.PSVersion, $env:OS, $Count, $Seconds, $Parallel, $Resume
    Write-Log $startInfo
}

function Get-SimulatorMutex {
    <#
    .SYNOPSIS
        Не даёт двум экземплярам писать в один simulator-data одновременно.
    #>
    [CmdletBinding()]
    param()

    try {
        $mutex = New-Object System.Threading.Mutex($false, 'Local\DiscordGamesSimulator')
    } catch {
        Write-Log ('Mutex creation failed, continuing without lock: ' + $_.Exception.Message) -Level 'WARN'
        return [pscustomobject]@{ Mutex = $null; Acquired = $true }
    }
    $acquired = $false
    try {
        $acquired = $mutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        # Предыдущий экземпляр упал, не освободив мьютекс — это нормально.
        $acquired = $true
    }
    return [pscustomobject]@{ Mutex = $mutex; Acquired = $acquired }
}

# ---------------------------------------------------------------------------
# Настройки (язык интерфейса)
# ---------------------------------------------------------------------------

function Get-SettingsPath { return (Join-Path $script:Root 'settings.json') }

function Read-Settings {
    [CmdletBinding()]
    param()
    $path = Get-SettingsPath
    if (-not (Test-Path -LiteralPath $path)) { return @{} }
    try {
        $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $result = @{}
        foreach ($property in $data.PSObject.Properties) { $result[$property.Name] = $property.Value }
        return $result
    } catch {
        Write-Log ('Settings read failed: ' + $_.Exception.Message) -Level 'WARN'
        return @{}
    }
}

function Save-Settings {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Settings)
    try {
        $json = ConvertTo-Json -InputObject $Settings -Depth 4
        Set-Content -LiteralPath (Get-SettingsPath) -Value $json -Encoding UTF8
    } catch {
        Write-Log ('Settings write failed: ' + $_.Exception.Message) -Level 'WARN'
    }
}

# ---------------------------------------------------------------------------
# Каталог Discord: устойчивая загрузка + кэш + офлайн-фолбэк
# ---------------------------------------------------------------------------

function Get-DiscordCatalog {
    <#
    .SYNOPSIS
        Загружает каталог Discord с повторами, кэшем и фолбэком на прошлый запуск.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Messages,
        [int]$MaxAttempts = 3,
        [switch]$IgnoreCache
    )

    $cachePath = Join-Path $script:Root 'catalog\detectable.json'
    $csvPath = Join-Path $script:Root 'selected-games.csv'

    # TLS 1.2 нужен на старых системах, иначе получаем «connection closed».
    try {
        $current = [Net.ServicePointManager]::SecurityProtocol
        [Net.ServicePointManager]::SecurityProtocol = $current -bor [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Log ('TLS setup failed: ' + $_.Exception.Message) -Level 'WARN'
    }

    $headers = @{
        'User-Agent' = 'DiscordGamesSimulator/1.1 (+https://github.com/WinormanTeam/Discord-Games-Simulator)'
        'Accept'     = 'application/json'
    }

    if (-not $IgnoreCache) {
        for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
            try {
                Write-Log ('Catalog request attempt {0}' -f $attempt) -Level 'INFO'
                $catalog = Invoke-RestMethod -Uri $script:CatalogApi -Headers $headers `
                    -TimeoutSec 30 -MaximumRedirection 5
                if ($null -ne $catalog -and @($catalog).Count -gt 0) {
                    try {
                        $json = ConvertTo-Json -InputObject @($catalog) -Depth 12 -Compress
                        Set-Content -LiteralPath $cachePath -Value $json -Encoding UTF8
                    } catch {
                        Write-Log ('Cache write failed: ' + $_.Exception.Message) -Level 'WARN'
                    }
                    return @($catalog)
                }
                Write-Log 'Catalog response was empty' -Level 'WARN'
            } catch {
                Write-Log ('Catalog request failed: ' + $_.Exception.Message) -Level 'WARN'
            }
            if ($attempt -lt $MaxAttempts) {
                Start-Sleep -Seconds ([Math]::Min(8, [Math]::Pow(2, $attempt)))
            }
        }
    }

    # Фолбэк 1: кэш предыдущего удачного запроса.
    if (Test-Path -LiteralPath $cachePath) {
        try {
            $cached = Get-Content -LiteralPath $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $cached -and @($cached).Count -gt 0) {
                $age = 'неизвестно'
                try {
                    $age = (Get-Item -LiteralPath $cachePath).LastWriteTime.ToString('dd.MM.yyyy HH:mm')
                } catch { }
                Write-Host ($Messages['CatalogFromCache'] -f $age) -ForegroundColor Yellow
                Write-Log 'Catalog loaded from cache'
                return @($cached)
            }
        } catch {
            Write-Log ('Cache read failed: ' + $_.Exception.Message) -Level 'WARN'
        }
    }

    # Фолбэк 2: список, подготовленный в прошлый раз (-PrepareOnly).
    if (Test-Path -LiteralPath $csvPath) {
        try {
            $rows = Import-Csv -LiteralPath $csvPath -Encoding UTF8
            if ($null -ne $rows -and @($rows).Count -gt 0) {
                Write-Host $Messages['CatalogFromCsv'] -ForegroundColor Yellow
                Write-Log 'Catalog loaded from selected-games.csv'
                return @($rows | ForEach-Object {
                        [pscustomobject]@{
                            name        = [string]$_.game
                            executables = @([pscustomobject]@{
                                    name        = [string]$_.executable
                                    os          = 'win32'
                                    is_launcher = $false
                                })
                        }
                    })
            }
        } catch {
            Write-Log ('CSV fallback failed: ' + $_.Exception.Message) -Level 'WARN'
        }
    }

    throw $Messages['CatalogFailed']
}

# ---------------------------------------------------------------------------
# Заглушка: компиляция, проверка целостности, создание экземпляров
# ---------------------------------------------------------------------------

function New-PlaceholderExecutable {
    <#
    .SYNOPSIS
        Собирает exe-заглушку атомарно и пересобирает её при повреждении.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [hashtable]$Messages
    )

    $marker = $Path + '.version'
    $expectedVersion = $script:PlaceholderVersion

    $isValid = $false
    if ((Test-Path -LiteralPath $Path) -and (Test-Path -LiteralPath $marker)) {
        try {
            $file = Get-Item -LiteralPath $Path
            # Пустой или обрезанный exe после прерванной компиляции — пересобираем.
            if ($file.Length -gt 4096) {
                $stored = (Get-Content -LiteralPath $marker -Raw -Encoding UTF8).Trim()
                $isValid = ($stored -eq $expectedVersion)
            }
        } catch {
            $isValid = $false
        }
    }

    if ($isValid) {
        Write-Log 'Placeholder executable is up to date'
        return
    }

    $sourcePath = Join-Path $script:LibDir 'Placeholder.cs'
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw ('Не найден файл {0}. Распакуйте архив полностью.' -f $sourcePath)
    }

    Write-Host $Messages['BuildingPlaceholder'] -ForegroundColor Cyan
    $source = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8

    # Собираем во временный файл и подменяем только при успехе.
    $tempPath = Join-Path $script:Root ('window-placeholder-' + [guid]::NewGuid().ToString('N') + '.tmp.exe')
    try {
        Add-Type -TypeDefinition $source `
            -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing' `
            -OutputAssembly $tempPath -OutputType WindowsApplication -ErrorAction Stop

        $tempFile = Get-Item -LiteralPath $tempPath
        if ($tempFile.Length -lt 4096) {
            throw ('Сборка заглушки вернула подозрительно маленький файл: {0} байт.' -f $tempFile.Length)
        }

        Move-Item -LiteralPath $tempPath -Destination $Path -Force
        Set-Content -LiteralPath $marker -Value $expectedVersion -Encoding UTF8
        Write-Log ('Placeholder built: {0} bytes' -f $tempFile.Length)
    } finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
    }
}

function New-PlaceholderInstance {
    <#
    .SYNOPSIS
        Создаёт «экземпляр» заглушки: жёсткая ссылка на базовый exe (или копия).
    .DESCRIPTION
        Жёсткая ссылка занимает место один раз вместо 100 копий и снижает
        шум эвристик антивируса. Если ФС не поддерживает — падаем на копию.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    $parent = Split-Path -Path $DestinationPath -Parent
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    if (Test-Path -LiteralPath $DestinationPath) {
        Remove-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
    }

    try {
        New-Item -ItemType HardLink -Path $DestinationPath -Target $SourcePath -ErrorAction Stop | Out-Null
        return 'hardlink'
    } catch {
        Write-Log ('HardLink failed, falling back to copy: ' + $_.Exception.Message) -Level 'DEBUG'
        Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
        return 'copy'
    }
}

# ---------------------------------------------------------------------------
# Отрисовка панели
# ---------------------------------------------------------------------------

function Show-Banner {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Messages)

    Clear-Host
    Write-Host ' ============================================================' -ForegroundColor Cyan
    Write-Host ('                  ' + $Messages['Title']) -ForegroundColor White
    Write-Host ' ============================================================' -ForegroundColor Cyan
    Write-Host ('  ' + $Messages['Tagline']) -ForegroundColor Yellow
    Write-Host ''
}

function Show-RunPanel {
    <#
    .SYNOPSIS
        Перерисовывает панель текущего прогона (не чаще раза в секунду).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Messages,
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)][int]$ProcessId,
        [Parameter(Mandatory = $true)][int]$Index,
        [Parameter(Mandatory = $true)][int]$Total,
        [Parameter(Mandatory = $true)][int]$Elapsed,
        [Parameter(Mandatory = $true)][int]$Seconds,
        [Parameter(Mandatory = $true)][int]$RemainingSeconds,
        [Parameter(Mandatory = $true)][bool]$DiscordRunning,
        [string]$PreviousGame = ''
    )

    $fill = [Math]::Min(30, [int](30 * $Elapsed / [Math]::Max(1, $Seconds)))

    Show-Banner -Messages $Messages
    Write-Host ($Messages['NowPlaying'] -f $Game.game) -ForegroundColor Green
    Write-Host ($Messages['Exe'] -f $Game.executable)
    Write-Host ($Messages['Pid'] -f $ProcessId)
    Write-Host ($Messages['Queue'] -f ($Index + 1), $Total)
    Write-Host ($Messages['Remaining'] -f [Math]::Max(0, $Seconds - $Elapsed))
    $etaText = Format-Duration -Seconds $RemainingSeconds -Short
    Write-Host ($Messages['Eta'] -f $etaText) -ForegroundColor DarkCyan
    Write-Host ('  [{0}{1}]' -f ('#' * $fill), ('.' * (30 - $fill))) -ForegroundColor Cyan

    $discordText = if ($DiscordRunning) { $Messages['DiscordFound'] } else { $Messages['DiscordMissing'] }
    $discordColor = if ($DiscordRunning) { 'Green' } else { 'Red' }
    Write-Host ($Messages['Discord'] -f $discordText) -ForegroundColor $discordColor
    Write-Host $Messages['Detection'] -ForegroundColor Yellow

    if (-not [string]::IsNullOrWhiteSpace($PreviousGame)) {
        Write-Host ($Messages['Previous'] -f $PreviousGame) -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host $Messages['StopHint']
}

# ---------------------------------------------------------------------------
# Запись истории
# ---------------------------------------------------------------------------

function Add-HistoryEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Messages,
        [Parameter(Mandatory = $true)][datetime]$Time,
        [Parameter(Mandatory = $true)]$Game,
        [Parameter(Mandatory = $true)][string]$Status,
        [ValidateSet('sequential', 'parallel')][string]$Mode = 'sequential'
    )

    $row = New-HistoryRow -Time $Time -Game ([string]$Game.game) `
        -Executable ([string]$Game.executable) -Status $Status -Mode $Mode
    try {
        $row | Export-Csv -LiteralPath $script:HistoryPath -Append -NoTypeInformation `
            -Encoding $script:CsvEncoding
    } catch {
        Write-Log ('History write failed: ' + $_.Exception.Message) -Level 'ERROR'
    }
    Write-Log ('History: {0} | {1} | {2}' -f [string]$Game.game, [string]$Game.executable, $Status)
}

# ---------------------------------------------------------------------------
# Режимы запуска
# ---------------------------------------------------------------------------

function Invoke-SequentialRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Games,
        [Parameter(Mandatory = $true)][hashtable]$Messages,
        [Parameter(Mandatory = $true)][string]$BaseExecutable
    )

    $total = $Games.Count
    $discordRunning = $false
    $lastDiscordCheck = [datetime]::MinValue
    $runStart = Get-Date

    for ($i = 0; $i -lt $total; $i++) {
        $game = $Games[$i]
        $dir = Join-Path $script:Root ('s\' + $i)
        $relative = Get-SimulatorRelativePath -Executable $game.executable
        $exe = Join-Path $dir $relative

        New-PlaceholderInstance -SourcePath $BaseExecutable -DestinationPath $exe | Out-Null

        $started = Get-Date
        $process = $null
        $status = $Messages['StatusInterrupted']
        $interrupted = $true

        try {
            $arguments = New-PlaceholderArguments -Seconds $Seconds -Title $game.game
            $process = Start-Process -FilePath $exe -ArgumentList $arguments `
                -WorkingDirectory (Split-Path -Path $exe -Parent) -PassThru

            # WaitForExit(1000) вместо busy-poll каждые 100 мс.
            # Панель перерисовывается не чаще раза в секунду.
            while (-not $process.WaitForExit(1000)) {
                $elapsed = [int]((Get-Date) - $started).TotalSeconds

                # Get-Process — дорогая операция, опрашиваем раз в несколько секунд.
                if (((Get-Date) - $lastDiscordCheck).TotalSeconds -ge $script:DiscordCheckIntervalSeconds) {
                    $discordRunning = ($null -ne (Get-DiscordProcessId))
                    $lastDiscordCheck = Get-Date
                }

                $remaining = (($total - $i - 1) * $Seconds) + [Math]::Max(0, $Seconds - $elapsed)
                $previous = ''
                if ($i -gt 0) { $previous = [string]$Games[$i - 1].game }

                Show-RunPanel -Messages $Messages -Game $game -ProcessId $process.Id `
                    -Index $i -Total $total -Elapsed $elapsed -Seconds $Seconds `
                    -RemainingSeconds $remaining -DiscordRunning $discordRunning `
                    -PreviousGame $previous
            }

            $interrupted = $false
            $status = Get-PlaceholderExitStatus -ExitCode $process.ExitCode -Messages $Messages
        } catch {
            # Одна неудачно стартовавшая игра не должна прерывать прогон на 100 игр.
            $interrupted = $false
            $status = $Messages['StatusError'] -f $_.Exception.Message
            Write-Log ('Game failed: {0}: {1}' -f [string]$game.game, $_.Exception.Message) -Level 'ERROR'
            Write-Host ''
            Write-Host ('  ! ' + $status) -ForegroundColor Red
        } finally {
            if ($null -ne $process) {
                try { $process.Refresh() } catch { }
                if (-not $process.HasExited) {
                    try { $process.Kill() } catch { Write-Log ('Kill failed: ' + $_.Exception.Message) -Level 'WARN' }
                    $status = $Messages['StatusInterrupted']
                }
            }
            Add-HistoryEntry -Messages $Messages -Time $started -Game $game -Status $status -Mode 'sequential'
            if ($interrupted -and $null -eq $process) {
                # Fail-fast: не смогли даже стартовать — сообщаем и выходим.
                Write-Log ('Process did not start for {0}' -f $game.game) -Level 'ERROR'
            }
        }
    }

    Write-Host ($Messages['DurationDone'] -f (Format-Duration -Seconds ((Get-Date) - $runStart).TotalSeconds))
}

function Invoke-ParallelRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Games,
        [Parameter(Mandatory = $true)][hashtable]$Messages,
        [Parameter(Mandatory = $true)][string]$BaseExecutable
    )

    $jobs = New-Object System.Collections.Generic.List[object]
    $gateTimeout = Get-GateTimeoutSeconds -Count $Games.Count
    $gate = Join-Path $script:Root ('start-' + [guid]::NewGuid().ToString('N') + '.signal')

    try {
        for ($i = 0; $i -lt $Games.Count; $i++) {
            $game = $Games[$i]
            $dir = Join-Path $script:Root ('p\' + $i)
            $relative = Get-SimulatorRelativePath -Executable $game.executable
            $exe = Join-Path $dir $relative
            New-PlaceholderInstance -SourcePath $BaseExecutable -DestinationPath $exe | Out-Null

            $arguments = New-PlaceholderArguments -Seconds $Seconds -Title $game.game `
                -GatePath $gate -GateTimeoutSeconds $gateTimeout
            try {
                $process = Start-Process -FilePath $exe -ArgumentList $arguments `
                    -WorkingDirectory (Split-Path -Path $exe -Parent) -PassThru
            } catch {
                $failed = $Messages['StatusError'] -f $_.Exception.Message
                Write-Host ('  ! ' + $failed) -ForegroundColor Red
                Add-HistoryEntry -Messages $Messages -Time (Get-Date) -Game $game `
                    -Status $failed
                continue
            }

            $jobs.Add([pscustomobject]@{ Process = $process; Game = $game; Started = (Get-Date) })
            Write-Host ($Messages['Ready'] -f $process.Id, $game.game) -ForegroundColor Green
        }

        # Сигнал к одновременному старту.
        New-Item -ItemType File -Path $gate -Force | Out-Null
        $batchStart = Get-Date
        $hardLimit = $Seconds + $gateTimeout + 30

        do {
            $active = 0
            foreach ($job in $jobs) {
                try { $job.Process.Refresh() } catch { }
                if (-not $job.Process.HasExited) { $active++ }
            }
            $elapsed = [int]((Get-Date) - $batchStart).TotalSeconds
            $left = $Seconds - $elapsed
            if ($left -lt 0) { $left = 0 }
            Write-Host ("`r" + ($Messages['Running'] -f $active, $jobs.Count, $elapsed, $left) + '     ') `
                -NoNewline -ForegroundColor Cyan

            if ($active -gt 0) {
                if ($elapsed -gt $hardLimit) { throw $Messages['GateTimeout'] }
                Start-Sleep -Milliseconds 250
            }
        } while ($active -gt 0)

        Write-Host ''
        Write-Host ('  ' + $Messages['BatchFinished'])
    } finally {
        foreach ($job in $jobs) {
            try { $job.Process.Refresh() } catch { }
            if (-not $job.Process.HasExited) {
                try { $job.Process.Kill() } catch { }
                $status = $Messages['StatusInterrupted']
            } else {
                $status = Get-PlaceholderExitStatus -ExitCode $job.Process.ExitCode -Messages $Messages
            }
            Add-HistoryEntry -Messages $Messages -Time $job.Started -Game $job.Game `
                -Status $status -Mode 'parallel'
        }
        if (Test-Path -LiteralPath $gate) {
            Remove-Item -LiteralPath $gate -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# Меню
# ---------------------------------------------------------------------------

function Read-LanguageChoice {
    [CmdletBinding()]
    param()
    $answer = Read-Host '  Language / Язык: [1] Русский  [2] English'
    if ($answer -eq '2') { return 'en' }
    return 'ru'
}

function Invoke-Menu {
    <#
    .SYNOPSIS
        Интерактивное меню. Возвращает hashtable с выбранным действием или $null.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Messages)

    Show-Banner -Messages $Messages
    Write-Host ('  ' + $Messages['MenuTest'])
    Write-Host ('  ' + $Messages['MenuFull'])
    Write-Host ('  ' + $Messages['MenuFast'])
    Write-Host ('  ' + $Messages['MenuParallel'])
    Write-Host ('  ' + $Messages['MenuPrepare'])
    Write-Host ('  ' + $Messages['MenuLanguage'])
    Write-Host ('  ' + $Messages['MenuExit'])
    Write-Host ''

    $choice = Read-Host $Messages['MenuChoose']
    switch ($choice) {
        '1' { return @{ Count = 3; Seconds = 60; Parallel = $false; PrepareOnly = $false } }
        '2' { return @{ Count = 100; Seconds = 120; Parallel = $false; PrepareOnly = $false } }
        '3' { return @{ Count = 100; Seconds = 6; Parallel = $false; PrepareOnly = $false } }
        '4' { return @{ Count = 100; Seconds = 120; Parallel = $true; PrepareOnly = $false } }
        '5' { return @{ Count = 100; Seconds = 120; Parallel = $false; PrepareOnly = $true } }
        'l' { return @{ Language = (Read-LanguageChoice) } }
        default { return $null }
    }
}

# ---------------------------------------------------------------------------
# Главный сценарий
# ---------------------------------------------------------------------------

try {
    $onWindows = ($env:OS -eq 'Windows_NT')
    if (-not $onWindows -and (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue)) {
        $onWindows = [bool]$IsWindows
    }
    if (-not $onWindows) {
        Write-Host 'This script requires Windows (WinForms + Discord desktop).' -ForegroundColor Red
        exit 1
    }

    $corePath = Join-Path $LibDir 'SimulatorCore.ps1'
    if (-not (Test-Path -LiteralPath $corePath)) {
        throw ('Не найден файл {0}. Распакуйте архив полностью.' -f $corePath)
    }
    . $corePath

    Initialize-RunEnvironment

    $settings = Read-Settings
    if (-not $Language) {
        if ($settings.ContainsKey('language') -and $settings['language']) { $Language = [string]$settings['language'] }
        else { $Language = 'ru' }
    }
    $Messages = Initialize-SimulatorMessages -Language $Language
    $script:CsvEncoding = if ($PSVersionTable.PSVersion.Major -ge 6) { 'utf8BOM' } else { 'UTF8' }

    # Меню в цикле, чтобы после прогона можно было выбрать другой режим.
    while ($Menu) {
        $selection = Invoke-Menu -Messages $Messages
        if ($null -eq $selection) { Write-Host $Messages['MenuBye']; exit 0 }
        if ($selection.ContainsKey('Language')) {
            $Language = [string]$selection['Language']
            $settings['language'] = $Language
            Save-Settings -Settings $settings
            $Messages = Initialize-SimulatorMessages -Language $Language
            continue
        }
        $Count = [int]$selection['Count']
        $Seconds = [int]$selection['Seconds']
        $Parallel = [bool]$selection['Parallel']
        $PrepareOnly = [bool]$selection['PrepareOnly']
        $Menu = $false

        # Подтверждение спросим один раз — уже после загрузки каталога,
        # когда известна реальная длительность прогона.
        $Force = $false
    }

    $lock = Get-SimulatorMutex
    if (-not $lock.Acquired) {
        Write-Host ($Messages['OtherInstance'] -f 'DiscordGamesSimulator') -ForegroundColor Red
        Write-Host ($Messages['ErrorsInLog'] -f $script:LogPath)
        exit 1
    }

    try {
        # --- Подготовка заглушки -------------------------------------------
        $base = Join-Path $script:Root ('window-placeholder-v' + $script:PlaceholderVersion + '.exe')
        New-PlaceholderExecutable -Path $base -Messages $Messages -ErrorAction Stop

        # --- Каталог и отбор игр -------------------------------------------
        Write-Host $Messages['LoadingCatalog']
        $catalog = Get-DiscordCatalog -Messages $Messages
        $games = @(Select-CompatibleGames -Catalog $catalog -Count $Count `
                -BasePath $script:Root -SubDirectory ($(if ($Parallel) { 'p\{0}' } else { 's\{0}' })))

        if ($games.Count -eq 0) { throw $Messages['NoGames'] }
        if ($games.Count -lt $Count) {
            Write-Host ($Messages['CountWarning'] -f $games.Count, $Count) -ForegroundColor Yellow
            Write-Log ('Only {0} of {1} games available' -f $games.Count, $Count) -Level 'WARN'
        }

        $selectedRows = $games | Select-Object -Property @('game', 'executable')
        $csvPath = Join-Path $script:Root 'selected-games.csv'
        $selectedRows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding $script:CsvEncoding

        if ($PrepareOnly) {
            Write-Host ($Messages['Prepared'] -f $games.Count, $base) -ForegroundColor Green
            Write-Log ('PrepareOnly finished: {0} games' -f $games.Count)
            exit 0
        }

        # --- Режим дозапуска -----------------------------------------------
        if ($Resume) {
            $completed = @(Read-CompletedGames -HistoryPath $script:HistoryPath `
                    -SuccessStatusPrefix ([string]$Messages['StatusOk']))
            if ($completed.Count -gt 0) {
                $before = $games.Count
                $games = @($games | Where-Object { $completed -notcontains [string]$_.game })
                Write-Host ($Messages['ResumeSkipped'] -f ($before - $games.Count)) -ForegroundColor Cyan
            }
            if ($games.Count -eq 0) {
                Write-Host $Messages['ResumeNothing'] -ForegroundColor Green
                exit 0
            }
        }

        Write-Host $Messages['ExperimentWarn'] -ForegroundColor Yellow
        Write-Host $Messages['KeepDiscord']
        $plannedText = Format-Duration -Seconds ($games.Count * $Seconds) -Short
        Write-Host ('  ~' + $plannedText) -ForegroundColor DarkCyan
        if (-not $Force) {
            $answer = Read-Host ($Messages['RunAnyway'])
            if ($answer -and $answer -notmatch '^(y|Y|д|Д)') { Write-Host $Messages['MenuBye']; exit 0 }
        }
        Write-Log ('Run started: {0} games, {1}s each, parallel={2}' -f $games.Count, $Seconds, $Parallel)

        # --- Запуск ---------------------------------------------------------
        if ($Parallel) {
            Invoke-ParallelRun -Games $games -Messages $Messages -BaseExecutable $base
        } else {
            Invoke-SequentialRun -Games $games -Messages $Messages -BaseExecutable $base
        }

        Write-Host ''
        Write-Host $Messages['Finished'] -ForegroundColor Green
        Write-Log 'Run finished'
    } finally {
        if ($null -ne $lock.Mutex) {
            try { [void]$lock.Mutex.ReleaseMutex() } catch { }
            try { $lock.Mutex.Dispose() } catch { }
        }
    }
} catch {
    $message = $_.Exception.Message
    Write-Host ''
    Write-Host ('ОШИБКА / ERROR: ' + $message) -ForegroundColor Red
    if ($_.InvocationInfo -and $_.InvocationInfo.PositionMessage) {
        Write-Host $_.InvocationInfo.PositionMessage -ForegroundColor DarkGray
    }
    Write-Log ('Unhandled error: ' + $message) -Level 'ERROR'
    if ($_.ScriptStackTrace) { Write-Log ('Stack: ' + $_.ScriptStackTrace) -Level 'DEBUG' }
    if ($script:LogPath) { Write-Host ('Журнал / log: ' + $script:LogPath) -ForegroundColor DarkGray }
    exit 1
}
