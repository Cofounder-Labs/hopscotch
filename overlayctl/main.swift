//
//  main.swift
//  overlayctl
//
//  Created by Abhimanyu Yadav on 4/28/25.
//

import Foundation

// Parse command line arguments
func parseArguments() -> [String: Any]? {
    let args = CommandLine.arguments
    
    if args.count < 2 {
        printUsage()
        return nil
    }
    
    var command: [String: Any] = [:]
    
    switch args[1] {
    case "act":
        guard args.count >= 7 else {
            print("Error: act command requires x, y, width, height, and targetBundleID parameters")
            printUsage()
            return nil
        }
        
        guard let x = Double(args[2]),
              let y = Double(args[3]),
              let width = Double(args[4]),
              let height = Double(args[5]),
              let targetBundleID = args[6] as String? else {
            print("Error: Invalid parameter format")
            return nil
        }
        
        command["command"] = "act"
        command["params"] = [
            "x": x,
            "y": y,
            "width": width,
            "height": height,
            "targetBundleID": targetBundleID
        ]
        
    case "observe":
        guard args.count >= 6 else {
            print("Error: observe command requires x, y, width, and height parameters")
            printUsage()
            return nil
        }
        
        guard let x = Double(args[2]),
              let y = Double(args[3]),
              let width = Double(args[4]),
              let height = Double(args[5]) else {
            print("Error: Invalid parameter format")
            return nil
        }
        
        command["command"] = "observe"
        command["params"] = [
            "x": x,
            "y": y,
            "width": width,
            "height": height
        ]
        
    case "mode":
        guard args.count >= 3 else {
            print("Error: mode command requires a mode parameter (act or observe)")
            printUsage()
            return nil
        }
        
        let mode = args[2]
        if mode != "act" && mode != "observe" {
            print("Error: mode must be either 'act' or 'observe'")
            return nil
        }
        
        command["command"] = "mode"
        command["params"] = ["mode": mode]
        
    default:
        print("Error: Unknown command: \(args[1])")
        printUsage()
        return nil
    }
    
    return command
}

func printUsage() {
    print("""
    Usage:
      overlayctl act <x> <y> <width> <height> <targetBundleID>
      overlayctl observe <x> <y> <width> <height>
      overlayctl mode <act|observe>
    
    Examples:
      overlayctl act 100 200 300 100 com.apple.finder
      overlayctl observe 500 600 200 150
      overlayctl mode act
    """)
}

// Main execution
if let command = parseArguments() {
    do {
        let jsonData = try JSONSerialization.data(withJSONObject: command, options: [])
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            // Send the command to the overlay assistant
            print(jsonString)
            
            // Read and print responses
            while let response = readLine() {
                print(response)
            }
        }
    } catch {
        print("Error: Failed to serialize command: \(error.localizedDescription)")
    }
} 