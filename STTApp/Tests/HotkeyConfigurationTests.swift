@testable import STTApp
import XCTest
import Foundation
import AppKit

final class HotkeyConfigurationTests: XCTestCase {
    func testDefaultConfiguration() throws {
        let config = HotkeyConfiguration.default
        
        XCTAssertEqual(config.keyCode, 0)
        XCTAssertEqual(config.useCommand, true)
        XCTAssertEqual(config.useOption, true)
        XCTAssertEqual(config.useControl, false)
        XCTAssertEqual(config.useShift, false)
    }

    func testCustomConfiguration() throws {
        var config = HotkeyConfiguration()
        config.keyCode = 36
        config.useCommand = false
        config.useOption = true
        config.useControl = true
        config.useShift = false
        
        XCTAssertEqual(config.keyCode, 36)
        XCTAssertEqual(config.useCommand, false)
        XCTAssertEqual(config.useOption, true)
        XCTAssertEqual(config.useControl, true)
        XCTAssertEqual(config.useShift, false)
    }

    func testDescription() throws {
        var config = HotkeyConfiguration()
        config.keyCode = 49
        config.useCommand = true
        config.useOption = true
        config.useShift = true
        
        let description = config.description
        
        XCTAssertNotNil(description)
        XCTAssertFalse(description.isEmpty)
        XCTAssertTrue(description.contains("⌘"))
        XCTAssertTrue(description.contains("⌥"))
        XCTAssertTrue(description.contains("⇧"))
    }

    func testEquality() throws {
        var config1 = HotkeyConfiguration()
        config1.keyCode = 49
        config1.useCommand = true
        config1.useOption = true
        
        var config2 = HotkeyConfiguration()
        config2.keyCode = 49
        config2.useCommand = true
        config2.useOption = true
        
        var config3 = HotkeyConfiguration()
        config3.keyCode = 50
        config3.useCommand = true
        config3.useOption = false
        
        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }

    func testSingleModifier() throws {
        var configs: [HotkeyConfiguration] = []
        
        var config1 = HotkeyConfiguration()
        config1.keyCode = 36
        config1.useCommand = true
        config1.useOption = false
        config1.useControl = false
        config1.useShift = false
        configs.append(config1)
        
        var config2 = HotkeyConfiguration()
        config2.keyCode = 36
        config2.useCommand = false
        config2.useOption = true
        config2.useControl = false
        config2.useShift = false
        configs.append(config2)
        
        var config3 = HotkeyConfiguration()
        config3.keyCode = 36
        config3.useCommand = false
        config3.useOption = false
        config3.useControl = true
        config3.useShift = false
        configs.append(config3)
        
        var config4 = HotkeyConfiguration()
        config4.keyCode = 36
        config4.useCommand = false
        config4.useOption = false
        config4.useControl = false
        config4.useShift = true
        configs.append(config4)
        
        for config in configs {
            let flags = config.modifiers
            let modifierFlags = NSEvent.ModifierFlags(rawValue: flags)
            XCTAssertNotNil(modifierFlags)
        }
    }

    func testMultipleModifiers() throws {
        var config = HotkeyConfiguration()
        config.keyCode = 36
        config.useCommand = true
        config.useOption = true
        config.useControl = true
        config.useShift = true
        
        let flags = config.modifiers
        let modifierFlags = NSEvent.ModifierFlags(rawValue: flags)
        XCTAssertNotNil(modifierFlags)
        
        XCTAssertTrue(modifierFlags.contains(.command))
        XCTAssertTrue(modifierFlags.contains(.option))
        XCTAssertTrue(modifierFlags.contains(.control))
        XCTAssertTrue(modifierFlags.contains(.shift))
    }

    func testEmptyModifiers() throws {
        var config = HotkeyConfiguration()
        config.useCommand = false
        config.useOption = false
        config.useControl = false
        config.useShift = false
        
        let flags = config.modifiers
        let modifierFlags = NSEvent.ModifierFlags(rawValue: flags)
        XCTAssertNotNil(modifierFlags)
        XCTAssertTrue(modifierFlags.isEmpty)
    }
}
