import Testing
@testable import LarariCore

@Suite("Store query")
struct StoreQueryTests {
    @Test func aLetterAndADigitMakeAnAddress() {
        #expect(StoreQuery.isAddress("Andrássy út 12"))
        #expect(StoreQuery.isAddress("Fő utca 1/A"))
        #expect(StoreQuery.isAddress(" Sport u. 2-4., Budaörs "))
    }

    @Test func namesAndNumbersAloneAreNot() {
        #expect(!StoreQuery.isAddress("posta"))
        #expect(!StoreQuery.isAddress("Budaörs"))
        #expect(!StoreQuery.isAddress("  12  "))
        #expect(!StoreQuery.isAddress(""))
    }
}
