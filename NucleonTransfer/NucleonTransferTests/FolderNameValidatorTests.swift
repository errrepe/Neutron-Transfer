// Nucleon Transfer — FolderNameValidator offline tests (Swift Testing).
// Pure validation rules for the New Folder sheet: trim, empty, invalid
// characters, reserved names, UTF-8 byte cap, NFC normalization and the
// R5 same-folder duplicate check (folders and files alike).
// No network, no secrets.
import Foundation
import Testing

@testable import NucleonTransfer

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
        // M6: user-facing copy stays unit-free (the cap is in bytes,
        // not characters) — pin the exact wording.
        #expect(FolderNameError.tooLong.message == "That name is too long. Try a shorter name.")
    }

    @Test func returnsNFC() {
        // U+0065 U+0301 (e + combining acute) must come back as U+00E9.
        let decomposed = "Cafe\u{0301}"
        let got = try? FolderNameValidator.validate(decomposed).get()
        #expect(got == "Café")
        #expect(got?.utf8.count == 5) // "Caf" (3) + "é" (2 UTF-8 bytes)
    }

    // MARK: - R5 duplicate check

    @Test func duplicateFolderNameIsRejected() {
        #expect(
            FolderNameValidator.validate("Invoices", existingNames: ["Invoices", "Pictures"])
                == .failure(.alreadyExists("Invoices"))
        )
    }

    @Test func duplicateFileNameIsRejected() {
        // The server refuses a folder whose name collides with a FILE too
        // (2500) — the client flags either kind of sibling.
        #expect(
            FolderNameValidator.validate("report.pdf", existingNames: ["report.pdf"])
                == .failure(.alreadyExists("report.pdf"))
        )
    }

    @Test func duplicateMatchIsNFCExact() {
        // Decomposed input vs precomposed listing name — same node.
        #expect(
            FolderNameValidator.validate("Cafe\u{0301}", existingNames: ["Café"])
                == .failure(.alreadyExists("Café"))
        )
        // And the reverse: an NFD listing name still matches NFC input.
        #expect(
            FolderNameValidator.validate("Café", existingNames: ["Cafe\u{0301}"])
                == .failure(.alreadyExists("Café"))
        )
    }

    @Test func caseOnlyDifferenceIsAllowed() {
        // The server compares name hashes — the match is case-SENSITIVE.
        let got = try? FolderNameValidator.validate(
            "Invoices", existingNames: ["invoices", "INVOICES"]
        ).get()
        #expect(got == "Invoices")
    }

    @Test func structuralErrorWinsOverDuplicate() {
        // A malformed name reports its real error even if the set happens
        // to contain the normalized form.
        #expect(
            FolderNameValidator.validate("..", existingNames: [".."])
                == .failure(.reserved)
        )
    }

    @Test func messagesAreUserFacing() {
        for error in [
            FolderNameError.empty, .invalidCharacters, .reserved, .tooLong,
            .alreadyExists("Test"),
        ] {
            #expect(!error.message.isEmpty)
            #expect(error.message.first?.isLowercase == false)
        }
    }
}
