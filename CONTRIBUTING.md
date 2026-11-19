# Как внести вклад

Спасибо за интерес к проекту! Ниже — минимальные правила, которые
сэкономят время и вам, и мейнтейнеру.

## Что приветствуется

- Исправления багов с описанием шагов воспроизведения.
- Улучшение устойчивости (сеть, пути, кодировки, коды возврата).
- Новые Pester-тесты, особенно на `Select-CompatibleGames` и работу с путями.
- Правки документации и переводы.

## Перед PR

1. Проверьте синтаксис и тесты локально:

   ```powershell
   Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -Force
   Install-Module PSScriptAnalyzer -Scope CurrentUser -Force

   Invoke-Pester -Path ./tests
   Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
   ```

2. Убедитесь, что `Start.cmd` остался с переводами строк **CRLF**
   (это закреплено в `.gitattributes`).
3. Логика, которую можно протестировать без Windows, должна жить в
   `lib/SimulatorCore.ps1`, а не в `Run-Simulator.ps1`.
4. Не коммитьте `simulator-data/`, собранные `.exe`, журналы и архивы —
   они в `.gitignore`.

## Требования к совместимости

- Windows PowerShell **5.1** — основной таргет. Не используйте `?.`, `??`,
  `-Parallel` у `ForEach-Object` и другие возможности PowerShell 7+.
- `ConvertTo-Json` не принимает конвейерный ввод в 5.1: используйте
  `ConvertTo-Json -InputObject $x`.
- Любой новый файл `.ps1` должен проходить `Parser::ParseFile` без ошибок.

## Стиль

- Отступ — 4 пробела, кодировка UTF-8.
- Публичные функции: глагол из `Get-Verb`, `[CmdletBinding()]`, comment-based help.
- Пользовательские сообщения — через хэш-таблицу в
  `Initialize-SimulatorMessages` (ru **и** en), а не литералами по коду.

## Сообщения об ошибках

Прикладывайте:

- версию Windows и `$PSVersionTable.PSVersion`,
- журнал `simulator-data/logs/run-*.log`,
- скриншот консоли с текстом ошибки.

## Лицензия

Отправляя PR, вы соглашаетесь на распространение кода под лицензией MIT.
