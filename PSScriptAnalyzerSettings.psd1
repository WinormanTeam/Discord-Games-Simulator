@{
    # Правила, которые важны для этого проекта.
    Severity     = @('Error', 'Warning')

    IncludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSAvoidUsingPositionalParameters'
        'PSUseApprovedVerbs'
        'PSUseDeclaredVarsMoreThanAssignments'
        'PSUseSingularNouns'
        'PSAvoidUsingInvokeExpression'
        'PSAvoidUsingPlainTextForPassword'
        'PSUseCompatibleSyntax'
        'PSUseCompatibleCmdlets'
        'PSUseCompatibleCommands'
        'PSUseCompatibleTypes'
        'PSMisleadingBacktick'
        'PSPlaceOpenBrace'
        'PSPlaceCloseBrace'
        'PSAvoidTrailingWhitespace'
    )

    Rules        = @{
        # Write-Host осознанно используется: это интерактивная консольная панель,
        # а не библиотека с конвейером. Правило отключено с пояснением.
        PSAvoidUsingWriteHost      = @{ Enable = $false }

        # Позиционные параметры допустимы только в коротких однострочниках.
        PSAvoidUsingPositionalParameters = @{ Enable = $true }

        # Скрипт должен работать в Windows PowerShell 5.1.
        PSUseCompatibleSyntax      = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }

        # Стилевые правила: не блокируем CI из-за них, но фиксируем.
        PSPlaceOpenBrace           = @{ Enable = $true; OnSameLine = $true; IgnoreOneLineBlock = $true }
        PSPlaceCloseBrace          = @{ Enable = $true; NewLineAfter = $true; IgnoreOneLineBlock = $true }
        PSAvoidTrailingWhitespace  = @{ Enable = $true }

        # В CI нет Windows-модулей для полной проверки совместимости cmdlet'ов.
        PSUseCompatibleCmdlets     = @{ Enable = $false }
        PSUseCompatibleCommands    = @{ Enable = $false }
        PSUseCompatibleTypes       = @{ Enable = $false }
    }

    ExcludeRules = @(
        # В репозитории только два корневых скрипта, имена уже согласованы.
        'PSUseSingularNouns'
    )
}
