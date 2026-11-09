// Runtime localization for the tray application.
// English is the source language; every other catalog is keyed by the exact
// English string so a missing translation always falls back to readable text.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Web.Script.Serialization;

namespace BatteryGuardTray
{
    internal sealed class LocaleInfo
    {
        public readonly string Code;
        public readonly string Name;
        public readonly bool Rtl;

        public LocaleInfo(string code, string name, bool rtl)
        {
            Code = code;
            Name = name;
            Rtl = rtl;
        }
    }

    internal static class Loc
    {
        public static readonly LocaleInfo[] All =
        {
            new LocaleInfo("en", "English", false),
            new LocaleInfo("ar", "العربية", true),
            new LocaleInfo("es", "Español", false),
            new LocaleInfo("fr", "Français", false),
            new LocaleInfo("de", "Deutsch", false),
            new LocaleInfo("pt", "Português", false),
            new LocaleInfo("it", "Italiano", false),
            new LocaleInfo("ru", "Русский", false),
            new LocaleInfo("zh-CN", "简体中文", false),
            new LocaleInfo("zh-TW", "繁體中文", false),
            new LocaleInfo("ja", "日本語", false),
            new LocaleInfo("ko", "한국어", false),
            new LocaleInfo("hi", "हिन्दी", false),
            new LocaleInfo("bn", "বাংলা", false),
            new LocaleInfo("ur", "اردو", true),
            new LocaleInfo("fa", "فارسی", true),
            new LocaleInfo("tr", "Türkçe", false),
            new LocaleInfo("nl", "Nederlands", false),
            new LocaleInfo("pl", "Polski", false),
            new LocaleInfo("uk", "Українська", false),
            new LocaleInfo("ro", "Română", false),
            new LocaleInfo("el", "Ελληνικά", false),
            new LocaleInfo("cs", "Čeština", false),
            new LocaleInfo("sv", "Svenska", false),
            new LocaleInfo("da", "Dansk", false),
            new LocaleInfo("fi", "Suomi", false),
            new LocaleInfo("he", "עברית", true),
            new LocaleInfo("th", "ไทย", false),
            new LocaleInfo("vi", "Tiếng Việt", false),
            new LocaleInfo("id", "Bahasa Indonesia", false)
        };

        private static readonly Dictionary<string, string> Map =
            new Dictionary<string, string>(StringComparer.Ordinal);
        private static string _code = "en";
        private static bool _loaded;

        [DllImport("kernel32.dll")]
        private static extern ushort GetUserDefaultUILanguage();

        public static string Code
        {
            get { return _code; }
        }

        public static LocaleInfo Find(string code)
        {
            if (string.IsNullOrEmpty(code)) return null;
            foreach (var item in All)
                if (string.Equals(item.Code, code, StringComparison.OrdinalIgnoreCase)) return item;
            return null;
        }

        public static bool IsRtl(string code)
        {
            var item = Find(code);
            return item != null && item.Rtl;
        }

        // PowerShell and other hosts can load a different CurrentUICulture.
        // Ask Windows for the user's display language instead so "auto" follows
        // the device rather than the process that launched the tray.
        private static CultureInfo WindowsUiCulture()
        {
            try
            {
                ushort languageId = GetUserDefaultUILanguage();
                if (languageId != 0)
                {
                    CultureInfo culture = CultureInfo.GetCultureInfo((int)languageId);
                    if (culture != null && !string.IsNullOrEmpty(culture.Name)) return culture;
                }
            }
            catch (Exception ex)
            {
                Program.Log("UI language read error: " + ex.Message);
            }

            return CultureInfo.InstalledUICulture ?? CultureInfo.CurrentUICulture;
        }

        // "auto" follows the Windows user UI language. Chinese is mapped by
        // script/region; Portuguese, Hebrew and Indonesian use their modern
        // two-letter codes. Anything unsupported falls back to English.
        public static string Resolve(string setting)
        {
            string value = (setting ?? "").Trim();
            if (value.Length == 0 || string.Equals(value, "auto", StringComparison.OrdinalIgnoreCase))
            {
                CultureInfo culture = WindowsUiCulture();
                string name = culture.Name ?? "";
                if (name.StartsWith("zh", StringComparison.OrdinalIgnoreCase))
                {
                    if (name.IndexOf("Hant", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        name.EndsWith("TW", StringComparison.OrdinalIgnoreCase) ||
                        name.EndsWith("HK", StringComparison.OrdinalIgnoreCase) ||
                        name.EndsWith("MO", StringComparison.OrdinalIgnoreCase))
                        return "zh-TW";
                    return "zh-CN";
                }

                string two = (culture.TwoLetterISOLanguageName ?? "").ToLowerInvariant();
                if (two == "iw") two = "he";
                if (two == "in") two = "id";
                foreach (var item in All)
                    if (string.Equals(item.Code, two, StringComparison.OrdinalIgnoreCase)) return item.Code;
                return "en";
            }

            var match = Find(value);
            if (match != null) return match.Code;
            if (value.StartsWith("zh-Hant", StringComparison.OrdinalIgnoreCase)) return "zh-TW";
            if (value.StartsWith("zh", StringComparison.OrdinalIgnoreCase)) return "zh-CN";
            return "en";
        }

        public static void Load(string setting)
        {
            string code = Resolve(setting);
            if (_loaded && string.Equals(_code, code, StringComparison.Ordinal)) return;

            _code = code;
            _loaded = true;
            Map.Clear();
            if (string.Equals(code, "en", StringComparison.OrdinalIgnoreCase)) return;

            string path = Path.Combine(Program.LocaleDirectory, code + ".json");
            try
            {
                if (!File.Exists(path)) return;
                var serializer = new JavaScriptSerializer();
                var data = serializer.Deserialize<Dictionary<string, object>>(File.ReadAllText(path));
                if (data == null) return;
                foreach (var pair in data)
                {
                    if (pair.Value == null) continue;
                    string text = Convert.ToString(pair.Value, CultureInfo.InvariantCulture);
                    if (!string.IsNullOrEmpty(text)) Map[pair.Key] = text;
                }
            }
            catch (Exception ex)
            {
                Program.Log("locale read error (" + code + "): " + ex.Message);
            }
        }

        public static string T(string source)
        {
            if (string.IsNullOrEmpty(source)) return source;
            string value;
            return Map.TryGetValue(source, out value) && !string.IsNullOrEmpty(value) ? value : source;
        }

        public static string F(string source, params object[] args)
        {
            try
            {
                return string.Format(CultureInfo.InvariantCulture, T(source), args);
            }
            catch
            {
                return source;
            }
        }

        public static string DisplayName(string code)
        {
            var item = Find(code);
            return item == null ? "English" : item.Name;
        }
    }
}
