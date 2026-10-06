import CoreGraphics
import Foundation
import Vision

/// Finds where the animal is in a photo, so a portrait can aim at it
/// (`FocalCrop`). Uses Vision's animal recognition (iOS 13 and later, Apple
/// documentation « VNRecognizeAnimalsRequest », read 2026-10-07), which returns
/// dogs and cats with a normalized bounding box. Everything runs on the phone;
/// the photo goes nowhere.
enum DogFocus {
    /// The point to aim at, or the fallback when no dog or cat is found, or when
    /// Vision cannot run (it needs resources the simulator may lack).
    static func focus(in image: CGImage) -> CGPoint {
        let request = VNRecognizeAnimalsRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let best = (request.results ?? []).max(by: { $0.confidence < $1.confidence })
        else { return FocalCrop.fallbackFocus }
        return FocalCrop.focus(forAnimalBox: best.boundingBox)
    }
}
