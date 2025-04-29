//
//  LogView.swift
//  hopscotch
//
//  Created by Abhimanyu Yadav on 4/28/25.
//

import SwiftUI

struct LogView: View {
    @ObservedObject var overlayController: OverlayController
    
    var body: some View {
        VStack {
            Text("Command Logs")
                .font(.headline)
                .padding(.top)
            
            List {
                ForEach(overlayController.commandLogs.reversed()) { log in
                    HStack {
                        Text(log.formattedTimestamp)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 100, alignment: .leading)
                        
                        Text(typeLabel(for: log.type))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(typeColor(for: log.type))
                            .frame(width: 80, alignment: .leading)
                        
                        Text(log.message)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(maxHeight: .infinity)
            
            HStack {
                Button("Clear Logs") {
                    overlayController.commandLogs.removeAll()
                }
                .padding()
                
                Spacer()
            }
        }
        .frame(width: 600, height: 300)
    }
    
    private func typeLabel(for type: LogType) -> String {
        switch type {
        case .command:
            return "[CMD]"
        case .response:
            return "[RES]"
        case .info:
            return "[INFO]"
        case .error:
            return "[ERR]"
        }
    }
    
    private func typeColor(for type: LogType) -> Color {
        switch type {
        case .command:
            return .blue
        case .response:
            return .green
        case .info:
            return .primary
        case .error:
            return .red
        }
    }
}

#Preview {
    LogView(overlayController: OverlayController())
} 