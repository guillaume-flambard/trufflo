import Foundation

/// The breeds the form can search (docs/specs/A-premiere-impression.md, A-REQ-03).
///
/// Written by us (decision D1), not imported from the FCI nomenclature: that
/// list leaves out breeds it does not recognise and its reuse terms were not
/// checked. French names as people say them, with the aliases they type.
///
/// A chosen entry is stored as an ordinary declared breed (`breedKind`
/// "known", the name in `breedLabel`). The identifier never leaves this file:
/// nothing is derived from a breed (A-REQ-05), so nothing needs it stored.
public struct Breed: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let aliases: [String]

    init(_ id: String, _ name: String, _ aliases: [String] = []) {
        self.id = id
        self.name = name
        self.aliases = aliases
    }
}

public enum BreedCatalog {
    /// Matches typed text against names and aliases, best first: a name that
    /// starts with the query, then a word of the name that does, then an
    /// alias, then a name that merely contains it. Accents, case, hyphens and
    /// apostrophes are ignored, so "berge" finds "Berger allemand".
    public static func search(_ query: String, in breeds: [Breed] = all) -> [Breed] {
        let needle = normalized(query)
        guard !needle.isEmpty else { return [] }
        let ranked = breeds.compactMap { breed -> (Int, Breed)? in
            let name = normalized(breed.name)
            let aliases = breed.aliases.map(normalized)
            if name.hasPrefix(needle) { return (0, breed) }
            if name.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) { return (1, breed) }
            if aliases.contains(where: { $0 == needle || $0.hasPrefix(needle) }) { return (2, breed) }
            if name.contains(needle) || aliases.contains(where: { $0.contains(needle) }) { return (3, breed) }
            return nil
        }
        return ranked
            .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1.name.localizedStandardCompare($1.1.name) == .orderedAscending }
            .map(\.1)
    }

    /// The entry whose name is exactly this label, if any: tells a breed chosen
    /// from the catalogue from one typed by hand.
    public static func entry(named label: String) -> Breed? {
        let needle = normalized(label)
        guard !needle.isEmpty else { return nil }
        return all.first { normalized($0.name) == needle }
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "'", with: " ")
            .replacingOccurrences(of: "’", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    public static let all: [Breed] = [
        Breed("affenpinscher", "Affenpinscher"),
        Breed("airedale-terrier", "Airedale terrier", ["airedale"]),
        Breed("akita-americain", "Akita américain"),
        Breed("akita-inu", "Akita inu", ["akita"]),
        Breed("american-staffordshire-terrier", "American staffordshire terrier", ["amstaff", "staff americain"]),
        Breed("ariegeois", "Ariégeois"),
        Breed("barbet", "Barbet"),
        Breed("basenji", "Basenji"),
        Breed("basset-artesien-normand", "Basset artésien normand"),
        Breed("basset-fauve-de-bretagne", "Basset fauve de Bretagne"),
        Breed("basset-hound", "Basset hound"),
        Breed("beagle", "Beagle"),
        Breed("beagle-harrier", "Beagle-harrier"),
        Breed("bearded-collie", "Bearded collie", ["colley barbu"]),
        Breed("beauceron", "Beauceron", ["berger de beauce", "bas rouge"]),
        Breed("bedlington-terrier", "Bedlington terrier"),
        Breed("berger-allemand", "Berger allemand", ["ba", "german shepherd"]),
        Breed("berger-americain-miniature", "Berger américain miniature", ["mini aussie"]),
        Breed("berger-australien", "Berger australien", ["aussie", "australian shepherd"]),
        Breed("berger-belge-groenendael", "Berger belge groenendael", ["groenendael"]),
        Breed("berger-belge-laekenois", "Berger belge laekenois", ["laekenois"]),
        Breed("berger-belge-malinois", "Berger belge malinois", ["malinois"]),
        Breed("berger-belge-tervueren", "Berger belge tervueren", ["tervueren"]),
        Breed("berger-blanc-suisse", "Berger blanc suisse"),
        Breed("berger-des-pyrenees", "Berger des Pyrénées", ["labrit"]),
        Breed("berger-des-shetland", "Berger des Shetland", ["sheltie", "shetland"]),
        Breed("berger-hollandais", "Berger hollandais"),
        Breed("berger-picard", "Berger picard"),
        Breed("bichon-bolonais", "Bichon bolonais", ["bolognese"]),
        Breed("bichon-frise", "Bichon à poil frisé", ["bichon frise"]),
        Breed("bichon-havanais", "Bichon havanais", ["havanais"]),
        Breed("bichon-maltais", "Bichon maltais", ["maltais"]),
        Breed("bobtail", "Bobtail", ["old english sheepdog"]),
        Breed("border-collie", "Border collie", ["border"]),
        Breed("border-terrier", "Border terrier"),
        Breed("barzoi", "Barzoï", ["borzoi", "levrier russe"]),
        Breed("boston-terrier", "Boston terrier"),
        Breed("bouledogue-americain", "Bouledogue américain", ["american bulldog"]),
        Breed("bouledogue-anglais", "Bouledogue anglais", ["bulldog anglais", "english bulldog"]),
        Breed("bouledogue-francais", "Bouledogue français", ["bouledogue", "frenchie", "french bulldog"]),
        Breed("bouvier-bernois", "Bouvier bernois", ["bernois"]),
        Breed("bouvier-des-flandres", "Bouvier des Flandres"),
        Breed("boxer", "Boxer"),
        Breed("braque-allemand", "Braque allemand", ["kurzhaar"]),
        Breed("braque-d-auvergne", "Braque d'Auvergne"),
        Breed("braque-de-weimar", "Braque de Weimar", ["weimaraner"]),
        Breed("braque-francais", "Braque français"),
        Breed("braque-hongrois", "Braque hongrois", ["vizsla"]),
        Breed("briard", "Briard", ["berger de brie"]),
        Breed("bull-terrier", "Bull terrier"),
        Breed("bullmastiff", "Bullmastiff"),
        Breed("cairn-terrier", "Cairn terrier"),
        Breed("cane-corso", "Cane corso"),
        Breed("caniche", "Caniche", ["caniche toy", "caniche nain", "poodle"]),
        Breed("cavalier-king-charles", "Cavalier king charles", ["cavalier", "king charles"]),
        Breed("chien-chinois-a-crete", "Chien chinois à crête"),
        Breed("chien-d-eau-espagnol", "Chien d'eau espagnol"),
        Breed("chien-d-eau-portugais", "Chien d'eau portugais"),
        Breed("chien-de-montagne-des-pyrenees", "Chien de montagne des Pyrénées", ["patou"]),
        Breed("chien-loup-tchecoslovaque", "Chien-loup tchécoslovaque", ["chien loup"]),
        Breed("chien-loup-de-saarloos", "Chien-loup de Saarloos", ["saarloos"]),
        Breed("chihuahua", "Chihuahua"),
        Breed("chow-chow", "Chow-chow"),
        Breed("cocker-americain", "Cocker américain"),
        Breed("cocker-anglais", "Cocker anglais", ["cocker"]),
        Breed("colley", "Colley à poil long", ["colley", "collie", "rough collie"]),
        Breed("coton-de-tulear", "Coton de Tuléar", ["coton"]),
        Breed("dalmatien", "Dalmatien"),
        Breed("dobermann", "Dobermann", ["doberman"]),
        Breed("dogue-allemand", "Dogue allemand", ["danois", "great dane"]),
        Breed("dogue-argentin", "Dogue argentin"),
        Breed("dogue-de-bordeaux", "Dogue de Bordeaux"),
        Breed("drahthaar", "Drahthaar", ["braque allemand a poil dur"]),
        Breed("epagneul-breton", "Épagneul breton", ["breton"]),
        Breed("epagneul-francais", "Épagneul français"),
        Breed("epagneul-japonais", "Épagneul japonais", ["chin"]),
        Breed("epagneul-nain-continental", "Épagneul nain continental", ["papillon", "phalene"]),
        Breed("eurasier", "Eurasier"),
        Breed("fox-terrier", "Fox terrier", ["fox"]),
        Breed("golden-retriever", "Golden retriever", ["golden"]),
        Breed("grand-bleu-de-gascogne", "Grand bleu de Gascogne"),
        Breed("grand-griffon-vendeen", "Grand griffon vendéen"),
        Breed("griffon-bruxellois", "Griffon bruxellois"),
        Breed("griffon-korthals", "Griffon korthals", ["korthals"]),
        Breed("husky-siberien", "Husky sibérien", ["husky"]),
        Breed("jack-russell-terrier", "Jack russell terrier", ["jack russell", "jack"]),
        Breed("kelpie", "Kelpie australien", ["kelpie"]),
        Breed("labrador-retriever", "Labrador retriever", ["labrador", "labro"]),
        Breed("lagotto-romagnolo", "Lagotto romagnolo"),
        Breed("leonberg", "Leonberg"),
        Breed("levrier-afghan", "Lévrier afghan", ["afghan"]),
        Breed("levrier-espagnol", "Lévrier espagnol", ["galgo"]),
        Breed("whippet", "Whippet"),
        Breed("greyhound", "Greyhound", ["levrier anglais"]),
        Breed("lhassa-apso", "Lhassa apso"),
        Breed("malamute", "Malamute de l'Alaska", ["malamute"]),
        Breed("mastiff", "Mastiff"),
        Breed("matin-de-naples", "Mâtin de Naples"),
        Breed("berger-d-anatolie", "Berger d'Anatolie", ["kangal"]),
        Breed("norfolk-terrier", "Norfolk terrier"),
        Breed("nova-scotia-duck-tolling-retriever", "Retriever de la Nouvelle-Écosse", ["toller"]),
        Breed("parson-russell-terrier", "Parson russell terrier"),
        Breed("pekinois", "Pékinois"),
        Breed("petit-basset-griffon-vendeen", "Petit basset griffon vendéen"),
        Breed("petit-chien-lion", "Petit chien lion"),
        Breed("petit-epagneul-de-munster", "Petit épagneul de Münster"),
        Breed("pinscher-moyen", "Pinscher moyen", ["pinscher"]),
        Breed("pinscher-nain", "Pinscher nain", ["zwergpinscher"]),
        Breed("pitbull", "American pit bull terrier", ["pitbull", "pit bull"]),
        Breed("podenco", "Podenco", ["podenco ibicenco"]),
        Breed("pointer", "Pointer anglais", ["pointer"]),
        Breed("porcelaine", "Porcelaine"),
        Breed("pug", "Carlin", ["pug"]),
        Breed("rhodesian-ridgeback", "Rhodesian ridgeback", ["ridgeback"]),
        Breed("rottweiler", "Rottweiler", ["rott"]),
        Breed("saint-bernard", "Saint-bernard"),
        Breed("saluki", "Saluki"),
        Breed("samoyede", "Samoyède"),
        Breed("schipperke", "Schipperke"),
        Breed("schnauzer-geant", "Schnauzer géant"),
        Breed("schnauzer-moyen", "Schnauzer moyen", ["schnauzer"]),
        Breed("schnauzer-nain", "Schnauzer nain"),
        Breed("scottish-terrier", "Scottish terrier", ["scottie"]),
        Breed("setter-anglais", "Setter anglais", ["setter"]),
        Breed("setter-gordon", "Setter gordon"),
        Breed("setter-irlandais", "Setter irlandais"),
        Breed("shar-pei", "Shar-pei"),
        Breed("shiba-inu", "Shiba inu", ["shiba"]),
        Breed("shih-tzu", "Shih tzu"),
        Breed("spitz-allemand", "Spitz allemand", ["spitz", "loulou de pomeranie", "pomeranian"]),
        Breed("spitz-japonais", "Spitz japonais"),
        Breed("springer-anglais", "Springer anglais", ["springer"]),
        Breed("staffordshire-bull-terrier", "Staffordshire bull terrier", ["staffie", "staffy", "staff"]),
        Breed("teckel", "Teckel", ["dachshund", "saucisse"]),
        Breed("terre-neuve", "Terre-neuve", ["newfoundland"]),
        Breed("terrier-tibetain", "Terrier tibétain"),
        Breed("volpino", "Volpino italien"),
        Breed("welsh-corgi-cardigan", "Welsh corgi cardigan"),
        Breed("welsh-corgi-pembroke", "Welsh corgi pembroke", ["corgi"]),
        Breed("west-highland-white-terrier", "West highland white terrier", ["westie"]),
        Breed("yorkshire-terrier", "Yorkshire terrier", ["yorkshire", "yorkie"]),
    ]
}
