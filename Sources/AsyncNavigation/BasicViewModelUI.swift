//
//  BasicViewModelUI.swift
//  ReducerArchitecture
//
//  Created by Ilya Belenkiy on 11/9/25.
//

import SwiftUI

/// The protocol for a content view backed by a view model.
@MainActor
public protocol ViewModelContentView: View {
    /// The type of the view model associated with the content view.
    associatedtype ViewModel: BasicViewModel

    /// Initializes the view with a view model.
    init(_ viewModel: ViewModel)
}

/// The namespace that contains the view model and its content view.
///
/// Having a namespace enables using the same standard names for all components
/// and differentiating them by the namespace. For example, the `Onboarding`
/// namespace may have `ViewModel` and `ContentView`, and the `Login` namespace
/// may also have `ViewModel` and `ContentView`, without any name clashes.
public protocol ViewModelUINamespace {
    /// The type for the content view.
    associatedtype ContentView: ViewModelContentView

    /// The type for the view model.
    associatedtype ViewModel: BasicViewModel where ViewModel == ContentView.ViewModel
}

/// A common base for navigation elements, allowing storage of elements of
/// different types in the same navigation stack using this protocol as the
/// element type.
public protocol ViewModelUIContainer: Hashable, Identifiable {
    /// The namespace that contains both the view model and its content view types.
    associatedtype Nsp: ViewModelUINamespace

    var viewModel: Nsp.ViewModel { get }
    init(_ viewModel: Nsp.ViewModel)
}

extension ViewModelUIContainer {
    /// Provides a way to construct the content view from the view model.
    @MainActor
    public func makeView() -> some View {
        Nsp.ContentView(viewModel).id(viewModel.id)
    }

    /// Same as `makeView`, but type-erased.
    @MainActor
    public func makeAnyView() -> AnyView {
        AnyView(makeView())
    }

    public var id: UUID {
        viewModel.id
    }

    @MainActor
    public var value: Nsp.ViewModel.ValuePublisher {
        viewModel.value
    }

    public var anyViewModel: any BasicViewModel {
        viewModel
    }

    @MainActor
    public func cancel() {
        viewModel.cancel()
    }
}

/// A strictly typed navigation element. Values of this type are used in
/// navigation stacks, sheets, alerts, and child content in container UIs.
public struct ViewModelUI<Nsp: ViewModelUINamespace>: ViewModelUIContainer {
    public let viewModel: Nsp.ViewModel

    nonisolated public static func == (lhs: ViewModelUI, rhs: ViewModelUI) -> Bool {
        lhs.viewModel === rhs.viewModel
    }

    public init(_ viewModel: Nsp.ViewModel) {
        self.viewModel = viewModel
    }

    public init?(_ viewModel: Nsp.ViewModel?) {
        guard let viewModel else { return nil }
        self.init(viewModel)
    }
}
