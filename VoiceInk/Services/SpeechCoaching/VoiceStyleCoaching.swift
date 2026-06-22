//
//  VoiceStyleCoaching.swift
//  VoiceInk
//
//  Knowledge base for the "How to reach the style" coaching trainer.
//  For each preset style — named rhetorical techniques (what it is → formula →
//  examples) and brief tips per axis. For custom profiles (without a stable key)
//  only generic drills along the delta direction are shown.
//
//  Content draws on four schools: Milton Erickson (NLP), Voss-style negotiation,
//  the Minto pyramid (leadership), and classic oratory (the speaker).
//

import Foundation

/// A localized pair of strings. Resolved via the project's shared L10n.
struct LocStr {
    let ru: String
    let en: String
    var text: String { L10n.t(en: en, ru: ru) }

    init(_ ru: String, _ en: String) {
        self.ru = ru
        self.en = en
    }
}

/// A single coaching technique for a specific axis of a specific style.
struct CoachingPattern: Identifiable {
    let id = UUID()
    let name: LocStr
    let what: LocStr
    let formula: LocStr
    /// Ready-made example phrases. Content is Russian (Russian speech is being trained), language-agnostic.
    let examples: [String]
    let axis: VoiceProfileMatcher.Axis
    /// Profile phrases that this technique implements — shown in the card body
    /// so the user can see exactly which words to add for it.
    let relatedMarkers: [String]
}

/// A generic drill by (axis, direction) — for custom profiles without a stable key.
struct StyleDrill {
    let title: LocStr
    let how: LocStr
}

/// Stable key for a preset style. Names in the DB are editable, so we keep the
/// mapping in one place and only for isPreset profiles.
enum VoiceStyleKey: String {
    case erickson, negotiator, leader, speaker

    static func from(profile: VoiceProfileTarget) -> VoiceStyleKey? {
        guard profile.isPreset else { return nil }
        switch profile.name {
        case "Эриксоновский гипнотизёр": return .erickson
        case "Жёсткий переговорщик":      return .negotiator
        case "Спокойный лидер":           return .leader
        case "Харизматичный спикер":      return .speaker
        default:                          return nil
        }
    }
}

enum VoiceStyleCoaching {

    // MARK: - Public lookup

    /// Style techniques for a specific axis (usually 1, sometimes several for markers).
    static func patterns(for key: VoiceStyleKey?, axis: VoiceProfileMatcher.Axis) -> [CoachingPattern] {
        guard let key else { return [] }
        return allPatterns[key]?.filter { $0.axis == axis } ?? []
    }

    /// A brief style-specific tip for an axis (for presets).
    static func axisDrill(for key: VoiceStyleKey?, axis: VoiceProfileMatcher.Axis) -> LocStr? {
        guard let key else { return nil }
        return axisDrills[key]?[axis]
    }

    /// A generic drill by direction (for custom profiles / fallback).
    static func genericDrill(axis: VoiceProfileMatcher.Axis,
                             direction: VoiceProfileMatcher.AxisDirection) -> StyleDrill? {
        genericDrills[axis]?[direction]
    }

    // MARK: - Named techniques by style

    private static let allPatterns: [VoiceStyleKey: [CoachingPattern]] = [
        .erickson: ericksonPatterns,
        .negotiator: negotiatorPatterns,
        .leader: leaderPatterns,
        .speaker: speakerPatterns
    ]

    private static let ericksonPatterns: [CoachingPattern] = [
        CoachingPattern(
            name: LocStr("Связка pacing-leading", "Pacing-and-leading bridge"),
            what: LocStr(
                "Сначала называешь то, что прямо сейчас бесспорно верно (поза, дыхание, обстановка), потом через мягкую связку ведёшь к нужной мысли. Бесспорное снимает критику.",
                "First name something undeniably true right now, then via a soft connector lead to the suggestion. The undeniable part disarms critique."),
            formula: LocStr(
                "[факт о настоящем] + «и пока» / «и сейчас» + [внушение через «ты можешь»]",
                "[present fact] + «и пока»/«и сейчас» + [suggestion via «ты можешь»]"),
            examples: [
                "И пока ты читаешь эту строку, ты можешь заметить, как дыхание само становится ровнее.",
                "И сейчас, когда ты держишь телефон в руке, ты можешь позволить плечам опуститься."
            ],
            axis: .markers, relatedMarkers: ["и пока", "и сейчас", "ты можешь", "и когда"]),
        CoachingPattern(
            name: LocStr("Вшитая команда в обёртке", "Embedded command"),
            what: LocStr(
                "Прямое указание прячется внутри длинной фразы про возможность. «Ты можешь расслабиться» проходит мимо защиты, ведь грамматически это лишь сообщение о возможности.",
                "A direct instruction hides inside a longer sentence about possibility — grammatically just a statement about an option, so it slips past defenses."),
            formula: LocStr(
                "[обёртка] + «ты можешь» / «и ты» + [действие] + [продолжение, чтобы команда не торчала]",
                "[wrapper] + «ты можешь»/«и ты» + [command] + [tail so it doesn't stick out]"),
            examples: [
                "Интересно, как легко ты можешь отпустить эту тревогу прямо сейчас, ещё не закончив абзац.",
                "И ты замечаешь, насколько проще дышать, когда не нужно держать всё под контролем."
            ],
            axis: .markers, relatedMarkers: ["ты можешь", "и ты"]),
        CoachingPattern(
            name: LocStr("Цепочка трюизмов (yes-set)", "Truism chain / yes-set"),
            what: LocStr(
                "Три-четыре очевидно истинных утверждения подряд через «и» создают инерцию согласия — на последнем звене вставляешь внушение. Заодно удлиняет предложение и поднимает сложность.",
                "Three-four obviously true statements joined by «и» build agreement momentum — on the last link you slip in the suggestion. Bonus: longer sentences and higher complexity."),
            formula: LocStr(
                "[правда 1] + «и» + [правда 2] + «и пока» + [правда 3] + «по мере того как» + [внушение]",
                "[truth 1] + «и» + [truth 2] + «и пока» + [truth 3] + «по мере того как» + [suggestion]"),
            examples: [
                "Ты сидишь, ты дышишь, и пока ты слушаешь эти слова, по мере того как день идёт, тебе становится спокойнее.",
                "Время идёт, мысли приходят и уходят, и пока это происходит, ты можешь выбрать ту, что ведёт к цели."
            ],
            axis: .markers, relatedMarkers: ["и пока", "по мере того как", "ты можешь", "и когда"]),
        CoachingPattern(
            name: LocStr("Пресуппозиция и причинная связка", "Presupposition + causal link"),
            what: LocStr(
                "Спорное подаётся как решённый фон: не «надо ли», а «когда» и «по мере того как». Псевдопричинная связка «это значит что» / «так что» склеивает два факта, будто один вытекает из другого.",
                "The debatable is framed as settled: not «whether» but «when». A pseudo-causal link glues two facts as if one follows from the other."),
            formula: LocStr(
                "[факт] + «это значит что» / «так что» + [вывод]; либо «и когда» / «по мере того как» + [действие]",
                "[fact] + «это значит что»/«так что» + [conclusion]; or «и когда»/«по мере того как» + [action]"),
            examples: [
                "Ты уже дочитал до этого места, это значит что часть тебя хочет разобраться, так что давай разберёмся.",
                "По мере того как ты привыкаешь к новому ритму, это значит что старая тревога теряет власть."
            ],
            axis: .markers, relatedMarkers: ["это значит что", "так что", "и когда", "по мере того как"]),
        CoachingPattern(
            name: LocStr("Двойная связка иллюзорного выбора", "Double bind (illusory choice)"),
            what: LocStr(
                "Выбор из двух вариантов, где оба ведут к нужному результату. Человек выбирает КАК, а не БУДЕТ ЛИ — иллюзия свободы снимает сопротивление. «Возможно / может быть» смягчают рамку.",
                "A choice of two options that both lead where you want. The person picks HOW, not WHETHER — the illusion of freedom removes resistance. The «возможно / может быть» softeners ease the frame."),
            formula: LocStr(
                "«ты можешь» + [вариант А] + «или» + [вариант Б] (оба = нужный исход); приправь «возможно»",
                "«ты можешь» + [A] + «or» + [B] (both = desired); season with «возможно»"),
            examples: [
                "Ты можешь начать прямо сейчас или дать себе минуту — и в любом случае ты начнёшь.",
                "Возможно, ясность придёт сегодня вечером, а возможно завтра утром, но она придёт."
            ],
            axis: .markers, relatedMarkers: ["ты можешь", "возможно", "может быть"]),
        CoachingPattern(
            name: LocStr("Образный заход «представь»", "Imagery opener «imagine»"),
            what: LocStr(
                "Приглашение вообразить переносит в нужную сцену, где человек сам достраивает детали. «Если бы» вводит мягкое сослагательное пространство, а длинное описание сцены тянет предложение к 30 словам.",
                "An invitation to imagine moves the person into a scene they complete themselves. «If» opens a soft hypothetical space, and a long sensory continuation stretches the sentence toward 30 words."),
            formula: LocStr(
                "«представь себе» / «если бы» + [сцена] + «и пока» + [деталь] + «ты можешь» + [ощущение]",
                "«представь себе»/«если бы» + [scene] + «и пока» + [detail] + «ты можешь» + [feeling]"),
            examples: [
                "Представь себе тихое утро, где спешить некуда, и пока свет заполняет комнату, ты можешь почувствовать, что весь день твой.",
                "Представь себе, что решение уже принято, и пока ты привыкаешь к этой мысли, тревога тает сама собой."
            ],
            axis: .sentenceLength, relatedMarkers: ["представь себе", "если бы", "и пока", "ты можешь"])
    ]

    private static let negotiatorPatterns: [CoachingPattern] = [
        CoachingPattern(
            name: LocStr("Якорь-вывод «поэтому»", "Anchor-conclusion bridge"),
            what: LocStr(
                "Каждую мысль закрывай выводом через «поэтому» или «именно поэтому». Наблюдение превращается в позицию, а речь — в череду решений, а не размышлений.",
                "Close every thought with a conclusion via «поэтому». An observation becomes a stance, and speech becomes a chain of decisions rather than musings."),
            formula: LocStr(
                "[факт] — поэтому [действие]. / Именно поэтому [позиция].",
                "[fact] — therefore [action]. / That is exactly why [stance]."),
            examples: [
                "Сроки горят. Поэтому режем объём до главного.",
                "Они молчат три дня. Именно поэтому звоним первыми."
            ],
            axis: .markers, relatedMarkers: ["поэтому", "именно поэтому", "позиция"]),
        CoachingPattern(
            name: LocStr("Калиброванный вопрос «что если / как»", "Calibrated «what if / how» question"),
            what: LocStr(
                "Воссовское ядро. Вместо утверждения — открытый вопрос на «что если» или «как»: он отдаёт контроль собеседнику и вшивает два маркера. При надиктовке формулируй задачи как вопросы себе.",
                "The Voss core. Instead of asserting, pose an open «what if / how» question — it hands control over and embeds two markers."),
            formula: LocStr(
                "Что если [сценарий]? / Как мы [действие], если [условие]?",
                "What if [scenario]? / How do we [action] given [condition]?"),
            examples: [
                "Что если они откажут? Готовим второй вариант.",
                "Что если убрать скидку и добавить срок?"
            ],
            axis: .markers, relatedMarkers: ["что если", "вопрос", "решение"]),
        CoachingPattern(
            name: LocStr("Нумерованный фрейм «первое / второе»", "Numbered frame"),
            what: LocStr(
                "Разбивай мысль на пронумерованные пункты «первое / второе». Структурирует речь, режет воду и сразу даёт два сильных маркера. Идеально для надиктовки решений и писем.",
                "Split the thought into «first / second». Structures speech, cuts filler and yields two strong markers."),
            formula: LocStr(
                "Первое — [пункт]. Второе — [пункт]. Поэтому [вывод].",
                "First — [point]. Second — [point]. Therefore [conclusion]."),
            examples: [
                "Первое — фиксируем цену. Второе — двигаем сроки.",
                "Первое: кто решает. Второе: кто мешает сказать да."
            ],
            axis: .markers, relatedMarkers: ["первое", "второе", "поэтому", "решение"]),
        CoachingPattern(
            name: LocStr("Ярлык + рубленая декларация", "Label + clipped declarative"),
            what: LocStr(
                "Назови ситуацию ярлыком в одной короткой фразе — «Похоже, цель такая». Это воссовский labeling плюс рубленое предложение до 10 слов. Двигает длину вниз и подтягивает маркер «цель».",
                "Name the situation with a one-line label. Voss labeling plus a clipped sub-10-word sentence."),
            formula: LocStr(
                "Похоже, [ярлык]. Цель — [результат]. Точка.",
                "Looks like [label]. The goal — [result]. Period."),
            examples: [
                "Похоже, их держит риск. Цель — снять риск.",
                "Видно, что бюджет жёсткий. Меняем условия, не цену."
            ],
            axis: .sentenceLength, relatedMarkers: ["цель", "результат", "решение", "позиция"]),
        CoachingPattern(
            name: LocStr("Бинарный выбор", "Binary choice framing"),
            what: LocStr(
                "Сворачивай развилку в два чистых варианта со словом «выбор» или «или». Убирает воду и якорит решение. Маркер «выбор» редкий — поднимает ось сильно.",
                "Collapse a fork into two clean options with «choice» or «either/or». Cuts filler and anchors the decision."),
            formula: LocStr(
                "Выбор простой: [А] или [Б]. Я за [А], поэтому [действие].",
                "The choice is simple: [A] or [B]. I pick [A], therefore [action]."),
            examples: [
                "Выбор простой: цена или сроки. Берём сроки.",
                "Либо они дают скидку, либо мы уходим. Это позиция."
            ],
            axis: .markers, relatedMarkers: ["выбор", "решение", "позиция", "поэтому"]),
        CoachingPattern(
            name: LocStr("Цель → результат короткими фразами", "Goal-to-result, short clauses"),
            what: LocStr(
                "Открывай блок целью, закрывай результатом — короткими главными предложениями без придаточных и запятых. Именно отказ от «который / потому что» и запятых роняет сложность к 1, а не сами слова «цель/результат».",
                "Open with the goal, close with the result — in short main clauses, no subordinate clauses or commas. It's dropping «which / because» and commas that lowers complexity to 1, not the words «goal/result» themselves."),
            formula: LocStr(
                "Цель — [что]. Результат — [измеримое]. Точка после каждой.",
                "The goal — [what]. The result — [measurable]. A period after each."),
            examples: [
                "Цель — закрыть сделку. Результат — подпись к среде.",
                "Цель — их «да». Убираем всё лишнее. Это позиция."
            ],
            axis: .complexity, relatedMarkers: ["цель", "результат", "позиция"])
    ]

    private static let leaderPatterns: [CoachingPattern] = [
        CoachingPattern(
            name: LocStr("Вывод вперёд (пирамида Минто)", "Conclusion-first (Minto pyramid)"),
            what: LocStr(
                "Сначала называешь решение или результат одним предложением, потом разворачиваешь аргументы. Слушатель сразу знает, к чему всё идёт — ядро стиля лидера.",
                "State the decision in one sentence first, then unpack the reasoning. The listener instantly knows the destination."),
            formula: LocStr(
                "[решение одним предложением] + потому что + [причина 1] + [причина 2]",
                "[decision in one sentence] + because + [reason 1] + [reason 2]"),
            examples: [
                "Решение: запускаем в среду. Причина — данные собраны, риск минимален.",
                "Мой вывод — переносим релиз. Ниже три фактора, которые на это влияют."
            ],
            axis: .markers, relatedMarkers: ["решение", "результат", "цель"]),
        CoachingPattern(
            name: LocStr("Нумерованная тройка", "Numbered triad"),
            what: LocStr(
                "Раскладывай мысль на «первое / второе / третье». Самый дешёвый способ поднять ось маркеров и одновременно сделать речь структурной без воды.",
                "Break the point into «first / second / third». The cheapest way to raise markers and structure speech."),
            formula: LocStr(
                "Есть [N] пункта. Первое — [X]. Второе — [Y]. Третье — [Z].",
                "There are [N] points. First — [X]. Second — [Y]. Third — [Z]."),
            examples: [
                "Три приоритета на неделю. Первое — нанять. Второе — починить оплату. Третье — отчёт.",
                "Два пункта. Первое — качество кода. Второе — план тестирования."
            ],
            axis: .markers, relatedMarkers: ["первое", "второе", "третье", "приоритет", "план"]),
        CoachingPattern(
            name: LocStr("Назначение ответственности и срока", "Owner-and-deadline assignment"),
            what: LocStr(
                "Каждое действие привязывай к человеку и дате. Язык ответственности и сроков отличает лидера от мечтателя — и это две самых редких маркер-фразы у тебя.",
                "Tie every action to a person and a date. The language of responsibility and deadlines separates a leader from a dreamer."),
            formula: LocStr(
                "[действие] — ответственность на [кто], сроки [когда]",
                "[action] — responsibility on [who], deadline [when]"),
            examples: [
                "Запускаем рассылку — ответственность на Анне, сроки до пятницы.",
                "Подготовка отчёта — ответственность команды, срок неделя."
            ],
            axis: .markers, relatedMarkers: ["ответственность", "сроки", "следующий шаг", "результат"]),
        CoachingPattern(
            name: LocStr("Мостик к следующему шагу", "Next-step bridge"),
            what: LocStr(
                "Закрывай каждый блок мысли явным «следующий шаг». Превращает рассуждение в план и не даёт диктовке расплыться — речь всегда движется к действию.",
                "Close each block with an explicit «next step». Turns reasoning into a plan."),
            formula: LocStr(
                "Итог: [вывод]. Следующий шаг — [конкретное действие].",
                "Bottom line: [conclusion]. Next step — [concrete action]."),
            examples: [
                "Цель ясна. Следующий шаг — собрать команду в 10:00.",
                "План согласован. Следующий шаг — отправить смету клиенту."
            ],
            axis: .markers, relatedMarkers: ["следующий шаг", "план", "цель", "результат", "решение"]),
        CoachingPattern(
            name: LocStr("Рубленая декларатива", "Clipped declarative"),
            what: LocStr(
                "Дроби длинные конструкции на короткие утверждения по 12-18 слов. Убирай придаточные «который / потому что». Спокойная уверенность звучит в коротком предложении.",
                "Split long constructions into short 12-18-word statements. Drop subordinate clauses. Calm confidence lives in short sentences."),
            formula: LocStr(
                "[подлежащее] + [глагол] + [объект]. Точка. Новая мысль — новое предложение.",
                "[subject] + [verb] + [object]. Full stop. New thought — new sentence."),
            examples: [
                "Мы переносим релиз. Данные ещё не готовы. Решение примем в среду.",
                "Бюджет утверждён. Команда собрана. Стартуем в понедельник."
            ],
            axis: .sentenceLength, relatedMarkers: ["решение", "приоритет", "результат"]),
        CoachingPattern(
            name: LocStr("Глаголы вместо отглагольных", "Verbs over nominalizations"),
            what: LocStr(
                "Заменяй канцелярит на простые глаголы: не «осуществить запуск», а «запустить». Снижает сложность к целевым 2 и звучит как живой лидер, а не протокол.",
                "Replace bureaucratic nouns with plain verbs: not «carry out a launch» but «launch». Drops complexity to 2."),
            formula: LocStr(
                "вместо «[существительное] + осуществить / провести» → один простой глагол",
                "instead of «carry out / conduct + [noun]» → one plain verb"),
            examples: [
                "Не «принять решение о переносе», а «решаем перенести».",
                "Не «осуществить проверку качества», а «проверить качество»."
            ],
            axis: .complexity, relatedMarkers: ["решение", "качество", "цель", "план"])
    ]

    private static let speakerPatterns: [CoachingPattern] = [
        CoachingPattern(
            name: LocStr("Правило трёх", "Rule of three"),
            what: LocStr(
                "Три коротких параллельных элемента подряд — мозг ловит ритм и запоминает. Каждый пункт = отдельное короткое предложение, поэтому средняя длина падает к целевым 15 словам.",
                "Three short parallel items in a row — the brain catches the rhythm. Each is its own short sentence, pulling length toward 15 words."),
            formula: LocStr(
                "[элемент 1]. [элемент 2]. [элемент 3]. — три раза подряд одной грамматикой",
                "[item 1]. [item 2]. [item 3]. — three in a row, same grammar"),
            examples: [
                "Это просто. Это быстро. Это работает.",
                "Мы пришли. Мы попробовали. Мы поняли."
            ],
            axis: .sentenceLength, relatedMarkers: ["слушайте", "поймёте"]),
        CoachingPattern(
            name: LocStr("Прямой вызов к слушателю", "Direct call to the audience"),
            what: LocStr(
                "Развернись от темы к человеку: вставь обращение-команду. Слушатель включается, и фраза сразу звучит как речь со сцены, а не пересказ.",
                "Turn from the topic to the person: drop in an address-command. The listener leans in, and the phrase instantly sounds like a speech, not a recap."),
            formula: LocStr(
                "[Слушайте / Давайте / Представь] + , + [мысль, которую ты и так говоришь]",
                "[Listen / Let's / Imagine] + , + [the thought you were going to say anyway]"),
            examples: [
                "Слушайте, тут всё держится на одной детали.",
                "Давайте честно: мы это откладывали полгода."
            ],
            axis: .markers, relatedMarkers: ["слушайте", "давайте", "представьте", "представь"]),
        CoachingPattern(
            name: LocStr("Сенсорный мост", "Sensory bridge"),
            what: LocStr(
                "Не «вот данные», а «посмотрите на данные». Глагол восприятия превращает абстракцию в картинку и ставит маркер профиля. Бьёт две оси: маркеры и образность.",
                "Not «here's the data» but «look at the data». A perception verb turns abstraction into a picture and plants a marker."),
            formula: LocStr(
                "[Представьте / Почувствуйте / Увидите] + [конкретная сцена или результат]",
                "[Imagine / Feel / You'll see] + [a concrete scene or result]"),
            examples: [
                "Представьте: понедельник, инбокс пустой, ни одной просрочки.",
                "Почувствуйте разницу — раньше час, теперь три минуты."
            ],
            axis: .markers, relatedMarkers: ["представьте", "почувствуйте", "увидите", "представь"]),
        CoachingPattern(
            name: LocStr("Микро-история", "Micro-story"),
            what: LocStr(
                "Замени абстрактный тезис коротким случаем. Конкретные существительные и глаголы действия снижают сложность и держат внимание лучше любого аргумента. Рассказывай через двоеточие и тире, а не через «когда» — союз поднял бы сложность обратно.",
                "Swap an abstract claim for a short case. Concrete nouns and action verbs lower complexity and hold attention. Tell it with a colon and a dash, not «when» — the conjunction would push complexity back up."),
            formula: LocStr(
                "Помню [момент / историю]: [конкретное действие] — и [что изменилось]",
                "I remember a [moment / story]: [a concrete action] — and [what changed]"),
            examples: [
                "Помню момент: я чуть не бросил — а потом одно письмо всё развернуло.",
                "Расскажу историю: клиент позвонил в пятницу в шесть вечера — и всё закрутилось."
            ],
            axis: .complexity, relatedMarkers: ["история", "момент"]),
        CoachingPattern(
            name: LocStr("Связка «именно поэтому»", "«That's exactly why» link"),
            what: LocStr(
                "Усиливай вывод акцентом-маркером вместо нейтрального «поэтому». «Именно» и «именно поэтому» добавляют точности и набивают ось маркеров на стыке причины и следствия.",
                "Reinforce a conclusion with an accent-marker instead of a flat «so». «Exactly» adds precision and feeds the markers axis."),
            formula: LocStr(
                "[факт / наблюдение] + именно поэтому + [вывод или действие]",
                "[fact / observation] + that's exactly why + [conclusion]"),
            examples: [
                "Все устали к четвергу — именно поэтому встречу двигаем на утро.",
                "Спрос упал. Именно поэтому мы и меняем заголовок."
            ],
            axis: .markers, relatedMarkers: ["именно", "именно поэтому", "точно"]),
        CoachingPattern(
            name: LocStr("Контраст «было / стало»", "Before / after contrast"),
            what: LocStr(
                "Старое против нового, и раздели их точкой — не тире: метрика считает предложения по точке, так что точка реально режет длинную фразу пополам, а тире нет. Контраст создаёт драматизм.",
                "Old versus new, split by a period — not a dash: the metric counts sentences by the period, so a period actually halves a long phrase while a dash does not. Contrast creates drama."),
            formula: LocStr(
                "Раньше [старое]. Теперь [новое].",
                "Before [old]. Now [new]."),
            examples: [
                "Раньше мы гадали. Теперь мы знаем.",
                "Они говорили «невозможно». Мы сделали за неделю."
            ],
            axis: .sentenceLength, relatedMarkers: ["точно"])
    ]

    // MARK: - Brief per-axis tips (style-specific)

    private static let axisDrills: [VoiceStyleKey: [VoiceProfileMatcher.Axis: LocStr]] = [
        .erickson: [
            .markers: LocStr(
                "Самая тяжёлая ось (30%), а ты почти не вплетаешь маркеры. Начинай каждую мысль со связки «и пока» / «и сейчас» / «и когда», а указания подавай через «ты можешь» вместо «надо».",
                "Heaviest axis (30%) and you barely weave markers in. Open every thought with «и пока»/«и сейчас», and phrase instructions via «ты можешь»."),
            .sentenceLength: LocStr(
                "Тебе надо УДЛИНЯТЬ до 30 слов. Не ставь точку после первой мысли: цепляй вторую через «и пока», «по мере того как». Держи интонацию ровной — модель ставит точку на паузе.",
                "You need to LENGTHEN toward 30 words. Don't end after the first thought: chain a second via «и пока». Keep intonation level."),
            .complexity: LocStr(
                "Цель 5 — многоэтажные конструкции. Поднимай придаточными «который», «когда», «если», «пока», «чтобы» — это счётные маркеры подчинения. Связки «это значит что» / «так что» кормят ось маркер-фраз, а сложность поднимают только запятыми. Дроби длинную фразу паузами, не точками.",
                "Target 5 means multi-level constructions. Raise it with «который», «когда», «если», «пока», «чтобы» — the counted subordination markers. The «это значит что» / «так что» connectors feed the marker axis and only add complexity via commas. Break long phrases with pauses, not periods."),
            .wpm: LocStr(
                "Цель медленная — 105, не гонка. Гипноз живёт в плавности: говори чуть медленнее обычного, тяни гласные на связках. Перелёт штрафуется так же, как недолёт.",
                "Target is slow — 105, not a race. Speak a touch slower, stretch vowels on connectors. Overshoot is penalized like undershoot."),
            .fillers: LocStr(
                "Порог жёсткий — ≤1. Твоя «пауза вместо паразита» здесь и есть инструмент: где рука тянется сказать «ну/вот», молчи или тяни связку «и… пока…». Пауза углубляет транс, паразит ломает.",
                "Strict threshold — ≤1. Your «pause instead of filler» is the tool here: stay silent or stretch a connector. A pause deepens the trance.")
        ],
        .negotiator: [
            .markers: LocStr(
                "Вшивай 4 опорных слова на 100: начинай блоки с «первое/второе», закрывай через «поэтому», задачи ставь как «что если». Почти не используешь «цель», «выбор», «позиция» — добавляй сознательно.",
                "Embed 4 anchors per 100: open with «first/second», close with «поэтому», frame tasks as «что если». Add «цель», «выбор», «позиция» on purpose."),
            .sentenceLength: LocStr(
                "Режь до 10 слов. Длинную мысль ставь на точку, а не на запятую. Одно предложение — одна мысль. После диктовки разбей каждое «и / который» на два.",
                "Cut to 10 words. Break long thoughts on a period. One sentence — one idea. Split every «and/which» into two."),
            .complexity: LocStr(
                "Сложность 1: прямой порядок слов, бытовые слова вместо книжных, ноль придаточных. Говори как отдаёшь команду, а не как пишешь отчёт.",
                "Complexity 1: direct word order, plain words, zero clauses. Speak like you give an order, not write a report."),
            .wpm: LocStr(
                "Держи ~130: контроль, не гонка. Делай паузу после ярлыка и после вывода — пауза якорит сильнее скорости.",
                "Hold ~130: control, not a race. Pause after a label and a conclusion — the pause anchors harder than speed."),
            .fillers: LocStr(
                "Паразитов ≤1. Вместо «ну / как бы / типа» ставь точку и молчи. Пустоту замени маркером: не «ну вот», а «поэтому».",
                "Fillers ≤1. Replace «um/like» with a period and silence. Swap the void for a marker: not «well so», but «поэтому».")
        ],
        .leader: [
            .markers: LocStr(
                "Открывай мысль словом «решение / цель / приоритет», закрывай «следующий шаг / результат». Цель — 3 маркера на 100 слов, у тебя их почти нет. Каждое действие подписывай «ответственность» и «сроки».",
                "Open with «decision/goal/priority», close with «next step/result». Target 3 per 100. Tag every action with «responsibility» and «deadline»."),
            .sentenceLength: LocStr(
                "Держи около 18 слов. Поймал «который», «потому что», «в связи с» — ставь точку и начинай новую мысль. Длинная мысль = две коротких.",
                "Keep about 18 words. If you catch «which», «because» — put a full stop. A long thought = two short ones."),
            .complexity: LocStr(
                "Целься в 2: простые глаголы вместо канцелярита, никаких причастных оборотов. «Запускаем», а не «осуществляем запуск». Одна мысль — одно подлежащее и один глагол.",
                "Aim for 2: plain verbs over bureaucratese, no participial clauses. «We launch», not «we are carrying out a launch»."),
            .wpm: LocStr(
                "Держи спокойные 120 — темп уверенности, не спешки. После каждого пункта списка делай микропаузу: она даёт вес и сама замедляет до цели.",
                "Hold a calm 120 — the pace of confidence. Pause after each list item: it adds weight and slows you to target."),
            .fillers: LocStr(
                "Паразиты заменяй паузой — лидер молчит увереннее, чем мямлит. Цель ≤1. Сомневаешься — остановись на полсекунды, потом скажи вывод.",
                "Replace fillers with a pause — a leader is more confident in silence. Target ≤1. When unsure, stop, then state the conclusion.")
        ],
        .speaker: [
            .markers: LocStr(
                "Цель 4 на 100, а ты почти их не используешь. Начинай каждую 3-4 фразу с обращения: «Слушайте…», «Давайте…», «Представьте…». Выводы помечай «именно поэтому». Добей эту ось первой.",
                "Target 4 per 100 and you barely use them. Open every 3rd-4th phrase with «Listen…», «Let's…». Tag conclusions with «that's exactly why»."),
            .sentenceLength: LocStr(
                "Целевая длина 15, держи короткие рубленые фразы. Длинное предложение с «который» или «потому что» — режь на два. Правило трёх и контраст «было/стало» делают это сами.",
                "Target 15 — keep phrases short. Cut long sentences with «which» in two. Rule of three and before/after contrast do this automatically."),
            .complexity: LocStr(
                "Цель 2 — говори картинками, а не понятиями. Меняй абстрактные существительные («оптимизация») на сцену из микро-истории: кто, что сделал, что увидел. Конкретика всегда проще.",
                "Target 2 — speak in pictures, not concepts. Swap abstract nouns for a micro-story scene: who did what. Concrete is simpler."),
            .wpm: LocStr(
                "Цель 160 — энергичный, но разнообразный темп. Не тарахти ровно: после риторического вопроса держи паузу, потом ускоряйся на правиле трёх. Контраст темпа = харизма.",
                "Target 160 — energetic but varied. Pause after a rhetorical question, then speed up through the rule of three. Tempo contrast equals charisma."),
            .fillers: LocStr(
                "Цель ≤2. Лови «ну», «как бы», «короче» — заменяй рабочей паузой или маркером: вместо «ну вот» скажи «слушайте». Пустое слово превращается в инструмент.",
                "Target ≤2. Catch «um», «like» — replace with a working pause or a marker: instead of «um well» say «listen».")
        ]
    ]

    // MARK: - Generic drills for custom profiles

    private static let genericDrills: [VoiceProfileMatcher.Axis: [VoiceProfileMatcher.AxisDirection: StyleDrill]] = [
        .sentenceLength: [
            .increase: StyleDrill(
                title: LocStr("Удлиняй предложения", "Lengthen sentences"),
                how: LocStr("Соединяй две мысли через «и», «потому что», «при этом» вместо точки.",
                            "Join two thoughts with «and», «because» instead of a full stop.")),
            .decrease: StyleDrill(
                title: LocStr("Руби короче", "Cut shorter"),
                how: LocStr("Одна мысль — одно предложение. Ставь точку там, где тянет на запятую.",
                            "One thought = one sentence. End where you'd put a comma."))
        ],
        .complexity: [
            .increase: StyleDrill(
                title: LocStr("Усложняй конструкции", "Add subordination"),
                how: LocStr("Вставляй придаточные: «который», «если», «когда», «потому что».",
                            "Add clauses: «which», «if», «when», «because».")),
            .decrease: StyleDrill(
                title: LocStr("Упрощай речь", "Simplify"),
                how: LocStr("Дроби сложное на простые фразы, убирай вложенность и канцелярит.",
                            "Break complex constructions into simple phrases, drop nesting."))
        ],
        .wpm: [
            .increase: StyleDrill(
                title: LocStr("Говори энергичнее", "Speak faster"),
                how: LocStr("Формулируй мысль до записи и диктуй без раздумий — паузы тоже идут в хронометраж.",
                            "Form the thought before recording and dictate without hesitation.")),
            .decrease: StyleDrill(
                title: LocStr("Замедли темп", "Slow down"),
                how: LocStr("Делай осознанную паузу после каждой фразы — это снижает WPM и звучит увереннее.",
                            "Pause deliberately after each phrase — it lowers WPM and sounds more assured."))
        ],
        .fillers: [
            .decrease: StyleDrill(
                title: LocStr("Меньше паразитов", "Fewer fillers"),
                how: LocStr("Замени заполнитель паузой — тишина в транскрипт не попадает. Дави верхнее слово из «Топ паразитов».",
                            "Replace the filler with a pause — silence never reaches the transcript."))
        ],
        .markers: [
            .increase: StyleDrill(
                title: LocStr("Вплетай фразы стиля", "Weave in style phrases"),
                how: LocStr("Вставляй характерные фразы профиля в естественные места — открытие мысли и вывод.",
                            "Insert the profile's signature phrases at natural spots — opening a thought and concluding."))
        ]
    ]
}
