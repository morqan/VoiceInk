//
//  SpeechMetricTips.swift
//  VoiceInk
//
//  Тексты info-попапов для Speech Analytics и дашборд-блока «Речь сегодня».
//  Каждый текст: что это → как реально считается → цель → как улучшить.
//  Формулы описаны честно, по фактической реализации в SpeechMetricsAnalyzer
//  и VoiceProfileMatcher — включая известные ограничения измерений.
//

import Foundation

enum SpeechMetricTips {

    // MARK: - Stat-карточки

    static var fillers: String {
        L10n.t(
            en: "Filler words from a built-in list (~19 Russian words and phrases: «ну», «вот», «типа», «как бы», «то есть»…) per 100 words: total fillers ÷ total words × 100 over the period. The speech model usually drops «uh/um» sounds on its own, so the real value is slightly higher. Target ≤ 2 is clean prepared speech, up to 4 is the orange zone. To improve: pause instead of filling — silence never reaches the transcript; attack one word from «Top fillers» at a time.",
            ru: "Слова-заполнители из встроенного списка (~19 русских слов и фраз: «ну», «вот», «типа», «как бы», «то есть»…) на каждые 100 слов: сумма паразитов ÷ сумма слов за период × 100. Звуки «эээ/эм» модель распознавания обычно вырезает сама, так что реальное значение чуть выше показанного. Цель ≤ 2 — уровень чистой подготовленной речи, до 4 — оранжевая зона. Как улучшить: вместо заполнителя — пауза (тишина в транскрипт не попадает); выбивай по одному слову из «Топ паразитов» за раз."
        )
    }

    static var sentenceLength: String {
        L10n.t(
            en: "Average words per sentence: total words ÷ number of sentences (split by «. ? !»). Punctuation is placed by the speech model, not by you, so the metric partly reflects its segmentation style. Target ≤ 18 words is the comfortable listening threshold, 18–25 is orange. To shorten: finish the thought with falling intonation and pause — that's where the model puts a period.",
            ru: "Среднее число слов в предложении: сумма слов за период ÷ число предложений (по знакам «. ? !»). Пунктуацию расставляет модель распознавания, не ты, — отчасти метрика отражает её стиль сегментации. Цель ≤ 18 слов — порог комфортного восприятия на слух, 18–25 — оранжевая зона. Чтобы сократить: завершай мысль интонацией вниз и делай паузу — именно там модель ставит точку."
        )
    }

    static var anglicisms: String {
        L10n.t(
            en: "Latin-script words in Russian speech per 100 words. There is no dictionary: any word of ≥ 3 Latin letters counts, including brands and terms (API, GitHub); Cyrillic-spelled loanwords («дедлайн») are not caught. If ≥ 50% of the words are fully Latin, the text counts as English and the metric becomes zero. Target ≤ 1, up to 3 is orange. Unavoidable terms can be excluded via word replacements.",
            ru: "Латинские слова в русской речи на 100 слов. Словаря нет: считается любое слово из ≥ 3 латинских букв, включая бренды и термины (API, GitHub); заимствования кириллицей («дедлайн») не ловятся. Если латинских слов ≥ 50%, текст считается английским и метрика обнуляется. Цель ≤ 1, до 3 — оранжевая зона. Неизбежные термины можно убрать из счёта через словарь замен."
        )
    }

    static var wpm: String {
        L10n.t(
            en: "Words per minute: words ÷ total recording time. KEY POINT — the «pause tax»: pauses and hesitations while you're searching for the next word are counted as time, so this number is your articulation pace MINUS the pauses. A low number usually doesn't mean you talk slowly — it means you stall mid-thought. How to raise it: form the thought before you hit record and dictate without freezing — pure articulation is naturally fast. Target is set by the active style profile (105 for Erickson … 160 for the Speaker); 120–150 is the conversational norm.",
            ru: "Слов в минуту: слова ÷ полное время записи. ГЛАВНОЕ — «паузный налог»: паузы и зависания, пока ты ищешь следующее слово, считаются как время, поэтому это твой темп артикуляции МИНУС паузы. Низкая цифра обычно значит не «говорю медленно», а «проседаю на полуслове». Как поднять: сформулируй мысль до нажатия записи и диктуй без зависаний — чистая артикуляция сама по себе быстрая. Цель задаёт активный профиль стиля (105 у Эриксона … 160 у Спикера); разговорная норма — 120–150."
        )
    }

    static var totalWords: String {
        L10n.t(
            en: "Total dictated volume for the period: the sum of words across counted dictations. Dictations shorter than 15 words are not recorded into analytics at all. No target — it's mileage: the more words, the more reliable the other metrics.",
            ru: "Объём наговоренного за период: сумма слов всех зачтённых диктовок. Диктовки короче 15 слов в аналитику не записываются вовсе. Цели нет — это «пробег»: чем больше слов, тем достовернее остальные метрики периода."
        )
    }

    static var enRuRatio: String {
        L10n.t(
            en: "Language balance: the share of Latin letters among all letters — counted by characters, not words, so long English words weigh more. 0% is pure Russian, 100% is pure English. No target — it's context: in sessions where ≥ 50% of the words are Latin, the anglicism metric is automatically zero.",
            ru: "Языковой баланс: доля латинских букв среди всех букв текста — по символам, а не словам, поэтому длинные английские слова весят больше. 0% — чистый русский, 100% — чистый английский. Порога нет, это контекст: в сессиях, где латинских слов ≥ 50%, метрика англицизмов автоматически нулевая."
        )
    }

    static var complexity: String {
        L10n.t(
            en: "Speech subordination: (subordinating markers «который / чтобы / если / когда / потому что…» + 0.3 × commas) ÷ sentence count, word-boundary matched. Reference: 0 — clipped simple phrases, ~1 — one clause per sentence, 5+ — multi-level constructions. Commas come from the speech model — treat it as a guide, not a precise measure. Target depends on the profile: Negotiator 1, Leader and Speaker 2, Erickson 5.",
            ru: "Подчинённость речи: (подчинительные союзы «который / чтобы / если / когда / потому что…» + 0,3 × запятые) ÷ число предложений, считается по границам слов. Ориентир: 0 — рубленые простые фразы, ~1 — один оборот на предложение, 5+ — многоэтажные конструкции. Запятые ставит модель распознавания — это ориентир, не точное измерение. Цель зависит от профиля: Переговорщик 1, Лидер и Спикер 2, Эриксон 5."
        )
    }

    // MARK: - Совпадение со стилем

    static var matchScore: String {
        L10n.t(
            en: "How close your speech over the period is to the target style, 0–100: a weighted sum of five axes — marker phrases 30%, sentence length 20%, complexity 20%, pace 15%, fillers 15%. Computed locally from dictation text: intonation, pauses and delivery are not measured — it's a lexical approximation of the style, not a full measurement. The fastest gains come from the profile's marker phrases — the heaviest axis.",
            ru: "Похожесть твоей речи за период на целевой стиль, 0–100: взвешенная сумма пяти осей — маркер-фразы 30%, длина предложения 20%, сложность 20%, темп 15%, паразиты 15%. Считается локально по тексту диктовок: интонация, паузы и подача не учитываются — это лексическое приближение к стилю, а не его полное измерение. Быстрее всего скор растёт от маркер-фраз профиля — у этой оси самый большой вес."
        )
    }

    static var axisWPM: String {
        L10n.t(
            en: "Pace proximity to the profile target: 100% at exact match, linearly down to 0% at double the target (or at zero) — over- and undershoot are penalized equally. Note: WPM includes recording pauses, so it reads low.",
            ru: "Близость темпа к цели профиля: 100% при точном попадании, линейно к 0% при темпе вдвое выше цели (или при нуле) — перелёт и недолёт штрафуются одинаково. Помни: WPM считается с паузами записи и потому занижен."
        )
    }

    static var axisSentence: String {
        L10n.t(
            en: "Average sentence length proximity to the profile target; over- and undershoot are penalized equally. To lengthen: join thoughts with «и», «потому что», «по мере того как». To shorten: one thought — one sentence, finish with falling intonation.",
            ru: "Близость средней длины предложения к цели профиля; перелёт и недолёт штрафуются одинаково. Удлинить: соединяй мысли связками «и», «потому что», «по мере того как». Укоротить: одна мысль — одно предложение, завершай интонацией вниз."
        )
    }

    static var axisComplexity: String {
        L10n.t(
            en: "Subordination-per-sentence proximity to the profile target. To raise: add clauses — «который», «если», «когда», «потому что». To lower: split constructions into simple phrases.",
            ru: "Близость числа подчинений на предложение к цели профиля. Поднять: вставляй придаточные — «который», «если», «когда», «потому что». Опустить: дроби конструкции на простые фразы."
        )
    }

    static var axisFillers: String {
        L10n.t(
            en: "100% while fillers stay within the profile threshold; then minus 50 points per threshold-worth of excess (zero at triple the threshold). Cure: pauses instead of fillers.",
            ru: "100%, пока паразитов не больше порога профиля; дальше минус 50 пунктов за каждое превышение на величину порога (0% при тройном пороге). Лечится паузами вместо заполнителей."
        )
    }

    static func axisMarkers(phrases: [String]) -> String {
        let list = phrases.joined(separator: ", ")
        let suffixEn = phrases.isEmpty ? "" : " Profile phrases: \(list)."
        let suffixRu = phrases.isEmpty ? "" : " Фразы профиля: \(list)."
        return L10n.t(
            en: "Frequency of the style's signature phrases per 100 words — the heaviest axis, 30% of the total. Counted at word boundaries, and one phrase covers at most 40% of the target — the style needs a repertoire, not one word on repeat. The shown value is already capped; raw per-phrase counts are on the chips below. Weave phrases into natural spots: opening a thought, concluding.\(suffixEn)",
            ru: "Частота фирменных фраз стиля на 100 слов — самая тяжёлая ось, 30% итога. Считается по границам слов, и одна фраза покрывает не более 40% цели — стилю нужен репертуар, а не одно слово на повторе. Показанный факт — уже с капом; полные счётчики каждой фразы — на chips ниже. Вплетай фразы в естественные места: открытие мысли, вывод.\(suffixRu)"
        )
    }

    // MARK: - Секции

    static var streaks: String {
        L10n.t(
            en: "How many consecutive days the daily aggregate stays on target (for sentence length — day words ÷ day sentences, pooled like the card). Computed over the whole history, regardless of the selected period. A day without dictations doesn't break the streak — it's skipped; only a failing day with data breaks it. Flame at 7 days.",
            ru: "Сколько дней подряд дневной суммарный показатель держится в цели (для длины предложения — слова дня ÷ предложения дня, взвешенно, как на карточке). Считается по всей истории, независимо от выбранного периода. День без диктовок стрик не ломает — он просто пропускается; ломает только день с данными, проваливший цель. Огонёк — с 7 дней."
        )
    }

    static var trends: String {
        L10n.t(
            en: "Daily dynamics for the selected period. A WPM point is the day's pooled pace (day words ÷ day recording time); a fillers point is the day's rate (day fillers ÷ day words × 100), the dashed line is the ≤ 2 target; the Match Score point is the day's match with the active style. Days without dictations aren't drawn as zeros — the line connects neighbors. Watch the slope over 2–4 weeks: individual points are noisy.",
            ru: "Динамика по дням выбранного периода. Точка WPM — честный дневной темп (слова дня ÷ время записей дня); точка паразитов — дневной rate (паразиты дня ÷ слова дня × 100), пунктир — цель ≤ 2; точка Match Score — дневное совпадение с активным стилем. Дни без диктовок не рисуются нулями — линия соединяет соседние точки. Смотри на наклон за 2–4 недели: отдельные точки шумные."
        )
    }

    static var fillerEvolution: String {
        L10n.t(
            en: "Your personal fillers, detected automatically — no manual list. A word is flagged as your filler when it's both frequent AND ubiquitous (appears across many dictations regardless of topic — a topic word isn't ubiquitous). It tracks change over time: new / gone / up / down. A new suspicious word first goes «watching» (not counted) and joins the count only if it persists steadily ≥ 2 weeks — protection against false positives. Note: «эээ/ммм» the speech model doesn't transcribe, so they aren't seen here.",
            ru: "Твои личные паразиты, обнаруженные автоматически — без ручных списков. Слово помечается твоим паразитом, когда оно одновременно частое И вездесущее (встречается во многих диктовках независимо от темы — тематическое слово вездесущим не бывает). Отслеживается динамика: появился / ушёл / вырос / упал. Новое подозрительное слово сначала идёт «под наблюдением» (не в счёт) и попадает в счёт, только если держится устойчиво ≥ 2 недель — защита от ложных срабатываний. Учти: «эээ/ммм» модель распознавания не пишет, поэтому здесь их не видно."
        )
    }

    static var topFillers: String {
        L10n.t(
            en: "Most frequent fillers for the period (up to 10) with hit counts; the dictionary is fixed — ~19 Russian words and phrases. This is your work plan: take the top word and suppress it for a week — the fastest way to drop the overall rate.",
            ru: "Самые частые паразиты за период (до 10) с числом вхождений; словарь фиксированный — ~19 русских слов и фраз. Это твой план работы: возьми верхнее слово и неделю дави именно его — самый быстрый способ уронить общий показатель."
        )
    }

    static var topAnglicisms: String {
        L10n.t(
            en: "Latin-script words for the period by frequency. There is no dictionary — brands and terms (API, GitHub) land here too. Remove unavoidable terms from the count via word replacements.",
            ru: "Латинские слова за период по убыванию частоты. Словаря нет — сюда попадают и бренды с терминами (API, GitHub). Неизбежные термины убери из счёта через словарь замен."
        )
    }

    static var topRepetitions: String {
        L10n.t(
            en: "Words of 4+ letters repeated ≥ 5 times within one dictation (fillers and anglicisms excluded). Counts sum across dictations: «15×» may mean 5+5+5 in three sessions; word forms aren't merged («проект/проекта» count separately). Cure: synonyms — unless it's an irreplaceable term.",
            ru: "Слова от 4 букв, повторённые ≥ 5 раз в пределах одной диктовки (паразиты и англицизмы исключены). Счётчики суммируются между диктовками: «15×» может означать 5+5+5 в трёх сессиях; формы слова не склеиваются («проект/проекта» — разные). Лечится синонимами — если это не незаменимый термин."
        )
    }

    static var recentSessions: String {
        L10n.t(
            en: "Latest dictations of the period (up to 15). Badges: w — words, wpm — pace, f — fillers, en — anglicisms, rep — repeated words. These are raw per-session counts, not per-100-words: «3f» in a long dictation is better than in a short one.",
            ru: "Последние диктовки периода (до 15). Бейджи: w — слов, wpm — темп, f — паразитов, en — англицизмов, rep — слов-повторов. Это сырые счётчики сессии, не на 100 слов: «3f» в длинной диктовке лучше, чем в короткой."
        )
    }
}
