//
//  Adobe-Downloader
//
//  Created by X1a0He on 2024/10/30.
//
import Foundation

actor CancelTracker {
    private var cancelledIds: Set<UUID> = []
    private var pausedIds: Set<UUID> = []
    private var downloadTasks: [UUID: URLSessionDownloadTask] = [:]
    private var sessions: [UUID: URLSession] = [:]
    private var resumeData: [UUID: Data] = [:]

    func registerTask(_ id: UUID, task: URLSessionDownloadTask, session: URLSession) {
        downloadTasks[id] = task
        sessions[id] = session
    }
    
    func cancel(_ id: UUID) async {
        cancelledIds.insert(id)
        pausedIds.remove(id)
        resumeData.removeValue(forKey: id)
        
        if let task = downloadTasks[id] {
            await withCheckedContinuation { continuation in
                task.cancel { _ in
                    continuation.resume()
                }
            }
            downloadTasks.removeValue(forKey: id)
        }
        
        if let session = sessions[id] {
            session.invalidateAndCancel()
            sessions.removeValue(forKey: id)
        }
    }
    
    func pause(_ id: UUID) async {
        if !cancelledIds.contains(id) {
            pausedIds.insert(id)
            if let task = downloadTasks[id] {
                let data = await withCheckedContinuation { continuation in
                    task.cancel(byProducingResumeData: { data in
                        continuation.resume(returning: data)
                    })
                }
                if let data = data {
                    resumeData[id] = data
                }
            }
        }
    }
    
    func getResumeData(_ id: UUID) -> Data? {
        return resumeData[id]
    }
    
    func resume(_ id: UUID) async {
        pausedIds.remove(id)
    }
    
    func isPaused(_ id: UUID) async -> Bool {
        pausedIds.contains(id)
    }
    
    func isCancelled(_ id: UUID) async -> Bool {
        cancelledIds.contains(id)
    }
    
    func clearTask(_ id: UUID) {
        cancelledIds.remove(id)
        pausedIds.remove(id)
        downloadTasks.removeValue(forKey: id)
        sessions.removeValue(forKey: id)
        resumeData.removeValue(forKey: id)
    }
} 
