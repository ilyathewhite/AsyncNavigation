//
//  NavigationNode.swift
//  ReducerArchitecture
//
//  Created by Ilya Belenkiy on 11/3/25.
//

import SwiftUI

/// Describes a specific place in a navigation flow.
///
/// Conceptually, the navigation flow is modeled by nesting: each next node is
/// nested deeper than the previous one. For example:
/// ```swift
/// await node1.then { value1, index1 in
///     await node2.then { value2, index2 in
///         await node3.then { value3, index3 in
///             proxy.popToRoot()
///         }
///     }
/// }
/// ```
/// This describes navigation `node1` -> `node2` -> `node3`, where `value1` is
/// the result of interacting with the `node1` screen, and `index1` is the
/// index to use to pop to `node1` (similarly for the other nodes).
///
/// These APIs are main-actor isolated.
@MainActor
public struct NavigationNode<Nsp: ViewModelUINamespace> {
    @State private var viewModel: Nsp.ViewModel
    let proxy: NavigationProxy

    public init(_ viewModel: Nsp.ViewModel, _ proxy: NavigationProxy) {
        self.viewModel = viewModel
        self.proxy = proxy
    }

    /// Defines what happens after this node in the flow and passes this
    /// node's value to the next node.
    ///
    /// - Parameters:
    ///   - callback: A closure that receives the value produced at this node
    ///     and the index that identifies this node so that you can return to it
    ///     later.
    /// - Throws: Throws if `callback` throws, allowing cancellation of the flow.
    public func then(_ callback: @escaping (Nsp.ViewModel.PublishedValue, Int) async throws -> Void) async throws {
        let index = proxy.push(ViewModelUI<Nsp>(viewModel))
        try await viewModel.get { value in
            try await callback(value, index)
        }
    }

    /// Defines what happens after this node in the flow and passes this
    /// node's value to the next node.
    ///
    /// - Parameters:
    ///   - callback: A closure that receives the value produced at this node
    ///     and the index that identifies this node so that you can return to it
    ///     later.
    public func then(_ callback: @escaping (Nsp.ViewModel.PublishedValue, Int) async -> Void) async {
        let index = proxy.push(ViewModelUI<Nsp>(viewModel))
        await viewModel.get { value in
            await callback(value, index)
        }
    }

    /// Defines what happens after this node in the flow and passes this
    /// node's value to the next node.
    ///
    /// - Parameters:
    ///   - callback: A closure that receives the value produced at this node
    ///     and the index that identifies this node so that you can return to it
    ///     later.
    /// - Throws: Throws if `callback` throws, allowing cancellation of the flow.
    public func thenReplacingTop(_ callback: @escaping (Nsp.ViewModel.PublishedValue, Int) async throws -> Void) async throws {
        let index = proxy.replaceTop(with: ViewModelUI<Nsp>(viewModel))
        try await viewModel.get { value in
            try await callback(value, index)
        }
    }

    /// Defines what happens after this node in the flow and passes this
    /// node's value to the next node.
    ///
    /// - Parameters:
    ///   - callback: A closure that receives the value produced at this node
    ///     and the index that identifies this node so that you can return to it
    ///     later.
    public func thenReplacingTop(_ callback: @escaping (Nsp.ViewModel.PublishedValue, Int) async -> Void) async {
        let index = proxy.replaceTop(with: ViewModelUI<Nsp>(viewModel))
        await viewModel.get { value in
            await callback(value, index)
        }
    }
}

