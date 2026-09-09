//
//  AudioAssetStore.swift
//  Sorae
//
//  Audio ships in the asset catalog as data sets, which hand back `Data` rather
//  than a file URL. `AVAudioFile` needs a URL, so each asset is written once to
//  the caches directory and reused from there on every later launch.
//
//  Caches is the right home for this: the system may reclaim it, and if it does
//  the asset is simply re-materialised from the bundle.
//

import Foundation
import UIKit

enum AudioAssetStore {

    enum Failure: Error {
        case assetMissing(String)
        case writeFailed(String, underlying: Error)
    }

    /// Returns a file URL for the named data-set asset, materialising it on
    /// first use. Safe to call from a background thread.
    nonisolated static func url(forDataSet name: String, fileExtension: String = "wav") throws -> URL {
        let destination = cacheDirectory().appendingPathComponent("\(name).\(fileExtension)")

        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }

        guard let asset = NSDataAsset(name: name) else {
            throw Failure.assetMissing(name)
        }

        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try asset.data.write(to: destination, options: .atomic)
        } catch {
            throw Failure.writeFailed(name, underlying: error)
        }

        return destination
    }

    nonisolated private static func cacheDirectory() -> URL {
        let base = (try? FileManager.default.url(for: .cachesDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true))
            ?? URL.temporaryDirectory
        return base.appendingPathComponent("Ambience", isDirectory: true)
    }
}
