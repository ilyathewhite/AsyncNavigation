//
//  TestNavigationProxy.swift
//  ReducerArchitecture
//
//  Created by Ilya Belenkiy on 11/3/25.
//

import Foundation

public class TestNavigationProxy: NavigationProxy {
    class PlaceholderViewModel: BasicViewModel {
        var publishedValue: PublishedValues<Void> = .init()

        func publish(_ value: Void) {
            _publish(value)
        }
        
        typealias PublishedValue = Void

        var id: UUID = .init()
        var name = ""
        var isCancelled = false

        func cancel() {
            isCancelled = true
            _cancel()
        }

        var children: [String : any BasicViewModel] = [:]
    }

    public struct ViewModelInfo {
        public let timeIndex: Int
        public let viewModel: any BasicViewModel

        @MainActor
        static let placeholder = Self.init(timeIndex: -1, viewModel: PlaceholderViewModel())
    }

    public enum CurrentViewModelError: Error {
        case typeMismatch
    }

    public private(set) var stack: [any ViewModelUIContainer] = []
    public private(set) var currentViewModel: ViewModelInfo = .placeholder
    private let viewModels = MainActorValueSource<ViewModelInfo>(initialValue: .placeholder)
    public var currentViewModels: MainActorSequence<ViewModelInfo> { viewModels.values }

    public init() {}

    /// Returns the view model of a particular type for a given time index.
    ///
    /// Used only for testing.
    public func getViewModel<Nsp: ViewModelUINamespace>(_ type: Nsp.Type, _ timeIndex: inout Int) async throws -> Nsp.ViewModel {
        let value = await currentViewModels.first(where: { $0.timeIndex == timeIndex })
        guard let viewModel = value?.viewModel as? Nsp.ViewModel else {
            throw CurrentViewModelError.typeMismatch
        }
        timeIndex += 1
        return viewModel
    }

    /// Returns the view model of a particular type for a given time index.
    ///
    /// Used only for testing.
    public func getViewModel<T: BasicViewModel>(_ type: T.Type, _ timeIndex: inout Int) async throws -> T {
        let value = await currentViewModels.first(where: { $0.timeIndex == timeIndex })
        guard let viewModel = value?.viewModel as? T else {
            throw CurrentViewModelError.typeMismatch
        }
        timeIndex += 1
        return viewModel
    }

    @MainActor
    /// Used only for testing.
    public func backAction() {
        return pop()
    }

    func updateCurrentViewModel() {
        guard let viewModel = stack.last?.anyViewModel else {
            assertionFailure()
            return
        }
        let timeIndex = currentViewModel.timeIndex + 1
        currentViewModel = .init(timeIndex: timeIndex, viewModel: viewModel)
        viewModels.send(currentViewModel)
    }

    public var currentIndex: Int {
        stack.count - 1
    }

    public func push<Nsp: ViewModelUINamespace>(_ viewModelUI: ViewModelUI<Nsp>) -> Int {
        stack.append(viewModelUI)
        updateCurrentViewModel()
        return stack.count - 1
    }

    public func replaceTop<Nsp: ViewModelUINamespace>(with viewModelUI: ViewModelUI<Nsp>) -> Int {
        guard let last = stack.last else {
            assertionFailure()
            return 0
        }
        last.cancel()

        stack[stack.count - 1] = viewModelUI
        updateCurrentViewModel()
        return stack.count - 1
    }

    public func pop(to index: Int) {
        guard 0 <= index, index < stack.count else {
            assertionFailure()
            return
        }
        let k = stack.count - 1 - index
        // cancel order should be in reverse of push order
        var valuesToCancel: [any BasicViewModel] = []
        for _ in 0..<k {
            let viewModelUI = stack.removeLast()
            valuesToCancel.append(viewModelUI.anyViewModel)
        }

        for value in valuesToCancel {
            value.cancel()
        }

        updateCurrentViewModel()
    }

    public func popToRoot() {
        pop(to: 0)
    }
}
