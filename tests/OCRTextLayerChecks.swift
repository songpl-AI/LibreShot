import AppKit
import SwiftUI

@main struct OCRTextLayerChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let image = NSImage(size: CGSize(width: 800, height: 600))
        let regions = [
            OCRTextRegion(id: 2, text: "Second line", bounds: CGRect(x: 0.6, y: 0.6, width: 0.2, height: 0.05), confidence: 1),
            OCRTextRegion(id: 1, text: "First line", bounds: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.05), confidence: 1)
        ]
        let model = OCRTextLayerModel(image: image, regions: regions, text: "First line\nSecond line")
        precondition(model.regions.map(\.id) == [1, 2], "Regions keep reading order")
        precondition(model.selectedIDs.isEmpty && model.selectedCount == 0)
        model.applySelection([1], extending: false)
        precondition(model.selectedText == "First line")
        model.copySelection()
        precondition(NSPasteboard.general.string(forType: .string) == "First line",
                     "Copying one selected line uses the original OCR text")
        precondition(model.copyFeedback == "已复制 1 行")
        model.applySelection([2], extending: true)
        precondition(model.selectedText == "First line\nSecond line")
        model.copySelection()
        precondition(NSPasteboard.general.string(forType: .string) == "First line\nSecond line")
        precondition(model.copyFeedback == "已复制 2 行")
        model.selectAll()
        precondition(model.selectedIDs == [1, 2])
        precondition(model.isAllSelected && model.selectionSummary == "已全选 2 行")
        model.clearSelection()
        precondition(model.selectedIDs.isEmpty)
        model.copySelection()
        precondition(NSPasteboard.general.string(forType: .string) == "First line\nSecond line",
                     "Copying with no selection copies every line")
        precondition(model.copyFeedback == "已复制全部 2 行")
        model.copyLine(2)
        precondition(model.selectedIDs == [2] && model.selectedText == "Second line")

        let partial = OCRTextLayerModel(image: image, regions: regions, text: "First line\nSecond line")
        partial.applyCharacterSelection(regionID: 1, range: NSRange(location: 0, length: 5), extending: false)
        precondition(partial.selectedText == "First")
        precondition(partial.selectionSummary == "已选 5 字")
        partial.copySelection()
        precondition(NSPasteboard.general.string(forType: .string) == "First",
                     "Character selection copies only the selected range")
        let cross = OCRTextLayerModel(image: image, regions: regions, text: "First line\nSecond line")
        cross.applyRangeSelection(from: (regionID: 1, character: 6), to: (regionID: 2, character: 6))
        precondition(cross.selectedText == "line\nSecond", "Cross-line ranges keep the trailing and leading pieces")
        precondition(cross.selectedRanges[1] != nil && cross.selectedRanges[2] != nil)
        cross.applyRangeSelection(from: (regionID: 2, character: 6), to: (regionID: 1, character: 6))
        precondition(cross.selectedText == "line\nSecond", "Reverse cross-line drags select the same text")
        let three = OCRTextLayerModel(image: image, regions: [
            OCRTextRegion(id: 1, text: "First line", bounds: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.05), confidence: 1),
            OCRTextRegion(id: 2, text: "Second line", bounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.05), confidence: 1),
            OCRTextRegion(id: 3, text: "Third line", bounds: CGRect(x: 0.1, y: 0.3, width: 0.3, height: 0.05), confidence: 1)
        ], text: "First line\nSecond line\nThird line")
        three.applyRangeSelection(from: (regionID: 1, character: 6), to: (regionID: 3, character: 5))
        precondition(three.selectedRanges[1] != nil && three.selectedRanges[3] != nil)
        precondition(three.selectedRanges[2] == NSRange(location: 0, length: 11),
                     "Middle lines are selected in full")
        precondition(three.selectedText == "line\nSecond line\nThird")

        let chinese = OCRTextLayerModel(image: image,
                                        regions: [OCRTextRegion(id: 9, text: "付款页·设计评审",
                                                                bounds: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.05),
                                                                confidence: 1)],
                                        text: "付款页·设计评审")
        chinese.applyCharacterSelection(regionID: 9, range: NSRange(location: 4, length: 4), extending: false)
        precondition(chinese.selectedText == "设计评审")

        var closed = false
        model.onClose = { closed = true }
        model.close()
        precondition(closed, "The layer close action reaches the window owner")

        let canvas = OCRTextLayerCanvasView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        canvas.model = model
        canvas.imageRect = CGRect(x: 50, y: 40, width: 700, height: 500)
        precondition(canvas.regionID(at: CGPoint(x: 200, y: 100)) == 1, "Canvas hit testing maps normalized OCR boxes")
        precondition(canvas.regionID(at: CGPoint(x: 540, y: 350)) == 2)
        precondition(canvas.regionID(at: CGPoint(x: 20, y: 20)) == nil)
        precondition(canvas.characterIndex(at: CGPoint(x: 120, y: 100), regionID: 1) == 0)
        precondition(canvas.characterIndex(at: CGPoint(x: 330, y: 100), regionID: 1) == 10)

        // Drive the real canvas with window events: click, double-click copy,
        // marquee selection and the ⌘A/⌘C shortcuts.
        let interactionModel = OCRTextLayerModel(image: image, regions: regions, text: "First line\nSecond line")
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let canvasWindow = OCRTextLayerCanvasView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        canvasWindow.model = interactionModel
        canvasWindow.imageRect = CGRect(x: 50, y: 40, width: 700, height: 500)
        window.contentView = canvasWindow
        window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        defer { window.close() }

        func post(_ type: NSEvent.EventType, at point: CGPoint, count: Int = 1,
                  flags: NSEvent.ModifierFlags = []) {
            let event = NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x, y: 600 - point.y),
                                           modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil,
                                           eventNumber: 0, clickCount: count, pressure: 1)!
            NSApp.postEvent(event, atStart: false)
        }
        func flush() {
            let deadline = Date().addingTimeInterval(0.2)
            while let queued = NSApp.nextEvent(matching: .any, until: deadline, inMode: .default, dequeue: true) {
                NSApp.sendEvent(queued)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        func click(_ point: CGPoint, count: Int = 1, flags: NSEvent.ModifierFlags = []) {
            post(.leftMouseDown, at: point, count: count, flags: flags)
            post(.leftMouseUp, at: point, count: count, flags: flags)
            flush()
        }

        click(CGPoint(x: 200, y: 100))
        precondition(interactionModel.selectedIDs == [1], "A canvas click selects the line under the pointer")
        click(CGPoint(x: 540, y: 350))
        precondition(interactionModel.selectedIDs == [2], "A second click replaces the selection")

        click(CGPoint(x: 200, y: 100), count: 2)
        precondition(NSPasteboard.general.string(forType: .string) == "First line",
                     "Double-clicking a line copies it")

        interactionModel.clearSelection()
        post(.leftMouseDown, at: CGPoint(x: 20, y: 20))
        post(.leftMouseDragged, at: CGPoint(x: 700, y: 400))
        post(.leftMouseUp, at: CGPoint(x: 700, y: 400))
        flush()
        precondition(interactionModel.selectedIDs == [1, 2], "A marquee selects every intersected line")

        window.makeKey()
        window.makeFirstResponder(canvasWindow)
        precondition(window.firstResponder === canvasWindow, "The canvas owns keyboard focus")
        interactionModel.clearSelection()
        post(.leftMouseDown, at: CGPoint(x: 125, y: 100))
        post(.leftMouseDragged, at: CGPoint(x: 240, y: 100))
        post(.leftMouseUp, at: CGPoint(x: 240, y: 100))
        flush()
        precondition(interactionModel.selectedRanges[1] != nil)
        precondition(interactionModel.selectedText.hasPrefix("F") && interactionModel.selectedText.count < 10,
                     "Dragging inside one line selects a character range")
        let draggedText = interactionModel.selectedText
        interactionModel.copySelection()
        precondition(NSPasteboard.general.string(forType: .string) == draggedText)

        interactionModel.clearSelection()
        post(.leftMouseDown, at: CGPoint(x: 200, y: 100))
        post(.leftMouseDragged, at: CGPoint(x: 540, y: 350))
        post(.leftMouseUp, at: CGPoint(x: 540, y: 350))
        flush()
        precondition(interactionModel.selectedRanges[1] != nil && interactionModel.selectedRanges[2] != nil,
                     "Cross-line drag selects the trailing and leading pieces")
        precondition(!interactionModel.selectedText.isEmpty && interactionModel.selectedText.contains("line"))
        let crossText = interactionModel.selectedText
        interactionModel.copySelection()
        precondition(NSPasteboard.general.string(forType: .string) == crossText)

        interactionModel.clearSelection()
        let keyA = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command],
                                    timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                    characters: "a", charactersIgnoringModifiers: "a", isARepeat: false,
                                    keyCode: 0)!
        window.sendEvent(keyA)
        precondition(interactionModel.selectedIDs == [1, 2], "⌘A selects all recognized lines")
        let keyC = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command],
                                    timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                    characters: "c", charactersIgnoringModifiers: "c", isARepeat: false,
                                    keyCode: 8)!
        window.sendEvent(keyC)
        precondition(NSPasteboard.general.string(forType: .string) == "First line\nSecond line",
                     "⌘C copies the current selection")
        interactionModel.clearSelection()
        let returnKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                         timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                         characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false,
                                         keyCode: 36)!
        window.sendEvent(returnKey)
        precondition(NSPasteboard.general.string(forType: .string) == "First line\nSecond line",
                     "Return copies all when nothing is selected")
        precondition(interactionModel.copyFeedback == "已复制全部 2 行")

        // A live select-all must repaint the canvas, not only update the footer.
        interactionModel.clearSelection()
        canvasWindow.display()
        let before = bluePixels(canvasWindow)
        interactionModel.selectAll()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        canvasWindow.display()
        let after = bluePixels(canvasWindow)
        precondition(after > before + 20, "Select-all repaints the visible selection")

        let empty = OCRTextLayerModel(image: image, regions: [], text: "")
        precondition(empty.regions.isEmpty && empty.selectedText.isEmpty)
        print("PASS: OCR text layer ordering, selection, copy, click/double-click, marquee, shortcuts, select-all repaint and close")
    }

    static func bluePixels(_ view: NSView) -> Int {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 0 }
        view.cacheDisplay(in: view.bounds, to: rep)
        var count = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.blueComponent > 0.65 && color.blueComponent - color.redComponent > 0.2 {
                    count += 1
                }
            }
        }
        return count
    }
}
