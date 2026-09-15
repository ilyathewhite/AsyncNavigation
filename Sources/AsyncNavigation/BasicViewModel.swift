//
//  BasicViewModel.swift
//  ReducerArchitecture
//
//  Created by Ilya Belenkiy on 11/8/25.
//

import Foundation
import Combine

/// Provides the basic APIs that each view model is expected to have to work
/// with async navigation.
@MainActor
public protocol BasicViewModel: ObservableObject, Hashable, Identifiable {
    /// The type of value that the user gets as a result of interacting with
    /// the UI for the view model when the user either closes the UI or
    /// navigates away from it to the next one.
    associatedtype PublishedValue: Sendable

    nonisolated var id: UUID { get }

    /// Provides a way to check whether the UI is active or can still be active.
    /// Used in sheets, alerts, and assertions.
    var isCancelled: Bool { get }

    /// Provides the low-level API to return the result of interacting with the
    /// UI for the view model when the user either closes the UI or
    /// navigates away from it to the next one.
    /// A class that conforms to `BasicViewModel` should not use it directly.
    var publishedValue: PublishedValues<PublishedValue> { get }

    /// This method should be called to return the result of interacting with the
    /// UI for the view model when the user either closes the UI or
    /// navigates away from it to the next one.
    func publish(_ value: PublishedValue)

    /// This method is called when the user will no longer interact with the UI
    /// for the view model, for example, when the UI sheet is closed or when the
    /// user navigates from the UI to a previous place in the flow.
    func cancel()

    /// Indicates whether there is a request for a published value.
    ///
    /// Useful for testing navigation flows.
    var hasRequest: Bool { get }

    /// Provides a key that is typically used in child UI (sheet, alert, or UI
    /// that is part of a container UI, like master / detail, or inspector UI).
    /// Commonly, only one object of this type is active as a child UI, so using
    /// a default key provides an easy way to identify and access it.
    ///
    /// The default implementation is the class name.
    nonisolated static var viewModelDefaultKey: String { get }

    /// Storage for child view models that is managed by `BasicViewModel` that
    /// provides higher-level APIs.
    var children: [String: any BasicViewModel] { get set }

    /// A low-level API related to SwiftUI. A default implementation is provided.
    func sendObjectWillChange()
}

public extension BasicViewModel {
    nonisolated
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs === rhs
    }

    nonisolated
    func hash(into hasher: inout Hasher) {
        id.hash(into: &hasher)
    }

    nonisolated
    static var viewModelDefaultKey: String { "\(Self.self)" }
}

extension BasicViewModel where Self.ObjectWillChangePublisher == ObservableObjectPublisher {
    public func sendObjectWillChange() {
        objectWillChange.send()
    }
}

// MARK: - Child view models

extension BasicViewModel {
    /// Adds a child to the view model. The view model must not already contain a
    /// child with the provided `key`.
    public func addChild<VM: BasicViewModel>(
        _ child: VM,
        key: String = VM.viewModelDefaultKey,
        didAddChild: ((_ child: VM, _ key: String) -> Void)? = nil
    ) {
        assert(children[key] == nil)
        sendObjectWillChange()
        children[key] = child
        didAddChild?(child, key)
    }

    /// Removes a child from the view model. If not `nil`, `child` must be a child
    /// of the view model.
    /// - Parameters:
    ///   - child: The child view model to be removed.
    ///   - delay: Whether to delay the actual removal until the next UI update.
    ///
    /// `delay` is useful to allow animated transitions for removing the UI for
    /// `child`.
    public func removeChild(_ child: (any BasicViewModel)?, delay: Bool = true) {
        guard let child else { return }
        sendObjectWillChange()
        child.cancel()
        if delay {
            DispatchQueue.main.async {
                self.removeChildImpl(child)
            }
        }
        else {
            removeChildImpl(child)
        }
    }

    private func removeChildImpl(_ child: (any BasicViewModel)?) {
        guard let child else { return }
        assert(child.isCancelled)
        guard let index = children.firstIndex(where: { $1 === child }) else { return }
        children.remove(at: index)
    }

    /// Adds a child to the view model. If the view model already contains a
    /// child with the provided `key`, the child view model expression is not
    /// evaluated.
    public func addChildIfNeeded<VM: BasicViewModel>(
        _ child: @autoclosure () -> VM,
        key: String = VM.viewModelDefaultKey,
        didAddChild: ((_ child: VM, _ key: String) -> Void)? = nil
    ) {
        if children[key] == nil {
            addChild(child(), key: key, didAddChild: didAddChild)
        }
    }

    /// Returns a child view model with a specific `key`.
    ///
    /// A child view model should not be saved in `@State` or `@ObjectState` of a
    /// view because that creates a retain cycle:
    /// View State -> View Model -> View Model Environment -> View State or
    /// Child View State -> Child View Model -> Child View Model Environment -> Child View State
    /// The retain cycle is there even with @ObservedObject because then SwiftUI
    /// View State still adds a reference to the view model.
    ///
    /// The only way to break the retain cycle is to set the view model
    /// environment to nil by cancelling the view model. (Setting the view model
    /// environment to nil directly is dangerous because the view model might
    /// still receive messages after that but when the view model is cancelled
    /// those messages are automatically ignored.)
    ///
    /// This is done automatically when a view model is popped from the
    /// navigation stack or when its sheet is dismissed.
    ///
    /// However, if a child view model is not retained by the view model itself
    /// and is saved via the view state instead, the child view model is not
    /// cancelled. Using the `child` APIs allows the child view model to be
    /// cancelled automatically when its parent view model is cancelled
    /// manually or as a result of going out of scope.
    ///
    /// Example where the view model is a container for a child view model:
    /// ```Swift
    /// private var childViewModel: ChildViewModelNsp.ViewModel { viewModel.child()! }
    ///
    /// public init(_ viewModel: ViewModel) {
    ///    self.viewModel = viewModel
    ///    viewModel.addChildIfNeeded(ChildViewModelNsp.viewModel())
    /// }
    /// ```
    ///
    /// The force unwrapping of `viewModel.child()` is appropriate here because
    /// the child is expected to be there throughout the lifetime of `viewModel` and
    /// the view.
    public func child<VM: BasicViewModel>(key: String = VM.viewModelDefaultKey) -> VM? {
        children[key] as? VM
    }

    /// Same as `child` but type-erased.
    ///
    /// This may be useful in a container UI where the content may be different depending
    /// on the context.
    public func anyChild(key: String) -> (any BasicViewModel)? {
        children[key]
    }

    /// Runs a child view model until it produces the first value.
    public func run<VM: BasicViewModel>(
        _ child: VM,
        key: String = VM.viewModelDefaultKey,
        didAddChild: ((_ child: VM, _ key: String) -> Void)? = nil
    ) async throws -> VM.PublishedValue {
        addChild(child, key: key, didAddChild: didAddChild)
        defer { removeChild(child) }
        return try await child.firstValue()
    }
}

// MARK: - Published values helpers

public extension BasicViewModel {
    var hasRequest: Bool { publishedValue.hasRequest }
    var isCancelled: Bool { publishedValue.isFinished }

    /// Every output published after iteration starts, followed by cancellation as an error.
    var throwingAsyncValues: PublishedValues<PublishedValue> { publishedValue }

    /// Every output published after iteration starts. View-model cancellation ends iteration.
    var asyncValues: MainActorSequence<PublishedValue> { publishedValue.values }

    /// Emits once when the view model is cancelled, including for a late subscriber.
    var cancellation: MainActorSequence<Void> { publishedValue.cancellation }

    /// Runs a callback for each output. Callback errors propagate; view-model cancellation ends the loop.
    func get(callback: @escaping (PublishedValue) async throws -> Void) async throws {
        for await value in asyncValues { try await callback(value) }
    }

    func get(callback: @escaping (PublishedValue) async -> Void) async {
        for await value in asyncValues { await callback(value) }
    }

    func getFirst(callback: @escaping (PublishedValue) async throws -> Void) async throws {
        var iterator = throwingAsyncValues.makeAsyncIterator()
        guard let value = try await iterator.next() else { throw NavigationCancellation.cancel }
        try await callback(value)
    }

    func getFirst(callback: @escaping (PublishedValue) async -> Void) async {
        var iterator = asyncValues.makeAsyncIterator()
        if let value = await iterator.next() { await callback(value) }
    }

    /// Waits for the first output and cancels the view model when the wait ends.
    func firstValue() async throws -> PublishedValue {
        defer { cancel() }
        return try await firstValueWithoutCancelling()
    }

    /// Waits for the first output without cancelling the view model when the wait ends.
    /// Source cancellation or cancellation of the waiting task throws and detaches this observation.
    func firstValueWithoutCancelling() async throws -> PublishedValue {
        var iterator = throwingAsyncValues.makeAsyncIterator()
        guard let value = try await iterator.next() else { throw NavigationCancellation.cancel }
        return value
    }

    /// Waits for an active value request, source cancellation, or cancellation of the calling task.
    func getRequest() async { await publishedValue.waitForRequest() }

    func publishOnRequest(_ value: PublishedValue) async {
        await getRequest()
        guard !Task.isCancelled, !publishedValue.isFinished else { return }
        publish(value)
    }

    func cancelOnRequest() async {
        await getRequest()
        guard !Task.isCancelled, !publishedValue.isFinished else { return }
        cancel()
    }

    func publish(_ value: PublishedValue) { _publish(value) }

    func _publish(_ value: PublishedValue) { publishedValue.send(value) }

    func cancel() { _cancel() }

    func _cancel() { publishedValue.finish() }
}
