import XCTest
@testable import Memora

final class CardSetSalvageTests: XCTestCase {
    func testCompleteJSONDecodes() throws {
        let raw = #"{"type":"rule","title":"الكسور","note":"","cards":[{"front":"ما قاعدة القسمة على كسر؟","back":"نضرب في مقلوب الكسر"}]}"#
        let set = try AIService.decodeCardSet(raw)
        XCTAssertEqual(set.title, "الكسور")
        XCTAssertEqual(set.cards.count, 1)
    }

    func testCutOffJSONKeepsCompleteCards() throws {
        let raw = #"{"type":"words","title":"Fruit {list}","cards":[{"front":"apple","back":"تفاحة \"حمراء\""},{"front":"pear","back":"كمثرى"},{"front":"plu"#
        let set = try AIService.decodeCardSet(raw)
        XCTAssertEqual(set.cards.map(\.front), ["apple", "pear"])
        XCTAssertEqual(set.cards.first?.back, "تفاحة \"حمراء\"")
        XCTAssertEqual(set.title, "Fruit {list}")
        XCTAssertEqual(set.type, "words")
    }

    func testNothingUsableThrows() {
        XCTAssertThrowsError(try AIService.decodeCardSet(#"{"cards":[{"front":"x"#))
    }
}
