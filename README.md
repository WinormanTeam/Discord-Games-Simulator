<div align="center">

<img width="100%" alt="Discord Games Simulator Banner" src="https://github.com/user-attachments/assets/231d9767-032d-49ed-971d-24a49c72fad0" />

# 🎮 Discord-Games-Simulator

**Экспериментальная имитация запуска 100 игр для получения значка «Универсал».**  
*Никакие игры скачивать и устанавливать не нужно!*

![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=for-the-badge&logo=powershell&logoColor=white)
![Discord](https://img.shields.io/badge/Discord-5865F2?style=for-the-badge&logo=discord&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white)

<br>

<img width="369" height="242" alt="Simulator Preview" src="https://github.com/user-attachments/assets/920c07ab-7660-4d5f-8552-6c669f93e709" />

</div>

---

## ✨ Возможности

| Функция | Описание |
| :--- | :--- |
| 🎯 **100 игр в базе** | Используются игры напрямую из официального каталога Discord. |
| 🔒 **Полная безопасность** | Не требуются пароль или токен — скрипт **не заходит** в ваш аккаунт. |
| 💾 **Экономия места** | Сами игры не скачиваются, создаются лишь пустые `.exe` файлы-заглушки. |
| 📊 **Удобная панель** | Отображает текущую игру, имя EXE, PID, таймер, прогресс и статус Discord. |
| 📝 **Логирование** | Вся история запусков аккуратно сохраняется в `simulator-data/history.csv`. |
| 🛑 **Умное завершение** | Остановка в любой момент через `Ctrl+C`. Если закрыть окно, процессы сами завершатся по таймеру. |
| 🔍 **Открытый код** | Весь исходный код прозрачен и легко читается в файле `.ps1`. |

---

## 🚀 Как пользоваться

> [!IMPORTANT]
> **Важно:** Файлы `Start.cmd` и `Run-Simulator.ps1` обязательно должны лежать рядом в одной папке!

1. **Распакуй архив** в любую удобную папку на компьютере.
2. **Открой десктопный Discord** и убедись, что включено обнаружение игровой активности (*Настройки → Зарегистрированные игры*).
3. **Дважды кликни по `Start.cmd`**, выбери нужный режим в меню и запусти тест.
