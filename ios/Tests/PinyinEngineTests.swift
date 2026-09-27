import XCTest
@testable import LianAiCore

final class PinyinEngineTests: XCTestCase {
    func testFullDictionaryIsBundled() {
        XCTAssertEqual(PinyinEngine.lexiconEntryCount, 65_125)
    }

    func testIncrementalSpellingAndCommonPhrases() {
        for prefix in ["d", "da", "daj", "daji", "dajia", "dajiah", "dajiaha", "dajiahao"] {
            let matches = PinyinEngine.matches(for: prefix)
            XCTAssertFalse(matches.isEmpty, prefix)
            XCTAssertTrue(matches.contains { $0.inputCount == prefix.count }, prefix)
        }
        for (input, word) in ["d": "的", "dajia": "大家", "dajiahao": "大家好",
                              "nihao": "你好", "wozhidao": "我知道", "xiexie": "谢谢",
                              "beijing": "北京", "shanghai": "上海", "mingtian": "明天"] {
            XCTAssertEqual(PinyinEngine.candidates(for: input).first, word, input)
        }
    }

    func testIncompleteLastSyllableAndInitials() {
        XCTAssertTrue(PinyinEngine.candidates(for: "daj").contains("大家"))
        XCTAssertTrue(PinyinEngine.candidates(for: "niha").contains("你好"))
        XCTAssertTrue(PinyinEngine.candidates(for: "djh").contains("大家好"))
        XCTAssertTrue(PinyinEngine.candidates(for: "nh").contains("你好"))
        XCTAssertTrue(PinyinEngine.candidates(for: "xyz").contains("信用证"))
    }

    func testExplicitSyllableBoundariesAndUmlaut() {
        XCTAssertEqual(PinyinEngine.candidates(for: "xi'an").first, "西安")
        XCTAssertTrue(PinyinEngine.candidates(for: "xi'an").allSatisfy { $0 != "先" })
        XCTAssertFalse(PinyinEngine.candidates(for: "xi'").contains("先"))
        XCTAssertEqual(PinyinEngine.candidates(for: "ni'hao").first, "你好")
        XCTAssertEqual(PinyinEngine.candidates(for: "DAJIAHAO").first, "大家好")
        XCTAssertTrue(PinyinEngine.candidates(for: "nv").contains("女"))
        XCTAssertEqual(PinyinEngine.candidates(for: "nü"), PinyinEngine.candidates(for: "nv"))
    }

    func testCandidateCoverageAndDeterministicRanking() {
        for input in ["d", "shi", "dajiahao", "wozhidao", "nihaoiuv", "xi'an", "djh"] {
            let candidates = PinyinEngine.matches(for: input)
            XCTAssertEqual(candidates, PinyinEngine.matches(for: input))
            XCTAssertEqual(Set(candidates.map(\.text)).count, candidates.count)
            XCTAssertTrue(candidates.allSatisfy { $0.inputCount > 0 && $0.inputCount <= input.count })
        }
        for invalid in ["", "'", "iuv", "hello!", "你好", String(repeating: "a", count: 61)] {
            XCTAssertTrue(PinyinEngine.matches(for: invalid).isEmpty, invalid)
        }
    }

    func testWarmPerKeystrokeLookupLatency() {
        _ = PinyinEngine.lexiconEntryCount
        let inputs = ["d", "da", "daj", "dajia", "dajiah", "dajiahao", "w", "wo", "wozhidao", "n", "nihao"]
        let start = Date()
        for _ in 0..<5 { for input in inputs { _ = PinyinEngine.matches(for: input) } }
        let average = Date().timeIntervalSince(start) / Double(inputs.count * 5)
        print("Pinyin mean warm lookup: \(average * 1000) ms")
        XCTAssertLessThan(average, 0.05, "Candidate lookup should fit a typing frame budget on the development host")
    }
}
