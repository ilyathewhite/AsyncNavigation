# Changelog

## Unreleased

- Build the package and its tests in Swift 6 language mode, retaining the Swift 6.2 toolchain requirement.
- Isolate `windowGroup()` to the main actor and mark the `taskAlert` completion parameter as `sending`.
  Alert results can remain non-`Sendable` when ownership is transferred to the waiting task.
- Remove the legacy `ValuePublisher`, `value`, `valueResult`, and `isCancelledPublisher` output APIs,
  including the forwarding `ViewModelUIContainer.value` property.

### Migration from 2.0.0

Use `viewModel.asyncValues` to observe outputs, or `viewModel.throwingAsyncValues` when cancellation should throw.
Use `viewModel.cancellation` to observe cancellation. Access these sequences through `container.viewModel`
when working with a `ViewModelUIContainer`.

## 2.0.0

- Require Swift tools 6.2, iOS 18, macOS 15, and tvOS 18. Swift 5 language mode remains supported.
- Require `BasicViewModel.PublishedValue` and `BaseViewModel<T>` outputs to be `Sendable`.
- Replace the `publishedValue` subject with `PublishedValues`, backed by Swift Concurrency and Async Algorithms `share()`.
- Preserve every output, including duplicates and optional `nil`, for each active iterator.
- Subscribe when an iterator is created; do not replay outputs published before that subscription.
- Finish pending navigation waits on source cancellation, consumer cancellation, or view-model destruction.
- Add `firstValueWithoutCancelling()` for waiting for one output while keeping the view model reusable.
- Replace request polling and navigation test publishers with main-actor async sequences.
- Remove the CombineEx dependency. Preserve `value`, `valueResult`, and `isCancelledPublisher` as Combine adapters.

### Migration

Custom view models should declare `let publishedValue = PublishedValues<PublishedValue>()` and remove stored
`hasRequest` properties. The protocol supplies request tracking. Continue to call `publish`, `cancel`, `_publish`,
and `_cancel` as before. Use `NavigationCancellation.cancel` instead of `CombineEx.Cancel.cancel` for navigation errors.
Custom conformers should call `publishedValue.finish()` from `isolated deinit` so externally retained output
sequences finish when the view model is destroyed. `BaseViewModel` already handles this.

Use `for await value in viewModel.asyncValues` or `for try await value in viewModel.throwingAsyncValues`.
Both are main-actor APIs. Use `.value` when a Combine publisher is still needed. Subscriptions on the main actor
register immediately; subscriptions from other executors register asynchronously on the main actor. Outputs are
delivered asynchronously on the main actor. `firstValue()` continues to cancel the view model after waiting.
Use `firstValueWithoutCancelling()` to await one output while leaving the view model active; source or task
cancellation still throws. `getFirst` also leaves the view model active. The throwing `get` overload propagates callback errors and ends
normally when the view model is cancelled.

In navigation tests, replace `currentViewModelPublisher.value` with `currentViewModel`, and
`currentViewModelPublisher.values` with `currentViewModels`.
