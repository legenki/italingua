# Italingua — подготовка к App Store

Состояние на 2026-11-20. Что уже сделано в репозитории и что может сделать только владелец.

## Сделано в проекте

| Что | Где |
|---|---|
| Версия и номер сборки из `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` (1.0 / 1) | `Config/Base.xcconfig`, `project.yml` |
| `ITSAppUsesNonExemptEncryption = NO` (только системное шифрование) | `project.yml` → `Config/Info.plist` |
| Hardened Runtime на macOS (`ENABLE_HARDENED_RUNTIME[sdk=macosx*]`) | `Config/Base.xcconfig` |
| Privacy Manifest: без трекинга, без сбора данных, UserDefaults — причина `CA92.1` | `App/PrivacyInfo.xcprivacy` |
| Категория `public.app-category.education`, строки микрофона/распознавания речи на ru/en/es | `project.yml`, `App/InfoPlist.xcstrings` |
| Черновик метаданных ru/en/es, ключевые слова, заметки для ревью, текст политики | `AppStore/metadata.md` |

Проверено:
- Тесты (`... CODE_SIGNING_ALLOWED=NO test`) и `tools/validate_content.py` проходят.
- `xcodebuild archive` для macOS собирается (подпись Apple Development): Hardened Runtime включён, в бандле есть
  `Italingua.icns`, `Assets.car`, `PrivacyInfo.xcprivacy`; entitlements — CloudKit, App Sandbox, микрофон, сеть-клиент.
- iOS-сборка без подписи (Release, generic iOS): иконка `Italingua60x60@2x.png` / `76x76@2x~ipad.png` и `Assets.car`
  генерируются из `Config/Italingua.icon` (Icon Composer), манифест в бандле. Маркетинговая иконка 1024 берётся из
  `Assets.car` — отдельный PNG не нужен.
- Без Apple Intelligence: `ModelStatus` показывает причину; «Вставь слово» переходит на `FallbackFillBlankGenerator`
  (вспомнить слово по переводу), «Переведи фразу» сверяет только с образцом, «Чтение» показывает предупреждение.
- Без iCloud: хранилище `Progress` (`cloudKitDatabase: .automatic`) работает локально и начинает синхронизацию после
  входа в iCloud; экран статистики показывает статус аккаунта.
- Без распознавания итальянского / без доступа к микрофону — сообщение об ошибке, ответ можно ввести текстом.

Оставлено как есть:
- `aps-environment = development` в entitlements: при экспорте для App Store Xcode подставляет значение из
  дистрибутивного профиля (`production`). Проверить в Organizer → Distribute → «Summary» — должно быть `production`.
- `com.apple.security.network.client`: офлайн-приложению сеть не нужна, но entitlement оставлен для CloudKit и
  скачивания языкового пакета распознавания (идут через системные службы, но удалять его без проверки
  подписанной синхронизации рискованно). На ревью не влияет.

## Шаги владельца

1. **Xcode → Settings → Accounts**: добавить Apple ID команды `Y6A9LRQDH7`. Без аккаунта iOS-архив не собирается
   («No Accounts… No profiles for com.y6a9lrqdh7.italingua»); macOS-архив собрался только потому, что профиль
   уже лежал локально.
2. **Developer portal → Identifiers**: у `com.y6a9lrqdh7.italingua` включены iCloud (CloudKit, контейнер
   `iCloud.com.y6a9lrqdh7.italingua`) и Push Notifications (нужны для тихих пушей CloudKit). Automatic signing создаст
   дистрибутивные профили сам.
3. **CloudKit Console → контейнер `iCloud.com.y6a9lrqdh7.italingua` → Schema → Deploy Schema Changes…** —
   выкатить схему из Development в Production. Перед этим один раз запустить **подписанную** сборку и
   пройти хотя бы одно упражнение, добавить слово в избранное, заметку к правилу и т. д., чтобы все типы записей
   (`CD_WordProgress`, `CD_Mistake`, `CD_RuleNote`, `CD_ReviewLog`, `CD_FavoriteWord`, `CD_SessionRecord`) появились
   в Development. Без деплоя синхронизация в App Store/TestFlight-сборках не работает. После релиза поля и типы можно
   только добавлять — удалять и переименовывать модели прогресса нельзя.
4. **App Store Connect → Apps → +**: новое приложение, платформы iOS и macOS, bundle ID `com.y6a9lrqdh7.italingua`,
   основной язык — английский (English (U.S.)), русский и испанский — локализации; SKU `italingua`. Заполнить по `AppStore/metadata.md`: цену и страны (не указаны),
   App Privacy («Data Not Collected»), возрастной рейтинг, категорию, локализации ru/en/es.
5. **Политика конфиденциальности и поддержка**: опубликовать страницу (текст в `metadata.md`) и указать оба URL.
6. **Сборка и загрузка** (для каждой платформы):
   ```bash
   xcodegen generate
   ```
   затем в Xcode: схема Italingua → Any iOS Device (arm64) → Product → Archive → Distribute App → App Store Connect →
   Upload; то же для «My Mac». Или из терминала (сначала macOS, затем `generic/platform=iOS`):
   ```bash
   xcodebuild -project Italingua.xcodeproj -scheme Italingua -configuration Release -destination 'generic/platform=macOS' -archivePath build-archive/Italingua-macOS.xcarchive -allowProvisioningUpdates archive
   ```
   ```bash
   xcodebuild -exportArchive -archivePath build-archive/Italingua-macOS.xcarchive -exportPath build-archive/export-macOS -exportOptionsPlist AppStore/ExportOptions.plist -allowProvisioningUpdates
   ```
   Перед каждой новой загрузкой увеличивать `CURRENT_PROJECT_VERSION` в `Config/Base.xcconfig`.
7. **TestFlight**: проверить на устройстве с Apple Intelligence и без неё, с iCloud и без, синхронизацию iPhone ↔ Mac
   (после шага 3).
8. **Скриншоты**: iPhone 6.9″, iPad 13″, Mac — размеры и сюжеты в `metadata.md`.
9. **Review Notes**: вставить текст из `metadata.md` (Apple Intelligence, голос, офлайн).
10. Отправить на ревью; для macOS и iOS — отдельные версии на одной записи приложения.
