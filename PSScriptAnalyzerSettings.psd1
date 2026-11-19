@{
    # ВАЖНО: здесь намеренно НЕТ ключа Severity.
    # Если Severity задан в файле настроек, он перебивает параметр -Severity
    # командлета Invoke-ScriptAnalyzer, и разделение «ошибки / предупреждения»
    # в CI ломается. Уровень задаётся в самом workflow.

    IncludeRules = @(
        'PSAvoidUsingPositionalParameters'
        'PSUseApprovedVerbs'
        'PSUseDeclaredVarsMoreThanAssignments'
        'PSAvoidUsingInvokeExpression'
        'PSAvoidUsingPlainTextForPassword'
        'PSAvoidGlobalVars'
        'PSUseCompatibleSyntax'
        'PSMisleadingBacktick'
        'PSAvoidTrailingWhitespace'
        'PSPossibleIncorrectComparisonWithNull'
        'PSUseOutputTypeCorrectly'
    )

    Rules        = @{
        # Write-Host осознанно используется: это интерактивная консольная панель,
        # а не библиотека с конвейером. Правило отключено и НЕ включено в
        # IncludeRules выше (иначе оно включается обратно).
        PSAvoidUsingWriteHost      = @{ Enable = $false }

        # Позиционные параметры допустимы только в коротких однострочниках.
        PSAvoidUsingPositionalParameters = @{ Enable = $true }

        # Основной таргет — Windows PowerShell 5.1.
        PSUseCompatibleSyntax      = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.0')
        }

        # В CI нет Windows-модулей для полной проверки совместимости.
        PSUseCompatibleCmdlets     = @{ Enable = $false }
        PSUseCompatibleCommands    = @{ Enable = $false }
        PSUseCompatibleTypes       = @{ Enable = $false }
    }

    ExcludeRules = @(
        # В репозитории два корневых скрипта, имена уже согласованы.
        'PSUseSingularNouns'
    )
}
