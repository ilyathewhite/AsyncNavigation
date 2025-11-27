# Async Navigation

This package provides a way to express app navigation as an async function.

Here is an example from
[SyncUpsTRA](https://github.com/ilyathewhite/SyncUpsTRA). Each screen is expressed as a navigation node
(`NavigationNode<SyncUpDetails>`, `NavigationNode<RecordMeeting>`, `NavigationNode<MeetingNotes>`).
The app flow is in the `run` method. The code first shows sync-up details, then,
depending on the action, it can start a meeting, show meeting notes, or delete the sync-up. You can easily
see the complete flow from the code. The actual navigation is done via a navigation proxy.

For more details, see my blog posts about async navigation:
- [Setting the stage for navigation with async functions](https://ilyathewhite.github.io/posts/setting-stage-for-async-navigation/)
- [Sheets and alerts with async functions](https://ilyathewhite.github.io/posts/sheets-and-alerts/)

```swift
@MainActor
struct AppFlow {
    let rootIndex: Int
    let syncUp: SyncUp
    let proxy: NavigationProxy

    func endFlow() {
        proxy.pop(to: rootIndex)
    }

    func syncDetails(_ syncUp: SyncUp) -> NavigationNode<SyncUpDetails> {
        .init(SyncUpDetails.store(syncUp), proxy)
    }

    func recordMeeting(_ syncUp: SyncUp) -> NavigationNode<RecordMeeting> {
        .init(RecordMeeting.store(syncUp: syncUp), proxy)
    }

    func showMeetingNotes(syncUp: SyncUp, meeting: Meeting) -> NavigationNode<MeetingNotes> {
        .init(MeetingNotes.store(syncUp: syncUp, meeting: meeting), proxy)
    }

    public func run() async {
        await syncDetails(syncUp).then { detailsAction, detailsIndex in
            switch detailsAction {
            case .startMeeting:
                await recordMeeting(syncUp).then { meetingAction, _ in
                    switch meetingAction {
                    case .discard:
                        break
                    case .save(let meeting):
                        appEnv.storageClient.saveMeetingNotes(syncUp, meeting)
                    }
                    proxy.pop(to: detailsIndex)
                }

            case .showMeetingNotes(let meeting):
                await showMeetingNotes(syncUp: syncUp, meeting: meeting).then { _ , _ in
                    endFlow()
                }

            case .deleteSyncUp:
                appEnv.storageClient.deleteSyncUp(syncUp)
                endFlow()
            }
        }
    }
}
```
