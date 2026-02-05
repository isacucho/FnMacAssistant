//
//  NotificationHelper.swift
//  FnMacAssistant
//
//  Created by Isacucho on 02/04/26.
//

import Foundation
import UserNotifications

final class NotificationHelper {
    static let shared = NotificationHelper()

    private init() {}

    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
