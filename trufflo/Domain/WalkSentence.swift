import Foundation

/// The line under a finished walk: when it was and which of the week it makes
/// ("Balade du matin, la 3e de la semaine."). Everything in it is a fact the app
/// already holds. It never says better, longer, more than: a walk is not compared with
/// another one, with another dog, or with a number somebody did not choose.
public enum WalkSentence {
    public static func make(endedAt: Date, weekCount: Int, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: endedAt)
        let moment: String
        switch hour {
        case 5..<12: moment = "du matin"
        case 12..<18: moment = "de l'après-midi"
        case 18..<23: moment = "du soir"
        default: moment = "de nuit"
        }
        guard weekCount >= 1 else { return "Balade \(moment)." }
        let rank = weekCount == 1 ? "la première" : "la \(weekCount)e"
        return "Balade \(moment), \(rank) de la semaine."
    }
}
