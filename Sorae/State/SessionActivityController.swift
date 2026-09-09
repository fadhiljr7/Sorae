//
//  SessionActivityController.swift
//  Sorae
//
//  Owns the Live Activity's lifecycle. Its whole job is one rule:
//
//      the activity exists exactly while a soundscape is playing and the app
//      is not in front — and it disappears the moment playback stops.
//
//  Minimising the app is not on its own a reason to show anything. Nor is
//  starting playback while the app is open. Both have to be true.
//
//  Everything is driven through `reconcile`, which is handed the whole world it
//  cares about and works out what to do. There is no start/stop API for callers
//  to get out of step with.
//

import ActivityKit
import Foundation
import Observation

@MainActor
@Observable
final class SessionActivityController {

    /// What the activity should be showing, or nothing at all.
    struct Snapshot: Equatable {
        var isPlaying: Bool
        var isForeground: Bool
        /// When a timed session ends. nil plays open-ended.
        var sessionEndsAt: Date?
        var summary: String
    }

    private(set) var isShowing = false

    private weak var mixer: MixerModel?
    private var isForeground = true
    private var activity: Activity<SoraeActivityAttributes>?
    /// Requests and updates are async, so a burst of changes could otherwise
    /// start two activities or end one twice.
    private var work: Task<Void, Never>?
    private var applied: SoraeActivityAttributes.ContentState?

    /// Starts listening to the mixer. The controller drives itself from here on.
    func attach(to mixer: MixerModel) {
        self.mixer = mixer
        mixer.onPlaybackStateChange = { [weak self] in self?.sync() }
        sync()
    }

    /// The only thing the interface has to tell it.
    func setForeground(_ foreground: Bool) {
        guard foreground != isForeground else { return }
        isForeground = foreground
        sync()
    }

    private func sync() {
        guard let mixer else { return }
        let snapshot = mixer.activitySnapshot
        reconcile(.init(isPlaying: snapshot.isPlaying,
                        isForeground: isForeground,
                        sessionEndsAt: snapshot.endsAt,
                        summary: snapshot.summary))
    }

    func reconcile(_ snapshot: Snapshot) {
        work?.cancel()
        work = Task { [weak self] in
            await self?.apply(snapshot)
        }
    }

    /// Called when the app is going away for good.
    func endImmediately() {
        work?.cancel()
        let activity = activity
        self.activity = nil
        applied = nil
        isShowing = false
        Task { await activity?.end(nil, dismissalPolicy: .immediate) }
    }

    // MARK: Reconciliation

    private func apply(_ snapshot: Snapshot) async {
        guard snapshot.isPlaying else {
            await end()
            return
        }

        let state = SoraeActivityAttributes.ContentState(
            sessionEndsAt: snapshot.sessionEndsAt,
            summary: snapshot.summary
        )

        if activity == nil {
            // Only ever begins from the background. Playing with the app open is
            // not a reason to put anything in the Dynamic Island.
            guard !snapshot.isForeground else { return }
            await start(with: state)
        } else if state != applied {
            await update(to: state)
        }
    }

    private func start(with state: SoraeActivityAttributes.ContentState) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            let started = try Activity.request(
                attributes: SoraeActivityAttributes(),
                content: content(for: state),
                pushType: nil
            )
            activity = started
            applied = state
            isShowing = true
        } catch {
            // Denied, or too many activities. Nothing to recover — the mixer
            // carries on regardless.
            activity = nil
            applied = nil
            isShowing = false
        }
    }

    private func update(to state: SoraeActivityAttributes.ContentState) async {
        guard let activity else { return }
        await activity.update(content(for: state))
        applied = state
    }

    private func end() async {
        guard let activity else { return }
        self.activity = nil
        applied = nil
        isShowing = false
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    /// The countdown ticks in the widget from `sessionEndsAt`, so that date is
    /// also the point after which the activity's content is out of date.
    private func content(
        for state: SoraeActivityAttributes.ContentState
    ) -> ActivityContent<SoraeActivityAttributes.ContentState> {
        ActivityContent(state: state, staleDate: state.sessionEndsAt)
    }
}
