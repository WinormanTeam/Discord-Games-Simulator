#requires -Modules Pester
<#
    Юнит-тесты ядра симулятора.
    Запуск: Invoke-Pester -Path ./tests
    Работают и на Linux, и на Windows: в тестах нет WinForms и запуска окон.
#>

BeforeAll {
    # Путь строится кроссплатформенно: тесты гоняются и в CI на Linux.
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $corePath = Join-Path $repoRoot 'lib/SimulatorCore.ps1'
    $corePath = (Resolve-Path -LiteralPath $corePath).Path
    . $corePath

    # Компактная фикстура, повторяющая форму ответа Discord detectable-API.
    $script:Catalog = @(
        [pscustomobject]@{
            name        = 'Game One'
            executables = @(
                [pscustomobject]@{ name = 'game1.exe'; os = 'win32'; is_launcher = $false }
            )
        }
        [pscustomobject]@{
            name        = 'Launcher Game'
            executables = @(
                [pscustomobject]@{ name = 'launcher.exe'; os = 'win32'; is_launcher = $true }
            )
        }
        [pscustomobject]@{
            name        = 'Linux Only'
            executables = @(
                [pscustomobject]@{ name = 'linuxgame'; os = 'linux'; is_launcher = $false }
            )
        }
        [pscustomobject]@{
            name        = 'No Executables'
        }
        [pscustomobject]@{
            name        = 'Traversal Game'
            executables = @(
                [pscustomobject]@{ name = '..\..\evil.exe'; os = 'win32'; is_launcher = $false }
            )
        }
        [pscustomobject]@{
            name        = 'Nested Game'
            executables = @(
                [pscustomobject]@{ name = 'bin\x64\nested.exe'; os = 'win32'; is_launcher = $false }
            )
        }
        [pscustomobject]@{
            name        = 'Duplicate Game'
            executables = @(
                [pscustomobject]@{ name = 'GAME1.EXE'; os = 'win32'; is_launcher = $false }
            )
        }
        [pscustomobject]@{
            name        = 'Null Entry'
            executables = @(
                $null
                [pscustomobject]@{ name = 'second.exe'; os = 'win32'; is_launcher = $false }
            )
        }
    )
}

Describe 'Select-CompatibleGames' {
    BeforeAll {
        $script:Selected = @(Select-CompatibleGames -Catalog $script:Catalog -Count 100)
    }

    It 'берёт win32-исполняемые файлы' {
        $names = $script:Selected.game
        $names | Should -Contain 'Game One'
        $names | Should -Contain 'Nested Game'
    }

    It 'отбрасывает лончеры (is_launcher = true)' {
        $script:Selected.game | Should -Not -Contain 'Launcher Game'
    }

    It 'отбрасывает чужие ОС' {
        $script:Selected.game | Should -Not -Contain 'Linux Only'
    }

    It 'не падает на записи без executables' {
        $script:Selected.game | Should -Not -Contain 'No Executables'
    }

    It 'защищает от path traversal в именах exe' {
        $script:Selected.game | Should -Not -Contain 'Traversal Game'
        ($script:Selected | Where-Object { $_.executable -match '\.\.' }) | Should -BeNullOrEmpty
    }

    It 'дедуплицирует игры по имени exe без учёта регистра' {
        @($script:Selected | Where-Object { $_.game -eq 'Duplicate Game' }).Count | Should -Be 0
    }

    It 'пропускает пустые (null) элементы executables' {
        $script:Selected.game | Should -Contain 'Game One'
    }

    It 'соблюдает лимит -Count' {
        $limited = @(Select-CompatibleGames -Catalog $script:Catalog -Count 1)
        $limited.Count | Should -Be 1
    }

    It 'возвращает пустой результат для пустого каталога' {
        $empty = @(Select-CompatibleGames -Catalog @() -Count 10)
        $empty.Count | Should -Be 0
    }

    It 'сохраняет относительный путь вложенного exe' {
        $nested = $script:Selected | Where-Object { $_.game -eq 'Nested Game' }
        $nested.executable | Should -Be 'bin\x64\nested.exe'
    }

    It 'отсекает имена, из-за которых путь превысит MAX_PATH' {
        # Длинное имя игры + длинная база => кандидат не проходит бюджет 240 символов.
        $longBase = 'C:\' + ('a' * 200)
        $deep = @(
            [pscustomobject]@{
                name        = 'Deep'
                executables = @(
                    [pscustomobject]@{ name = ('b' * 60) + '.exe'; os = 'win32'; is_launcher = $false }
                )
            }
        )
        @(Select-CompatibleGames -Catalog $deep -Count 1 -BasePath $longBase).Count | Should -Be 0
    }
}

Describe 'Test-ExecutablePathSafety' {
    It 'принимает обычное относительное имя' {
        (Test-ExecutablePathSafety -Executable 'game.exe').IsSafe | Should -BeTrue
    }

    It 'принимает вложенный путь' {
        (Test-ExecutablePathSafety -Executable 'bin/game.exe').IsSafe | Should -BeTrue
    }

    It 'отклоняет <Executable>' -ForEach @(
        @{ Executable = '../game.exe' }
        @{ Executable = 'bin/../../game.exe' }
        @{ Executable = 'C:\Windows\system32\calc.exe' }
        @{ Executable = '//server/share/game.exe' }
        @{ Executable = '/etc/passwd' }
        @{ Executable = 'bin//game.exe' }
        @{ Executable = 'game.exe ' }
        @{ Executable = '' }
    ) {
        (Test-ExecutablePathSafety -Executable $Executable).IsSafe | Should -BeFalse
    }

    It 'отклоняет имя длиннее 140 символов' {
        $long = ('a' * 140) + '.exe'
        (Test-ExecutablePathSafety -Executable $long).IsSafe | Should -BeFalse
    }
}

Describe 'Get-SimulatorRelativePath' {
    It 'не оставляет двойных обратных слешей' {
        # Регрессия: раньше было .Replace('/','\\') => bin\\game.exe
        Get-SimulatorRelativePath -Executable 'bin/game.exe' | Should -Be 'bin\game.exe'
    }

    It 'не меняет путь без слешей' {
        Get-SimulatorRelativePath -Executable 'game.exe' | Should -Be 'game.exe'
    }
}

Describe 'ConvertTo-SafeFileComponent' {
    It 'заменяет запрещённые в Windows символы' {
        ConvertTo-SafeFileComponent -Name 'A/B\C:D*E?F"G<H>I|J' | Should -Not -Match '[\\/:*?"<>|]'
    }

    It 'не оставляет хвостовых точек и пробелов' {
        ConvertTo-SafeFileComponent -Name 'Game...' | Should -Be 'Game'
    }

    It 'возвращает заглушку для пустой строки' {
        ConvertTo-SafeFileComponent -Name '' | Should -Be 'game'
        ConvertTo-SafeFileComponent -Name '   ' | Should -Be 'game'
    }

    It 'ограничивает длину' {
        (ConvertTo-SafeFileComponent -Name ('x' * 200) -MaxLength 20).Length | Should -BeLessOrEqual 20
    }
}

Describe 'New-PlaceholderArguments' {
    It 'возвращает секунды и заголовок в кавычках' {
        $args = New-PlaceholderArguments -Seconds 60 -Title 'My Game'
        $args[0] | Should -Be '60'
        $args[1] | Should -Be '"My Game"'
    }

    It 'не добавляет аргументы гейта без GatePath' {
        (New-PlaceholderArguments -Seconds 60 -Title 'G').Count | Should -Be 2
    }

    It 'добавляет путь гейта и таймаут' {
        $args = New-PlaceholderArguments -Seconds 5 -Title 'G' -GatePath 'C:\gate.signal' -GateTimeoutSeconds 120
        $args.Count | Should -Be 4
        $args[3] | Should -Be '120'
    }

    It 'вырезает кавычки из заголовка (иначе ломается argv)' {
        $args = New-PlaceholderArguments -Seconds 5 -Title 'Bad "Quoted" Game'
        $args[1] | Should -Not -Match '"Bad'
        $args[1] | Should -Be '"Bad Quoted Game"'
    }
}

Describe 'Get-GateTimeoutSeconds' {
    It 'растёт с количеством игр' {
        (Get-GateTimeoutSeconds -Count 100) | Should -BeGreaterThan (Get-GateTimeoutSeconds -Count 5)
    }

    It 'не меньше 90 секунд' {
        (Get-GateTimeoutSeconds -Count 1) | Should -BeGreaterOrEqual 90
    }

    It 'покрывает 100 спавнов процесса' {
        (Get-GateTimeoutSeconds -Count 100) | Should -BeGreaterOrEqual 300
    }
}

Describe 'Get-PlaceholderExitStatus' {
    BeforeAll { $script:Messages = Initialize-SimulatorMessages -Language 'en' }

    It 'код 0 => успех' {
        Get-PlaceholderExitStatus -ExitCode 0 -Messages $script:Messages |
            Should -Be $script:Messages['StatusOk']
    }

    It 'код 3 => окно не дождалось сигнала (а не «успех»)' {
        Get-PlaceholderExitStatus -ExitCode 3 -Messages $script:Messages |
            Should -Be $script:Messages['StatusGateTimeout']
    }

    It 'код 2 => ошибка аргументов' {
        Get-PlaceholderExitStatus -ExitCode 2 -Messages $script:Messages | Should -Match 'arguments'
    }

    It 'прочие коды => ошибка с номером' {
        Get-PlaceholderExitStatus -ExitCode 7 -Messages $script:Messages | Should -Match '7'
    }
}

Describe 'Format-Duration' {
    It 'форматирует секунды' {
        Format-Duration -Seconds 45 | Should -Be '45 с'
    }

    It 'форматирует минуты' {
        Format-Duration -Seconds 125 | Should -Be '2 мин 05 с'
    }

    It 'форматирует часы' {
        Format-Duration -Seconds 8055 | Should -Be '2 ч 14 мин 15 с'
    }

    It 'не падает на отрицательном значении' {
        Format-Duration -Seconds -10 | Should -Be '0 с'
    }

    It 'короткий формат' {
        Format-Duration -Seconds 8055 -Short | Should -Be '2 ч 14 мин'
    }
}

Describe 'Read-CompletedGames + New-HistoryRow' {
    BeforeEach {
        $script:HistoryFile = Join-Path $TestDrive 'history.csv'
    }

    It 'считает выполненными только успешные свежие строки' {
        $messages = Initialize-SimulatorMessages -Language 'en'
        $ok = New-HistoryRow -Time (Get-Date) -Game 'Good' -Executable 'good.exe' `
            -Status $messages['StatusOk'] -Mode 'sequential'
        $bad = New-HistoryRow -Time (Get-Date) -Game 'Bad' -Executable 'bad.exe' `
            -Status 'process error: 2' -Mode 'sequential'
        $old = New-HistoryRow -Time (Get-Date).AddDays(-10) -Game 'Old' -Executable 'old.exe' `
            -Status $messages['StatusOk'] -Mode 'sequential'
        @($ok, $bad, $old) | Export-Csv -LiteralPath $script:HistoryFile -NoTypeInformation -Encoding UTF8

        $completed = @(Read-CompletedGames -HistoryPath $script:HistoryFile `
                -SuccessStatusPrefix $messages['StatusOk'])

        $completed | Should -Contain 'Good'
        $completed | Should -Not -Contain 'Bad'
        $completed | Should -Not -Contain 'Old'
    }

    It 'возвращает пустой список, если файла нет' {
        @(Read-CompletedGames -HistoryPath (Join-Path $TestDrive 'missing.csv')).Count | Should -Be 0
    }

    It 'New-HistoryRow пишет ISO-время и режим' {
        $row = New-HistoryRow -Time ([datetime]'2026-01-02T03:04:05') -Game 'G' `
            -Executable 'g.exe' -Status 'ok' -Mode 'parallel'
        $row.time | Should -Match '^2026-01-02T03:04:05'
        $row.mode | Should -Be 'parallel'
    }
}

Describe 'Initialize-SimulatorMessages' {
    It 'содержит все ключи для ru и en' {
        $ru = Initialize-SimulatorMessages -Language 'ru'
        $en = Initialize-SimulatorMessages -Language 'en'
        foreach ($key in $ru.Keys) {
            $en.ContainsKey($key) | Should -BeTrue -Because "ключа $key нет в английской локали"
        }
        $ru['MenuChoose'] | Should -Not -Be $en['MenuChoose']
    }

    It 'не содержит пустых строк' {
        $ru = Initialize-SimulatorMessages -Language 'ru'
        foreach ($key in $ru.Keys) {
            [string]::IsNullOrWhiteSpace([string]$ru[$key]) | Should -BeFalse -Because "пустой ключ $key"
        }
    }
}

Describe 'Test-PathLengthBudget' {
    It 'пропускает короткий путь' {
        Test-PathLengthBudget -Path 'C:\a\b.exe' | Should -BeTrue
    }

    It 'отклоняет путь длиннее бюджета' {
        Test-PathLengthBudget -Path ('C:\' + ('a' * 300)) | Should -BeFalse
    }
}
