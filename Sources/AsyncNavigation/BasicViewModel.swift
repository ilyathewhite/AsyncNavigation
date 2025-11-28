//
//  BasicViewModel.swift
//  ReducerArchitecture
//
//  Created by Ilya Belenkiy on 11/8/25.
//

import Foundation
import Combine
import CombineEx

/// Provides the basic APIs that each view model is expected to have to work
/// with async navigation.
@MainActor
public protocol BasicViewModel: ObservableObject, Hashable, Identifiable {
    /// The type of value that the user gets as a result of interacting with
    /// the UI for the view model when the user either closes the UI or
    /// navigates away from it to the next one.
    associatedtype PublishedValue

    nonisolated var id: UUID { get }

    /// Provides a way to check whether the UI is active or can still be active.
    /// Used in sheets, alerts, and assertions.
    var isCancelled: Bool { get }

    /// Provides the low-level API to return the result of interacting with the
    /// UI for the view model when the user either closes the UI or
    /// navigates away from it to the next one.
    /// A class that conforms to `BasicViewModel` should not use it directly.
    var publishedValue: PassthroughSubject<PublishedValue, Cancel> { get }

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
    var hasRequest: Bool { get set }

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
    public func addChild<VM: BasicViewModel>(_ child: VM, key: String = VM.viewModelDefaultKey) {
        assert(children[key] == nil)
        sendObjectWillChange()
        children[key] = child
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
    public func addChildIfNeeded<VM: BasicViewModel>(_ child: @autoclosure () -> VM, key: String = VM.viewModelDefaultKey) {
        if children[key] == nil {
            addChild(child())
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
    public func run<VM: BasicViewModel>(_ child: VM, key: String = VM.viewModelDefaultKey) async throws -> VM.PublishedValue {
        addChild(child, key: key)
        defer { removeChild(child) }
        return try await child.firstValue()
    }
}

// MARK: - Published values helpers

public extension BasicViewModel {
    typealias ValuePublisher = AnyPublisher<PublishedValue, Cancel>

    /// Provides the result of interacting with the UI for the view model when
    /// the user either closes the UI or navigates away from it to the next one.
    ///
    /// This is a publisher and not a single value because the user may come back
    /// to the same UI after navigating forward in the flow.
    var value: AnyPublisher<PublishedValue, Cancel> {
        publishedValue
            .handleEvents(
                receiveOutput: { [weak self] _ in
                    assert(Thread.isMainThread)
                    self?.hasRequest = false
                },
                receiveRequest: { [weak self] _ in
                    assert(Thread.isMainThread)
                    self?.hasRequest = true
                }
            )
            .subscribe(on: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    /// Same as `value`, but provides `Result` values.
    var valueResult: AnyPublisher<Result<PublishedValue, Cancel>, Never> {
        value
            .map { .success($0) }
            .catch { Just(.failure($0)) }
            .eraseToAnyPublisher()
    }

    /// Same as `value`, but provides an async sequence.
    var throwingAsyncValues: AsyncThrowingPublisher<AnyPublisher<PublishedValue, Cancel>> {
        value.values
    }

    /// Same as `value`, but provides an async sequence that ignores cancellation.
    var asyncValues: AsyncPublisher<AnyPublisher<PublishedValue, Never>> {
        value
            .catch { _ in Empty<PublishedValue, Never>() }
            .eraseToAnyPublisher()
            .values
    }


    /// Runs an async callback whenever a new value becomes available.
    /// Throws an error if the view model gets cancelled before completing the sequence.
    /// Useful for the async navigation API.
    func get(callback: @escaping (PublishedValue) async throws -> Void) async throws {
        try await asyncValues.get(callback: callback)
    }

    /// Runs an async callback whenever a new value becomes available.
    /// Useful for the async navigation API.
    func get(callback: @escaping (PublishedValue) async -> Void) async {
        await asyncValues.get(callback: callback)
    }

    /// Runs a callback when the first value becomes available.
    /// Throws an error if the view model gets cancelled before the first value.
    /// Useful for sheets and alerts.
    func getFirst(callback: @escaping (PublishedValue) async throws -> Void) async throws {
        let firstValue = try await value.first().async()
        try await callback(firstValue)
    }

    /// Runs a callback when the first value becomes available.
    /// Useful for sheets and alerts.
    func getFirst(callback: @escaping (PublishedValue) async -> Void) async {
        if let firstValue = try? await value.first().async() {
            await callback(firstValue)
        }
    }

    /// Provides the first value when it becomes available.
    /// Throws an error if the view model gets cancelled before the first value.
    /// Useful for sheets and alerts.
    func firstValue() async throws -> PublishedValue {
        defer { cancel() }
        return try await value.first().async()
    }

    /// A convenience API to avoid a race condition between the code that needs a
    /// first value and the code that provides it.
    func getRequest() async {
        while !hasRequest {
            await Task.yield()
        }
    }

    /// A convenience API, useful for testing.
    func publishOnRequest(_ value: PublishedValue) async {
        while !hasRequest {
            await Task.yield()
        }
        publish(value)
    }

    /// An implementation of this protocol should call this function as part of
    /// `publish`.
    func _publish(_ value: PublishedValue) {
        publishedValue.send(value)
    }

    /// An implementation of this protocol should call this function as part of
    /// `cancel`.
    func _cancel() {
        publishedValue.send(completion: .failure(.cancel))
    }

    /// Provides a value (Void) when the view model is cancelled.
    var isCancelledPublisher: AnyPublisher<Void, Never> {
        publishedValue
            .map { _ in false }
            .replaceError(with: true)
            .filter { $0 }
            .map { _ in () }
            .eraseToAnyPublisher()
    }
}

