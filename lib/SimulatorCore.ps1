<#
.SYNOPSIS
    Чистые (тестируемые) функции ядра Discord Games Simulator.

.DESCRIPTION
    Здесь нет запуска окон, сети и интерактивного UI — только логика,
    которую можно покрыть Pester-тестами на Linux и Windows.
    Основной скрипт Run-Simulator.ps1 подключает этот файл через dot-source.

    Файл намеренно совместим с Windows PowerShell 5.1 (без ?. и ??).
#>

# Максимальная длина полного пути с запасом под лимит Win32 MAX_PATH (260).
$script:MaxPathLength = 240
# Имя исполняемого файла, разрешённое каталогом Discord.
$script:ExecutableNamePattern = '^[a-zA-Z0-9_ -][a-zA-Z0-9_./ -]*\.exe$'
$script:MaxExecutableNameLength = 140

function Initialize-SimulatorMessages {
    <#
    .SYNOPSIS
        Возвращает таблицу строк интерфейса для выбранного языка (ru/en).
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('ru', 'en')]
        [string]$Language = 'ru'
    )

    $ru = @{
        Title            = 'DISCORD GAME SIMULATOR'
        Tagline          = 'Локальная имитация | зачёт значка Discord: НЕ ПОДТВЕРЖДЁН'
        # Меню
        MenuTest         = '[1] Тест: 3 игры x 60 секунд'
        MenuFull         = '[2] Полный прогон: 100 игр x 120 секунд'
        MenuFast         = '[3] Быстрый последовательный: 100 игр x 6 секунд'
        MenuParallel     = '[4] Параллельный (все окна одновременно)'
        MenuPrepare      = '[5] Только подготовка файлов, без запуска'
        MenuLanguage     = '[L] Сменить язык / Switch language'
        MenuExit         = '[0] Выход'
        MenuChoose       = '  Выбор'
        MenuBye          = 'Выход.'
        ContinuePrompt   = 'Нажмите Enter, чтобы вернуться в меню...'
        RunAnyway        = 'Запустить? [Y/n]'
        # Сообщения
        LoadingCatalog   = 'Загрузка публичного каталога Discord. Вход не требуется.'
        BuildingPlaceholder = 'Сборка exe-заглушки (только при первом запуске или обновлении)...'
        CatalogFromCache = 'Каталог Discord недоступен, использую кэш от {0}.'
        CatalogFromCsv   = 'Использую ранее подготовленный список selected-games.csv.'
        CatalogFailed    = 'Не удалось получить каталог Discord: все попытки исчерпаны.'
        Prepared         = 'Подготовлено игр: {0}. Файл окна: {1}'
        NoGames          = 'Не найдено ни одного совместимого исполняемого файла.'
        ExperimentWarn   = 'ЭКСПЕРИМЕНТ: обнаружение Discord и зачёт значка НЕ гарантированы.'
        KeepDiscord      = 'Держите десктопный Discord открытым. Ctrl+C останавливает прогон.'
        PreparingAll     = 'Подготовка одновременного запуска...'
        Ready            = '  ГОТОВО  PID {0,-7} {1}'
        Running          = '  РАБОТАЕТ: {0}/{1} | прошло: {2}s | осталось: ~{3}'
        BatchFinished    = 'Пакет завершён. Зачёт значка не проверен.'
        GateTimeout      = 'Часть окон не закрылась за отведённый таймаут.'
        # Панель текущей игры
        NowPlaying       = '  СЕЙЧАС     : {0}'
        Exe              = '  EXE        : {0}'
        Pid              = '  PID        : {0} (работает)'
        Queue            = '  ОЧЕРЕДЬ    : {0} / {1}'
        Remaining        = '  ОСТАЛОСЬ   : {0}s'
        Eta              = '  ДО КОНЦА   : ~{0}'
        DiscordFound     = 'клиент найден'
        DiscordMissing   = 'НЕ ЗАПУЩЕН'
        Discord          = '  DISCORD    : {0}'
        Detection        = '  ДЕТЕКТ     : проверьте «Зарегистрированные игры» в Discord'
        Previous         = '  ПРЕДЫДУЩАЯ : {0}'
        StopHint         = '  Ctrl+C — остановка. Каждое окно закрывается по таймеру.'
        Finished         = 'Готово. Проверьте значок в Discord вручную.'
        # Статусы истории
        StatusOk         = 'локальный процесс завершён; зачёт в Discord не подтверждён'
        StatusInterrupted= 'прервано пользователем'
        StatusError      = 'ошибка процесса: {0}'
        StatusGateTimeout= 'окно не дождалось сигнала запуска'
        ResumeSkipped    = 'Пропущено (уже выполнено): {0}'
        ResumeNothing    = 'Все игры уже выполнены, повтор не требуется.'
        CountWarning     = 'Каталог дал только {0} уникальных игр вместо запрошенных {1}.'
        BlockedFile      = 'Снимаю блокировку Windows с файлов проекта...'
        OtherInstance    = 'Обнаружен другой запущенный экземпляр симулятора ({0}).'
        NeedWindows      = 'Этот скрипт поддерживает только Windows (нужен WinForms/Discord).'
        DurationDone     = 'Длительность прогона: {0}.'
        ErrorsInLog      = 'Подробный журнал: {0}'
    }

    $en = $ru.Clone()
    $en.Title            = 'DISCORD GAME SIMULATOR'
    $en.Tagline          = 'Local simulation | Discord badge credit: UNVERIFIED'
    $en.MenuTest         = '[1] Test: 3 games x 60 seconds'
    $en.MenuFull         = '[2] Full: 100 games x 120 seconds'
    $en.MenuFast         = '[3] FAST SEQUENTIAL: 100 games x 6 seconds'
    $en.MenuParallel     = '[4] Parallel (all windows at once)'
    $en.MenuPrepare      = '[5] Prepare files only, no launch'
    $en.MenuLanguage     = '[L] Switch language / Сменить язык'
    $en.MenuExit         = '[0] Exit'
    $en.MenuChoose       = '  Choose'
    $en.MenuBye          = 'Bye.'
    $en.ContinuePrompt   = 'Press Enter to return to the menu...'
    $en.RunAnyway        = 'Start? [Y/n]'
    $en.LoadingCatalog   = 'Loading public Discord catalog. No login required.'
    $en.BuildingPlaceholder = 'Building the placeholder exe (first run or after an update)...'
    $en.CatalogFromCache = 'Discord catalog unavailable, using cache from {0}.'
    $en.CatalogFromCsv   = 'Using previously prepared selected-games.csv.'
    $en.CatalogFailed    = 'Could not load the Discord catalog: all attempts failed.'
    $en.Prepared         = 'Prepared {0} games. Window executable: {1}'
    $en.NoGames          = 'No compatible executable names found.'
    $en.ExperimentWarn   = 'EXPERIMENT: Discord detection and badge credit are NOT guaranteed.'
    $en.KeepDiscord      = 'Keep Discord desktop open. Ctrl+C stops the experiment.'
    $en.PreparingAll     = 'Preparing simultaneous start...'
    $en.Ready            = '  READY  PID {0,-7} {1}'
    $en.Running          = '  RUNNING: {0}/{1} | elapsed: {2}s | left: ~{3}'
    $en.BatchFinished    = 'Batch finished. Discord credit is unverified.'
    $en.GateTimeout      = 'Some windows did not close within the timeout.'
    $en.NowPlaying       = '  NOW        : {0}'
    $en.Exe              = '  EXE        : {0}'
    $en.Pid              = '  PID        : {0} (running)'
    $en.Queue            = '  QUEUE      : {0} / {1}'
    $en.Remaining        = '  REMAINING  : {0}s'
    $en.Eta              = '  ETA        : ~{0}'
    $en.DiscordFound     = 'client process found'
    $en.DiscordMissing   = 'NOT RUNNING'
    $en.Discord          = '  DISCORD    : {0}'
    $en.Detection        = '  DETECTION  : check Registered Games in Discord'
    $en.Previous         = '  PREVIOUS   : {0}'
    $en.StopHint         = '  Ctrl+C stops. Each game window closes by timer.'
    $en.Finished         = 'Finished. Check the badge manually in Discord.'
    $en.StatusOk         = 'local process completed; Discord credit unverified'
    $en.StatusInterrupted= 'interrupted by user'
    $en.StatusError      = 'process error: {0}'
    $en.StatusGateTimeout= 'window never received the start signal'
    $en.ResumeSkipped    = 'Skipped (already completed): {0}'
    $en.ResumeNothing    = 'All games are already completed, nothing to redo.'
    $en.CountWarning     = 'Catalog produced only {0} unique games instead of {1}.'
    $en.BlockedFile      = 'Removing the Windows download block from project files...'
    $en.OtherInstance    = 'Another simulator instance is already running ({0}).'
    $en.NeedWindows      = 'This script supports Windows only (needs WinForms/Discord).'
    $en.DurationDone     = 'Total run duration: {0}.'
    $en.ErrorsInLog      = 'Detailed log: {0}'

    if ($Language -eq 'en') { return $en }
    return $ru
}

function ConvertTo-SafeFileComponent {
    <#
    .SYNOPSIS
        Превращает произвольное имя игры в безопасное имя файла.
    .DESCRIPTION
        Заменяет запрещённые в Windows символы и точки на дефис,
        обрезает хвостовые точки/пробелы и ограничивает длину.
        Защищает от выхода за пределы каталога и от зарезервированных имён.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Name,

        [ValidateRange(1, 200)]
        [int]$MaxLength = 60
    )

    if ([string]::IsNullOrWhiteSpace($Name)) { return 'game' }

    $safe = $Name -replace '[\\/:*?"<>|]', '-'
    $safe = $safe -replace '\.', '-'
    $safe = $safe -replace '\s+', ' '
    $safe = $safe.Trim().TrimEnd('.', ' ')
    if ($safe.Length -gt $MaxLength) {
        $safe = $safe.Substring(0, $MaxLength).Trim().TrimEnd('.', ' ')
    }
    if ([string]::IsNullOrWhiteSpace($safe)) { return 'game' }
    return $safe
}

function Get-SafeProperty {
    <#
    .SYNOPSIS
        Читает свойство объекта, не падая под Set-StrictMode при его отсутствии.
    .DESCRIPTION
        Ответ Discord detectable-API не гарантирует наличие полей is_launcher/os
        у каждого элемента, а StrictMode на отсутствующем свойстве выбрасывает
        исключение. Возвращает $Default, если свойства нет.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [AllowNull()]
        $Default = $null
    )

    if ($null -eq $Object) { return $Default }
    $properties = $Object.PSObject.Properties
    if ($null -eq $properties) { return $Default }
    foreach ($property in $properties) {
        if ($property.Name -eq $Name) { return $property.Value }
    }
    return $Default
}

function Get-SimulatorExecutableLeaf {
    <#
    .SYNOPSIS
        Возвращает имя файла (последний сегмент) без расширения, в нижнем регистре.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Executable
    )

    $normalized = $Executable.Replace('\', '/')
    $leaf = ($normalized.Split('/') | Select-Object -Last 1)
    if ($leaf -match '\.exe$') { return ($leaf -replace '\.exe$', '').ToLowerInvariant() }
    return ([string]$leaf).ToLowerInvariant()
}

function Test-ExecutablePathSafety {
    <#
    .SYNOPSIS
        Проверяет, безопасно ли относительное имя exe из каталога Discord.
    .DESCRIPTION
        Отсекает абсолютные пути, диски, UNC, сегменты '' / '.' / '..',
        слишком длинные имена. Возвращает объект с полями IsSafe и Reason.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Executable
    )

    if ([string]::IsNullOrWhiteSpace($Executable)) {
        return [pscustomobject]@{ IsSafe = $false; Reason = 'empty' }
    }
    if ($Executable.Length -gt $script:MaxExecutableNameLength) {
        return [pscustomobject]@{ IsSafe = $false; Reason = 'too-long' }
    }

    $normalized = $Executable.Replace('\', '/')
    if ($normalized -match '^[A-Za-z]:' -or $normalized.StartsWith('//') -or $normalized.StartsWith('/')) {
        return [pscustomobject]@{ IsSafe = $false; Reason = 'absolute' }
    }
    if ($normalized -notmatch $script:ExecutableNamePattern) {
        return [pscustomobject]@{ IsSafe = $false; Reason = 'bad-chars' }
    }
    if (@($normalized.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0) {
        return [pscustomobject]@{ IsSafe = $false; Reason = 'traversal' }
    }
    return [pscustomobject]@{ IsSafe = $true; Reason = '' }
}

function Test-PathLengthBudget {
    <#
    .SYNOPSIS
        Проверяет, что итоговый путь не выйдет за лимит Win32 MAX_PATH.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [int]$Budget = $script:MaxPathLength
    )
    return ($Path.Length -le $Budget)
}

function Get-SimulatorRelativePath {
    <#
    .SYNOPSIS
        Возвращает относительный путь exe, всегда с одинарным обратным слешем.
    .DESCRIPTION
        Раньше в коде была замена на две обратные косые ('\\') из-за чего
        получался путь вида bin\\game.exe.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable
    )
    return $Executable.Replace('/', '\')
}

function Select-CompatibleGames {
    <#
    .SYNOPSIS
        Отбирает игры каталога Discord, для которых можно создать заглушку.
    .PARAMETER Catalog
        Массив объектов из https://discord.com/api/v9/applications/detectable.
    .PARAMETER Count
        Сколько максимум игр вернуть.
    .PARAMETER BasePath
        Каталог, где будут лежать заглушки (для проверки длины пути).
    .PARAMETER SubDirectory
        Шаблон подкаталога одной игры, например 's\{0}' или 'p\{0}'.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Catalog,

        [ValidateRange(1, 1000)]
        [int]$Count = 100,

        [string]$BasePath = '',
        [string]$SubDirectory = 's\{0}'
    )

    $selected = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    foreach ($game in $Catalog) {
        if ($null -eq $game) { continue }

        $executables = Get-SafeProperty -Object $game -Name 'executables'
        if ($null -eq $executables) { continue }

        $gameName = [string](Get-SafeProperty -Object $game -Name 'name' -Default '')

        foreach ($entry in @($executables)) {
            if ($null -eq $entry) { continue }

            $name = [string](Get-SafeProperty -Object $entry -Name 'name' -Default '')
            $os = [string](Get-SafeProperty -Object $entry -Name 'os' -Default '')
            $isLauncher = Get-SafeProperty -Object $entry -Name 'is_launcher' -Default $false

            if ($os -ne 'win32') { continue }
            if ($isLauncher -eq $true) { continue }

            $safety = Test-ExecutablePathSafety -Executable $name
            if (-not $safety.IsSafe) { continue }

            $leaf = Get-SimulatorExecutableLeaf -Executable $name
            if ([string]::IsNullOrEmpty($leaf)) { continue }
            if ($seen.ContainsKey($leaf)) { continue }

            # Проверяем бюджет длины итогового пути до того, как что-то создавать.
            if (-not [string]::IsNullOrWhiteSpace($BasePath)) {
                $index = $selected.Count
                $sub = $SubDirectory -f $index
                $relative = Get-SimulatorRelativePath -Executable $name
                $candidate = [System.IO.Path]::Combine($BasePath, $sub, $relative)
                if (-not (Test-PathLengthBudget -Path $candidate)) { continue }
            }

            $seen[$leaf] = $true
            $selected.Add([pscustomobject]@{
                    game       = $gameName
                    executable = $name
                    leaf       = $leaf
                })
            break
        }

        if ($selected.Count -ge $Count) { break }
    }

    return $selected.ToArray()
}

function New-PlaceholderArguments {
    <#
    .SYNOPSIS
        Собирает список аргументов командной строки для exe-заглушки.
    .DESCRIPTION
        Возвращает массив строк: секунды, заголовок в кавычках, (опционально)
        путь к сигнальному файлу в кавычках и таймаут ожидания сигнала.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Seconds,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Title,
        [string]$GatePath = '',
        [int]$GateTimeoutSeconds = 90
    )

    $safeTitle = $Title.Replace('"', '').Replace("'", '')
    $arguments = @([string]$Seconds, ('"' + $safeTitle + '"'))
    if (-not [string]::IsNullOrWhiteSpace($GatePath)) {
        $arguments += ('"' + $GatePath + '"')
        $arguments += [string]$GateTimeoutSeconds
    }
    return $arguments
}

function Get-PlaceholderExitStatus {
    <#
    .SYNOPSIS
        Преобразует код возврата заглушки в человекочитаемый статус.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$ExitCode,
        [hashtable]$Messages = @{},
        [switch]$Interrupted
    )

    if ($Interrupted) {
        if ($Messages['StatusInterrupted']) { return [string]$Messages['StatusInterrupted'] }
        return 'interrupted'
    }
    if ($ExitCode -eq 3) {
        if ($Messages['StatusGateTimeout']) { return [string]$Messages['StatusGateTimeout'] }
        return 'gate timeout'
    }
    if ($ExitCode -eq 2) { return 'window error (bad arguments)' }
    if ($ExitCode -ne 0) { return ('error {0}' -f $ExitCode) }
    if ($Messages['StatusOk']) { return [string]$Messages['StatusOk'] }
    return 'ok'
}

function Format-Duration {
    <#
    .SYNOPSIS
        Форматирует секунды в компактную строку вида '2 ч 14 мин 05 с'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [double]$Seconds,
        [switch]$Short
    )

    if ($Seconds -lt 0) { $Seconds = 0 }
    $span = [TimeSpan]::FromSeconds([Math]::Round($Seconds))
    if ($Short) {
        if ($span.TotalHours -ge 1) { return ('{0} ч {1:00} мин' -f [int]$span.TotalHours, $span.Minutes) }
        if ($span.TotalMinutes -ge 1) { return ('{0} мин {1:00} с' -f [int]$span.TotalMinutes, $span.Seconds) }
        return ('{0} с' -f $span.Seconds)
    }
    if ($span.TotalHours -ge 1) { return ('{0} ч {1:00} мин {2:00} с' -f [int]$span.TotalHours, $span.Minutes, $span.Seconds) }
    if ($span.TotalMinutes -ge 1) { return ('{0} мин {1:00} с' -f [int]$span.TotalMinutes, $span.Seconds) }
    return ('{0} с' -f $span.Seconds)
}

function Read-CompletedGames {
    <#
    .SYNOPSIS
        Читает history.csv и возвращает имена игр, успешно выполненных за указанный срок.
    .DESCRIPTION
        Нужно для режима -Resume: не повторять игры, которые уже отработали.
        Строки с ошибками или прерыванием не считаются выполненными.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HistoryPath,
        [double]$WithinHours = 72,
        [string]$SuccessStatusPrefix = 'локальный процесс завершён'
    )

    if (-not (Test-Path -LiteralPath $HistoryPath)) { return @() }

    $cutoff = (Get-Date).AddHours(-1 * $WithinHours)
    $result = New-Object System.Collections.Generic.List[string]

    try {
        $rows = Import-Csv -LiteralPath $HistoryPath -Encoding UTF8
    } catch {
        return @()
    }

    foreach ($row in $rows) {
        if ($null -eq $row) { continue }
        $status = [string]$row.status
        # Успехом считаем только строки, начинающиеся с ожидаемого префикса.
        if (-not $status.StartsWith($SuccessStatusPrefix)) { continue }
        $time = $null
        if (-not [DateTime]::TryParse([string]$row.time, [ref]$time)) { continue }
        if ($time -lt $cutoff) { continue }
        if (-not [string]::IsNullOrWhiteSpace([string]$row.game)) {
            $result.Add([string]$row.game)
        }
    }

    return $result.ToArray()
}

function New-HistoryRow {
    <#
    .SYNOPSIS
        Формирует строку для history.csv в едином для всех режимов виде.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$Time,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Game,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Executable,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Status,
        [ValidateSet('sequential', 'parallel')]
        [string]$Mode = 'sequential'
    )

    return [pscustomobject]@{
        time       = $Time.ToString('o')
        game       = $Game
        executable = $Executable
        status     = $Status
        mode       = $Mode
    }
}

function Get-DiscordProcessId {
    <#
    .SYNOPSIS
        Возвращает PID первого найденного процесса Discord или $null.
    #>
    [CmdletBinding()]
    param()

    $names = @('Discord', 'DiscordPTB', 'DiscordCanary', 'DiscordDevelopment')
    $found = @(Get-Process -Name $names -ErrorAction SilentlyContinue)
    if ($found.Count -eq 0) { return $null }
    return $found[0].Id
}

function Get-GateTimeoutSeconds {
    <#
    .SYNOPSIS
        Вычисляет таймаут ожидания сигнального файла для параллельного режима.
    .DESCRIPTION
        Раньше таймаут был жёстко 60 секунд, но 100 последовательных
        Start-Process на медленной машине могут не уложиться в это время.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 1000)]
        [int]$Count,
        [ValidateRange(5, 3600)]
        [int]$MinSeconds = 90
    )

    # ~3 секунды на каждый Start-Process с запасом, но не меньше минимума.
    $estimated = $Count * 3
    return [int][Math]::Max($MinSeconds, $estimated)
}
