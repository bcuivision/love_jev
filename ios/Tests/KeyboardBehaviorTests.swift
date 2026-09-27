import XCTest
@testable import LianAiCore

final class KeyboardBehaviorTests: XCTestCase {
    @MainActor func testSuggestionAppendsWithoutReplacingDraft() {
        let keyboard = KeyboardModel()
        var draft = "我觉得，"
        keyboard.insert = { draft += $0 }
        keyboard.phase = .ready(.preview)
        keyboard.useSuggestion()
        XCTAssertEqual(draft, "我觉得，" + Suggestion.preview.text)
        XCTAssertEqual(keyboard.feedback, "已填入，可编辑后发送")
    }

    @MainActor func testCompositionBackspaceDoesNotDeleteHostDraft() {
        let keyboard = KeyboardModel()
        var deletes = 0
        keyboard.delete = { deletes += 1 }
        keyboard.type("n")
        keyboard.type("i")
        keyboard.backspace()
        XCTAssertEqual(keyboard.composition, "n")
        XCTAssertEqual(deletes, 0)
        keyboard.backspace()
        keyboard.backspace()
        XCTAssertEqual(deletes, 1)
    }

    @MainActor func testCandidateCommitAndLanguageSwitchPreserveText() {
        let keyboard = KeyboardModel()
        let document = MarkedDocument()
        document.connect(keyboard)
        for letter in "nihao" { keyboard.type(String(letter)) }
        XCTAssertEqual(document.text, "nihao")
        XCTAssertNotNil(document.markedRange)
        XCTAssertEqual(keyboard.candidates.first, "你好")
        keyboard.space()
        XCTAssertEqual(document.text, "你好")
        XCTAssertNil(document.markedRange)
        XCTAssertTrue(keyboard.composition.isEmpty)
        keyboard.switchLanguage()
        keyboard.type("x")
        XCTAssertEqual(document.text, "你好x")
    }

    @MainActor func testMarkedBackspacePreservesDraftAndClearsLastLetter() {
        let keyboard = KeyboardModel()
        let document = MarkedDocument("原有草稿👋")
        document.connect(keyboard)
        keyboard.type("n")
        keyboard.type("i")
        XCTAssertEqual(document.text, "原有草稿👋ni")
        XCTAssertEqual(document.markedSelection, NSRange(location: 2, length: 0))
        keyboard.backspace()
        XCTAssertEqual(document.text, "原有草稿👋n")
        keyboard.backspace()
        XCTAssertEqual(document.text, "原有草稿👋")
        XCTAssertNil(document.markedRange)
        keyboard.backspace()
        XCTAssertEqual(document.text, "原有草稿")
    }

    @MainActor func testCandidateReplacesOnlyMarkedTextInMiddleOfDraft() {
        let keyboard = KeyboardModel()
        let document = MarkedDocument("前文👋后文")
        document.selection = NSRange(location: 4, length: 0)
        document.connect(keyboard)
        for letter in "ni" { keyboard.type(String(letter)) }
        keyboard.commitComposition("你")
        XCTAssertEqual(document.text, "前文👋你后文")
        XCTAssertNil(document.markedRange)
    }

    @MainActor func testPinyinReplacesHostSelection() {
        let keyboard = KeyboardModel()
        let document = MarkedDocument("前旧文字后")
        document.selection = NSRange(location: 1, length: 3)
        document.connect(keyboard)
        for letter in "nihao" { keyboard.type(String(letter)) }
        XCTAssertEqual(document.text, "前nihao后")
        keyboard.returnKey()
        XCTAssertEqual(document.text, "前你好后")
        XCTAssertFalse(document.text.contains("\n"))
    }

    @MainActor func testUnknownPinyinRemainsLiteralWithoutDuplication() {
        let keyboard = KeyboardModel()
        let document = MarkedDocument()
        document.connect(keyboard)
        for letter in "iuv" { keyboard.type(String(letter)) }
        keyboard.returnKey()
        XCTAssertEqual(document.text, "iuv")
        XCTAssertNil(document.markedRange)
    }

    @MainActor func testSuggestionCommitsCompositionBeforeAppending() {
        let keyboard = KeyboardModel()
        let document = MarkedDocument("草稿：")
        document.connect(keyboard)
        for letter in "nihao" { keyboard.type(String(letter)) }
        keyboard.phase = .ready(.preview)
        keyboard.useSuggestion()
        XCTAssertEqual(document.text, "草稿：你好" + Suggestion.preview.text)
        XCTAssertNil(document.markedRange)
    }

    @MainActor func testPunctuationAndLanguageSwitchCommitMarkedTextOnce() {
        let keyboard = KeyboardModel()
        let document = MarkedDocument()
        document.connect(keyboard)
        for letter in "nihao" { keyboard.type(String(letter)) }
        keyboard.type("，")
        for letter in "wo" { keyboard.type(String(letter)) }
        keyboard.switchLanguage()
        keyboard.type("x")
        XCTAssertEqual(document.text, "你好，我x")
        XCTAssertNil(document.markedRange)
    }

    @MainActor func testSwitchingKeyboardFinishesLiteralComposition() {
        let keyboard = KeyboardModel()
        let document = MarkedDocument()
        document.connect(keyboard)
        keyboard.type("n")
        var switched = false
        keyboard.nextKeyboard = {
            XCTAssertNil(document.markedRange)
            switched = true
        }
        keyboard.switchKeyboard()
        XCTAssertEqual(document.text, "n")
        XCTAssertTrue(keyboard.composition.isEmpty)
        XCTAssertTrue(switched)
    }

    @MainActor func testChangingDocumentsDoesNotTouchNewDraft() {
        let keyboard = KeyboardModel()
        let oldDocument = MarkedDocument()
        oldDocument.connect(keyboard)
        keyboard.type("n")
        let newDocument = MarkedDocument("另一个聊天")
        newDocument.connect(keyboard)
        keyboard.resetComposition()
        keyboard.type("w")
        keyboard.type("o")
        keyboard.space()
        XCTAssertEqual(newDocument.text, "另一个聊天我")
        XCTAssertEqual(oldDocument.text, "n")
    }

    @MainActor func testMovingCursorEndsCompositionWithoutReplacingNewSelection() {
        let keyboard = KeyboardModel()
        let document = MarkedDocument("原稿")
        document.connect(keyboard)
        keyboard.type("n")
        keyboard.finishComposition()
        document.selection = NSRange(location: 0, length: 0)
        keyboard.type("w")
        keyboard.type("o")
        keyboard.space()
        XCTAssertEqual(document.text, "我原稿n")
    }

    @MainActor func testRecognizingOrIdleStateCannotInsertPreviousSuggestion() {
        let keyboard = KeyboardModel()
        var inserted = ""
        keyboard.insert = { inserted += $0 }
        keyboard.phase = .ready(.preview)
        keyboard.phase = .recognizing
        keyboard.useSuggestion()
        XCTAssertEqual(inserted, "")
        keyboard.phase = .waiting
        keyboard.useSuggestion()
        XCTAssertEqual(inserted, "")
    }

    func testUnknownPinyinDoesNotInventOrDropSuffix() {
        XCTAssertEqual(PinyinEngine.candidates(for: "wozhidao").first, "我知道")
        let matches = PinyinEngine.matches(for: "nihaoiuv")
        XCTAssertTrue(matches.contains(PinyinCandidate(text: "你好", inputCount: 5)))
        XCTAssertFalse(matches.contains { $0.inputCount == 8 })
    }

    @MainActor func testCandidatesAppearOnFirstLetterAndEveryKeystroke() {
        let keyboard = KeyboardModel()
        let document = MarkedDocument()
        document.connect(keyboard)
        for letter in "Dajiahao" {
            keyboard.type(String(letter))
            XCTAssertFalse(keyboard.candidates.isEmpty, keyboard.composition)
            XCTAssertEqual(document.text, keyboard.composition)
        }
        XCTAssertEqual(keyboard.candidates.first, "大家好")
        keyboard.space()
        XCTAssertEqual(document.text, "大家好")
        XCTAssertNil(document.markedRange)
        XCTAssertTrue(keyboard.candidateMatches.isEmpty)
    }

    @MainActor func testPartialSelectionKeepsSuffixMarkedInMiddleOfDraft() throws {
        let keyboard = KeyboardModel()
        let document = MarkedDocument("前文👋后文")
        document.selection = NSRange(location: 4, length: 0)
        document.connect(keyboard)
        for letter in "dajiahao" { keyboard.type(String(letter)) }
        let everyone = try XCTUnwrap(keyboard.candidateMatches.first { $0.text == "大家" })
        keyboard.selectCandidate(everyone)
        XCTAssertEqual(document.text, "前文👋大家hao后文")
        XCTAssertEqual(keyboard.composition, "hao")
        XCTAssertEqual(document.markedRange, NSRange(location: 6, length: 3))
        keyboard.backspace()
        XCTAssertEqual(document.text, "前文👋大家ha后文")
        keyboard.type("o")
        keyboard.space()
        XCTAssertEqual(document.text, "前文👋大家好后文")
        XCTAssertNil(document.markedRange)
    }

    @MainActor func testInvalidSuffixAndStaleCandidateCannotDeleteInput() throws {
        let keyboard = KeyboardModel()
        let document = MarkedDocument()
        document.connect(keyboard)
        for letter in "nihao" { keyboard.type(String(letter)) }
        let stale = try XCTUnwrap(keyboard.candidateMatches.first)
        keyboard.resetComposition()
        document.markedRange = nil
        for letter in "iuv" { keyboard.type(String(letter)) }
        keyboard.selectCandidate(stale)
        XCTAssertEqual(document.text, "nihaoiuv")
        keyboard.commitComposition()
        XCTAssertEqual(document.text, "nihaoiuv")
        XCTAssertNil(document.markedRange)
    }

    @MainActor func testUnknownSuffixSurvivesPrefixSelectionAndPunctuation() throws {
        let keyboard = KeyboardModel()
        let document = MarkedDocument()
        document.connect(keyboard)
        for letter in "nihaoiuv" { keyboard.type(String(letter)) }
        keyboard.selectCandidate(try XCTUnwrap(keyboard.candidateMatches.first { $0.text == "你好" }))
        XCTAssertEqual(keyboard.composition, "iuv")
        XCTAssertEqual(document.text, "你好iuv")
        keyboard.type("，")
        XCTAssertEqual(document.text, "你好iuv，")
        XCTAssertNil(document.markedRange)
    }

    @MainActor func testBackspaceAndLanguageSwitchClearCandidateState() {
        let keyboard = KeyboardModel()
        keyboard.type("d")
        XCTAssertFalse(keyboard.candidates.isEmpty)
        keyboard.backspace()
        XCTAssertTrue(keyboard.candidates.isEmpty)
        keyboard.type("n")
        keyboard.switchLanguage()
        XCTAssertTrue(keyboard.candidates.isEmpty)
        keyboard.type("D")
        XCTAssertTrue(keyboard.composition.isEmpty)
    }
}

/// Models the host's UTF-16 selection and marked range, including text after the cursor.
@MainActor private final class MarkedDocument {
    var text: String
    var selection: NSRange
    var markedRange: NSRange?
    var markedSelection: NSRange?

    init(_ text: String = "") {
        self.text = text
        selection = NSRange(location: text.utf16.count, length: 0)
    }

    func connect(_ keyboard: KeyboardModel) {
        keyboard.markText = { [self] text, range in
            let target = markedRange ?? selection
            replace(target, with: text)
            markedRange = NSRange(location: target.location, length: text.utf16.count)
            markedSelection = range
            selection = NSRange(location: target.location + range.location, length: range.length)
        }
        keyboard.unmarkText = { [self] in markedRange = nil; markedSelection = nil }
        keyboard.insert = { [self] text in replace(markedRange ?? selection, with: text); markedRange = nil }
        keyboard.delete = { [self] in
            if selection.length > 0 { replace(selection, with: ""); return }
            guard selection.location > 0 else { return }
            let prefix = (text as NSString).substring(to: selection.location)
            let length = String(prefix.last!).utf16.count
            replace(NSRange(location: selection.location - length, length: length), with: "")
        }
    }

    private func replace(_ range: NSRange, with value: String) {
        text = (text as NSString).replacingCharacters(in: range, with: value)
        selection = NSRange(location: range.location + value.utf16.count, length: 0)
    }
}

final class RecommendationReasonTests: XCTestCase {
    @MainActor func testReasonIsHiddenUntilTappedAndNeverInserted() {
        let keyboard = KeyboardModel()
        keyboard.phase = .ready(.preview)
        var draft = "原有草稿"
        keyboard.insert = { draft += $0 }
        XCTAssertFalse(keyboard.showsRecommendationReason)
        keyboard.toggleRecommendationReason()
        XCTAssertTrue(keyboard.showsRecommendationReason)
        XCTAssertEqual(draft, "原有草稿")
        keyboard.useSuggestion()
        XCTAssertEqual(draft, "原有草稿" + Suggestion.preview.text)
        XCTAssertFalse(keyboard.showsRecommendationReason)
    }

    @MainActor func testNewAnalysisAndDraftChangesDismissPreviousReason() {
        let keyboard = KeyboardModel()
        keyboard.phase = .ready(.preview)
        keyboard.toggleRecommendationReason()
        keyboard.phase = .recognizing
        XCTAssertFalse(keyboard.showsRecommendationReason)
        keyboard.toggleRecommendationReason()
        XCTAssertFalse(keyboard.showsRecommendationReason)
        keyboard.phase = .ready(.preview)
        keyboard.toggleRecommendationReason()
        keyboard.draftImpactPhase = .waiting
        XCTAssertFalse(keyboard.showsRecommendationReason)
        keyboard.toggleRecommendationReason()
        XCTAssertFalse(keyboard.showsRecommendationReason)
    }

    @MainActor func testReasonClosesWithoutChangingKeyboardOrDraft() {
        let keyboard = KeyboardModel()
        keyboard.phase = .ready(.preview)
        keyboard.layout = .numbers
        keyboard.toggleRecommendationReason()
        keyboard.toggleRecommendationReason()
        XCTAssertFalse(keyboard.showsRecommendationReason)
        XCTAssertEqual(keyboard.layout, .numbers)
        XCTAssertEqual(keyboard.suggestion, .preview)
    }

    func testStructuredReasonDecodesAndOldResponsesRemainCompatible() throws {
        let legacy = #"{"sessionID":"s","revision":1,"recommendation":"你好","intimacy":null,"explanation":"旧版说明","isDemo":false}"#
        let decoder = JSONDecoder()
        XCTAssertNil(try decoder.decode(AssistantResponse.self, from: Data(legacy.utf8)).reason)
        let encoded = try JSONEncoder().encode(Suggestion.preview)
        let restored = try decoder.decode(Suggestion.self, from: encoded)
        XCTAssertEqual(restored.reason, Suggestion.preview.reason)
        XCTAssertTrue(restored.reason?.isValid == true)
        XCTAssertFalse(RecommendationReason(relationshipStage: " ", observation: "依据", action: "行动", expectedResult: "效果").isValid)
        XCTAssertFalse(RecommendationReason(relationshipStage: "了解中", observation: "依据", action: String(repeating: "长", count: 301), expectedResult: "效果").isValid)
    }
}
