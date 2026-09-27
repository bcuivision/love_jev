import Foundation

/// An offline decoder backed by the bundled Rime/Android Pinyin IME lexicon.
/// Each result records exactly how much input it replaces; a prefix selection
/// must leave the rest marked in the host document.
struct PinyinCandidate: Equatable, Identifiable {
    let text: String
    let inputCount: Int
    var id: String { "\(inputCount):\(text)" }
}

struct PinyinEngine {
    private static let lexicon = Lexicon()
    static var lexiconEntryCount: Int { lexicon.entries.count }
    static func candidates(for composition: String) -> [String] {
        matches(for: composition).map(\.text)
    }

    static func matches(for composition: String) -> [PinyinCandidate] {
        let input = Array(composition.lowercased().replacingOccurrences(of: "ü", with: "v"))
        guard !input.isEmpty, input.count <= 60,
              input.allSatisfy({ $0 == "'" || ($0 >= "a" && $0 <= "z") }),
              input.first != "'" else { return [] }
        let count = input.count
        var paths = Array(repeating: [Path](), count: count + 1)
        paths[count] = [Path(text: "", score: 0)]
        var leading: [RankedCandidate] = []

        // A small beam over complete words, with completion only at the final
        // syllable. No partial path can masquerade as a whole-input candidate.
        for start in stride(from: count - 1, through: 0, by: -1) {
            if input[start] == "'" {
                paths[start] = paths[start + 1]
                continue
            }
            var choices: [Path] = []
            var code = ""
            var boundaries: [Int] = []
            for end in (start + 1)...count {
                let letter = input[end - 1]
                if letter == "'" {
                    if end > start + 1, input[end - 2] == "'" { break }
                    boundaries.append(code.count)
                    continue
                }
                code.append(letter)
                let terminal = end == count || (end == count - 1 && input[end] == "'")
                let consumed = terminal ? count : end
                let words = lexicon.lookup(code, boundaries: boundaries,
                                           completing: terminal && input.last != "'")
                for word in words {
                    if start == 0 {
                        leading.append(RankedCandidate(text: word.text, inputCount: consumed, score: word.score))
                    }
                    for suffix in paths[consumed].prefix(3) {
                        choices.append(Path(text: word.text + suffix.text, score: word.score + suffix.score))
                    }
                }
            }
            paths[start] = bestPaths(choices, limit: 4)
        }

        var result: [PinyinCandidate] = []
        var seen = Set<String>()
        func append(_ text: String, _ consumed: Int) {
            guard !text.isEmpty, seen.insert(text).inserted else { return }
            result.append(PinyinCandidate(text: text, inputCount: consumed))
        }
        if let sentence = paths[0].first { append(sentence.text, count) }
        // Initials such as nh / djh are a whole-phrase alternative. Full spelling
        // wins whenever it exists (e.g. shi must not become three initials).
        let initials = String(input)
        if !initials.contains("'") {
            for index in lexicon.initials[initials, default: []].prefix(12) {
                append(lexicon.entries[index].text, count)
            }
        }
        leading.sort {
            if $0.inputCount != $1.inputCount { return $0.inputCount > $1.inputCount }
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.text < $1.text
        }
        // Keep shorter choices reachable even when there are many homophones
        // for the full phrase. Users can then compose word by word.
        for candidate in leading.filter({ $0.inputCount == count }).prefix(16) {
            append(candidate.text, candidate.inputCount)
        }
        var perLength: [Int: Int] = [:]
        for candidate in leading where candidate.inputCount < count {
            guard perLength[candidate.inputCount, default: 0] < 6 else { continue }
            perLength[candidate.inputCount, default: 0] += 1
            append(candidate.text, candidate.inputCount)
        }
        // Other sentence combinations are less useful than actual dictionary
        // words (e.g. 大家号 should not push 大家 out of the first visible page).
        for path in paths[0].dropFirst() { append(path.text, count) }
        return Array(result.prefix(48))
    }

    private struct Path { let text: String; let score: Double }
    private struct RankedCandidate { let text: String; let inputCount: Int; let score: Double }
    private static func bestPaths(_ paths: [Path], limit: Int) -> [Path] {
        var seen = Set<String>()
        return Array(paths.sorted {
            $0.score == $1.score ? $0.text < $1.text : $0.score > $1.score
        }.filter { seen.insert($0.text).inserted }.prefix(limit))
    }

    private struct Entry {
        let text: String
        let spelling: String
        let frequency: Int
        var score: Double { log(Double(frequency) + 1) - 16 }
        func accepts(_ boundaries: [Int]) -> Bool {
            guard !boundaries.isEmpty else { return true }
            var offset = 0
            var available = Set<Int>()
            for syllable in spelling.split(separator: " ") {
                offset += syllable.count
                available.insert(offset)
            }
            return boundaries.allSatisfy { available.contains($0) }
        }
    }

    private struct Lexicon {
        let entries: [Entry]
        let exact: [String: [Int]]
        let initials: [String: [Int]]
        let codes: [String]

        init() {
            #if SWIFT_PACKAGE
            let bundle = Bundle.module
            #else
            let bundle = Bundle.main
            #endif
            let source = bundle.url(forResource: "pinyin_simp.dict", withExtension: "yaml")
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
            var entries: [Entry] = []
            entries.reserveCapacity(66_000)
            for line in source.split(separator: "\n") where !line.hasPrefix("#") {
                let fields = line.split(separator: "\t")
                guard fields.count == 3, let frequency = Int(fields[2]) else { continue }
                entries.append(Entry(text: String(fields[0]), spelling: String(fields[1]), frequency: frequency))
            }
            // A packaging failure must not make basic input unusable.
            if entries.isEmpty {
                entries = [Entry(text: "的", spelling: "de", frequency: 4_828_294),
                           Entry(text: "你", spelling: "ni", frequency: 1_000_000),
                           Entry(text: "我", spelling: "wo", frequency: 1_192_789),
                           Entry(text: "你好", spelling: "ni hao", frequency: 20_728),
                           Entry(text: "大家好", spelling: "da jia hao", frequency: 1_115)]
            }
            entries.sort {
                if $0.frequency != $1.frequency { return $0.frequency > $1.frequency }
                if $0.text != $1.text { return $0.text < $1.text }
                return $0.spelling < $1.spelling
            }
            var exact: [String: [Int]] = [:]
            var initials: [String: [Int]] = [:]
            for (index, entry) in entries.enumerated() {
                let syllables = entry.spelling.split(separator: " ")
                exact[syllables.joined(), default: []].append(index)
                if syllables.count > 1 {
                    let key = String(syllables.compactMap(\.first))
                    initials[key, default: []].append(index)
                }
            }
            self.entries = entries
            self.exact = exact
            self.initials = initials
            codes = exact.keys.sorted()
        }

        func lookup(_ code: String, boundaries: [Int], completing: Bool) -> [Path] {
            var result: [Path] = []
            for index in exact[code, default: []] where entries[index].accepts(boundaries) {
                let entry = entries[index]
                result.append(Path(text: entry.text, score: entry.score))
                if result.count == 16 { break }
            }
            if completing {
                var lower = 0, upper = codes.count
                while lower < upper {
                    let middle = (lower + upper) / 2
                    if codes[middle] < code { lower = middle + 1 } else { upper = middle }
                }
                var predictions: [Path] = []
                for position in lower..<codes.count {
                    let key = codes[position]
                    guard key.hasPrefix(code) else { break }
                    guard key != code else { continue }
                    // Only complete the syllable being typed, never add entirely
                    // untyped syllables (d -> 的; daj -> 大家; da != 大家).
                    for index in exact[key, default: []].prefix(4) {
                        let entry = entries[index]
                        let lastLength = entry.spelling.split(separator: " ").last?.count ?? 0
                        guard code.count > key.count - lastLength, entry.accepts(boundaries) else { continue }
                        predictions.append(Path(text: entry.text,
                            score: entry.score - 1.5 - Double(key.count - code.count) * 0.15))
                    }
                }
                result += PinyinEngine.bestPaths(predictions, limit: 12)
            }
            return result
        }
    }
}
