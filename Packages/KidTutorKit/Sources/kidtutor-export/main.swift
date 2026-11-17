// Turns samples.json copied from the iPad into folders of PNGs, one folder per character,
// ready to drag into the Create ML app as an Image Classifier training set.
import Foundation
import KidTutorKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: kidtutor-export <samples.json> <output-folder>\n".utf8))
    exit(2)
}

let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2], isDirectory: true)

do {
    let samples = try SampleStore.decode(Data(contentsOf: input))
    var counts: [String: Int] = [:]
    for sample in samples {
        guard let label = sample.confirmedLabel,
              let image = InkRenderer.render(sample.ink),
              let png = InkRenderer.pngData(image) else { continue }
        let folder = output.appendingPathComponent(CharacterLabel.folderName(for: label), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent("\(sample.id.uuidString).png"))
        counts[label, default: 0] += 1
    }
    for (label, count) in counts.sorted(by: { $0.key < $1.key }) {
        print("\(CharacterLabel.folderName(for: label))\t\(count)")
    }
    print("Wrote \(counts.values.reduce(0, +)) images to \(output.path)")
} catch {
    FileHandle.standardError.write(Data("kidtutor-export: \(error.localizedDescription)\n".utf8))
    exit(1)
}
