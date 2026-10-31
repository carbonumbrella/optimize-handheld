# Optimize-Handheld

Скрипт очистки и настройки Windows 10/11 для портативных ПК: в первую очередь MSI Claw, но подходит и для других. Собран по изменениям, которые были сделаны на Claw 8 AI+.

## Как запустить

Распакуй архив в любую папку и запусти `Optimize-Handheld.cmd`:

1. **Audit**: только проверяет и ничего не меняет. Начни с него.
2. **Apply Standard**: безопасный набор.
3. **Apply Full**: Standard плюс то, чем некоторые всё же пользуются.
4. **Undo**: откат последнего применения.

Скрипт сам запросит права администратора. Перед применением попросит ввести `YES` и попробует создать точку восстановления. После применения перезагрузи устройство и снова запусти аудит: он покажет, что всё осталось на месте и сколько памяти занято.

## Что меняет

| Категория | Уровень | Что делает |
|---|---|---|
| Apps | Standard | Удаляет Clipchamp, Кортану, Bing News, Bing Weather, Bing Search, Get Help, Tips, Office Hub, Solitaire, новый Outlook, People, Power Automate, To Do, Dev Home, Почту и Календарь, Feedback Hub, Teams |
| AI | Standard | Удаляет приложение Copilot и пакеты локального ИИ Windows (Recall, Click to Do и другие), отключает их политиками, запрещает Chrome скачивать Gemini Nano |
| Policies | Standard | Отключает предложения приложений, рекламу, Bing в «Пуск», виджеты, автоустановку OneDrive |
| Telemetry | Standard | Отключает телеметрию, службу DiagTrack, задачи сбора данных |
| Capabilities | Standard | Удаляет Steps Recorder, Internet Explorer, WordPad, Math Recognizer, PowerShell ISE, дополнительные обои, PowerShell 2.0, Work Folders |
| UserTweaks | Standard | Отключает рекламный ID, рекомендации в «Пуск», кнопку виджетов |
| RamTrim | Standard | Отключает предзагрузку Edge и Cross-device Resume |
| LoginKeyboard | Standard | Сенсорная клавиатура работает на экране входа |
| AppsExtra | Full | Удаляет Карты, Phone Link, CrossDevice, виджеты, Media Player, Кино и ТВ, Будильники, Запись голоса, Sticky Notes, Quick Assist |
| TelemetryExtra | Full | Отключает задачи Compatibility Appraiser и Disk Diagnostics |
| CapabilitiesExtra | Full | Удаляет WMIC и старый Windows Media Player. Некоторые установщики производителей вызывают WMIC |
| RamTrimVendor | Full | Убирает из автозапуска Intel DSA, Logitech Options+, интерфейс Intel Graphics, аудиоэффекты DTS и intelliGo. **Звук может измениться** |

**Не трогает:** Xbox, Game Bar, Gaming Services, Store, winget, Edge, Terminal, Calculator, Photos, Camera, Paint, Snipping Tool, Notepad, Family Safety, Windows Update, Защитник Windows, драйверы, утилиты производителей (MSI Center M, ClawTweaks, HidHide, Armoury Crate, Legion Space). Удаляется только то, что перечислено в таблице.

## Что переключить вручную

**ClawTweaks не работает при включённой «Целостности памяти».** Скрипт её не меняет. Если нужен ClawTweaks, выключи её сам: «Безопасность Windows → Безопасность устройства → Изоляция ядра → Целостность памяти», затем перезагрузись. Это снижает защиту Windows, поэтому без ClawTweaks трогать её незачем.

## Лог

Каждый запуск пишет `logs\<режим>-<дата>.log` рядом со скриптом. Если что-то пошло не так, пришли этот файл. Имена учётной записи и компьютера в нём заменены.

- **Состояния:**
  - `SAME`: уже как нужно;
  - `WOULD`: аудит изменил бы;
  - `CHANGED`: изменено;
  - `SKIP`: нет на этом устройстве;
  - `WARN`: предупреждение;
  - `NOADMIN`: нужны права администратора;
  - `FAIL`: ошибка, с причиной и номером строки.
- **Сведения об устройстве:** модель, процессор, версия Windows, главные потребители памяти, автозапуск, сторонние службы и список приложений. Это нужно, чтобы дополнять скрипт для новых устройств.

## Откат

Прежние значения сохраняются в `logs\state-<дата>.json`. Пункт **Undo** возвращает настройки реестра, службы, задачи и компоненты Windows. Для возврата компонентов нужен интернет. Удалённые приложения откат не возвращает: их ставят заново из Microsoft Store, а их список будет в логе.

## После больших обновлений Windows

Крупные обновления возвращают часть приложений и сбрасывают политики. Запусти аудит, и если он покажет `WOULD`, примени скрипт ещё раз.

## Командная строка

```
.\Optimize-Handheld.ps1 -Mode Apply -Level Standard -Skip Capabilities,AI
.\Optimize-Handheld.ps1 -Mode Apply -Only Apps,Telemetry -Yes
.\Optimize-Handheld.ps1 -Mode Undo -StateFile .\logs\state-20261101-120000.json
```

Проверка применения и отката на тестовом разделе реестра: `tests\Test-ApplyUndo.ps1`.
