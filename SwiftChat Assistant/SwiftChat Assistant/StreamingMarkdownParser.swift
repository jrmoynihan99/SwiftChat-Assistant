import Foundation
import Observation

// Represents a completed markdown block
struct MarkdownBlock: Identifiable {
    let id = UUID()
    let content: String
    let type: BlockType
    
    enum BlockType {
        case heading
        case listItem
        case paragraph
        case codeBlock
        case other
    }
}

// Parser that processes streaming text and identifies complete blocks
@Observable
class StreamingMarkdownParser {
    var completedBlocks: [MarkdownBlock] = []
    var currentBlock: String = ""
    
    // ✅ Flag to signal that animated characters should be cleared
    var shouldClearAnimatedChars: Bool = false
    
    private var buffer: String = ""
    private var inCodeBlock = false
    private var codeBlockFenceCount = 0
    
    // Add tokens at controlled typewriter pace
    func addToken(_ token: String) {
        buffer += token
        currentBlock = buffer
        parseCompletedBlocks()
    }
    
    // Reset parser state
    func reset() {
        buffer = ""
        completedBlocks = []
        currentBlock = ""
        inCodeBlock = false
        codeBlockFenceCount = 0
        shouldClearAnimatedChars = false
    }
    
    // Parse buffer for completed blocks
    private func parseCompletedBlocks() {
        // Keep trying to parse blocks until we can't find any more
        while true {
            let initialBlockCount = completedBlocks.count
            
            // Try each parser in order
            if tryParseCodeBlock() { continue }
            if tryParseHeading() { continue }
            if tryParseListItem() { continue }
            if tryParseParagraph() { continue }
            
            // If no blocks were parsed, we're done
            if completedBlocks.count == initialBlockCount {
                break
            }
        }
        
        // Update current block to show remaining unformatted text
        currentBlock = buffer
    }
    
    // Try to parse a code block
    private func tryParseCodeBlock() -> Bool {
        // Look for ``` patterns
        let fences = buffer.components(separatedBy: "```")
        let fenceCount = fences.count - 1
        
        // Need at least 2 fences (opening and closing)
        if fenceCount >= 2 {
            // Find the second ```
            var searchString = buffer
            var firstFenceEnd: String.Index?
            var secondFenceEnd: String.Index?
            
            if let firstRange = searchString.range(of: "```") {
                firstFenceEnd = firstRange.upperBound
                searchString = String(searchString[firstRange.upperBound...])
                
                if let secondRange = searchString.range(of: "```") {
                    // Calculate position in original buffer
                    let offset = buffer.distance(from: buffer.startIndex, to: firstFenceEnd!)
                    let secondStart = searchString.distance(from: searchString.startIndex, to: secondRange.lowerBound)
                    let totalOffset = offset + secondStart
                    secondFenceEnd = buffer.index(buffer.startIndex, offsetBy: totalOffset + 3) // +3 for ```
                }
            }
            
            if let end = secondFenceEnd {
                let codeBlockContent = String(buffer[..<end])
                let block = MarkdownBlock(content: codeBlockContent + "\n", type: .codeBlock)
                completedBlocks.append(block)
                buffer = String(buffer[end...])
                
                // ✅ Signal to clear animated characters
                shouldClearAnimatedChars = true
                
                print("🟦 Code block completed: \(codeBlockContent.prefix(50))...")
                return true
            }
        }
        
        return false
    }
    
    // Try to parse a heading (### text\n)
    private func tryParseHeading() -> Bool {
        let lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
        
        // Need at least 2 elements (line + separator that creates empty string)
        if lines.count >= 2 {
            let firstLine = String(lines[0])
            let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
            
            // Check if it's a heading (starts with # and has content)
            if trimmed.hasPrefix("#") {
                let hashCount = trimmed.prefix(while: { $0 == "#" }).count
                if hashCount >= 1 && hashCount <= 6 {
                    // Valid heading levels are 1-6
                    let afterHashes = trimmed.dropFirst(hashCount)
                    if afterHashes.first == " " || afterHashes.isEmpty {
                        // This is a valid heading
                        let headingContent = firstLine + "\n"
                        let block = MarkdownBlock(content: headingContent, type: .heading)
                        completedBlocks.append(block)
                        
                        // Remove from buffer (including the newline)
                        buffer = lines.dropFirst().joined(separator: "\n")
                        
                        // ✅ Signal to clear animated characters
                        shouldClearAnimatedChars = true
                        
                        print("🟪 Heading completed: \(firstLine)")
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    // Try to parse a list item (- text\n or 1. text\n)
    private func tryParseListItem() -> Bool {
        let lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
        
        if lines.count >= 2 {
            let firstLine = String(lines[0])
            let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
            
            // Check for bullet list (-, *, +)
            let isBullet = (trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")) && trimmed.count > 2
            
            // Check for numbered list (1. , 2. , etc)
            let isNumbered = trimmed.range(of: "^\\d+\\. ", options: .regularExpression) != nil
            
            if isBullet || isNumbered {
                let itemContent = firstLine + "\n"
                let block = MarkdownBlock(content: itemContent, type: .listItem)
                completedBlocks.append(block)
                
                // Remove from buffer
                buffer = lines.dropFirst().joined(separator: "\n")
                
                // ✅ Signal to clear animated characters
                shouldClearAnimatedChars = true
                
                print("🟨 List item completed: \(firstLine)")
                return true
            }
        }
        
        return false
    }
    
    // Try to parse a paragraph (text\n\n)
    private func tryParseParagraph() -> Bool {
        // Look for double newline indicating paragraph end
        if let range = buffer.range(of: "\n\n") {
            let paragraphContent = String(buffer[..<range.upperBound])
            
            // Only create block if there's actual content
            let trimmed = paragraphContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let block = MarkdownBlock(content: paragraphContent, type: .paragraph)
                completedBlocks.append(block)
                buffer = String(buffer[range.upperBound...])
                
                // ✅ Signal to clear animated characters
                shouldClearAnimatedChars = true
                
                print("🟩 Paragraph completed: \(trimmed.prefix(50))...")
                return true
            } else {
                // Just remove the empty content
                buffer = String(buffer[range.upperBound...])
            }
        }
        
        return false
    }
}
