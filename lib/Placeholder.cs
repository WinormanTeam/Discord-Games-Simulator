// Исходник exe-заглушки для Discord Games Simulator.
// Компилируется на лету в powershell (Add-Type -OutputType WindowsApplication).
//
// Аргументы:
//   [0] секунды до автоматического закрытия окна (обязателен, 1..86400)
//   [1] заголовок окна / текст (обязателен)
//   [2] (необязательно) путь к сигнальному файлу: окно ждёт его появления
//   [3] (необязательно) таймаут ожидания сигнала в секундах (по умолчанию 90)
//
// Коды возврата:
//   0 — окно отработало и закрылось по таймеру
//   2 — некорректные аргументы (видно в history.csv как ошибка, а не как успех)
//   3 — сигнальный файл так и не появился (окно не считалось запущенным)
//
// Замечания:
//  * Тип приложения — WindowsApplication, поэтому консоли нет. Все ошибки
//    показываются через MessageBox, иначе пользователь не увидит ничего.
//  * Все обращения к args[] защищены проверкой длины.

using System;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Threading;
using System.Windows.Forms;

internal static class Placeholder
{
    private const int ErrorBadArguments = 2;
    private const int ErrorGateTimeout = 3;

    [STAThread]
    private static int Main(string[] args)
    {
        if (args == null || args.Length < 2)
        {
            return Fail(ErrorBadArguments, "Ожидается минимум два аргумента: секунды и заголовок.\r\n" +
                                          "Expected at least two arguments: seconds and title.");
        }

        int seconds;
        if (!int.TryParse(args[0], NumberStyles.Integer, CultureInfo.InvariantCulture, out seconds)
            || seconds < 1 || seconds > 86400)
        {
            return Fail(ErrorBadArguments, "Некорректное число секунд: \"" + args[0] + "\".\r\n" +
                                          "Invalid seconds value: \"" + args[0] + "\".");
        }

        string title = args.Length > 1 ? args[1] : string.Empty;
        if (string.IsNullOrEmpty(title))
        {
            title = "Discord Games Simulator";
        }
        if (title.Length > 120)
        {
            title = title.Substring(0, 120);
        }

        // Параллельный режим: ждём сигнальный файл, чтобы все окна стартовали вместе.
        if (args.Length > 2 && !string.IsNullOrEmpty(args[2]))
        {
            string gatePath = args[2];
            int timeout = 90;
            if (args.Length > 3)
            {
                int parsedTimeout;
                if (int.TryParse(args[3], NumberStyles.Integer, CultureInfo.InvariantCulture, out parsedTimeout)
                    && parsedTimeout > 0 && parsedTimeout <= 3600)
                {
                    timeout = parsedTimeout;
                }
            }

            DateTime deadline = DateTime.UtcNow.AddSeconds(timeout);
            while (!File.Exists(gatePath))
            {
                if (DateTime.UtcNow > deadline)
                {
                    return ErrorGateTimeout;
                }
                Thread.Sleep(50);
            }
        }

        try
        {
            Application.EnableVisualStyles();
            using (Form form = new Form())
            {
                form.Text = title;
                form.Width = 460;
                form.Height = 140;
                form.StartPosition = FormStartPosition.CenterScreen;
                form.MinimizeBox = false;
                form.ShowIcon = false;

                Label label = new Label();
                label.Text = "Local activity simulator: " + title;
                label.Dock = DockStyle.Fill;
                label.TextAlign = ContentAlignment.MiddleCenter;
                label.AutoEllipsis = true;
                form.Controls.Add(label);

                // Обязательно полное имя: System.Threading.Timer и
                // System.Windows.Forms.Timer одновременно в области видимости.
                using (System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer())
                {
                    timer.Interval = seconds * 1000;
                    timer.Tick += delegate { form.Close(); };
                    timer.Start();
                    Application.Run(form);
                }
            }
            return 0;
        }
        catch (Exception exception)
        {
            return Fail(1, exception.Message);
        }
    }

    private static int Fail(int code, string message)
    {
        try
        {
            MessageBox.Show(message, "Discord Games Simulator", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
        catch
        {
            // MessageBox может быть недоступен в неинтерактивной сессии — молча выходим.
        }
        return code;
    }
}
