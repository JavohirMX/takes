import Testing
@testable import Takes

@Test func sanSpeechPawnToE4() {
    #expect(SANSpeech.speak("e4") == "pawn to e4")
}

@Test func sanSpeechRookTakesC6() {
    #expect(SANSpeech.speak("Rxc6") == "rook takes c6")
}

@Test func sanSpeechBishopTakesCheck() {
    #expect(SANSpeech.speak("Bxc6+") == "bishop takes c6 check")
}

@Test func sanSpeechShortCastle() {
    #expect(SANSpeech.speak("O-O") == "short castle")
}

@Test func sanSpeechPromotion() {
    #expect(SANSpeech.speak("e8=Q") == "pawn to e8 promotes to queen")
}

@Test func sanSpeechKnightDisambiguation() {
    #expect(SANSpeech.speak("Nbd2") == "knight b to d2")
}

@Test func sanSpeechPawnCaptureDropsFile() {
    #expect(SANSpeech.speak("exd5") == "pawn takes d5")
}
