//
//  InspectionFields.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import SwiftUI

    /// Native copyable broker values wrap in every source inspector; positions can fill the trailing column.
    func inspectionField(_ label: String, _ value: String, fillsTrailingColumn: Bool = false) -> some View {
        LabeledContent(label) {
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: fillsTrailingColumn ? .infinity : nil, alignment: .trailing)
        }
    }

    /// Gives field groups consistent spacing and leading alignment inside their native group boxes.
    func inspectionFields(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
    }
#endif
