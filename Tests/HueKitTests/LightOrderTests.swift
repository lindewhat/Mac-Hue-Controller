import Testing
@testable import HueKit

@Test func numbersAndLettersInNaturalOrder() {
    #expect(LightOrder.sorted(["Spot 10", "Spot 2", "Spot 1"]) == ["Spot 1", "Spot 2", "Spot 10"])
    #expect(LightOrder.sorted(["Bulb, c", "Bulb, a", "Bulb, b"]) == ["Bulb, a", "Bulb, b", "Bulb, c"])
}

@Test func upMiddleDown() {
    #expect(LightOrder.sorted(["Ensis down", "Ensis up"]) == ["Ensis up", "Ensis down"])
    #expect(LightOrder.sorted(["Shelf bottom", "Shelf middle", "Shelf top"]) == ["Shelf top", "Shelf middle", "Shelf bottom"])
}

@Test func leftMiddleRightInEnglishAndDanish() {
    #expect(LightOrder.sorted(["TV, right", "TV, middle", "TV, left"]) == ["TV, left", "TV, middle", "TV, right"])
    // The real living room: one name in Danish, one in English.
    #expect(LightOrder.sorted(["TV, højre", "TV, left"]) == ["TV, left", "TV, højre"])
    #expect(LightOrder.sorted(["Lampe højre", "Lampe venstre"]) == ["Lampe venstre", "Lampe højre"])
}

@Test func positionWordFirst() {
    #expect(LightOrder.sorted(["Right lamp", "Left lamp"]) == ["Left lamp", "Right lamp"])
}

@Test func wordNumbersAndOrdinals() {
    #expect(LightOrder.sorted(["Pendant three", "Pendant one", "Pendant two"]) == ["Pendant one", "Pendant two", "Pendant three"])
    #expect(LightOrder.sorted(["Spot tredje", "Spot første", "Spot anden"]) == ["Spot første", "Spot anden", "Spot tredje"])
}

@Test func differentLightsStayAlphabeticalAndFamiliesStayTogether() {
    let names = ["Køkken lightstrip", "Hue Adore Spot 2", "Ceiling", "Hue Adore Spot 1", "TV right", "Desk", "TV left"]
    #expect(LightOrder.sorted(names) == ["Ceiling", "Desk", "Hue Adore Spot 1", "Hue Adore Spot 2",
                                         "Køkken lightstrip", "TV left", "TV right"])
}

@Test func ordinaryWordsAreNotMistakenForPositions() {
    // "Ensis" etc. aren't position words; single-word names sort normally.
    #expect(LightOrder.sorted(["Up", "Down", "Lamp"]) == ["Down", "Lamp", "Up"])
}
