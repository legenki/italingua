# Italingua — черновик метаданных App Store

Черновик: владелец проверяет и вставляет в App Store Connect. Лимиты App Store: имя и подзаголовок — 30 символов,
ключевые слова — 100 байт (через запятую, без пробелов), рекламный текст — 170, описание — 4000.

## Общее

| Поле | Значение |
|---|---|
| Имя | Italingua |
| Bundle ID | `com.y6a9lrqdh7.italingua` (iOS + macOS — одна запись приложения, Universal Purchase) |
| SKU | `italingua` |
| Основной язык | Английский (English (U.S.)); русский и испанский — дополнительные локализации страницы |
| Категория | Образование (Education); вторая — Справочники (Reference), по желанию |
| Цена | $4.99 (базовая страна — США), выставлено в ASC 2026-11-22 |
| Страны | все, кроме материкового Китая (174); Apple Intelligence доступна не во всех регионах |
| Возрастной рейтинг | 4+ (нет пользовательского контента от других людей, нет веб-доступа; текст генерируется моделью на устройстве — в анкете ответить «нет» на все пункты) |
| Авторские права | `© 2026 <имя владельца>` |
| URL политики конфиденциальности | https://github.com/legenki/italingua/blob/main/PRIVACY.md |
| URL поддержки | https://github.com/legenki/italingua/issues |
| Маркетинговый URL | необязателен |

### App Privacy («Сбор данных»)
Ответ: **«Данные не собираются»** (Data Not Collected). Прогресс хранится на устройстве и в частной базе CloudKit
пользователя (разработчик её не видит), речь распознаётся на устройстве и не сохраняется, аналитики и рекламы нет.
Совпадает с `App/PrivacyInfo.xcprivacy`.

### Шифрование
`ITSAppUsesNonExemptEncryption = NO` уже в Info.plist — вопрос об экспорте не появится.

---

## Русский (ru)

**Подзаголовок (≤30):** Итальянский A1–A2 по урокам

**Рекламный текст (≤170):**
40 уроков итальянского от нуля до A2: правила простыми словами, 1900+ слов с озвучкой и упражнения, которые
Apple Intelligence составляет прямо на устройстве.

**Ключевые слова (≤100 байт):**
`итальянский,грамматика,слова,карточки,A1,A2,italiano`
(кириллица — 2 байта на букву, поэтому слов меньше; Apple также учитывает слова из имени и подзаголовка)

**Описание:**
Italingua — курс итальянского для начинающих: от алфавита и произношения до уровня A2.

КУРС
• 40 уроков: вводный курс и основная часть, уровни A1 и A2.
• 100 грамматических тем с правилами, объяснёнными простыми словами, таблицами спряжения и примерами с озвучкой.
• Более 1900 слов с переводом, артиклем и произношением.

ПРАКТИКА
• Карточки с интервальным повторением: слова возвращаются тогда, когда пора их повторить.
• «Вставь слово»: предложения на слова урока, ответ можно сказать вслух.
• «Переведи фразу»: свободный перевод с подсказкой минимального исправления и типа ошибки.
• Чтение: короткие тексты на словах урока или упрощение своего текста до уровня A1/A2.
• Ошибки, избранные слова и заметки к правилам — всё под рукой.

ПРИВАТНО И ОФЛАЙН
• Всё работает на устройстве: без аккаунта, рекламы и аналитики.
• Упражнения составляет Apple Intelligence прямо на устройстве; распознавание речи и озвучка — тоже на устройстве.
• Прогресс синхронизируется между iPhone, iPad и Mac через ваш iCloud.

Интерфейс на русском, английском и испанском.

Генерируемые упражнения и тексты требуют устройства с поддержкой Apple Intelligence. Без неё доступны уроки,
правила, словарь, карточки, проверка перевода по образцу и упражнение «вспомни слово по переводу».

**Что нового (1.0):** Первый выпуск.

**Что нового (1.1):**
• iPhone открывается на экране «Сегодня»; все уроки — по кнопке слева вверху.
• Произношение слышно и в беззвучном режиме.
• Кнопки упражнений в уроке — в один ряд.
• Поиск слова показывает список результатов, пока вы печатаете.
• Новая карта уроков в статистике: прогресс по каждому уроку с первого взгляда.
• Аккуратнее отступы, карточка «Слово дня» и показатели на экране iPhone.
• Исправлены ошибки.

---

## English (en)

**Subtitle (≤30):** Italian A1–A2 lesson by lesson

**Promotional text (≤170):**
40 Italian lessons from zero to A2: clear grammar, 1,900+ words with audio, and exercises written on your device
by Apple Intelligence.

**Keywords (≤100 bytes):**
`italian,learn,grammar,vocabulary,flashcards,italy,beginner,A1,A2,verbs,pronunciation,course,italiano`

**Description:**
Italingua is an Italian course for beginners — from the alphabet and pronunciation up to level A2.

THE COURSE
• 40 lessons: an introductory course and the main course, levels A1 and A2.
• 100 grammar topics with plain-language explanations, conjugation tables and spoken examples.
• Over 1,900 words with translation, article and pronunciation.

PRACTICE
• Flashcards with spaced repetition: words come back when it’s time to review them.
• Fill in the blank: sentences built on the lesson’s words — answer by typing or out loud.
• Translate the phrase: free translation with a minimal correction and the type of mistake.
• Reading: short texts on the lesson’s words, or simplify your own text to A1/A2.
• Mistakes, favourite words and your own notes on the rules, all in one place.

PRIVATE AND OFFLINE
• Everything runs on your device: no account, no ads, no analytics.
• Exercises are written on device by Apple Intelligence; speech recognition and audio are on device too.
• Progress syncs across iPhone, iPad and Mac through your iCloud.

Interface in English, Spanish and Russian.

Generated exercises and texts require a device that supports Apple Intelligence. Without it you still get the
lessons, rules, vocabulary, flashcards, translation checking against the model answer, and a recall-the-word-from-its-translation
exercise.

**What’s New (1.0):** First release.

**What’s New (1.1):**
• On iPhone the app opens on Today; all lessons are one tap away at the top left.
• Pronunciation now plays with the Ring/Silent switch on.
• Exercise buttons in a lesson fit in one row.
• Word search keeps the list of results while you type.
• A new lesson map in Statistics shows your progress in every lesson at a glance.
• Tidier margins, Word of the Day card and stats on iPhone.
• Bug fixes.

---

## Español (es)

**Subtítulo (≤30):** Italiano A1–A2 por lecciones

**Texto promocional (≤170):**
40 lecciones de italiano de cero a A2: gramática clara, más de 1900 palabras con audio y ejercicios creados en tu
dispositivo por Apple Intelligence.

**Palabras clave (≤100 bytes):**
`italiano,aprender,gramática,vocabulario,tarjetas,italia,principiante,A1,A2,verbos,curso`

**Descripción:**
Italingua es un curso de italiano para principiantes: desde el alfabeto y la pronunciación hasta el nivel A2.

EL CURSO
• 40 lecciones: un curso introductorio y el curso principal, niveles A1 y A2.
• 100 temas de gramática explicados con palabras sencillas, tablas de conjugación y ejemplos con audio.
• Más de 1900 palabras con traducción, artículo y pronunciación.

PRÁCTICA
• Tarjetas con repetición espaciada: las palabras vuelven cuando toca repasarlas.
• Completa la frase: oraciones con las palabras de la lección; responde escribiendo o en voz alta.
• Traduce la frase: traducción libre con una corrección mínima y el tipo de error.
• Lectura: textos breves con las palabras de la lección, o simplifica tu propio texto a A1/A2.
• Errores, palabras favoritas y tus notas sobre las reglas, todo a mano.

PRIVADO Y SIN CONEXIÓN
• Todo funciona en tu dispositivo: sin cuenta, sin anuncios, sin analítica.
• Apple Intelligence crea los ejercicios en el dispositivo; el reconocimiento de voz y el audio también son locales.
• El progreso se sincroniza entre iPhone, iPad y Mac a través de tu iCloud.

Interfaz en español, inglés y ruso.

Los ejercicios y textos generados requieren un dispositivo compatible con Apple Intelligence. Sin ella siguen
disponibles las lecciones, las reglas, el vocabulario, las tarjetas, la corrección de traducciones con la respuesta
modelo y el ejercicio de recordar la palabra a partir de su traducción.

**Novedades (1.0):** Primera versión.

**Novedades (1.1):**
• En el iPhone la app se abre en Hoy; todas las lecciones están a un toque, arriba a la izquierda.
• La pronunciación se oye también con el iPhone en silencio.
• Los botones de ejercicios de la lección caben en una fila.
• La búsqueda de palabras mantiene la lista de resultados mientras escribes.
• Un nuevo mapa de lecciones en Estadísticas muestra tu progreso en cada lección de un vistazo.
• Márgenes, tarjeta de la Palabra del día y estadísticas más cuidados en el iPhone.
• Corrección de errores.

---

## Заметки для App Review (Review Notes, en)

Ответ на запрос Apple по Guideline 2.1 (2026-11-23): к заметкам нужна запись экрана с iPhone (вложение
в «App Review Information → Attachment»).

```
1. Screen recording: attached to this submission (recorded on iPhone, latest iOS). It starts at launch and shows the Today screen, the lesson list, a lesson with its grammar rule, Flashcards, Fill in the blank, Translate a phrase, Reading and Statistics. The app has no account registration, login, user-generated content or paid content inside the app (it is a paid-upfront app with no In-App Purchases).

2. Purpose and audience: Italingua is an Italian course for beginners (CEFR A1–A2), aimed at adult self-learners, mainly speakers of Russian, English and Spanish (the interface is in these three languages). It solves the problem of learning Italian grammar and vocabulary in a structured way without a teacher or an internet connection: 40 lessons, 100 grammar topics explained in plain language and 1,900+ words with audio, plus spaced-repetition flashcards and exercises that check the learner's answers.

3. How to use: no login, account or sample files are needed. Launch the app: the Today screen opens. Tap "Open lesson" on the Continue card, or open "All lessons" (top left on iPhone) and pick a lesson. In a lesson, open a grammar topic to read the rule and hear the examples; use the buttons at the bottom for Flashcards, Fill in the word, Translate a phrase and Reading. Statistics are in the toolbar (chart icon); Settings (theme, interface language, voice answers) are in the toolbar too. Voice answers in "Fill in the word" are optional and ask for microphone and speech-recognition permission on first use.

4. External services: none. The app does not use any server, third-party SDK, analytics, ads, payment processor or external AI service. It uses only Apple frameworks on the device: Foundation Models (Apple Intelligence, on-device model) to write example sentences, reading texts and translation hints; Speech (on-device SpeechTranscriber, Italian) for optional voice answers; AVSpeechSynthesizer for audio; and the user's private iCloud database (CloudKit) to sync progress between the user's own devices. All course content (lessons, rules, vocabulary) is bundled in the app.

5. Regional differences: the app works the same in all regions. The only difference comes from Apple Intelligence availability: on devices or in regions where Apple Intelligence is not available or not enabled, the app shows a notice and the generated exercises fall back to non-generated versions (recall the word from its translation; translation checked against the model answer). Lessons, grammar, vocabulary, flashcards and statistics work everywhere.

6. Regulated industry / third-party material: not applicable. Italingua is a language-learning app; all course content (texts, rules, word lists, translations) was written by the developer, who owns the rights to it. No third-party copyrighted material is included.

Additional notes:
- Works fully offline; no account or sign-in is needed.
- Progress syncs through the user's private CloudKit database; nothing is sent to the developer.
```

---

## Политика конфиденциальности (текст для страницы по URL)

> **Italingua — политика конфиденциальности.** Italingua не собирает, не передаёт и не продаёт персональные данные.
> В приложении нет аккаунтов, рекламы, аналитики и сторонних SDK. Прогресс обучения хранится на устройстве и, если
> включён iCloud, в частной базе iCloud пользователя — разработчик к ней доступа не имеет. Микрофон используется только
> для голосовых ответов; речь распознаётся на устройстве и не сохраняется. Упражнения составляет модель Apple
> Intelligence на устройстве. Вопросы: `<почта владельца>`.

(Ту же политику нужно выложить на en/es или одной страницей на английском.)

---

## Скриншоты (делает владелец)

Обязательные размеры в App Store Connect на момент подготовки: iPhone 6.9″ (1320×2868 или 1290×2796),
iPad 13″ (2064×2752 или 2048×2732), Mac (16:10, например 2880×1800). По 3–10 штук на язык; можно один набор
на ru и переиспользовать для en/es, если не переводить интерфейс на скриншотах. Сюжеты: список уроков,
тема с правилом и таблицей спряжения, карточки, «Вставь слово», «Переведи фразу», статистика.
