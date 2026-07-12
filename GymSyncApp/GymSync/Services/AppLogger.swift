import Foundation
import os

enum AppLogger {
    static let subsystem = "app.gymsync.ios"
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let db = Logger(subsystem: subsystem, category: "db")
    static let workout = Logger(subsystem: subsystem, category: "workout")
    static let health = Logger(subsystem: subsystem, category: "health")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let chat = Logger(subsystem: subsystem, category: "chat")
    static let lobby = Logger(subsystem: subsystem, category: "lobby")
    static let sessions = Logger(subsystem: subsystem, category: "sessions")
    static let soundboard = Logger(subsystem: subsystem, category: "soundboard")
}
