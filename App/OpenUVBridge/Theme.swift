// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

enum FieldTheme {
    static let background = Color(red: 0.07, green: 0.08, blue: 0.06)
    static let panel = Color(red: 0.12, green: 0.14, blue: 0.10)
    static let amber = Color(red: 0.90, green: 0.64, blue: 0.24)
    static let text = Color(red: 0.95, green: 0.94, blue: 0.90)
    static let dim = Color(red: 0.66, green: 0.65, blue: 0.56)
    static let good = Color(red: 0.56, green: 0.75, blue: 0.42)
    static let warn = Color(red: 0.83, green: 0.40, blue: 0.31)
}

struct FieldBanner: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(FieldTheme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(FieldTheme.panel)
            .overlay(Rectangle().frame(height: 2).foregroundStyle(FieldTheme.amber), alignment: .top)
    }
}

struct FieldEmpty: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(FieldTheme.text)
            Text(detail).font(.subheadline).foregroundStyle(FieldTheme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}
