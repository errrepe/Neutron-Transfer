// Neutron Transfer — FolderNameValidator offline tests (Swift Testing).
// Pure validation rules for the New Folder sheet: trim, empty, invalid
// characters, reserved names, UTF-8 byte cap and NFC normalization.
// No network, no secrets.
import Foundation
import Testing

@testable import NeutronTransfer

struct FolderNameValidatorTests {
    @Test func plainNamePasses() {
        #expect((try? FolderNameValidator.validate("Invoices").get()) == "Invoices")
    }

    @Test func trimsWhitespace() {
        let got = try? FolderNameValidator.validate("  Untitled Folder \n").get()
        #expect(got == "Untitled Folder")
    }

    @Test func whitespaceOnlyIsEmpty() {
        #expect(FolderNameValidator.validate("   \n\t ") == .failure(.empty))
        #expect(FolderNameValidator.validate("") == .failure(.empty))
    }

    @Test func slashIsInvalid() {
        #expect(FolderNameValidator.validate("a/b") == .failure(.invalidCharacters))
        #expect(FolderNameValidator.validate("/root") == .failure(.invalidCharacters))
    }

    @Test func nulIsInvalid() {
        #expect(FolderNameValidator.validate("a\0b") == .failure(.invalidCharacters))
    }

    @Test func dotNamesAreReserved() {
        #expect(FolderNameValidator.validate(".") == .failure(.reserved))
        #expect(FolderNameValidator.validate("..") == .failure(.reserved))
        // Names that merely CONTAIN dots are fine.
        #expect((try? FolderNameValidator.validate(".config").get()) == ".config")
        #expect((try? FolderNameValidator.validate("a..b").get()) == "a..b")
    }

    @Test func byteCapIsUtf8() {
        let ok = String(repeating: "a", count: 255)
        #expect((try? FolderNameValidator.validate(ok).get()) == ok)
        let tooLong = String(repeating: "a", count: 256)
        #expect(FolderNameValidator.validate(tooLong) == .failure(.tooLong))
        // Multibyte: 128 × "é" (2 UTF-8 bytes each) = 256 bytes → too long.
        let multibyte = String(repeating: "é", count: 128)
        #expect(FolderNameValidator.validate(multibyte) == .failure(.tooLong))
    }

    @Test func returnsNFC() {
        // U+0065 U+0301 (e + combining acute) must come back as U+00E9.
        let decomposed = "Cafe\u{0301}"
        let got = try? FolderNameValidator.validate(decomposed).get()
        #expect(got == "Café")
        #expect(got?.utf8.count == 5) // "Caf" (3) + "é" (2 UTF-8 bytes)
    }

    @Test func messagesAreUserFacing() {
        for error in [FolderNameError.empty, .invalidCharacters, .reserved, .tooLong] {
            #expect(!error.message.isEmpty)
            #expect(error.message.first?.isLowercase == false)
        }
    }
}
