//
//  IPASource.swift
//  FnMacAssistant
//
//  Created by Isacucho on 06/11/25.
//

import Foundation

struct IPASource: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var url: String
}
